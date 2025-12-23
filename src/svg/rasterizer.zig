//! SVG Rasterizer - CoreGraphics-based SVG path rendering
//!
//! Rasterizes SVG path data to RGBA bitmaps at device resolution.
//! Uses two-channel encoding: R = fill alpha, G = stroke alpha.
//! This allows the shader to apply different colors to fill and stroke.

const std = @import("std");
const svg_mod = @import("../core/svg.zig");

const cg = @cImport({
    @cInclude("CoreGraphics/CoreGraphics.h");
});

pub const RasterizedSvg = struct {
    width: u32,
    height: u32,
    offset_x: i16,
    offset_y: i16,
};

pub const RasterizeError = error{
    EmptyPath,
    GraphicsError,
    BufferTooSmall,
    OutOfMemory,
};

/// Stroke options for SVG rendering
pub const StrokeOptions = struct {
    enabled: bool = false,
    width: f32 = 1.0,
};

/// Rasterize SVG path data to RGBA buffer
pub fn rasterize(
    allocator: std.mem.Allocator,
    path_data: []const u8,
    viewbox: f32,
    device_size: u32,
    buffer: []u8,
) RasterizeError!RasterizedSvg {
    return rasterizeWithOptions(allocator, path_data, viewbox, device_size, buffer, true, .{});
}

