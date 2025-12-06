//! macOS Platform implementation using Cocoa/AppKit

const std = @import("std");
const objc = @import("objc");
const App = @import("../../core/app.zig").App;

// External Foundation constant - linked at runtime
extern "c" const NSDefaultRunLoopMode: *anyopaque;

pub const MacPlatform = struct {
    app: objc.Object,
    delegate: ?objc.Object,
    running: bool,

    const Self = @This();

    pub fn init() !Self {
        // Get NSApplication class
        const NSApp = objc.getClass("NSApplication") orelse return error.ClassNotFound;

        // Get shared application instance
        const app = NSApp.msgSend(objc.Object, "sharedApplication", .{});

        // Set activation policy to regular (foreground app)
        _ = app.msgSend(bool, "setActivationPolicy:", .{@as(i64, 0)}); // NSApplicationActivationPolicyRegular

        return .{
            .app = app,
            .delegate = null,
            .running = false,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
        // NSApplication is a singleton, don't release
    }

    pub fn run(self: *Self, app_ctx: *App, callback: ?*const fn (*App) void) void {
        _ = callback;
        _ = app_ctx;

        // Create autorelease pool
        const NSAutoreleasePoolClass = objc.getClass("NSAutoreleasePool") orelse return;
        const pool = NSAutoreleasePoolClass.msgSend(objc.Object, "alloc", .{});
        const pool_init = pool.msgSend(objc.Object, "init", .{});
        defer pool_init.msgSend(void, "drain", .{});

        self.running = true;

        // Activate the app
        _ = self.app.msgSend(void, "activateIgnoringOtherApps:", .{true});

        // Finish launching
        _ = self.app.msgSend(void, "finishLaunching", .{});

        // Run the event loop manually so we have control
        while (self.running) {
            // Create an inner autorelease pool for each iteration
            const inner_pool = NSAutoreleasePoolClass.msgSend(objc.Object, "alloc", .{});
            const inner_pool_init = inner_pool.msgSend(objc.Object, "init", .{});
            defer inner_pool_init.msgSend(void, "drain", .{});

            // Poll for events using the extern NSDefaultRunLoopMode
            const event = self.app.msgSend(
                ?*anyopaque,
                "nextEventMatchingMask:untilDate:inMode:dequeue:",
                .{
                    @as(u64, 0xFFFFFFFFFFFFFFFF), // NSEventMaskAny
                    @as(?*anyopaque, null), // distantPast - don't wait
                    NSDefaultRunLoopMode,
                    true,
                },
            );

            if (event) |e| {
                self.app.msgSend(void, "sendEvent:", .{e});
            }

            // Brief sleep to avoid spinning
            std.Thread.sleep(16 * std.time.ns_per_ms); // ~60fps
        }
    }

    pub fn quit(self: *Self) void {
        self.running = false;
        _ = self.app.msgSend(void, "terminate:", .{@as(?*anyopaque, null)});
    }
};
