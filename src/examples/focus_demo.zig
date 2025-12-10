//! Focus & Keyboard Navigation Demo
//!
//! Demonstrates the unified focus system with:
//! - Tab/Shift-Tab navigation between focusable elements
//! - Visual focus indicators (focus rings)
//! - Tab index ordering
//! - Focus callbacks
//!
//! Press Tab to cycle forward, Shift-Tab to cycle backward.
//! Press 1-4 to jump to specific fields.
//! Press Escape to blur all.

const std = @import("std");
const gooey = @import("gooey");
const ui = gooey.ui;

// =============================================================================
// Application State
// =============================================================================

var state = struct {
    // Form fields
    first_name: []const u8 = "",
    last_name: []const u8 = "",
    email: []const u8 = "",
    notes: []const u8 = "",

    // UI state
    status_message: []const u8 = "Press Tab to navigate between fields",
    focus_count: u32 = 0,
    last_focused: []const u8 = "(none)",
    initialized: bool = false,
}{};

// =============================================================================
// Main Entry Point
// =============================================================================

pub fn main() !void {
    try gooey.run(.{
        .title = "Focus & Keyboard Navigation Demo",
        .width = 800,
        .height = 600,
        .render = render,
        .on_event = onEvent,
    });
}

// =============================================================================
// Render Function
// =============================================================================

fn render(g: *gooey.UI) void {
    // Initialize focus on first render
    if (!state.initialized) {
        state.initialized = true;
        g.focusTextInput("first_name");
        state.last_focused = "first_name";
    }

    const size = g.windowSize();

    // Use a single root box with component children
    g.box(.{
        .width = size.width,
        .height = size.height,
        .padding = .{ .all = 24 },
        .gap = 20,
        .direction = .column,
        .background = ui.Color.rgb(0.95, 0.95, 0.97),
    }, .{
        Header{},
        MainContent{}, // Wrap the row in a component
        KeyboardHints{},
    });
}

// =============================================================================
// Components
// =============================================================================

const Header = struct {
    pub fn render(_: @This(), b: *ui.Builder) void {
        b.box(.{
            .padding = .{ .all = 16 },
            .background = ui.Color.rgb(0.2, 0.4, 0.8),
            .corner_radius = 8,
        }, .{
            ui.text("Focus & Keyboard Navigation Demo", .{
                .size = 20,
                .color = ui.Color.white,
            }),
        });
    }
};

/// Wrapper component for the main content row
const MainContent = struct {
    pub fn render(_: @This(), b: *ui.Builder) void {
        b.hstack(.{ .gap = 24 }, .{
            FormCard{},
            FocusInfoCard{},
        });
    }
};

const FormCard = struct {
    pub fn render(_: @This(), b: *ui.Builder) void {
        b.box(.{
            .padding = .{ .all = 24 },
            .gap = 16,
            .background = ui.Color.white,
            .corner_radius = 12,
            .direction = .column,
            .width = 320,
            .shadow = ui.ShadowConfig.drop(8),
        }, .{
            ui.text("Contact Form", .{
                .size = 18,
                .color = ui.Color.rgb(0.2, 0.2, 0.2),
            }),

            // Form fields with explicit tab order
            FormField{ .id = "first_name", .label = "First Name", .placeholder = "Enter first name", .bind = &state.first_name, .tab_index = 1 },
            FormField{ .id = "last_name", .label = "Last Name", .placeholder = "Enter last name", .bind = &state.last_name, .tab_index = 2 },
            FormField{ .id = "email", .label = "Email", .placeholder = "you@example.com", .bind = &state.email, .tab_index = 3 },
            FormField{ .id = "notes", .label = "Notes", .placeholder = "Optional notes...", .bind = &state.notes, .tab_index = 4 },

            ui.button("Submit Form", submitForm),
        });
    }
};

const FormField = struct {
    id: []const u8,
    label: []const u8,
    placeholder: []const u8,
    bind: *[]const u8,
    tab_index: i32,

    pub fn render(self: @This(), b: *ui.Builder) void {
        b.vstack(.{ .gap = 4 }, .{
            ui.text(self.label, .{
                .size = 12,
                .color = ui.Color.rgb(0.4, 0.4, 0.4),
            }),
            ui.input(self.id, .{
                .placeholder = self.placeholder,
                .width = 280,
                .bind = self.bind,
                .tab_index = self.tab_index,
            }),
        });
    }
};

