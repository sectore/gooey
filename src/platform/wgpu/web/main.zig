//! Gooey Web Demo
//!
//! Shows a counter app using gooey's Scene primitives.
//! This demonstrates the architecture - user code builds scenes,
//! the platform renders them.

const std = @import("std");
const imports = @import("imports.zig");
const unified = @import("unified");
const scene_mod = @import("scene");
const WebPlatform = @import("platform.zig").WebPlatform;
const WebWindow = @import("window.zig").WebWindow;

const MAX_PRIMITIVES: u32 = 4096;
const MAX_GLYPHS: u32 = 8192;
const TEXT_SIZE: f32 = 48;

const Uniforms = extern struct {
    viewport_width: f32,
    viewport_height: f32,
};

const GpuGlyph = extern struct {
    pos_x: f32 = 0,
    pos_y: f32 = 0,
    size_x: f32 = 0,
    size_y: f32 = 0,
    uv_left: f32 = 0,
    uv_top: f32 = 0,
    uv_right: f32 = 0,
    uv_bottom: f32 = 0,
    color_h: f32 = 0,
    color_s: f32 = 0,
    color_l: f32 = 1,
    color_a: f32 = 1,
    clip_x: f32 = 0,
    clip_y: f32 = 0,
    clip_width: f32 = 99999,
    clip_height: f32 = 99999,

    pub fn fromScene(g: scene_mod.GlyphInstance) GpuGlyph {
        return .{
            .pos_x = g.pos_x,
            .pos_y = g.pos_y,
            .size_x = g.size_x,
            .size_y = g.size_y,
            .uv_left = g.uv_left,
            .uv_top = g.uv_top,
            .uv_right = g.uv_right,
            .uv_bottom = g.uv_bottom,
            .color_h = g.color.h,
            .color_s = g.color.s,
            .color_l = g.color.l,
            .color_a = g.color.a,
            .clip_x = g.clip_x,
            .clip_y = g.clip_y,
            .clip_width = g.clip_width,
            .clip_height = g.clip_height,
        };
    }
};

// =============================================================================
// Atlas
// =============================================================================

const AtlasGlyph = struct {
    uv_left: f32,
    uv_top: f32,
    uv_right: f32,
    uv_bottom: f32,
    width: f32,
    height: f32,
    bearing_x: f32,
    bearing_y: f32,
    advance: f32,
};

const Atlas = struct {
    const SIZE = 512;
    const MAX = 128;
    pixels: [SIZE * SIZE]u8 = [_]u8{0} ** (SIZE * SIZE),
    glyphs: [MAX]?AtlasGlyph = [_]?AtlasGlyph{null} ** MAX,
    cursor_x: u32 = 1,
    cursor_y: u32 = 1,
    row_height: u32 = 0,
    texture_handle: u32 = 0,

    fn getOrCreate(self: *Atlas, codepoint: u32, font: []const u8, size: f32) ?AtlasGlyph {
        if (codepoint >= MAX) return null;
        if (self.glyphs[codepoint]) |g| return g;

        var buf: [128 * 128]u8 = undefined;
        var w: u32 = 0;
        var h: u32 = 0;
        var bx: f32 = 0;
        var by: f32 = 0;
        var adv: f32 = 0;
        imports.rasterizeGlyph(font.ptr, @intCast(font.len), size, codepoint, &buf, buf.len, &w, &h, &bx, &by, &adv);
        if (w == 0 or h == 0) return null;

        if (self.cursor_x + w + 1 >= SIZE) {
            self.cursor_x = 1;
            self.cursor_y += self.row_height + 1;
            self.row_height = 0;
        }
        if (self.cursor_y + h + 1 >= SIZE) return null;

        for (0..h) |y| for (0..w) |x| {
            self.pixels[(self.cursor_y + y) * SIZE + (self.cursor_x + x)] = buf[y * w + x];
        };

        const g = AtlasGlyph{
            .uv_left = @as(f32, @floatFromInt(self.cursor_x)) / SIZE,
            .uv_top = @as(f32, @floatFromInt(self.cursor_y)) / SIZE,
            .uv_right = @as(f32, @floatFromInt(self.cursor_x + w)) / SIZE,
            .uv_bottom = @as(f32, @floatFromInt(self.cursor_y + h)) / SIZE,
            .width = @floatFromInt(w),
            .height = @floatFromInt(h),
            .bearing_x = bx,
            .bearing_y = by,
            .advance = adv,
        };
        self.glyphs[codepoint] = g;
        self.cursor_x += w + 1;
        self.row_height = @max(self.row_height, h);
        return g;
    }

    fn uploadTexture(self: *Atlas) void {
        if (self.texture_handle != 0) return;
        self.texture_handle = imports.createTexture(SIZE, SIZE, &self.pixels, self.pixels.len);
    }
};

