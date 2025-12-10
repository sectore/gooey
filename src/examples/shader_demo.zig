const std = @import("std");
const gooey = @import("gooey");
const ui = gooey.ui;

// Import the built-in shaders
const custom_shader = gooey.platform.mac.metal.custom_shader;

pub fn main() !void {
    try gooey.run(.{
        .title = "Shader Demo",
        .width = 800,
        .height = 600,
        .render = render,
        .custom_shaders = &.{ custom_shader.blur_shader, custom_shader.crt_shader },
    });
}

fn render(g: *gooey.UI) void {
    g.center(.{}, .{
        ShaderContent{},
    });
}

const ShaderContent = struct {
    pub fn render(_: @This(), b: *ui.Builder) void {
        b.vstack(.{ .gap = 24, .alignment = .center }, .{
            ui.text("Custom Shaders!", .{ .size = 48 }),
            ui.text("Watch the CRT effect", .{ .size = 24 }),
            BlueBox{},
        });
    }
};

const BlueBox = struct {
    pub fn render(_: @This(), b: *ui.Builder) void {
        b.box(.{
            .width = 300,
            .height = 150,
            .background = ui.Color.rgb(0.2, 0.6, 1.0),
            .corner_radius = 12,
        }, .{});
    }
};
