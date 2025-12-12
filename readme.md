# Gooey

A GPU-accelerated UI framework for Zig, targeting macOS with Metal rendering.

> ⚠️ **Early Development**: macOS-only. API is evolving.

<table>
  <tr>
    <td><img src="https://github.com/duanebester/gooey/blob/main/assets/screenshots/gooey-1.png" height="300px" /></td>
    <td><img src="https://github.com/duanebester/gooey/blob/main/assets/screenshots/gooey-2.png" height="300px" /></td>
  </tr>
  <tr>
    <td><img src="https://github.com/duanebester/gooey/blob/main/assets/screenshots/gooey-3.png" height="300px" /></td>
    <td><img src="https://github.com/duanebester/gooey/blob/main/assets/screenshots/gooey-dark.png" height="300px" /></td>
  </tr>
</table>

Now with custom shader support!

<img src="https://github.com/duanebester/gooey/blob/main/assets/screenshots/gooey-shader.png" height="300px" />

## Features

- **Metal Rendering** - Hardware-accelerated with MSAA anti-aliasing
- **Declarative UI** - Component-based layout with flexbox-style system
- **Retained Widgets** - TextInput, Checkbox, Scroll containers with state
- **Text Rendering** - CoreText shaping with subpixel positioning
- **Custom Shaders** - Drop in your own Metal shaders
- **Theming** - Built-in light/dark mode support

## Quick Start

**Requirements:** Zig 0.15.2+, macOS 12.0+

```bash
zig build run              # Showcase demo
zig build run-simple       # Counter example
zig build run-todo         # Todo app
zig build run-shader       # Custom shaders
zig build test             # Run tests
```

## Example

```zig
const std = @import("std");
const gooey = @import("gooey");
const ui = gooey.ui;

var state = struct { count: i32 = 0 }{};

const Counter = struct {
    var buf: [32]u8 = undefined;

    pub fn render(_: @This(), b: *ui.Builder) void {
        const str = std.fmt.bufPrint(&buf, "{d}", .{state.count}) catch "?";
        b.vstack(.{ .gap = 12, .alignment = .center }, .{
            ui.text(str, .{ .size = 48 }),
            ui.button("+ Increment", increment),
        });
    }
};

fn increment() void {
    state.count += 1;
}

pub fn main() !void {
    try gooey.run(.{
        .title = "Counter",
        .width = 300,
        .height = 200,
        .render = render,
    });
}

fn render(g: *gooey.UI) void {
    const size = g.windowSize();
    g.box(.{
        .width = size.width,
        .height = size.height,
        .alignment = .{ .main = .center, .cross = .center },
    }, .{Counter{}});
}
```

## More Examples

| Example  | Command                  | Description                       |
| -------- | ------------------------ | --------------------------------- |
| Showcase | `zig build run`          | Full feature demo with navigation |
| Todo App | `zig build run-todo`     | CRUD with entities and filters    |
| Login    | `zig build run-login`    | Form inputs with validation       |
| Layout   | `zig build run-layout`   | Flexbox, shrink, text wrapping    |
| Pomodoro | `zig build run-pomodoro` | Timer with context/state          |
| Shader   | `zig build run-shader`   | Custom Metal shaders              |

## Inspiration

- [GPUI](https://github.com/zed-industries/zed/tree/main/crates/gpui) - Zed's GPU UI framework
- [Clay](https://github.com/nicbarker/clay) - Immediate mode layout
- [Ghostty](https://github.com/ghostty-org/ghostty) - Zig + Metal terminal
