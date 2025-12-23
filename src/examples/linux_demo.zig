//! Linux Demo - Simple colored quad rendering with Wayland + wgpu
//!
//! This demo shows the basic usage of gooey on Linux:
//! - Create a Wayland window
//! - Render colored quads using wgpu-native
//! - Handle the event loop

const std = @import("std");
const gooey = @import("gooey");

const platform = gooey.platform;
const Platform = platform.Platform;
const Window = platform.Window;
const Scene = gooey.Scene;
const Hsla = gooey.Hsla;
const Corners = gooey.core.scene.Corners;
const Edges = gooey.core.scene.Edges;
const Color = gooey.Color;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Initializing Linux platform...\n", .{});

    // Initialize platform
    var plat = try Platform.init();
    defer plat.deinit();

    std.debug.print("Platform initialized. Creating window...\n", .{});

    // Create window
    var window = try Window.init(allocator, &plat, .{
        .title = "Gooey Linux Demo",
        .width = 800,
        .height = 600,
        .background_color = Color.init(0.1, 0.1, 0.15, 1.0),
    });
    defer window.deinit();

    std.debug.print("Window created. Setting up scene...\n", .{});

    // Create a simple scene with colored quads
    var scene = Scene.init(allocator);
    defer scene.deinit();

    // Add some colorful quads
    // Red quad - top left
    scene.addQuad(.{
        .order = 0,
        .bounds_origin_x = 50,
        .bounds_origin_y = 50,
        .bounds_size_width = 200,
        .bounds_size_height = 150,
        .background = Hsla.init(0.0, 0.8, 0.5, 1.0), // Red
        .corner_radii = Corners.all(12),
    });

    // Green quad - top right
    scene.addQuad(.{
        .order = 1,
        .bounds_origin_x = 300,
        .bounds_origin_y = 50,
        .bounds_size_width = 200,
        .bounds_size_height = 150,
        .background = Hsla.init(0.33, 0.8, 0.5, 1.0), // Green
        .corner_radii = Corners.all(12),
    });

    // Blue quad - bottom left
    scene.addQuad(.{
        .order = 2,
        .bounds_origin_x = 50,
        .bounds_origin_y = 250,
        .bounds_size_width = 200,
        .bounds_size_height = 150,
        .background = Hsla.init(0.66, 0.8, 0.5, 1.0), // Blue
        .corner_radii = Corners.all(12),
    });

    // Purple quad - bottom right (with border)
    scene.addQuad(.{
        .order = 3,
        .bounds_origin_x = 300,
        .bounds_origin_y = 250,
        .bounds_size_width = 200,
        .bounds_size_height = 150,
        .background = Hsla.init(0.8, 0.7, 0.5, 1.0), // Purple
        .border_color = Hsla.init(0.8, 0.9, 0.7, 1.0), // Lighter purple border
        .corner_radii = Corners.all(12),
        .border_widths = Edges.all(3),
    });

    // Central overlapping quad with shadow
    scene.addShadow(.{
        .order = 4,
        .content_origin_x = 200,
        .content_origin_y = 175,
        .content_size_width = 200,
        .content_size_height = 150,
        .blur_radius = 20,
        .offset_x = 5,
        .offset_y = 5,
        .color = Hsla.init(0, 0, 0, 0.4),
        .corner_radii = Corners.all(16),
    });

    scene.addQuad(.{
        .order = 5,
        .bounds_origin_x = 200,
        .bounds_origin_y = 175,
        .bounds_size_width = 200,
        .bounds_size_height = 150,
        .background = Hsla.init(0.5, 0.9, 0.95, 1.0), // Cyan/white
        .corner_radii = Corners.all(16),
    });

    // Set scene on window
    window.setScene(&scene);
    window.requestRender();

    std.debug.print("Scene ready. Running event loop...\n", .{});
    std.debug.print("Press Ctrl+C to exit or close the window.\n", .{});

    // Run the event loop
    while (plat.isRunning() and !window.isClosed()) {
        // Poll for events
        if (!plat.poll()) break;

        // Render if needed
        window.renderFrame();
    }

    std.debug.print("Shutting down...\n", .{});
}
