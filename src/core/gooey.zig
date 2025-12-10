//! Gooey - Unified UI context
//!
//! Single struct that holds everything needed for UI, replacing the
//! App/Context/ViewContext complexity. Provides a clean API for:
//! - Layout (immediate mode)
//! - Rendering (retained scene)
//! - Widget management (retained widgets)
//! - Hit testing
//!
//! Example:
//! ```zig
//! var ui = try Gooey.init(allocator, window, &layout_engine, &scene, &text_system);
//! defer ui.deinit();
//!
//! // In render callback:
//! ui.beginFrame();
//! // Build UI...
//! const commands = ui.endFrame();
//! // Render commands to scene...
//! ```

const std = @import("std");

// Layout
const layout_mod = @import("../layout/layout.zig");
const engine_mod = @import("../layout/engine.zig");
const LayoutEngine = layout_mod.LayoutEngine;
const LayoutId = layout_mod.LayoutId;
const ElementDeclaration = layout_mod.ElementDeclaration;
const BoundingBox = layout_mod.BoundingBox;
const TextConfig = layout_mod.TextConfig;
const RenderCommand = layout_mod.RenderCommand;
const TextMeasurement = engine_mod.TextMeasurement;

// Scene
const scene_mod = @import("scene.zig");
const Scene = scene_mod.Scene;

// Text
const font_mod = @import("../font/main.zig");
const TextSystem = font_mod.TextSystem;

// Widgets
const widget_store_mod = @import("widget_store.zig");
const WidgetStore = widget_store_mod.WidgetStore;
const TextInput = @import("../elements/text_input.zig").TextInput;

// Platform
const Window = @import("../platform/mac/window.zig").Window;

// Input
const input_mod = @import("input.zig");
const InputEvent = input_mod.InputEvent;

