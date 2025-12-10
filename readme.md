# Gooey

A minimal GPU-accelerated UI framework for Zig, targeting macOS with Metal rendering.

> ⚠️ **Early Development**: macOS-only. API is evolving.

<img src="https://github.com/duanebester/gooey/blob/main/assets/screenshots/gooey.png" height="400px" />

## Features

- **Metal Rendering** - Hardware-accelerated with MSAA anti-aliasing
- **CVDisplayLink VSync** - Smooth 60Hz - 240Hz frame-paced rendering
- **Immediate-Mode Layout** - Clay-inspired declarative layout system
- **Retained Widgets** - TextInput with full IME/composition support
- **Text Rendering** - CoreText font loading, HarfBuzz shaping, glyph atlas caching
- **Simple API** - Plain structs, simple callbacks, no complex reactive system

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Application                              │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │  AppState (plain struct)                                    ││
│  │  - Your application data                                    ││
│  │  - Modified directly in input callbacks                     ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                          Gooey                                   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐   │
│  │ LayoutEngine │  │    Scene     │  │    WidgetStore       │   │
│  │ (immediate)  │  │  (retained)  │  │ (retained widgets)   │   │
│  └──────────────┘  └──────────────┘  └──────────────────────┘   │
│  ┌──────────────┐  ┌──────────────┐                             │
│  │  TextSystem  │  │   Window     │                             │
│  │  (retained)  │  │  (platform)  │                             │
│  └──────────────┘  └──────────────┘                             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Platform (macOS)                              │
│  MacPlatform, CVDisplayLink, Metal Renderer, NSWindow            │
└─────────────────────────────────────────────────────────────────┘
```

## Quick Start

### Prerequisites

- Zig 0.14.0+
- macOS 12.0+ (Metal required)
- Xcode Command Line Tools

### Build & Run

```bash
zig build run    # Run the login form demo
zig build test   # Run tests
```

## Example

```zig
const std = @import("std");
const gooey = @import("gooey");

// Plain state struct - no wrappers needed!
var g_state = struct {
    count: u32 = 0,
}{};

var g_ui: *gooey.Gooey = undefined;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Platform
    var plat = try gooey.MacPlatform.init();
    defer plat.deinit();

    // Window
    var window = try gooey.Window.init(allocator, &plat, .{
        .title = "Counter",
        .width = 400,
        .height = 300,
    });
    defer window.deinit();

    // UI Context (owns layout engine, scene, text system)
    var ui = try gooey.Gooey.initOwned(allocator, window);
    defer ui.deinit();
    g_ui = &ui;

    // Callbacks
    window.setRenderCallback(onRender);
    window.setInputCallback(onInput);
    window.setScene(ui.scene);
    window.setTextAtlas(ui.text_system.getAtlas());

    plat.run();
}

fn onRender(window: *gooey.Window) void {
    _ = window;
    buildUI(g_ui) catch {};
}

fn onInput(window: *gooey.Window, event: gooey.InputEvent) bool {
    if (event == .key_down and event.key_down.key == .space) {
        g_state.count += 1;
        window.requestRender();
        return true;
    }
    return false;
}

fn buildUI(ui: *gooey.Gooey) !void {
    ui.beginFrame();

    try ui.openElement(.{
        .id = gooey.layout.LayoutId.init("root"),
        .layout = .{ .sizing = gooey.layout.Sizing.fill() },
    });

    var buf: [32]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "Count: {}", .{g_state.count}) catch "?";
    try ui.text(text, .{});

    ui.closeElement();

    const commands = try ui.endFrame();
    ui.scene.clear();
    // ... render commands to scene ...
    ui.scene.finish();
}
```

## API Overview

### Gooey Context

The main entry point. Manages layout, scene, text system, and widgets.

```zig
// Non-owning (you provide the subsystems)
var ui = gooey.Gooey.init(allocator, window, &layout_engine, &scene, &text_system);

// Owning (Gooey creates and manages subsystems)
var ui = try gooey.Gooey.initOwned(allocator, window);
defer ui.deinit();
```

### Frame Lifecycle

```zig
ui.beginFrame();

// Build your UI
try ui.openElement(.{ .id = LayoutId.init("container"), .layout = .{ ... } });
try ui.text("Hello", .{});
ui.closeElement();

const commands = try ui.endFrame();
// Render commands to scene...
```

### Widgets

Widgets are retained across frames. Same ID = same instance.

```zig
// Get or create a text input
const input = ui.textInput("username");
input.setPlaceholder("Enter username");

// Focus management
ui.focusTextInput("username");
ui.widgets.blurAll();

// Get current text
const text = input.getText();
```

### Layout

Clay-inspired immediate mode layout:

```zig
try ui.openElement(.{
    .id = LayoutId.init("card"),
    .layout = .{
        .sizing = .{ .width = SizingAxis.fixed(400), .height = SizingAxis.fit() },
        .layout_direction = .top_to_bottom,
        .padding = Padding.all(16),
        .child_gap = 8,
    },
    .background_color = Color.white,
    .corner_radius = CornerRadius.all(8),
});

try ui.text("Title", .{ .font_size = 20 });
try ui.text("Subtitle", .{ .color = Color.rgb(0.5, 0.5, 0.5) });

ui.closeElement();
```

### Input Handling

```zig
fn onInput(window: *gooey.Window, event: gooey.InputEvent) bool {
    switch (event) {
        .key_down => |k| {
            if (k.key == .escape) {
                // Handle escape
                return true;
            }
        },
        .mouse_down => |m| {
            std.debug.print("Click at ({}, {})\n", .{m.position.x, m.position.y});
        },
        else => {},
    }
    return false;
}
```

## Project Structure

```
src/
├── core/
│   ├── gooey.zig        # Main Gooey context
│   ├── widget_store.zig # Retained widget storage
│   ├── scene.zig        # Render primitives (Quad, Shadow, Glyph)
│   ├── geometry.zig     # Point, Size, Rect, Color
│   ├── input.zig        # Input event types
│   ├── event.zig        # Event wrapper with phases
│   └── element_types.zig # ElementId, geometry types
├── elements/
│   └── text_input.zig   # TextInput widget
├── font/
│   └── ...              # Text system, atlas, shaping
├── layout/
│   └── ...              # Layout engine
├── platform/
│   └── mac/
│       ├── platform.zig # MacPlatform
│       ├── window.zig   # Window with Metal
│       └── metal/       # Metal renderer
├── main.zig             # Demo application
└── root.zig             # Public API exports
```

## Inspiration

- [GPUI](https://github.com/zed-industries/zed/tree/main/crates/gpui) - Zed's GPU UI framework
- [Clay](https://github.com/nicbarker/clay) - Immediate mode layout library
- [Ghostty](https://github.com/ghostty-org/ghostty) - Zig + Metal terminal
