//! Application context - the main entry point for a guiz application

const std = @import("std");
const platform = @import("../platform/mac/platform.zig");
const Window = @import("../platform/mac/window.zig").Window;
const geometry = @import("geometry.zig");

pub const App = struct {
    platform: platform.MacPlatform,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        return .{
            .platform = try platform.MacPlatform.init(),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.platform.deinit();
    }

    pub fn createWindow(self: *Self, options: Window.Options) !*Window {
        return try Window.init(self.allocator, &self.platform, options);
    }

    pub fn run(self: *Self, callback: ?*const fn (*Self) void) void {
        self.platform.run(self, callback);
    }

    pub fn quit(self: *Self) void {
        self.platform.quit();
    }
};
