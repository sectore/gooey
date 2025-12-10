//! macOS Window implementation with vsync-synchronized rendering
//!
//! Simplified version without Entity/View system integration.
//! Uses simple callbacks for rendering and input handling.

const std = @import("std");
const objc = @import("objc");
const geometry = @import("../../core/geometry.zig");
const scene_mod = @import("../../core/scene.zig");
const Atlas = @import("../../font/atlas.zig").Atlas;
const platform = @import("platform.zig");
const metal = @import("metal/metal.zig");
const input_view = @import("input_view.zig");
const input = @import("../../core/input.zig");
const display_link = @import("display_link.zig");
const appkit = @import("appkit.zig");

const NSRect = appkit.NSRect;
const NSSize = appkit.NSSize;
const DisplayLink = display_link.DisplayLink;

pub const Window = struct {
    allocator: std.mem.Allocator,
    ns_window: objc.Object,
    ns_view: objc.Object,
    metal_layer: objc.Object,
    renderer: metal.Renderer,
    display_link: ?DisplayLink,
    size: geometry.Size(f64),
    scale_factor: f64,
    title: []const u8,
    background_color: geometry.Color,
    needs_render: std.atomic.Value(bool),
    scene: ?*const scene_mod.Scene,
    text_atlas: ?*const Atlas = null,
    delegate: ?objc.Object = null,

    /// Mutex protecting all render-related state accessed from DisplayLink thread.
    /// This includes: scene, text_atlas, background_color, size, scale_factor, renderer.
    /// Must be held when:
    /// - DisplayLink callback reads scene/atlas for rendering
    /// - Main thread modifies scene/atlas/size
    render_mutex: std.Thread.Mutex = .{},

    /// Flag indicating we're in a live resize operation.
    /// During live resize, the main thread handles rendering synchronously,
    /// and the DisplayLink callback should skip rendering entirely.
    in_live_resize: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    /// Flag indicating the DisplayLink callback is currently rendering.
    /// Used to prevent the main thread from modifying state mid-render.
    render_in_progress: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    benchmark_mode: bool = false,

    /// Current mouse position (updated on every mouse event)
    mouse_position: geometry.Point(f64) = .{ .x = 0, .y = 0 },
    /// Whether mouse is inside the window
    mouse_inside: bool = false,
    hovered_quad_index: ?usize = null,

    // IME (Input Method Editor) state
    marked_text: []const u8 = "",
    marked_text_buffer: [256]u8 = undefined,
    inserted_text: []const u8 = "",
    inserted_text_buffer: [256]u8 = undefined,
    pending_key_event: ?objc.c.id = null,
    /// IME cursor rect in view coordinates (for candidate window positioning)
    ime_cursor_rect: appkit.NSRect = .{ .origin = .{ .x = 0, .y = 0 }, .size = .{ .width = 1, .height = 20 } },

    // =========================================================================
    // Simplified Callbacks
    // =========================================================================

    /// Called for input events. Return true if handled.
    on_input: ?InputCallback = null,

    /// Called each frame when rendering is needed.
    /// Use this to rebuild your UI/scene before the frame is drawn.
    on_render: ?RenderCallback = null,

    /// User data pointer for callbacks
    user_data: ?*anyopaque = null,

    // =========================================================================
    // Convenience accessors (so user code doesn't need to convert)
    // =========================================================================

    /// Window width in logical pixels
    pub fn width(self: *const Self) u32 {
        return @intFromFloat(self.size.width);
    }

    /// Window height in logical pixels
    pub fn height(self: *const Self) u32 {
        return @intFromFloat(self.size.height);
    }

    // =========================================================================
    // Types
    // =========================================================================

    /// Input callback: return true if the event was handled
    pub const InputCallback = *const fn (*Window, input.InputEvent) bool;

    /// Render callback: called each frame before drawing
    pub const RenderCallback = *const fn (*Window) void;

    pub const Options = struct {
        title: []const u8 = "gooey Window",
        width: f64 = 800,
        height: f64 = 600,
        background_color: geometry.Color = geometry.Color.init(0.2, 0.2, 0.25, 1.0),
        use_display_link: bool = true,
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, plat: *platform.MacPlatform, options: Options) !*Self {
        _ = plat;

        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .ns_window = undefined,
            .ns_view = undefined,
            .metal_layer = undefined,
            .renderer = undefined,
            .display_link = null,
            .size = geometry.Size(f64).init(options.width, options.height),
            .scale_factor = 1.0,
            .title = options.title,
            .background_color = options.background_color,
            .needs_render = std.atomic.Value(bool).init(true),
            .scene = null,
        };

        // Create NSWindow
        const NSWindow = objc.getClass("NSWindow") orelse return error.ClassNotFound;

        // Style mask: titled, closable, miniaturizable, resizable
        const style_mask: u64 = (1 << 0) | (1 << 1) | (1 << 2) | (1 << 3);

        // Content rect
        const content_rect = NSRect{
            .origin = .{ .x = 100, .y = 100 },
            .size = .{ .width = options.width, .height = options.height },
        };

        // Alloc and init window
        const window_alloc = NSWindow.msgSend(objc.Object, "alloc", .{});
        self.ns_window = window_alloc.msgSend(
            objc.Object,
            "initWithContentRect:styleMask:backing:defer:",
            .{
                content_rect,
                style_mask,
                @as(u64, 2), // NSBackingStoreBuffered
                false,
            },
        );

        const window_delegate = @import("window_delegate.zig");
        self.delegate = try window_delegate.create(self);
        self.ns_window.msgSend(void, "setDelegate:", .{self.delegate.?.value});

        // Set window title
        self.setTitle(options.title);

        const view_frame: NSRect = self.ns_window.msgSend(NSRect, "contentLayoutRect", .{});
        self.ns_view = try input_view.create(view_frame, self);
        self.ns_window.msgSend(void, "setContentView:", .{self.ns_view.value});

        // Enable mouse tracking for mouseMoved events
        try self.setupTrackingArea();

        // Get backing scale factor for Retina displays
        self.scale_factor = self.ns_window.msgSend(f64, "backingScaleFactor", .{});

        // Setup Metal layer
        try self.setupMetalLayer();

        // Initialize renderer with logical size and scale factor
        self.renderer = try metal.Renderer.init(self.metal_layer, self.size, self.scale_factor);

        // Setup display link for vsync
        if (options.use_display_link) {
            self.display_link = try DisplayLink.init();
            try self.display_link.?.setCallback(displayLinkCallback, @ptrCast(self));
            try self.display_link.?.start();

            const refresh_rate = self.display_link.?.getRefreshRate();
            std.debug.print("DisplayLink started at {d:.1}Hz\n", .{refresh_rate});
        }

        // Make window key and visible
        self.ns_window.msgSend(void, "makeKeyAndOrderFront:", .{@as(?*anyopaque, null)});

        // Mark for initial render
        self.requestRender();

        return self;
    }

    // =========================================================================
    // Callback Setters
    // =========================================================================

    /// Set the input callback
    pub fn setInputCallback(self: *Self, callback: InputCallback) void {
        self.on_input = callback;
    }

    /// Set the render callback (called each frame before drawing)
    pub fn setRenderCallback(self: *Self, callback: RenderCallback) void {
        self.on_render = callback;
    }

    /// Set user data pointer accessible in callbacks
    pub fn setUserData(self: *Self, data: ?*anyopaque) void {
        self.user_data = data;
    }

    /// Get user data pointer
    pub fn getUserData(self: *Self, comptime T: type) ?*T {
        if (self.user_data) |ptr| {
            return @ptrCast(@alignCast(ptr));
        }
        return null;
    }

    // =========================================================================
    // Scene Management
    // =========================================================================

    pub fn getHoveredQuad(self: *const Self) ?*const scene_mod.Quad {
        const idx = self.hovered_quad_index orelse return null;
        const s = self.scene orelse return null;
        if (idx < s.quads.items.len) {
            return &s.quads.items[idx];
        }
        return null;
    }

    /// Set the text atlas for automatic GPU sync (thread-safe)
    pub fn setTextAtlas(self: *Self, atlas: *const Atlas) void {
        // Only lock if we're not already in a render (which holds the lock)
        if (!self.render_in_progress.load(.acquire)) {
            self.render_mutex.lock();
            defer self.render_mutex.unlock();
        }
        self.text_atlas = atlas;
    }

    /// Set the scene (thread-safe)
    pub fn setScene(self: *Self, s: *const scene_mod.Scene) void {
        // Only lock if we're not already in a render (which holds the lock)
        if (!self.render_in_progress.load(.acquire)) {
            self.render_mutex.lock();
            defer self.render_mutex.unlock();
        }
        self.scene = s;
        self.requestRender();
    }

    pub fn getSize(self: *const Self) geometry.Size(f64) {
        return self.size;
    }

    // =========================================================================
    // IME Support
    // =========================================================================

    /// Set the marked (composing) text for IME
    pub fn setMarkedText(self: *Self, text: []const u8) void {
        if (text.len > self.marked_text_buffer.len) {
            @memcpy(self.marked_text_buffer[0..], text[0..self.marked_text_buffer.len]);
            self.marked_text = self.marked_text_buffer[0..self.marked_text_buffer.len];
        } else {
            @memcpy(self.marked_text_buffer[0..text.len], text);
            self.marked_text = self.marked_text_buffer[0..text.len];
        }
    }

    /// Clear the marked text (composition ended or cancelled)
    pub fn clearMarkedText(self: *Self) void {
        self.marked_text = "";
    }

    /// Set the inserted text for IME (copies to window-owned buffer)
    pub fn setInsertedText(self: *Self, text: []const u8) void {
        if (text.len > self.inserted_text_buffer.len) {
            @memcpy(self.inserted_text_buffer[0..], text[0..self.inserted_text_buffer.len]);
            self.inserted_text = self.inserted_text_buffer[0..self.inserted_text_buffer.len];
        } else {
            @memcpy(self.inserted_text_buffer[0..text.len], text);
            self.inserted_text = self.inserted_text_buffer[0..text.len];
        }
    }

    /// Set the IME cursor rect (call from TextInput during render)
    pub fn setImeCursorRect(self: *Self, x: f32, y: f32, w: f32, h: f32) void {
        self.ime_cursor_rect = .{
            .origin = .{ .x = @floatCast(x), .y = @floatCast(y) },
            .size = .{ .width = @floatCast(w), .height = @floatCast(h) },
        };
    }

    /// Check if there's active IME composition
    pub fn hasMarkedText(self: *const Self) bool {
        return self.marked_text.len > 0;
    }

    // =========================================================================
    // Input Handling
    // =========================================================================
    pub fn handleInput(self: *Self, event: input.InputEvent) bool {
        // Track mouse position
        switch (event) {
            .mouse_down, .mouse_up, .mouse_moved, .mouse_dragged => |m| {
                self.mouse_position = m.position;
            },
            .mouse_entered => |m| {
                self.mouse_position = m.position;
                self.mouse_inside = true;
            },
            .mouse_exited => |m| {
                self.mouse_position = m.position;
                self.mouse_inside = false;
            },
            else => {},
        }

        var handled = false;
        if (self.on_input) |callback| {
            handled = callback(self, event);
        }
        self.requestRender();
        return handled;
    }

    /// Get current mouse position
    pub fn getMousePosition(self: *const Self) geometry.Point(f64) {
        return self.mouse_position;
    }

    /// Check if mouse is inside window
    pub fn isMouseInside(self: *const Self) bool {
        return self.mouse_inside;
    }

    // =========================================================================
    // Window Lifecycle
    // =========================================================================

    pub fn deinit(self: *Self) void {
        if (self.delegate) |d| {
            self.ns_window.msgSend(void, "setDelegate:", .{@as(?*anyopaque, null)});
            d.msgSend(void, "release", .{});
        }
        if (self.display_link) |*dl| {
            dl.deinit();
        }
        self.renderer.deinit();
        self.ns_window.msgSend(void, "close", .{});
        self.allocator.destroy(self);
    }

    /// Called by delegate when window is resized
    /// Called by delegate when window is resized
    pub fn handleResize(self: *Self) void {
        const bounds: NSRect = self.ns_view.msgSend(NSRect, "bounds", .{});

        const new_width = bounds.size.width;
        const new_height = bounds.size.height;

        if (new_width < 1 or new_height < 1) {
            return;
        }

        const new_scale = self.ns_window.msgSend(f64, "backingScaleFactor", .{});

        if (new_width == self.size.width and
            new_height == self.size.height and
            new_scale == self.scale_factor)
        {
            return;
        }

        // Acquire render mutex to safely modify size/scale while DisplayLink might be reading
        self.render_mutex.lock();
        defer self.render_mutex.unlock();

        self.size.width = new_width;
        self.size.height = new_height;
        self.scale_factor = new_scale;

        self.metal_layer.msgSend(void, "setContentsScale:", .{new_scale});

        self.renderer.resize(geometry.Size(f64).init(
            new_width,
            new_height,
        ), new_scale);

        self.requestRender();

        // During live resize, render synchronously for smooth visuals
        if (self.in_live_resize.load(.acquire)) {
            const pool = createAutoreleasePool() orelse return;
            defer drainAutoreleasePool(pool);

            // Call render callback to update scene
            if (self.on_render) |callback| {
                callback(self);
            }

            if (self.text_atlas) |atlas| {
                self.renderer.updateTextAtlas(atlas) catch {};
            }

            if (self.scene) |s| {
                self.renderer.renderSceneSynchronous(s, self.background_color) catch {};
            } else {
                self.renderer.clearSynchronous(self.background_color);
            }
        }
    }

    pub fn handleClose(self: *Self) void {
        if (self.display_link) |*dl| {
            dl.stop();
        }
    }

    pub fn handleFocusChange(self: *Self, focused: bool) void {
        _ = focused;
        self.requestRender();
    }

    pub fn handleLiveResizeStart(self: *Self) void {
        self.in_live_resize.store(true, .release);
        self.metal_layer.msgSend(void, "setPresentsWithTransaction:", .{true});
    }

    pub fn handleLiveResizeEnd(self: *Self) void {
        self.in_live_resize.store(false, .release);
        self.metal_layer.msgSend(void, "setPresentsWithTransaction:", .{false});
        self.requestRender();
    }

    pub fn isInLiveResize(self: *const Self) bool {
        return self.in_live_resize.load(.acquire);
    }

    // =========================================================================
    // Rendering
    // =========================================================================

    /// Request a render on the next vsync
    pub fn requestRender(self: *Self) void {
        self.needs_render.store(true, .release);
    }

    /// Manual render (for when display link is disabled)
    pub fn render(self: *Self) void {
        self.renderer.clear(self.background_color);
    }

    pub fn setTitle(self: *Self, new_title: []const u8) void {
        self.title = new_title;

        const NSString = objc.getClass("NSString") orelse return;
        const ns_title = NSString.msgSend(
            objc.Object,
            "stringWithUTF8String:",
            .{new_title.ptr},
        );

        self.ns_window.msgSend(void, "setTitle:", .{ns_title});
    }

    pub fn setBackgroundColor(self: *Self, color: geometry.Color) void {
        self.background_color = color;
        self.requestRender();
    }

    // =========================================================================
    // Private Helpers
    // =========================================================================

    fn setupTrackingArea(self: *Self) !void {
        const bounds: NSRect = self.ns_view.msgSend(NSRect, "bounds", .{});

        const NSTrackingArea = objc.getClass("NSTrackingArea") orelse return error.ClassNotFound;

        const opts = appkit.NSTrackingAreaOptions;
        const options = opts.mouse_moved |
            opts.mouse_entered_and_exited |
            opts.active_in_key_window |
            opts.in_visible_rect;

        const tracking_area = NSTrackingArea.msgSend(objc.Object, "alloc", .{})
            .msgSend(objc.Object, "initWithRect:options:owner:userInfo:", .{
            bounds,
            options,
            self.ns_view.value,
            @as(?objc.c.id, null),
        });

        self.ns_view.msgSend(void, "addTrackingArea:", .{tracking_area.value});
    }

    fn setupMetalLayer(self: *Self) !void {
        const CAMetalLayer = objc.getClass("CAMetalLayer") orelse return error.ClassNotFound;
        self.metal_layer = CAMetalLayer.msgSend(objc.Object, "layer", .{});

        // Configure the layer
        self.metal_layer.msgSend(void, "setPixelFormat:", .{@as(u64, 80)}); // MTLPixelFormatBGRA8Unorm
        self.metal_layer.msgSend(void, "setContentsScale:", .{self.scale_factor});
        self.metal_layer.msgSend(void, "setDisplaySyncEnabled:", .{false});
        self.metal_layer.msgSend(void, "setMaximumDrawableCount:", .{@as(u64, 3)});

        self.ns_view.msgSend(void, "setWantsLayer:", .{true});
        self.ns_view.msgSend(void, "setLayer:", .{self.metal_layer});

        const drawable_size = NSSize{
            .width = self.size.width * self.scale_factor,
            .height = self.size.height * self.scale_factor,
        };
        self.metal_layer.msgSend(void, "setDrawableSize:", .{drawable_size});
    }
};

