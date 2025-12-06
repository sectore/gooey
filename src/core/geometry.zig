//! Core geometry types for the UI framework

const std = @import("std");

/// A 2D size with width and height
pub fn Size(comptime T: type) type {
    return struct {
        width: T,
        height: T,

        const Self = @This();

        pub fn init(width: T, height: T) Self {
            return .{ .width = width, .height = height };
        }

        pub fn zero() Self {
            return .{ .width = 0, .height = 0 };
        }
    };
}

/// A 2D point with x and y coordinates
pub fn Point(comptime T: type) type {
    return struct {
        x: T,
        y: T,

        const Self = @This();

        pub fn init(x: T, y: T) Self {
            return .{ .x = x, .y = y };
        }

        pub fn zero() Self {
            return .{ .x = 0, .y = 0 };
        }
    };
}

/// A rectangle with origin and size
pub fn Rect(comptime T: type) type {
    return struct {
        origin: Point(T),
        size: Size(T),

        const Self = @This();

        pub fn init(x: T, y: T, width: T, height: T) Self {
            return .{
                .origin = Point(T).init(x, y),
                .size = Size(T).init(width, height),
            };
        }

        pub fn zero() Self {
            return .{
                .origin = Point(T).zero(),
                .size = Size(T).zero(),
            };
        }
    };
}

/// RGBA color with components in 0.0-1.0 range
pub const Color = struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,

    pub fn init(r: f32, g: f32, b: f32, a: f32) Color {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    pub fn rgb(r: f32, g: f32, b: f32) Color {
        return init(r, g, b, 1.0);
    }

    pub const white = Color.rgb(1.0, 1.0, 1.0);
    pub const black = Color.rgb(0.0, 0.0, 0.0);
    pub const red = Color.rgb(1.0, 0.0, 0.0);
    pub const green = Color.rgb(0.0, 1.0, 0.0);
    pub const blue = Color.rgb(0.0, 0.0, 1.0);
    pub const clear = Color.init(0.0, 0.0, 0.0, 0.0);
};
