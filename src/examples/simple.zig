//! Simple Counter Example
//!
//! Demonstrates the minimal gooey.run() API with:
//! - Plain struct state (no wrappers!)
//! - Button click handling
//! - Component composition
//!
//! This is the simplest way to build a gooey app.

const std = @import("std");
const gooey = @import("gooey");

// UI module for declarative primitives
const ui = gooey.ui;

// =============================================================================
// Application State - just a plain struct!
// =============================================================================

var state = struct {
    count: i32 = 0,
    message: []const u8 = "Click the buttons! 🎉",
}{};

// =============================================================================
// Components - structs with render()
// =============================================================================

/// Counter display component
const Counter = struct {
    var count_buf: [32]u8 = undefined;

    pub fn render(_: @This(), b: *ui.Builder) void {
        const count_str = std.fmt.bufPrint(&count_buf, "{d}", .{state.count}) catch "?";

        b.vstack(.{ .gap = 8, .alignment = .center }, .{
            ui.text("Count:", .{ .size = 16, .color = ui.Color.rgb(0.3, 0.3, 0.3) }),
            ui.text(count_str, .{ .size = 48 }),
        });
    }
};

/// Button row component
const ButtonRow = struct {
    pub fn render(_: @This(), b: *ui.Builder) void {
        b.hstack(.{ .gap = 12 }, .{
            ui.button("- Decrease", decrement),
            ui.button("+ Increase", increment),
        });
    }
};

/// Card container component
const Card = struct {
    pub fn render(_: @This(), b: *ui.Builder) void {
        b.box(.{
            .padding = .{ .all = 32 },
            .gap = 20,
            .background = ui.Color.white,
            .corner_radius = 12,
            .alignment = .{ .main = .center, .cross = .center },
            .direction = .column,
        }, .{
            ui.text(state.message, .{ .size = 14, .color = ui.Color.rgb(0.5, 0.5, 0.5) }),
            Counter{},
            ButtonRow{},
            ui.button("Reset", reset),
        });
    }
};

// =============================================================================
// Entry Point
// =============================================================================

pub fn main() !void {
    try gooey.run(.{
        .title = "Simple Counter",
        .width = 400,
        .height = 300,
        .render = render,
        .on_event = onEvent,
    });
}

fn render(g: *gooey.UI) void {
    const size = g.windowSize();

    g.boxWithId("root", .{
        .width = size.width,
        .height = size.height,
        .alignment = .{ .main = .center, .cross = .center },
    }, .{
        Card{},
    });
}

// =============================================================================
// Event Handlers
// =============================================================================

fn increment() void {
    state.count += 1;
    state.message = "Incremented! 🚀";
}

fn decrement() void {
    state.count -= 1;
    state.message = "Decremented! 📉";
}

fn reset() void {
    state.count = 0;
    state.message = "Reset! 🔄";
}

fn onEvent(_: *gooey.UI, event: gooey.InputEvent) bool {
    if (event == .key_down and event.key_down.key == .escape) {
        return true;
    }
    return false;
}