const FocusInfoCard = struct {
    var count_buf: [64]u8 = undefined;

    pub fn render(_: @This(), b: *ui.Builder) void {
        const count_str = std.fmt.bufPrint(&count_buf, "Focus changes: {d}", .{state.focus_count}) catch "?";

        b.box(.{
            .padding = .{ .all = 24 },
            .gap = 12,
            .background = ui.Color.rgb(0.98, 0.98, 1.0),
            .corner_radius = 12,
            .direction = .column,
            .width = 300,
            .border_color = ui.Color.rgb(0.85, 0.85, 0.9),
            .border_width = 1,
        }, .{
            ui.text("Focus Status", .{
                .size = 16,
                .color = ui.Color.rgb(0.3, 0.3, 0.4),
            }),
            ui.text(state.status_message, .{
                .size = 12,
                .color = ui.Color.rgb(0.5, 0.5, 0.6),
            }),
            ui.text(count_str, .{
                .size = 14,
                .color = ui.Color.rgb(0.2, 0.4, 0.8),
            }),
            LastFocusedInfo{},
        });
    }
};

const LastFocusedInfo = struct {
    pub fn render(_: @This(), b: *ui.Builder) void {
        b.vstack(.{ .gap = 4 }, .{
            ui.text("Last focused:", .{
                .size = 11,
                .color = ui.Color.rgb(0.5, 0.5, 0.5),
            }),
            ui.text(state.last_focused, .{
                .size = 13,
                .color = ui.Color.rgb(0.2, 0.2, 0.3),
            }),
        });
    }
};

const KeyboardHints = struct {
    pub fn render(_: @This(), b: *ui.Builder) void {
        b.box(.{
            .padding = .{ .all = 12 },
            .gap = 16,
            .background = ui.Color.rgb(0.9, 0.92, 0.95),
            .corner_radius = 8,
            .direction = .row,
            .alignment = .{ .main = .center, .cross = .center },
        }, .{
            KeyHint{ .key = "Tab", .action = "Next" },
            KeyHint{ .key = "Shift+Tab", .action = "Prev" },
            KeyHint{ .key = "1-4", .action = "Jump" },
            KeyHint{ .key = "Esc", .action = "Blur" },
            KeyHint{ .key = "Enter", .action = "Submit" },
        });
    }
};

const KeyHint = struct {
    key: []const u8,
    action: []const u8,

    pub fn render(self: @This(), b: *ui.Builder) void {
        b.hstack(.{ .gap = 4 }, .{
            KeyBox{ .text = self.key },
            ui.text(self.action, .{
                .size = 11,
                .color = ui.Color.rgb(0.4, 0.4, 0.45),
            }),
        });
    }
};

const KeyBox = struct {
    text: []const u8,

    pub fn render(self: @This(), b: *ui.Builder) void {
        b.box(.{
            .padding = .{ .all = 4 },
            .background = ui.Color.rgb(0.3, 0.3, 0.35),
            .corner_radius = 4,
        }, .{
            ui.text(self.text, .{
                .size = 11,
                .color = ui.Color.white,
            }),
        });
    }
};

// =============================================================================
// Event Handlers
// =============================================================================

fn onEvent(g: *gooey.UI, event: gooey.InputEvent) bool {
    if (event != .key_down) return false;

    const key = event.key_down;

    // Tab navigation
    if (key.key == .tab) {
        if (key.modifiers.shift) {
            state.status_message = "Shift+Tab: Previous";
            g.focusPrev();
        } else {
            state.status_message = "Tab: Next";
            g.focusNext();
        }
        state.focus_count += 1;
        updateLastFocused(g);
        return true;
    }

    // Number keys to jump directly
    if (key.key == .@"1") {
        jumpToField(g, "first_name", "First Name (1)");
        return true;
    }
    if (key.key == .@"2") {
        jumpToField(g, "last_name", "Last Name (2)");
        return true;
    }
    if (key.key == .@"3") {
        jumpToField(g, "email", "Email (3)");
        return true;
    }
    if (key.key == .@"4") {
        jumpToField(g, "notes", "Notes (4)");
        return true;
    }

    // Escape to blur all
    if (key.key == .escape) {
        g.blurAll();
        state.status_message = "Focus cleared";
        state.last_focused = "(none)";
        state.focus_count += 1;
        return true;
    }

    // Enter to submit
    if (key.key == .@"return") {
        submitForm();
        return true;
    }

    return false;
}

fn jumpToField(g: *gooey.UI, field_id: []const u8, label: []const u8) void {
    g.focusTextInput(field_id);
    state.focus_count += 1;
    state.last_focused = field_id;
    state.status_message = label;
}

fn updateLastFocused(g: *gooey.UI) void {
    if (g.isElementFocused("first_name")) {
        state.last_focused = "first_name";
    } else if (g.isElementFocused("last_name")) {
        state.last_focused = "last_name";
    } else if (g.isElementFocused("email")) {
        state.last_focused = "email";
    } else if (g.isElementFocused("notes")) {
        state.last_focused = "notes";
    }
}

fn submitForm() void {
    if (state.first_name.len == 0) {
        state.status_message = "Error: First name required";
    } else if (state.email.len == 0) {
        state.status_message = "Error: Email required";
    } else {
        state.status_message = "Form submitted!";
    }
}
