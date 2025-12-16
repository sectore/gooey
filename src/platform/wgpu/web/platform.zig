//! WebPlatform - Platform implementation for WebAssembly/Browser

const std = @import("std");
const imports = @import("imports.zig");

pub const WebPlatform = struct {
    running: bool = true,

    const Self = @This();

    pub fn init() !Self {
        return .{ .running = true };
    }

    pub fn deinit(self: *Self) void {
        self.running = false;
    }

    /// On web, run() kicks off the animation loop (non-blocking)
    pub fn run(self: *Self) void {
        if (self.running) {
            imports.requestAnimationFrame();
        }
    }

    pub fn quit(self: *Self) void {
        self.running = false;
    }

    pub fn isRunning(self: *const Self) bool {
        return self.running;
    }
};
