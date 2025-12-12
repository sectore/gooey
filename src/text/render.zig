//! Text rendering - converts shaped text to GPU glyph instances

const std = @import("std");
const Scene = @import("../core/scene.zig").Scene;
const GlyphInstance = @import("../core/scene.zig").GlyphInstance;
const TextSystem = @import("text_system.zig").TextSystem;
const Hsla = @import("../core/mod.zig").Hsla;
const types = @import("types.zig");

const SUBPIXEL_VARIANTS_X = types.SUBPIXEL_VARIANTS_X;
const SUBPIXEL_VARIANTS_F: f32 = @floatFromInt(SUBPIXEL_VARIANTS_X);

pub const RenderTextOptions = struct {
    clipped: bool = true,
};

pub fn renderText(
    scene: *Scene,
    text_system: *TextSystem,
    text: []const u8,
    x: f32,
    baseline_y: f32,
    scale_factor: f32,
    color: Hsla,
    options: RenderTextOptions,
) !f32 {
    if (text.len == 0) return 0;

    var shaped = try text_system.shapeText(text);
    defer shaped.deinit(text_system.allocator);

    var pen_x = x;
    for (shaped.glyphs) |glyph| {
        // Convert to device pixels
        const device_x = (pen_x + glyph.x_offset) * scale_factor;
        const device_y = (baseline_y + glyph.y_offset) * scale_factor;

        // Extract fractional part for subpixel variant selection
        const frac_x = device_x - @floor(device_x);
        const subpixel_x: u8 = @intFromFloat(@floor(frac_x * SUBPIXEL_VARIANTS_F));

        const cached = try text_system.getGlyphSubpixel(glyph.glyph_id, subpixel_x, 0);

        if (cached.region.width > 0 and cached.region.height > 0) {
            const atlas = text_system.getAtlas();
            const uv = cached.region.uv(atlas.size);

            const glyph_w = @as(f32, @floatFromInt(cached.region.width)) / scale_factor;
            const glyph_h = @as(f32, @floatFromInt(cached.region.height)) / scale_factor;

            // Snap to device pixel grid, then add offset, then convert back to logical
            // This is how GPUI does it: floor(device_pos) + raster_offset
            const glyph_x = (@floor(device_x) + @as(f32, @floatFromInt(cached.offset_x))) / scale_factor;
            const glyph_y = (@floor(device_y) - @as(f32, @floatFromInt(cached.offset_y))) / scale_factor;

            const instance = GlyphInstance.init(glyph_x, glyph_y, glyph_w, glyph_h, uv.u0, uv.v0, uv.u1, uv.v1, color);

            if (options.clipped) {
                try scene.insertGlyphClipped(instance);
            } else {
                try scene.insertGlyph(instance);
            }
        }

        pen_x += glyph.x_advance;
    }

    return shaped.width;
}
