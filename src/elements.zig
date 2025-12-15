//! UI Elements for gooey
//!
//! Reusable UI components built on the gooey primitives.

pub const text_input = @import("widgets/text_input.zig");
pub const TextInput = text_input.TextInput;
pub const Bounds = text_input.Bounds;

pub const scroll_mod = @import("widgets/scroll_container.zig");
pub const ScrollContainer = scroll_mod.ScrollContainer;
pub const ScrollStyle = scroll_mod.Style;
pub const ScrollState = scroll_mod.ScrollState;
