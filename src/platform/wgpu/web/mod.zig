//! Web platform module
//!
//! Exports for WebAssembly/browser target.

pub const platform = @import("platform.zig");
pub const window = @import("window.zig");
pub const imports = @import("imports.zig");
pub const renderer = @import("renderer.zig");

pub const WebPlatform = platform.WebPlatform;
pub const WebWindow = window.WebWindow;
pub const WebRenderer = renderer.WebRenderer;
