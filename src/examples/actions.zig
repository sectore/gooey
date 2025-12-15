const std = @import("std");
const gooey = @import("gooey");
const ui = gooey.ui;
const Button = gooey.Button;

// Define action types
const Undo = struct {};
const Redo = struct {};
const Save = struct {};
const Cancel = struct {};

var state = struct {
    message: []const u8 = "",
    initialized: bool = false,
}{};

pub fn main() !void {
    try gooey.run(.{
        .title = "Actions Demo",
        .render = render,
    });
}

fn setupKeymap(g: *gooey.UI) void {
    if (state.initialized) return;
    state.initialized = true;

    g.gooey.keymap.bind(Undo, "cmd-z", null);
    g.gooey.keymap.bind(Redo, "cmd-shift-z", null);
    g.gooey.keymap.bind(Save, "cmd-s", "Editor");
    g.gooey.keymap.bind(Cancel, "escape", null);
}

fn render(g: *gooey.UI) void {
    setupKeymap(g);

    g.box(.{ .padding = .{ .all = 24 }, .gap = 16, .direction = .column }, .{
        ui.onAction(Undo, doUndo),
        ui.onAction(Redo, doRedo),
        ui.onAction(Cancel, doCancel),

        ui.text("Actions Demo", .{ .size = 24 }),
        ui.text(state.message, .{}),

        EditorPanel{},
        ButtonRow{},
    });
}

const EditorPanel = struct {
    pub fn render(_: @This(), b: *ui.Builder) void {
        b.box(.{
            .background = ui.Color.rgb(0.95, 0.95, 0.95),
        }, .{
            // Now these work! Processed during child rendering
            ui.keyContext("Editor"),
            ui.onAction(Save, save),

            ui.input("editor", .{ .placeholder = "Type here... (cmd+s to save)" }),
        });
    }
};

const ButtonRow = struct {
    pub fn render(_: @This(), b: *ui.Builder) void {
        b.hstack(.{
            .gap = 8,
        }, .{
            Button{ .label = "Undo (cmd+z)", .on_click = doUndo },
            Button{ .label = "Redo (cmd+shift+z)", .on_click = doRedo },
        });
    }
};

fn doUndo() void {
    state.message = "Undo!";
}
fn doRedo() void {
    state.message = "Redo!";
}
fn doCancel() void {
    state.message = "Cancelled!";
}
fn save() void {
    state.message = "Saved!";
}
