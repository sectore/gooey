//! SVG rendering module
//!
//! Provides atlas-cached SVG icon rendering using CoreGraphics rasterization.

pub const SvgAtlas = @import("atlas.zig").SvgAtlas;
pub const SvgKey = @import("atlas.zig").SvgKey;
pub const CachedSvg = @import("atlas.zig").CachedSvg;
pub const rasterize = @import("rasterizer.zig").rasterize;
pub const RasterizedSvg = @import("rasterizer.zig").RasterizedSvg;
