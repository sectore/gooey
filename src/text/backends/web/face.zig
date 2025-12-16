//! WebFontFace - Font implementation using JavaScript Canvas 2D API
//!
//! Rasterizes glyphs via JS imports and provides metrics.

const std = @import("std");
const types = @import("../../types.zig");
const font_face = @import("../../font_face.zig");

const Metrics = types.Metrics;
const GlyphMetrics = types.GlyphMetrics;
const RasterizedGlyph = types.RasterizedGlyph;
const SystemFont = types.SystemFont;
const FontFace = font_face.FontFace;

// JS imports
extern "env" fn getFontMetrics(
    font_ptr: [*]const u8,
    font_len: u32,
    size: f32,
    out_ascent: *f32,
    out_descent: *f32,
    out_line_height: *f32,
) void;

extern "env" fn measureText(
    font_ptr: [*]const u8,
    font_len: u32,
    size: f32,
    text_ptr: [*]const u8,
    text_len: u32,
) f32;

extern "env" fn rasterizeGlyph(
    font_ptr: [*]const u8,
    font_len: u32,
    size: f32,
    codepoint: u32,
    out_buffer: [*]u8,
    buffer_size: u32,
    out_width: *u32,
    out_height: *u32,
    out_bearing_x: *f32,
    out_bearing_y: *f32,
    out_advance: *f32,
) void;

pub const WebFontFace = struct {
    allocator: std.mem.Allocator,
    font_name: []const u8,
    point_size: f32,
    metrics: Metrics,

    const Self = @This();

    /// Load a system font
    pub fn initSystemFont(allocator: std.mem.Allocator, system_font: SystemFont, size: f32) !*Self {
        const font_name = switch (system_font) {
            .monospace => "monospace",
            .sans_serif => "system-ui, -apple-system, sans-serif",
            .serif => "Georgia, serif",
            .system => "system-ui, -apple-system, sans-serif",
        };

        return initNamed(allocator, font_name, size);
    }

    /// Load a font by CSS name
    pub fn initNamed(allocator: std.mem.Allocator, font_name: []const u8, size: f32) !*Self {
        const self = try allocator.create(Self);

        // Get font metrics from JS
        var ascent: f32 = 0;
        var descent: f32 = 0;
        var line_height: f32 = 0;

        getFontMetrics(
            font_name.ptr,
            @intCast(font_name.len),
            size,
            &ascent,
            &descent,
            &line_height,
        );

        // Measure cell width (for monospace detection)
        const m_width = measureText(font_name.ptr, @intCast(font_name.len), size, "M", 1);
        const i_width = measureText(font_name.ptr, @intCast(font_name.len), size, "i", 1);
        const is_monospace = @abs(m_width - i_width) < 0.1;

        self.* = .{
            .allocator = allocator,
            .font_name = font_name,
            .point_size = size,
            .metrics = .{
                .units_per_em = 1000,
                .ascender = ascent,
                .descender = descent,
                .line_gap = line_height - ascent - descent,
                .cap_height = ascent * 0.7, // Approximation
                .x_height = ascent * 0.5, // Approximation
                .underline_position = descent * 0.5,
                .underline_thickness = @max(1.0, size / 14.0),
                .line_height = line_height,
                .point_size = size,
                .is_monospace = is_monospace,
                .cell_width = m_width,
            },
        };

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }

    /// Get glyph ID - on web we just use the codepoint directly
    pub fn glyphIndex(_: *Self, codepoint: u21) u16 {
        // Web doesn't have real glyph IDs, use codepoint truncated to u16
        return @truncate(codepoint);
    }

    /// Get metrics for a glyph
    pub fn glyphMetrics(self: *Self, glyph_id: u16) GlyphMetrics {
        // Rasterize to get metrics (we'll cache this in practice)
        var buffer: [1]u8 = undefined;
        var width: u32 = 0;
        var height: u32 = 0;
        var bearing_x: f32 = 0;
        var bearing_y: f32 = 0;
        var advance: f32 = 0;

        rasterizeGlyph(
            self.font_name.ptr,
            @intCast(self.font_name.len),
            self.point_size,
            glyph_id,
            &buffer,
            0, // Don't actually write pixels, just get metrics
            &width,
            &height,
            &bearing_x,
            &bearing_y,
            &advance,
        );

        return .{
            .glyph_id = glyph_id,
            .advance_x = advance,
            .advance_y = 0,
            .bearing_x = bearing_x,
            .bearing_y = bearing_y,
            .width = @floatFromInt(width),
            .height = @floatFromInt(height),
        };
    }

    /// Render a glyph to a bitmap
    pub fn renderGlyph(
        self: *Self,
        glyph_id: u16,
        scale: f32,
        buffer: []u8,
        buffer_size: u32,
    ) !RasterizedGlyph {
        return self.renderGlyphSubpixel(glyph_id, scale, 0, 0, buffer, buffer_size);
    }

    /// Render a glyph with subpixel positioning
    pub fn renderGlyphSubpixel(
        self: *Self,
        glyph_id: u16,
        scale: f32,
        _: f32, // subpixel_x - not used on web
        _: f32, // subpixel_y - not used on web
        buffer: []u8,
        buffer_size: u32,
    ) !RasterizedGlyph {
        var width: u32 = 0;
        var height: u32 = 0;
        var bearing_x: f32 = 0;
        var bearing_y: f32 = 0;
        var advance: f32 = 0;

        const size = self.point_size * scale;

        rasterizeGlyph(
            self.font_name.ptr,
            @intCast(self.font_name.len),
            size,
            glyph_id,
            buffer.ptr,
            buffer_size,
            &width,
            &height,
            &bearing_x,
            &bearing_y,
            &advance,
        );

        return .{
            .width = width,
            .height = height,
            .offset_x = @intFromFloat(bearing_x),
            .offset_y = @intFromFloat(bearing_y),
            .advance_x = advance,
            .is_color = false,
        };
    }

    /// Get as FontFace interface
    pub fn fontFace(self: *Self) FontFace {
        return font_face.createFontFace(Self, self);
    }
};
