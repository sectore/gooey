//! Metal rendering module for gooey
//!
//! This module provides a clean, modular Metal API wrapper inspired by Ghostty.

pub const api = @import("api.zig");
pub const quad = @import("quad.zig");
pub const Renderer = @import("renderer.zig").Renderer;
pub const Vertex = @import("renderer.zig").Vertex;
pub const custom_shader = @import("custom_shader.zig");
