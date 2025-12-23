//! Linux Platform Module
//!
//! This module provides the Linux-specific platform implementation for gooey,
//! using Wayland for windowing and wgpu-native (Vulkan) for GPU rendering.
//!
//! ## Architecture
//!
//! - **Wayland**: Native display server protocol for window management
//! - **XDG Shell**: Standard window decorations and lifecycle
//! - **wgpu-native**: WebGPU implementation via Vulkan backend
//!
//! ## Usage
//!
//! ```zig
//! const linux = @import("gooey").platform.linux;
//!
//! var platform = try linux.LinuxPlatform.init();
//! defer platform.deinit();
//!
//! var window = try linux.Window.init(allocator, &platform, .{
//!     .title = "My App",
//!     .width = 800,
//!     .height = 600,
//! });
//! defer window.deinit();
//!
//! platform.run();
//! ```

// Core platform types
pub const platform = @import("platform.zig");
pub const window = @import("window.zig");
pub const renderer = @import("renderer.zig");

// Low-level bindings
pub const wayland = @import("wayland.zig");
pub const wgpu = @import("wgpu.zig");

// Shared GPU primitives (same as web)
pub const unified = @import("../wgpu/unified.zig");

// Type aliases for convenience
pub const LinuxPlatform = platform.LinuxPlatform;
pub const Window = window.Window;
pub const LinuxRenderer = renderer.LinuxRenderer;

// Re-export capabilities
pub const capabilities = LinuxPlatform.capabilities;