/// Gooey - unified UI context
pub const Gooey = struct {
    allocator: std.mem.Allocator,

    // Layout (immediate mode - rebuilt each frame)
    layout: *LayoutEngine,
    layout_owned: bool = false,

    // Rendering (retained)
    scene: *Scene,
    scene_owned: bool = false,

    // Text rendering
    text_system: *TextSystem,
    text_system_owned: bool = false,

    // Widgets (retained across frames)
    widgets: WidgetStore,

    // Platform
    window: *Window,

    // Frame state
    frame_count: u64 = 0,
    needs_render: bool = true,

    // Window dimensions (cached for convenience)
    width: f32 = 0,
    height: f32 = 0,
    scale_factor: f32 = 1.0,

    const Self = @This();

    /// Initialize Gooey with existing resources (non-owning)
    /// Use this when you already have LayoutEngine, Scene, TextSystem created
    pub fn init(
        allocator: std.mem.Allocator,
        window: *Window,
        layout_engine: *LayoutEngine,
        scene: *Scene,
        text_system: *TextSystem,
    ) Self {
        return .{
            .allocator = allocator,
            .layout = layout_engine,
            .scene = scene,
            .text_system = text_system,
            .widgets = WidgetStore.init(allocator),
            .window = window,
            .width = @floatCast(window.size.width),
            .height = @floatCast(window.size.height),
            .scale_factor = @floatCast(window.scale_factor),
        };
    }

    /// Initialize Gooey creating and owning all resources
    pub fn initOwned(allocator: std.mem.Allocator, window: *Window) !Self {
        // Create layout engine
        const layout_engine = allocator.create(LayoutEngine) catch return error.OutOfMemory;
        layout_engine.* = LayoutEngine.init(allocator);
        errdefer {
            layout_engine.deinit();
            allocator.destroy(layout_engine);
        }

        // Create scene
        const scene = allocator.create(Scene) catch return error.OutOfMemory;
        scene.* = Scene.init(allocator);
        errdefer {
            scene.deinit();
            allocator.destroy(scene);
        }

        // Create text system
        const text_system = allocator.create(TextSystem) catch return error.OutOfMemory;
        text_system.* = try TextSystem.initWithScale(allocator, @floatCast(window.scale_factor));
        errdefer {
            text_system.deinit();
            allocator.destroy(text_system);
        }

        // Load default font
        try text_system.loadFont("SF Mono", 16.0); // Changed from "Menlo"

        // Set up text measurement callback
        layout_engine.setMeasureTextFn(measureTextCallback, text_system);

        return .{
            .allocator = allocator,
            .layout = layout_engine,
            .layout_owned = true,
            .scene = scene,
            .scene_owned = true,
            .text_system = text_system,
            .text_system_owned = true,
            .widgets = WidgetStore.init(allocator),
            .window = window,
            .width = @floatCast(window.size.width),
            .height = @floatCast(window.size.height),
            .scale_factor = @floatCast(window.scale_factor),
        };
    }

    pub fn deinit(self: *Self) void {
        self.widgets.deinit();

        if (self.text_system_owned) {
            self.text_system.deinit();
            self.allocator.destroy(self.text_system);
        }
        if (self.scene_owned) {
            self.scene.deinit();
            self.allocator.destroy(self.scene);
        }
        if (self.layout_owned) {
            self.layout.deinit();
            self.allocator.destroy(self.layout);
        }
    }

    // =========================================================================
    // Frame Lifecycle
    // =========================================================================

    /// Call at the start of each frame before building UI
    pub fn beginFrame(self: *Self) void {
        self.frame_count += 1;
        self.widgets.beginFrame();

        // Update cached window dimensions
        self.width = @floatCast(self.window.size.width);
        self.height = @floatCast(self.window.size.height);
        self.scale_factor = @floatCast(self.window.scale_factor);

        // Clear scene for new frame
        self.scene.clear();

        // Begin layout pass
        self.layout.beginFrame(self.width, self.height);
    }

    /// Call at the end of each frame after building UI
    /// Returns the render commands for the frame
    pub fn endFrame(self: *Self) ![]const RenderCommand {
        self.widgets.endFrame();

        // End layout and get render commands
        return try self.layout.endFrame();
    }

    // =========================================================================
    // Layout Pass-through (convenience methods)
    // =========================================================================

    /// Open a layout element (container)
    pub fn openElement(self: *Self, decl: ElementDeclaration) !void {
        try self.layout.openElement(decl);
    }

    /// Close the current layout element
    pub fn closeElement(self: *Self) void {
        self.layout.closeElement();
    }

    /// Add a text element
    pub fn text(self: *Self, content: []const u8, config: TextConfig) !void {
        try self.layout.text(content, config);
    }

    // =========================================================================
    // Widget Access
    // =========================================================================

    /// Get or create a TextInput by ID
    /// Returns null on allocation failure
    pub fn textInput(self: *Self, id: []const u8) ?*TextInput {
        return self.widgets.textInput(id);
    }

    /// Focus a TextInput by ID
    pub fn focusTextInput(self: *Self, id: []const u8) void {
        self.widgets.focusTextInput(id);
        self.requestRender();
    }

    /// Get currently focused TextInput
    pub fn getFocusedTextInput(self: *Self) ?*TextInput {
        return self.widgets.getFocusedTextInput();
    }

    // =========================================================================
    // Hit Testing & Bounds
    // =========================================================================

    /// Get bounding box for a layout element by ID hash
    pub fn getBoundingBox(self: *Self, id: u32) ?BoundingBox {
        return self.layout.getBoundingBox(id);
    }

    /// Get bounding box by LayoutId
    pub fn getBounds(self: *Self, id: LayoutId) ?BoundingBox {
        return self.layout.getBoundingBox(id.id);
    }

    // =========================================================================
    // Render Control
    // =========================================================================

    /// Mark that a re-render is needed
    pub fn requestRender(self: *Self) void {
        self.needs_render = true;
        self.window.requestRender();
    }

    /// Check and clear the needs_render flag
    pub fn checkAndClearRenderFlag(self: *Self) bool {
        const result = self.needs_render;
        self.needs_render = false;
        return result;
    }

    /// Finish the scene after rendering
    pub fn finishScene(self: *Self) void {
        self.scene.finish();
    }

    // =========================================================================
    // Resource Access
    // =========================================================================

    pub fn getScene(self: *Self) *Scene {
        return self.scene;
    }

    pub fn getTextSystem(self: *Self) *TextSystem {
        return self.text_system;
    }

    pub fn getLayout(self: *Self) *LayoutEngine {
        return self.layout;
    }

    pub fn getWindow(self: *Self) *Window {
        return self.window;
    }
};

/// Text measurement callback for layout engine
fn measureTextCallback(
    text_content: []const u8,
    _: u16, // font_id
    _: u16, // font_size
    _: ?f32, // max_width
    user_data: ?*anyopaque,
) TextMeasurement {
    if (user_data) |ptr| {
        const text_system: *TextSystem = @ptrCast(@alignCast(ptr));
        const width = text_system.measureText(text_content) catch 0;
        const metrics = text_system.getMetrics();
        return .{
            .width = width,
            .height = if (metrics) |m| m.line_height else 20,
        };
    }
    return .{
        .width = @as(f32, @floatFromInt(text_content.len)) * 10,
        .height = 20,
    };
}