// =============================================================================
// App State (user-defined, like counter.zig)
// =============================================================================

const AppState = struct {
    count: i32 = 0,

    pub fn increment(self: *AppState) void {
        self.count += 1;
    }
    pub fn decrement(self: *AppState) void {
        self.count -= 1;
    }
    pub fn reset(self: *AppState) void {
        self.count = 0;
    }
};

// =============================================================================
// Global State
// =============================================================================

var platform: ?WebPlatform = null;
var window: ?*WebWindow = null;
var initialized: bool = false;

var pipeline_handle: u32 = 0;
var text_pipeline_handle: u32 = 0;
var primitive_buffer_handle: u32 = 0;
var uniform_buffer_handle: u32 = 0;
var bind_group_handle: u32 = 0;
var glyph_buffer_handle: u32 = 0;
var text_bind_group_handle: u32 = 0;
var sampler_handle: u32 = 0;

var primitives: [MAX_PRIMITIVES]unified.Primitive = undefined;
var gpu_glyphs: [MAX_GLYPHS]GpuGlyph = undefined;
var atlas: Atlas = .{};
var scene: scene_mod.Scene = undefined;
var scene_initialized: bool = false;

var app_state: AppState = .{};
var was_mouse_down: bool = false;

const unified_shader = @embedFile("unified_wgsl");
const text_shader = @embedFile("text_wgsl");
const font_name = "system-ui, -apple-system, sans-serif";

// =============================================================================
// Text Helpers
// =============================================================================

fn insertText(text: []const u8, x: f32, y: f32, scale: f32, color: scene_mod.Hsla) void {
    var cursor = x;
    for (text) |c| {
        if (atlas.getOrCreate(c, font_name, TEXT_SIZE * scale)) |g| {
            scene.insertGlyph(scene_mod.GlyphInstance.init(
                cursor + g.bearing_x,
                y + g.bearing_y,
                g.width,
                g.height,
                g.uv_left,
                g.uv_top,
                g.uv_right,
                g.uv_bottom,
                color,
            )) catch {};
            cursor += g.advance;
        }
    }
}

fn measureText(text: []const u8, scale: f32) f32 {
    var w: f32 = 0;
    for (text) |c| if (atlas.getOrCreate(c, font_name, TEXT_SIZE * scale)) |g| {
        w += g.advance;
    };
    return w;
}

// =============================================================================
// UI Building (mimics what Builder/Cx would do)
// =============================================================================

