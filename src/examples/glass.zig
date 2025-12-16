//! Liquid Glass Effect Demo
//!
//! Demonstrates the liquid glass transparency effect available on macOS 26.0+ (Tahoe).
//! On older macOS versions, falls back to traditional background blur.
//!
//! Run with: zig build run-glass

const std = @import("std");
const gooey = @import("gooey");
const ui = gooey.ui;
const Cx = gooey.Cx;
const Button = gooey.Button;
const Color = ui.Color;

const AppState = struct {
    glass_style: GlassStyle = .glass_regular,
    opacity: f32 = 0.7,
    corner_radius: f32 = 20.0,

    const GlassStyle = enum {
        none,
        blur,
        glass_regular,
        glass_clear,

        pub fn name(self: GlassStyle) []const u8 {
            return switch (self) {
                .none => "None (transparent only)",
                .blur => "Traditional Blur",
                .glass_regular => "Liquid Glass (Regular)",
                .glass_clear => "Liquid Glass (Clear)",
            };
        }

        pub fn next(self: GlassStyle) GlassStyle {
            return switch (self) {
                .none => .blur,
                .blur => .glass_regular,
                .glass_regular => .glass_clear,
                .glass_clear => .none,
            };
        }
    };

    pub fn cycleStyle(self: *AppState) void {
        self.glass_style = self.glass_style.next();
    }

    pub fn increaseOpacity(self: *AppState) void {
        self.opacity = @min(1.0, self.opacity + 0.1);
    }

    pub fn decreaseOpacity(self: *AppState) void {
        self.opacity = @max(0.1, self.opacity - 0.1);
    }

    pub fn increaseRadius(self: *AppState) void {
        self.corner_radius = @min(50.0, self.corner_radius + 5.0);
    }

    pub fn decreaseRadius(self: *AppState) void {
        self.corner_radius = @max(0.0, self.corner_radius - 5.0);
    }
};

// Colors
const text_color = Color.rgba(1, 1, 1, 0.95);
const text_muted = Color.rgba(1, 1, 1, 0.6);
const card_bg = Color.rgba(1, 1, 1, 0.1);

pub fn main() !void {
    var state = AppState{};

    try gooey.runCx(AppState, &state, render, .{
        .title = "Liquid Glass Demo",
        .width = 500,
        .height = 400,
        .background_color = gooey.Color.init(0.1, 0.1, 0.15, 0.6),
        // Enable transparency - required for glass effects
        .background_opacity = 0.3,
        // Request liquid glass (falls back to blur on older macOS)
        .glass_style = .glass_clear,
        .glass_corner_radius = 20.0,
    });
}

fn render(cx: *Cx) void {
    const s = cx.state(AppState);
    const size = cx.windowSize();

    cx.box(.{
        .width = size.width,
        .height = size.height,
        .padding = .{ .all = 24 },
        .direction = .column,
        .gap = 16,
    }, .{
        // Title
        ui.text("Liquid Glass Demo", .{
            .size = 28,
            .color = text_color,
        }),

        // Subtitle
        ui.text("Transparent window with glass effect", .{
            .size = 14,
            .color = text_muted,
        }),

        ui.spacer(),

        // Current style display
        cx.box(.{
            .padding = .{ .all = 16 },
            .corner_radius = 12,
            .background = card_bg,
            .direction = .column,
            .gap = 8,
        }, .{
            ui.textFmt("Style: {s}", .{s.glass_style.name()}, .{
                .size = 16,
                .color = text_color,
            }),
            ui.textFmt("Opacity: {d:.0}%", .{s.opacity * 100}, .{
                .size = 14,
                .color = text_muted,
            }),
            ui.textFmt("Corner Radius: {d:.0}pt", .{s.corner_radius}, .{
                .size = 14,
                .color = text_muted,
            }),
        }),

        // Controls
        cx.hstack(.{ .gap = 8 }, .{
            Button{
                .label = "Cycle Style",
                .on_click_handler = cx.update(AppState, AppState.cycleStyle),
            },
            Button{
                .label = "- Opacity",
                .variant = .secondary,
                .on_click_handler = cx.update(AppState, AppState.decreaseOpacity),
            },
            Button{
                .label = "+ Opacity",
                .variant = .secondary,
                .on_click_handler = cx.update(AppState, AppState.increaseOpacity),
            },
        }),

        cx.hstack(.{ .gap = 8 }, .{
            Button{
                .label = "- Radius",
                .variant = .secondary,
                .on_click_handler = cx.update(AppState, AppState.decreaseRadius),
            },
            Button{
                .label = "+ Radius",
                .variant = .secondary,
                .on_click_handler = cx.update(AppState, AppState.increaseRadius),
            },
        }),

        ui.spacer(),

        // Info text
        ui.text("Note: Liquid Glass requires macOS 26.0+ (Tahoe)", .{
            .size = 11,
            .color = text_muted,
        }),
        ui.text("Older versions fall back to traditional blur", .{
            .size = 11,
            .color = text_muted,
        }),
    });
}
