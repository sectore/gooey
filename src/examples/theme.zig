//! Theme System Example
//!
//! Demonstrates:
//! - Single entity observed by many components
//! - Cross-cutting concerns (theme affects everything)
//! - Real-time updates when theme changes
//! - b.readEntity() for simple observation (Phase 3)

const std = @import("std");
const gooey = @import("gooey");
const ui = gooey.ui;

// =============================================================================
// Theme Model
// =============================================================================

const Theme = struct {
    mode: Mode = .light,
    accent: AccentColor = .blue,
    font_size: FontSize = .medium,

    const Mode = enum {
        light,
        dark,

        fn background(self: Mode) ui.Color {
            return switch (self) {
                .light => ui.Color.rgb(0.95, 0.95, 0.95),
                .dark => ui.Color.rgb(0.12, 0.12, 0.14),
            };
        }

        fn card(self: Mode) ui.Color {
            return switch (self) {
                .light => ui.Color.white,
                .dark => ui.Color.rgb(0.2, 0.2, 0.22),
            };
        }

        fn text(self: Mode) ui.Color {
            return switch (self) {
                .light => ui.Color.rgb(0.1, 0.1, 0.1),
                .dark => ui.Color.rgb(0.9, 0.9, 0.9),
            };
        }

        fn subtle(self: Mode) ui.Color {
            return switch (self) {
                .light => ui.Color.rgb(0.5, 0.5, 0.5),
                .dark => ui.Color.rgb(0.6, 0.6, 0.6),
            };
        }
    };

    const AccentColor = enum {
        blue,
        green,
        purple,
        orange,

        fn color(self: AccentColor) ui.Color {
            return switch (self) {
                .blue => ui.Color.rgb(0.2, 0.5, 1.0),
                .green => ui.Color.rgb(0.2, 0.8, 0.4),
                .purple => ui.Color.rgb(0.6, 0.3, 0.9),
                .orange => ui.Color.rgb(1.0, 0.5, 0.2),
            };
        }

        fn name(self: AccentColor) []const u8 {
            return switch (self) {
                .blue => "Blue",
                .green => "Green",
                .purple => "Purple",
                .orange => "Orange",
            };
        }
    };

    const FontSize = enum {
        small,
        medium,
        large,

        fn size(self: FontSize) f32 {
            return switch (self) {
                .small => 12,
                .medium => 16,
                .large => 20,
            };
        }

        fn name(self: FontSize) []const u8 {
            return switch (self) {
                .small => "Small",
                .medium => "Medium",
                .large => "Large",
            };
        }
    };

    pub fn toggleMode(self: *Theme, cx: *gooey.EntityContext(Theme)) void {
        self.mode = if (self.mode == .light) .dark else .light;
        cx.notify(); // All observers update!
    }

    pub fn cycleAccent(self: *Theme, cx: *gooey.EntityContext(Theme)) void {
        self.accent = switch (self.accent) {
            .blue => .green,
            .green => .purple,
            .purple => .orange,
            .orange => .blue,
        };
        cx.notify();
    }

    pub fn cycleSize(self: *Theme, cx: *gooey.EntityContext(Theme)) void {
        self.font_size = switch (self.font_size) {
            .small => .medium,
            .medium => .large,
            .large => .small,
        };
        cx.notify();
    }
};

var theme_entity: gooey.Entity(Theme) = gooey.Entity(Theme).nil();
var initialized = false;

// =============================================================================
// Components - All observe the theme!
// =============================================================================