fn buildUI(viewport_w: f32, viewport_h: f32, scale: f32) void {
    scene.clear();

    const mouse_x = imports.getMouseX();
    const mouse_y = imports.getMouseY();
    const mouse_down = (imports.getMouseButtons() & 1) != 0;

    // Background
    scene.insertQuad(scene_mod.Quad.filled(0, 0, viewport_w, viewport_h, scene_mod.Hsla.init(0.58, 0.15, 0.18, 1))) catch {};

    // Card
    const card_w: f32 = 400 * scale;
    const card_h: f32 = 320 * scale;
    const card_x = (viewport_w - card_w) / 2;
    const card_y = (viewport_h - card_h) / 2 - 20 * scale;

    const card = scene_mod.Quad.rounded(card_x, card_y, card_w, card_h, scene_mod.Hsla.white, 16 * scale);
    scene.insertShadow(scene_mod.Shadow.forQuad(card, 30 * scale).withColor(scene_mod.Hsla.init(0, 0, 0, 0.25)).withOffset(0, 10 * scale)) catch {};
    scene.insertQuad(card) catch {};

    // Title
    const title = "Gooey Counter";
    insertText(title, card_x + (card_w - measureText(title, scale)) / 2, card_y + 55 * scale, scale, scene_mod.Hsla.init(0, 0, 0.2, 1));

    // Counter value
    var buf: [32]u8 = undefined;
    const count_str = std.fmt.bufPrint(&buf, "{d}", .{app_state.count}) catch "?";
    const count_color = if (app_state.count >= 0) scene_mod.Hsla.init(0.55, 0.8, 0.45, 1) else scene_mod.Hsla.init(0, 0.8, 0.5, 1);
    insertText(count_str, card_x + (card_w - measureText(count_str, scale * 2)) / 2, card_y + 150 * scale, scale * 2, count_color);

    // Buttons row
    const btn_w: f32 = 70 * scale;
    const btn_h: f32 = 50 * scale;
    const btn_y = card_y + 220 * scale;
    const gap: f32 = 15 * scale;
    const total_w = btn_w * 3 + gap * 2;
    const start_x = card_x + (card_w - total_w) / 2;

    // Minus button
    const minus_hovered = hitTest(mouse_x, mouse_y, start_x, btn_y, btn_w, btn_h);
    if (was_mouse_down and !mouse_down and minus_hovered) app_state.decrement();
    drawButton(start_x, btn_y, btn_w, btn_h, "-", minus_hovered, minus_hovered and mouse_down, scale, 0.0);

    // Plus button
    const plus_x = start_x + btn_w + gap;
    const plus_hovered = hitTest(mouse_x, mouse_y, plus_x, btn_y, btn_w, btn_h);
    if (was_mouse_down and !mouse_down and plus_hovered) app_state.increment();
    drawButton(plus_x, btn_y, btn_w, btn_h, "+", plus_hovered, plus_hovered and mouse_down, scale, 0.35);

    // Reset button
    const reset_x = start_x + (btn_w + gap) * 2;
    const reset_hovered = hitTest(mouse_x, mouse_y, reset_x, btn_y, btn_w, btn_h);
    if (was_mouse_down and !mouse_down and reset_hovered) app_state.reset();
    drawButton(reset_x, btn_y, btn_w, btn_h, "0", reset_hovered, reset_hovered and mouse_down, scale, 0.6);

    was_mouse_down = mouse_down;
    scene.finish();
}

fn hitTest(mx: f32, my: f32, x: f32, y: f32, w: f32, h: f32) bool {
    return mx >= x and mx <= x + w and my >= y and my <= y + h;
}

fn drawButton(x: f32, y: f32, w: f32, h: f32, label: []const u8, hovered: bool, pressed: bool, scale: f32, hue: f32) void {
    const lit: f32 = if (pressed) 0.35 else if (hovered) 0.5 else 0.45;
    const btn = scene_mod.Quad.rounded(x, y, w, h, scene_mod.Hsla.init(hue, 0.7, lit, 1), 8 * scale);
    const shadow_size: f32 = if (pressed) 4 * scale else 8 * scale;
    const shadow_offset: f32 = if (pressed) 2 * scale else 4 * scale;
    scene.insertShadow(scene_mod.Shadow.forQuad(btn, shadow_size).withColor(scene_mod.Hsla.init(0, 0, 0, 0.2)).withOffset(0, shadow_offset)) catch {};
    scene.insertQuad(btn) catch {};
    insertText(label, x + (w - measureText(label, scale * 0.8)) / 2, y + 33 * scale, scale * 0.8, scene_mod.Hsla.white);
}

// =============================================================================
// WASM Exports
// =============================================================================

