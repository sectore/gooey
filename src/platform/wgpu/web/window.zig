//! WebWindow - Window implementation for WebAssembly/Browser

const std = @import("std");
const imports = @import("imports.zig");

pub const WebWindow = struct {
    allocator: std.mem.Allocator,
    background_color: struct { r: f32, g: f32, b: f32, a: f32 } = .{ .r = 0.1, .g = 0.1, .b = 0.15, .a = 1.0 },

    const Self = @This();

    pub const Options = struct {
        title: []const u8 = "Gooey",
        width: f64 = 800,
        height: f64 = 600,
        background_color: struct { r: f64, g: f64, b: f64, a: f64 } = .{ .r = 0.95, .g = 0.95, .b = 0.95, .a = 1.0 },
    };

    pub fn init(allocator: std.mem.Allocator, _: anytype, options: Options) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .background_color = .{
                .r = @floatCast(options.background_color.r),
                .g = @floatCast(options.background_color.g),
                .b = @floatCast(options.background_color.b),
                .a = @floatCast(options.background_color.a),
            },
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }

    pub fn width(_: *const Self) u32 {
        return imports.getCanvasWidth();
    }

    pub fn height(_: *const Self) u32 {
        return imports.getCanvasHeight();
    }

    pub fn getScaleFactor(_: *const Self) f32 {
        return imports.getDevicePixelRatio();
    }

    pub fn getMouseX(_: *const Self) f32 {
        return imports.getMouseX();
    }

    pub fn getMouseY(_: *const Self) f32 {
        return imports.getMouseY();
    }

    pub fn isMouseInside(_: *const Self) bool {
        return imports.isMouseInCanvas();
    }
};