const ThemeControls = struct {
    theme: gooey.Entity(Theme),

    pub fn render(self: @This(), b: *ui.Builder) void {
        const t = b.readEntity(Theme, self.theme) orelse return;
        var cx = b.entityContext(Theme, self.theme) orelse return;

        b.box(.{
            .padding = .{ .all = 20 },
            .gap = 16,
            .background = t.mode.card(),
            .corner_radius = 12,
            .direction = .column,
        }, .{
            ui.text("Theme Settings", .{ .size = @as(u16, @intFromFloat(t.font_size.size())) + 4, .color = t.mode.text() }),

            b.hstack(.{ .gap = 12, .alignment = .center }, .{
                ui.text("Mode:", .{ .size = @as(u16, @intFromFloat(t.font_size.size())), .color = t.mode.subtle() }),
                ui.buttonHandler(
                    if (t.mode == .light) "☀ Light" else "☾ Dark",
                    cx.handler(Theme.toggleMode),
                ),
            }),

            b.hstack(.{ .gap = 12, .alignment = .center }, .{
                ui.text("Accent:", .{ .size = @as(u16, @intFromFloat(t.font_size.size())), .color = t.mode.subtle() }),
                ui.buttonHandler(t.accent.name(), cx.handler(Theme.cycleAccent)),
                b.box(.{
                    .width = 24,
                    .height = 24,
                    .background = t.accent.color(),
                    .corner_radius = 12,
                }, .{}),
            }),

            b.hstack(.{ .gap = 12, .alignment = .center }, .{
                ui.text("Size:", .{ .size = @as(u16, @intFromFloat(t.font_size.size())), .color = t.mode.subtle() }),
                ui.buttonHandler(t.font_size.name(), cx.handler(Theme.cycleSize)),
            }),
        });
    }
};

const PreviewCard = struct {
    theme: gooey.Entity(Theme),
    title: []const u8,
    content: []const u8,

    pub fn render(self: @This(), b: *ui.Builder) void {
        const t = b.readEntity(Theme, self.theme) orelse return;

        b.box(.{
            .padding = .{ .all = 20 },
            .gap = 12,
            .background = t.mode.card(),
            .corner_radius = 12,
            .direction = .column,
            .min_width = 200,
            .shadow = .{ .blur_radius = 10, .color = ui.Color.rgba(0, 0, 0, 0.15) },
        }, .{
            ui.text(self.title, .{ .size = @as(u16, @intFromFloat(t.font_size.size())) + 2, .color = t.accent.color() }),
            ui.text(self.content, .{ .size = @as(u16, @intFromFloat(t.font_size.size())), .color = t.mode.text() }),
            b.box(.{
                .padding = .{ .symmetric = .{ .x = 16, .y = 8 } },
                .background = t.accent.color(),
                .corner_radius = 6,
            }, .{
                ui.text("Action", .{ .size = @as(u16, @intFromFloat(t.font_size.size())), .color = ui.Color.white }),
            }),
        });
    }
};

// =============================================================================
// Entry Point
// =============================================================================

pub fn main() !void {
    try gooey.run(.{
        .title = "Theme System",
        .width = 700,
        .height = 500,
        .render = render,
    });
}

fn render(g: *gooey.UI) void {
    const gooey_ctx = g.gooey;

    if (!initialized) {
        initialized = true;
        theme_entity = gooey_ctx.createEntity(Theme, .{}) catch return;
    }

    const t = gooey_ctx.readEntity(Theme, theme_entity) orelse return;
    const size = g.windowSize();

    g.box(.{
        .width = size.width,
        .height = size.height,
        .background = t.mode.background(),
        .padding = .{ .all = 32 },
        .gap = 24,
        .direction = .column,
    }, .{
        ui.text("Theme System Demo", .{ .size = 28, .color = t.mode.text() }),
        ui.text("Change theme settings - all components update instantly!", .{
            .size = @as(u16, @intFromFloat(t.font_size.size())),
            .color = t.mode.subtle(),
        }),
        MainContent{ .theme = theme_entity },
    });
}

/// Main content layout - uses component to enable nesting
const MainContent = struct {
    theme: gooey.Entity(Theme),

    pub fn render(self: @This(), b: *ui.Builder) void {
        b.hstack(.{ .gap = 24 }, .{
            ThemeControls{ .theme = self.theme },
            PreviewCards{ .theme = self.theme },
        });
    }
};

/// Preview cards column
const PreviewCards = struct {
    theme: gooey.Entity(Theme),

    pub fn render(self: @This(), b: *ui.Builder) void {
        b.vstack(.{ .gap = 16 }, .{
            PreviewCard{
                .theme = self.theme,
                .title = "Preview Card",
                .content = "This card observes the theme entity and updates automatically.",
            },
            PreviewCard{
                .theme = self.theme,
                .title = "Another Card",
                .content = "Multiple components can observe the same entity.",
            },
        });
    }
};