export fn init() void {
    imports.log("Gooey Counter initializing...", .{});

    platform = WebPlatform.init() catch return;
    window = WebWindow.init(std.heap.wasm_allocator, &platform.?, .{}) catch return;
    scene = scene_mod.Scene.init(std.heap.wasm_allocator);
    scene_initialized = true;

    const shader = imports.createShaderModule(unified_shader.ptr, unified_shader.len);
    pipeline_handle = imports.createRenderPipeline(shader, "vs_main", 7, "fs_main", 7);
    const text_shader_h = imports.createShaderModule(text_shader.ptr, text_shader.len);
    text_pipeline_handle = imports.createRenderPipeline(text_shader_h, "vs_main", 7, "fs_main", 7);

    primitive_buffer_handle = imports.createBuffer(@sizeOf(unified.Primitive) * MAX_PRIMITIVES, 0x0080 | 0x0008);
    glyph_buffer_handle = imports.createBuffer(@sizeOf(GpuGlyph) * MAX_GLYPHS, 0x0080 | 0x0008);
    uniform_buffer_handle = imports.createBuffer(@sizeOf(Uniforms), 0x0040 | 0x0008);

    const bufs = [_]u32{ primitive_buffer_handle, uniform_buffer_handle };
    bind_group_handle = imports.createBindGroup(pipeline_handle, 0, &bufs, 2);

    for (32..127) |c| _ = atlas.getOrCreate(@intCast(c), font_name, 48);
    atlas.uploadTexture();
    sampler_handle = imports.createSampler();
    text_bind_group_handle = imports.createTextBindGroup(text_pipeline_handle, 0, glyph_buffer_handle, uniform_buffer_handle, atlas.texture_handle, sampler_handle);

    initialized = true;
    imports.log("Ready!", .{});
    if (platform) |*p| p.run();
}

export fn frame(timestamp: f64) void {
    _ = timestamp;
    if (!initialized) return;
    const w = window orelse return;

    const scale = w.getScaleFactor();
    const vw: f32 = @as(f32, @floatFromInt(w.width())) * scale;
    const vh: f32 = @as(f32, @floatFromInt(w.height())) * scale;

    buildUI(vw, vh, scale);

    // Convert & upload
    const prim_count = unified.convertScene(&scene, &primitives);
    var glyph_count: u32 = 0;
    for (scene.getGlyphs()) |g| {
        if (glyph_count >= MAX_GLYPHS) break;
        gpu_glyphs[glyph_count] = GpuGlyph.fromScene(g);
        glyph_count += 1;
    }

    const uniforms = Uniforms{ .viewport_width = vw, .viewport_height = vh };
    imports.writeBuffer(uniform_buffer_handle, 0, std.mem.asBytes(&uniforms).ptr, @sizeOf(Uniforms));
    if (prim_count > 0) imports.writeBuffer(primitive_buffer_handle, 0, std.mem.sliceAsBytes(primitives[0..prim_count]).ptr, @intCast(@sizeOf(unified.Primitive) * prim_count));
    if (glyph_count > 0) imports.writeBuffer(glyph_buffer_handle, 0, std.mem.sliceAsBytes(gpu_glyphs[0..glyph_count]).ptr, @intCast(@sizeOf(GpuGlyph) * glyph_count));

    // Render
    const bg = w.background_color;
    const tv = imports.getCurrentTextureView();
    imports.beginRenderPass(tv, bg.r, bg.g, bg.b, bg.a);
    if (prim_count > 0) {
        imports.setPipeline(pipeline_handle);
        imports.setBindGroup(0, bind_group_handle);
        imports.drawInstanced(6, prim_count);
    }
    if (glyph_count > 0) {
        imports.setPipeline(text_pipeline_handle);
        imports.setBindGroup(0, text_bind_group_handle);
        imports.drawInstanced(6, glyph_count);
    }
    imports.endRenderPass();
    imports.releaseTextureView(tv);

    if (platform) |p| {
        if (p.isRunning()) imports.requestAnimationFrame();
    }
}

export fn resize(w: u32, h: u32) void {
    _ = w;
    _ = h;
}