// =============================================================================
// Display Link Callback
// =============================================================================

/// CVDisplayLink callback - runs on high-priority background thread
///
/// THREAD SAFETY: This callback runs on a CVDisplayLink thread, NOT the main thread.
/// All access to shared Window state must be synchronized via render_mutex.
///
/// The render_mutex protects: scene, text_atlas, size, scale_factor, background_color, renderer.
/// The on_render callback is called WITH the lock held to prevent race conditions.
fn displayLinkCallback(
    dl: display_link.CVDisplayLinkRef,
    in_now: *const display_link.CVTimeStamp,
    in_output_time: *const display_link.CVTimeStamp,
    flags_in: u64,
    flags_out: *u64,
    user_info: ?*anyopaque,
) callconv(.c) display_link.CVReturn {
    _ = dl;
    _ = in_now;
    _ = in_output_time;
    _ = flags_in;
    _ = flags_out;

    const window: *Window = @ptrCast(@alignCast(user_info orelse return .success));

    // Skip rendering during live resize - main thread handles it synchronously
    if (window.in_live_resize.load(.acquire)) {
        return .success;
    }

    // Only render if needed (dirty flag pattern)
    const explicit_render = window.needs_render.swap(false, .acq_rel);
    const should_render = window.benchmark_mode or explicit_render;

    if (!should_render) {
        return .success;
    }

    const pool = createAutoreleasePool() orelse return .success;
    defer drainAutoreleasePool(pool);

    // Acquire render mutex for thread-safe access to all render state
    window.render_mutex.lock();
    defer window.render_mutex.unlock();

    // Mark that rendering is in progress
    window.render_in_progress.store(true, .release);
    defer window.render_in_progress.store(false, .release);

    // Call render callback to let user rebuild scene
    // NOTE: This is called with the lock held, so the callback must not
    // call any Window methods that also try to acquire the lock.
    if (window.on_render) |callback| {
        callback(window);
    }

    // Update text atlas if set
    if (window.text_atlas) |atlas| {
        window.renderer.updateTextAtlas(atlas) catch {};
    }

    // Render the scene
    if (window.scene) |s| {
        window.renderer.renderScene(s, window.background_color) catch |err| {
            std.debug.print("renderScene error: {}\n", .{err});
            window.renderer.clear(window.background_color);
        };
    } else {
        window.renderer.clear(window.background_color);
    }

    return .success;
}

// =============================================================================
// Helpers
// =============================================================================

fn createAutoreleasePool() ?objc.Object {
    const NSAutoreleasePool = objc.getClass("NSAutoreleasePool") orelse return null;
    const pool = NSAutoreleasePool.msgSend(objc.Object, "alloc", .{});
    return pool.msgSend(objc.Object, "init", .{});
}

fn drainAutoreleasePool(pool: objc.Object) void {
    pool.msgSend(void, "drain", .{});
}
