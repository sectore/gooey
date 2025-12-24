//! Render commands output from the layout system
//!
//! The layout engine produces these commands as a platform-agnostic
//! representation of what needs to be drawn. These commands are then
//! translated to GPU primitives by the render_bridge module.
//!
//! This module has NO dependencies on scene.zig or any GPU types,
//! keeping the layout system fully decoupled from rendering.

const std = @import("std");
const types = @import("types.zig");
const BoundingBox = types.BoundingBox;
const Color = types.Color;
const CornerRadius = types.CornerRadius;
const BorderWidth = types.BorderWidth;

/// Type of render command
pub const RenderCommandType = enum {
    none,
    shadow,
    rectangle,
    border,
    text,
    image,
    scissor_start,
    scissor_end,
    custom,
};

/// A single render command from layout
pub const RenderCommand = struct {
    /// Computed bounding box
    bounding_box: BoundingBox,
    /// Type of command
    command_type: RenderCommandType,
    /// Z-index for layering (higher = on top)
    z_index: i16 = 0,
    /// Insertion order for stable sorting within same z_index
    order: u32 = 0,
    /// Element ID this command belongs to
    id: u32 = 0,
    /// Command-specific data
    data: RenderData = .{ .none = {} },
};

/// Command-specific render data
pub const RenderData = union(RenderCommandType) {
    none: void,
    shadow: ShadowData,
    rectangle: RectangleData,
    border: BorderData,
    text: TextData,
    image: ImageData,
    scissor_start: ScissorData,
    scissor_end: void,
    custom: CustomData,
};

/// Data for shadow rendering
pub const ShadowData = struct {
    blur_radius: f32,
    color: Color,
    offset_x: f32,
    offset_y: f32,
    corner_radius: CornerRadius = .{},
};

/// Data for rectangle rendering
pub const RectangleData = struct {
    background_color: Color,
    corner_radius: CornerRadius = .{},
};

/// Data for border rendering
pub const BorderData = struct {
    color: Color,
    width: BorderWidth,
    corner_radius: CornerRadius = .{},
};

/// Data for text rendering
pub const TextData = struct {
    text: []const u8,
    color: Color,
    font_id: u16,
    font_size: u16,
    letter_spacing: i16 = 0,
    underline: bool = false,
    strikethrough: bool = false,
};

/// Data for image rendering
pub const ImageData = struct {
    image_data: *anyopaque,
    source_rect: ?BoundingBox = null,
};

/// Data for scissor/clip regions
pub const ScissorData = struct {
    clip_bounds: BoundingBox,
};

/// Data for custom rendering
pub const CustomData = struct {
    user_data: ?*anyopaque = null,
};

/// List of render commands (typically per-frame)
pub const RenderCommandList = struct {
    allocator: std.mem.Allocator,
    commands: std.ArrayList(RenderCommand),
    next_order: u32 = 0,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .commands = .{},
            .next_order = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.commands.deinit(self.allocator);
    }

    pub fn clear(self: *Self) void {
        self.commands.clearRetainingCapacity();
        self.next_order = 0;
    }

    pub fn append(self: *Self, cmd: RenderCommand) !void {
        var c = cmd;
        c.order = self.next_order;
        self.next_order += 1;
        try self.commands.append(self.allocator, c);
    }

    pub fn items(self: *const Self) []const RenderCommand {
        return self.commands.items;
    }

    pub fn sortByZIndex(self: *Self) void {
        // Sort by z_index first, then by insertion order for stability
        std.sort.pdq(RenderCommand, self.commands.items, {}, struct {
            fn lessThan(_: void, a: RenderCommand, b: RenderCommand) bool {
                if (a.z_index != b.z_index) {
                    return a.z_index < b.z_index;
                }
                return a.order < b.order;
            }
        }.lessThan);
    }
};
