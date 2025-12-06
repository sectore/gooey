//! Guiz Demo Application
//! Displays a window with a Metal-rendered background

const std = @import("std");
const guiz = @import("guiz");

pub fn main() !void {
    std.debug.print("Starting Guiz...\n", .{});

    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create the application
    var app = try guiz.App.init(allocator);
    defer app.deinit();

    // Create a window with custom options
    const window = try app.createWindow(.{
        .title = "Guiz - GPU UI Framework",
        .width = 1024,
        .height = 768,
        .background_color = guiz.Color.init(0.1, 0.1, 0.15, 1.0), // Dark blue-gray
    });
    defer window.deinit();

    std.debug.print("Window created: {s}\n", .{window.title});
    std.debug.print("Size: {d}x{d}\n", .{ window.size.width, window.size.height });

    // Run the application event loop
    // This will block until the application quits
    app.run(null);

    std.debug.print("Guiz shutting down.\n", .{});
}

test "basic geometry" {
    const size = guiz.Size(f64).init(100, 200);
    try std.testing.expectEqual(@as(f64, 100), size.width);
    try std.testing.expectEqual(@as(f64, 200), size.height);

    const color = guiz.Color.rgb(1.0, 0.5, 0.0);
    try std.testing.expectEqual(@as(f32, 1.0), color.r);
    try std.testing.expectEqual(@as(f32, 0.5), color.g);
    try std.testing.expectEqual(@as(f32, 0.0), color.b);
    try std.testing.expectEqual(@as(f32, 1.0), color.a);
}
