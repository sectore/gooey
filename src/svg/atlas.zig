//! SVG Atlas - Texture cache for rasterized SVG icons
//!
//! Caches rasterized SVGs in a texture atlas, keyed by path hash and size.

const std = @import("std");
const Atlas = @import("../text/atlas.zig").Atlas;
const Region = @import("../text/atlas.zig").Region;
const rasterizer = @import("rasterizer.zig");

/// Cache key for SVG lookup
pub const SvgKey = struct {
    /// Hash of SVG path data
    path_hash: u64,
    /// Device pixel size (width = height for square icons)
    device_size: u16,

    pub fn init(path_data: []const u8, logical_size: f32, scale_factor: f64) SvgKey {
        return .{
            .path_hash = std.hash.Wyhash.hash(0, path_data),
            .device_size = @intFromFloat(@ceil(logical_size * scale_factor)),
        };
    }
};

/// Cached SVG entry
pub const CachedSvg = struct {
    /// Region in atlas texture
    region: Region,
    /// Offset from logical position (device pixels)
    offset_x: i16,
    offset_y: i16,
};

/// SVG texture atlas with caching
pub const SvgAtlas = struct {
    allocator: std.mem.Allocator,
    /// RGBA texture atlas
    atlas: Atlas,
    /// Cache map
    cache: std.AutoHashMap(SvgKey, CachedSvg),
    /// Reusable rasterization buffer
    render_buffer: []u8,
    render_buffer_size: u32,
    /// Current scale factor
    scale_factor: f64,

    const Self = @This();
    const MAX_ICON_SIZE: u32 = 256;

    pub fn init(allocator: std.mem.Allocator, scale_factor: f64) !Self {
        // Buffer for largest possible icon (256x256 RGBA)
        const buffer_size = MAX_ICON_SIZE * MAX_ICON_SIZE * 4;
        const render_buffer = try allocator.alloc(u8, buffer_size);

        return .{
            .allocator = allocator,
            .atlas = try Atlas.initWithSize(allocator, .rgba, 512),
            .cache = std.AutoHashMap(SvgKey, CachedSvg).init(allocator),
            .render_buffer = render_buffer,
            .render_buffer_size = MAX_ICON_SIZE,
            .scale_factor = scale_factor,
        };
    }

    pub fn deinit(self: *Self) void {
        self.cache.deinit();
        self.atlas.deinit();
        self.allocator.free(self.render_buffer);
    }

    pub fn setScaleFactor(self: *Self, scale: f32) void {
        if (self.scale_factor != scale) {
            self.scale_factor = scale;
            self.clear();
        }
    }

    /// Get cached SVG or rasterize and cache it
    pub fn getOrRasterize(
        self: *Self,
        path_data: []const u8,
        viewbox: f32,
        logical_size: f32,
    ) !CachedSvg {
        const key = SvgKey.init(path_data, logical_size, self.scale_factor);

        if (self.cache.get(key)) |cached| {
            return cached;
        }

        // Rasterize
        const device_size = key.device_size;
        if (device_size > self.render_buffer_size) {
            return error.IconTooLarge;
        }

        @memset(self.render_buffer, 0);

        const rasterized = try rasterizer.rasterize(
            self.allocator,
            path_data,
            viewbox,
            device_size,
            self.render_buffer,
        );

        // Reserve atlas space
        const region = try self.reserveWithEviction(rasterized.width, rasterized.height);

        // Copy to atlas
        const pixel_count = rasterized.width * rasterized.height * 4;
        self.atlas.set(region, self.render_buffer[0..pixel_count]);

        const cached = CachedSvg{
            .region = region,
            .offset_x = rasterized.offset_x,
            .offset_y = rasterized.offset_y,
        };

        try self.cache.put(key, cached);
        return cached;
    }

    fn reserveWithEviction(self: *Self, width: u32, height: u32) !Region {
        if (try self.atlas.reserve(width, height)) |region| {
            return region;
        }

        // Try growing
        self.atlas.grow() catch |err| {
            if (err == error.AtlasFull) {
                self.clear();
                if (try self.atlas.reserve(width, height)) |region| {
                    return region;
                }
                return error.IconTooLarge;
            }
            return err;
        };

        return try self.atlas.reserve(width, height) orelse error.IconTooLarge;
    }

    pub fn clear(self: *Self) void {
        self.cache.clearRetainingCapacity();
        self.atlas.clear();
    }

    pub fn getAtlas(self: *const Self) *const Atlas {
        return &self.atlas;
    }

    pub fn getGeneration(self: *const Self) u32 {
        return self.atlas.generation;
    }
};
