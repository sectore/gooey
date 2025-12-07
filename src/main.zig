//! Guiz Demo Application
//! Displays a window with quad primitives

const std = @import("std");
const guiz = @import("guiz");

pub fn main() !void {
    std.debug.print("Starting Guiz...\n", .{});
    std.debug.print("Quad size: {} bytes\n", .{@sizeOf(guiz.Quad)});
    std.debug.print("Offsets: order={}, _pad0={}, bounds_origin_x={}, bounds_origin_y={}, bounds_size_width={}, bounds_size_height={}\n", .{
        @offsetOf(guiz.Quad, "order"),
        @offsetOf(guiz.Quad, "_pad0"),
        @offsetOf(guiz.Quad, "bounds_origin_x"),
        @offsetOf(guiz.Quad, "bounds_origin_y"),
        @offsetOf(guiz.Quad, "bounds_size_width"),
        @offsetOf(guiz.Quad, "bounds_size_height"),
    });
    std.debug.print("Offsets: clip_origin_x={}, clip_origin_y={}, clip_size_width={}, clip_size_height={}, background={}\n", .{
        @offsetOf(guiz.Quad, "clip_origin_x"),
        @offsetOf(guiz.Quad, "clip_origin_y"),
        @offsetOf(guiz.Quad, "clip_size_width"),
        @offsetOf(guiz.Quad, "clip_size_height"),
        @offsetOf(guiz.Quad, "background"),
    });

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try guiz.App.init(allocator);
    defer app.deinit();

    // Create a window
    var window = try app.createWindow(.{
        .title = "Guiz - Quad Rendering Demo",
        .width = 1024,
        .height = 768,
        .background_color = guiz.Color.init(0.1, 0.1, 0.15, 1.0),
    });
    defer window.deinit();

    // Create a scene with some quads
    var scene = guiz.Scene.init(allocator);
    defer scene.deinit();

    // Red rectangle
    try scene.insertQuad(guiz.Quad.filled(50, 50, 200, 150, guiz.Hsla.red));

    // Blue rounded rectangle
    try scene.insertQuad(guiz.Quad.rounded(300, 50, 200, 150, guiz.Hsla.blue, 20));

    // Green rectangle with border
    try scene.insertQuad(
        guiz.Quad.filled(550, 50, 200, 150, guiz.Hsla.green)
            .withBorder(guiz.Hsla.white, 3),
    );

    // Semi-transparent overlay with large corner radius
    try scene.insertQuad(
        guiz.Quad.rounded(100, 250, 300, 200, guiz.Hsla.init(0.6, 0.8, 0.5, 0.7), 40),
    );

    // Nested rounded rectangles
    try scene.insertQuad(guiz.Quad.rounded(500, 300, 250, 180, guiz.Hsla.init(0.9, 0.7, 0.3, 1.0), 15));
    try scene.insertQuad(guiz.Quad.rounded(520, 320, 210, 140, guiz.Hsla.init(0.1, 0.9, 0.6, 1.0), 10));

    scene.finish();

    // Store scene in window for rendering
    window.setScene(&scene);

    std.debug.print("Window created with {} quads\n", .{scene.quadCount()});

    app.run(null);

    std.debug.print("Guiz shutting down.\n", .{});
}