/// Rasterize SVG path data with fill and stroke options.
/// Output format: R = fill alpha, G = stroke alpha, B = unused, A = combined alpha
pub fn rasterizeWithOptions(
    allocator: std.mem.Allocator,
    path_data: []const u8,
    viewbox: f32,
    device_size: u32,
    buffer: []u8,
    fill: bool,
    stroke: StrokeOptions,
) RasterizeError!RasterizedSvg {
    if (path_data.len == 0) return error.EmptyPath;

    const required_size = device_size * device_size * 4;
    if (buffer.len < required_size) return error.BufferTooSmall;

    // Clear buffer (transparent black)
    @memset(buffer[0..required_size], 0);

    // Parse SVG path
    var parser = svg_mod.PathParser.init(allocator);
    var path = svg_mod.SvgPath.init(allocator);
    defer path.deinit();

    parser.parse(&path, path_data) catch return error.EmptyPath;
    if (path.commands.items.len == 0) return error.EmptyPath;

    // Flatten to points
    var points = std.ArrayList(svg_mod.Vec2){};
    defer points.deinit(allocator);
    var polygons = std.ArrayList(svg_mod.IndexSlice){};
    defer polygons.deinit(allocator);

    svg_mod.flattenPath(allocator, &path, 0.5, &points, &polygons) catch return error.OutOfMemory;

    if (points.items.len < 2) return error.EmptyPath;
    // For stroke-only, we need at least 2 points (a line)
    if (fill and (points.items.len < 3 or polygons.items.len == 0)) return error.EmptyPath;

    // Create color space
    const color_space = cg.CGColorSpaceCreateDeviceRGB();
    if (color_space == null) return error.GraphicsError;
    defer cg.CGColorSpaceRelease(color_space);

    const scale: f64 = @as(f64, @floatFromInt(device_size)) / @as(f64, viewbox);

    if (fill and stroke.enabled) {
        // Two-channel mode: fill in R, stroke in G
        const temp_size = device_size * device_size * 4;
        const fill_buffer = allocator.alloc(u8, temp_size) catch return error.OutOfMemory;
        defer allocator.free(fill_buffer);
        const stroke_buffer = allocator.alloc(u8, temp_size) catch return error.OutOfMemory;
        defer allocator.free(stroke_buffer);

        @memset(fill_buffer, 0);
        @memset(stroke_buffer, 0);

        // Render fill to temporary buffer
        {
            const ctx = cg.CGBitmapContextCreate(
                fill_buffer.ptr,
                device_size,
                device_size,
                8,
                device_size * 4,
                color_space,
                cg.kCGImageAlphaPremultipliedLast,
            );
            if (ctx == null) return error.GraphicsError;
            defer cg.CGContextRelease(ctx);

            cg.CGContextSetAllowsAntialiasing(ctx, true);
            cg.CGContextSetShouldAntialias(ctx, true);
            cg.CGContextTranslateCTM(ctx, 0, @floatFromInt(device_size));
            cg.CGContextScaleCTM(ctx, scale, -scale);

            for (polygons.items) |poly| {
                const pts = points.items[poly.start..poly.end];
                if (pts.len < 2) continue;
                cg.CGContextBeginPath(ctx);
                cg.CGContextMoveToPoint(ctx, pts[0].x, pts[0].y);
                for (pts[1..]) |pt| {
                    cg.CGContextAddLineToPoint(ctx, pt.x, pt.y);
                }
                cg.CGContextClosePath(ctx);
            }

            cg.CGContextSetRGBFillColor(ctx, 1.0, 1.0, 1.0, 1.0);
            cg.CGContextFillPath(ctx);
        }

        // Render stroke to temporary buffer
        {
            const ctx = cg.CGBitmapContextCreate(
                stroke_buffer.ptr,
                device_size,
                device_size,
                8,
                device_size * 4,
                color_space,
                cg.kCGImageAlphaPremultipliedLast,
            );
            if (ctx == null) return error.GraphicsError;
            defer cg.CGContextRelease(ctx);

            cg.CGContextSetAllowsAntialiasing(ctx, true);
            cg.CGContextSetShouldAntialias(ctx, true);
            cg.CGContextTranslateCTM(ctx, 0, @floatFromInt(device_size));
            cg.CGContextScaleCTM(ctx, scale, -scale);

            for (polygons.items) |poly| {
                const pts = points.items[poly.start..poly.end];
                if (pts.len < 2) continue;
                cg.CGContextBeginPath(ctx);
                cg.CGContextMoveToPoint(ctx, pts[0].x, pts[0].y);
                for (pts[1..]) |pt| {
                    cg.CGContextAddLineToPoint(ctx, pt.x, pt.y);
                }
                cg.CGContextClosePath(ctx);
            }

            cg.CGContextSetRGBStrokeColor(ctx, 1.0, 1.0, 1.0, 1.0);
            cg.CGContextSetLineWidth(ctx, stroke.width);
            cg.CGContextSetLineCap(ctx, cg.kCGLineCapRound);
            cg.CGContextSetLineJoin(ctx, cg.kCGLineJoinRound);
            cg.CGContextStrokePath(ctx);
        }

        // Combine: R = fill alpha, G = stroke alpha, B = 0, A = max(fill, stroke)
        var i: usize = 0;
        while (i < device_size * device_size) : (i += 1) {
            const idx = i * 4;
            const fill_a = fill_buffer[idx + 3];
            const stroke_a = stroke_buffer[idx + 3];
            buffer[idx + 0] = fill_a; // R = fill
            buffer[idx + 1] = stroke_a; // G = stroke
            buffer[idx + 2] = 0; // B = unused
            buffer[idx + 3] = @max(fill_a, stroke_a); // A = combined
        }
    } else {
        // Single channel mode (fill-only or stroke-only)
        const context = cg.CGBitmapContextCreate(
            buffer.ptr,
            device_size,
            device_size,
            8,
            device_size * 4,
            color_space,
            cg.kCGImageAlphaPremultipliedLast,
        );
        if (context == null) return error.GraphicsError;
        defer cg.CGContextRelease(context);

        cg.CGContextSetAllowsAntialiasing(context, true);
        cg.CGContextSetShouldAntialias(context, true);
        cg.CGContextTranslateCTM(context, 0, @floatFromInt(device_size));
        cg.CGContextScaleCTM(context, scale, -scale);

        for (polygons.items) |poly| {
            const pts = points.items[poly.start..poly.end];
            if (pts.len < 2) continue;

            cg.CGContextBeginPath(context);
            cg.CGContextMoveToPoint(context, pts[0].x, pts[0].y);

            for (pts[1..]) |pt| {
                cg.CGContextAddLineToPoint(context, pt.x, pt.y);
            }

            if (fill) {
                cg.CGContextClosePath(context);
            }
        }

        if (fill) {
            cg.CGContextSetRGBFillColor(context, 1.0, 1.0, 1.0, 1.0);
            cg.CGContextFillPath(context);

            // Copy alpha to R channel, clear G
            var i: usize = 0;
            while (i < device_size * device_size) : (i += 1) {
                const idx = i * 4;
                buffer[idx + 0] = buffer[idx + 3]; // R = A
                buffer[idx + 1] = 0; // G = 0 (no stroke)
                buffer[idx + 2] = 0;
            }
        } else if (stroke.enabled) {
            cg.CGContextSetRGBStrokeColor(context, 1.0, 1.0, 1.0, 1.0);
            cg.CGContextSetLineWidth(context, stroke.width);
            cg.CGContextSetLineCap(context, cg.kCGLineCapRound);
            cg.CGContextSetLineJoin(context, cg.kCGLineJoinRound);
            cg.CGContextStrokePath(context);

            // Copy alpha to G channel, clear R
            var i: usize = 0;
            while (i < device_size * device_size) : (i += 1) {
                const idx = i * 4;
                buffer[idx + 1] = buffer[idx + 3]; // G = A
                buffer[idx + 0] = 0; // R = 0 (no fill)
                buffer[idx + 2] = 0;
            }
        }
    }

    return RasterizedSvg{
        .width = device_size,
        .height = device_size,
        .offset_x = 0,
        .offset_y = 0,
    };
}
