//! LinuxWindow - Window implementation for Linux/Wayland
//!
//! Provides window creation and management using Wayland's XDG shell protocol,
//! with GPU rendering via wgpu-native.

const std = @import("std");
const wayland = @import("wayland.zig");
const wgpu = @import("wgpu.zig");
const LinuxRenderer = @import("renderer.zig").LinuxRenderer;
const LinuxPlatform = @import("platform.zig").LinuxPlatform;
const interface_mod = @import("../interface.zig");
const geometry = @import("../../core/geometry.zig");
const scene_mod = @import("../../core/scene.zig");
const text_mod = @import("../../text/mod.zig");

const Allocator = std.mem.Allocator;
const WindowOptions = interface_mod.WindowOptions;

pub const Window = struct {
    allocator: Allocator,
    platform: *LinuxPlatform,

    // Wayland objects
    wl_surface: ?*wayland.Surface = null,
    xdg_surface: ?*wayland.XdgSurface = null,
    xdg_toplevel: ?*wayland.XdgToplevel = null,
    decoration: ?*wayland.ZxdgToplevelDecorationV1 = null,
    frame_callback: ?*wayland.Callback = null,

    // Window state
    width: u32 = 800,
    height: u32 = 600,
    scale_factor: f64 = 1.0,
    configured: bool = false,
    closed: bool = false,
    pending_resize: bool = false,
    pending_width: u32 = 0,
    pending_height: u32 = 0,

    // Input state
    mouse_x: f64 = 0,
    mouse_y: f64 = 0,
    mouse_inside: bool = false,

    // Rendering
    renderer: LinuxRenderer,
    background_color: geometry.Color = geometry.Color.init(0.2, 0.2, 0.25, 1.0),
    needs_redraw: bool = true,

    // Scene reference (set externally)
    scene: ?*const scene_mod.Scene = null,
    text_atlas: ?*const text_mod.Atlas = null,

    // Title storage
    title_buf: [256]u8 = undefined,
    title_len: usize = 0,

    const Self = @This();

    pub fn init(allocator: Allocator, platform: *LinuxPlatform, options: WindowOptions) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.* = Self{
            .allocator = allocator,
            .platform = platform,
            .width = @intFromFloat(options.width),
            .height = @intFromFloat(options.height),
            .background_color = options.background_color,
            .renderer = LinuxRenderer.init(allocator),
        };

        // Store title
        const title_len = @min(options.title.len, self.title_buf.len - 1);
        @memcpy(self.title_buf[0..title_len], options.title[0..title_len]);
        self.title_buf[title_len] = 0;
        self.title_len = title_len;

        // Create Wayland surface
        const compositor = platform.getCompositor() orelse return error.NoCompositor;
        self.wl_surface = wayland.compositorCreateSurface(compositor) orelse return error.FailedToCreateSurface;

        // Set up surface listener
        const surface_listener = wayland.SurfaceListener{
            .enter = surfaceEnter,
            .leave = surfaceLeave,
            .preferred_buffer_scale = surfacePreferredScale,
            .preferred_buffer_transform = null,
        };
        _ = wayland.surfaceAddListener(self.wl_surface.?, &surface_listener, self);

        // Create XDG surface
        const xdg_wm_base = platform.getXdgWmBase() orelse return error.NoXdgWmBase;
        self.xdg_surface = wayland.xdgWmBaseGetXdgSurface(xdg_wm_base, self.wl_surface.?) orelse return error.FailedToCreateXdgSurface;

        // Set up XDG surface listener
        const xdg_surface_listener = wayland.XdgSurfaceListener{
            .configure = xdgSurfaceConfigure,
        };
        _ = wayland.xdgSurfaceAddListener(self.xdg_surface.?, &xdg_surface_listener, self);

        // Create XDG toplevel
        self.xdg_toplevel = wayland.xdgSurfaceGetToplevel(self.xdg_surface.?) orelse return error.FailedToCreateToplevel;

        // Set up toplevel listener
        const toplevel_listener = wayland.XdgToplevelListener{
            .configure = xdgToplevelConfigure,
            .close = xdgToplevelClose,
            .configure_bounds = null,
            .wm_capabilities = null,
        };
        _ = wayland.xdgToplevelAddListener(self.xdg_toplevel.?, &toplevel_listener, self);

        // Set window properties
        wayland.xdgToplevelSetTitle(self.xdg_toplevel.?, @ptrCast(&self.title_buf));
        wayland.xdgToplevelSetAppId(self.xdg_toplevel.?, "gooey");

        // Set size hints
        if (options.min_size) |min| {
            wayland.xdgToplevelSetMinSize(
                self.xdg_toplevel.?,
                @intFromFloat(min.width),
                @intFromFloat(min.height),
            );
        }
        if (options.max_size) |max| {
            wayland.xdgToplevelSetMaxSize(
                self.xdg_toplevel.?,
                @intFromFloat(max.width),
                @intFromFloat(max.height),
            );
        }

        // Request server-side decorations if available
        if (platform.getDecorationManager()) |dm| {
            self.decoration = wayland.zxdgDecorationManagerV1GetToplevelDecoration(dm, self.xdg_toplevel.?);
            if (self.decoration) |dec| {
                wayland.zxdgToplevelDecorationV1SetMode(dec, .server_side);
            }
        }

        // Commit surface to trigger configure events
        wayland.surfaceCommit(self.wl_surface.?);

        // Wait for initial configure
        _ = wayland.wl_display_roundtrip(platform.display.?);

        // Initialize renderer with Wayland surface
        const wl_display = platform.getDisplay() orelse return error.NoDisplay;
        try self.renderer.initWithWaylandSurface(
            wl_display,
            @ptrCast(self.wl_surface),
            self.width,
            self.height,
        );

        return self;
    }

    pub fn deinit(self: *Self) void {
        // Cancel any pending frame callback
        if (self.frame_callback) |cb| {
            wayland.callbackDestroy(cb);
        }

        // Clean up renderer
        self.renderer.deinit();

        // Destroy Wayland objects in reverse order
        if (self.decoration) |dec| wayland.zxdgToplevelDecorationV1Destroy(dec);
        if (self.xdg_toplevel) |tl| wayland.xdgToplevelDestroy(tl);
        if (self.xdg_surface) |xs| wayland.xdgSurfaceDestroy(xs);
        if (self.wl_surface) |s| wayland.surfaceDestroy(s);

        self.allocator.destroy(self);
    }

    // =========================================================================
    // Public Interface
    // =========================================================================

    pub fn getWidth(self: *const Self) u32 {
        return self.width;
    }

    pub fn getHeight(self: *const Self) u32 {
        return self.height;
    }

    pub fn getSize(self: *const Self) geometry.Size(f64) {
        return .{
            .width = @floatFromInt(self.width),
            .height = @floatFromInt(self.height),
        };
    }

    pub fn getScaleFactor(self: *const Self) f64 {
        return self.scale_factor;
    }

    pub fn setTitle(self: *Self, title: []const u8) void {
        const len = @min(title.len, self.title_buf.len - 1);
        @memcpy(self.title_buf[0..len], title[0..len]);
        self.title_buf[len] = 0;
        self.title_len = len;

        if (self.xdg_toplevel) |tl| {
            wayland.xdgToplevelSetTitle(tl, @ptrCast(&self.title_buf));
        }
    }

    pub fn setBackgroundColor(self: *Self, color: geometry.Color) void {
        self.background_color = color;
        self.requestRender();
    }

    pub fn getMousePosition(self: *const Self) geometry.Point(f64) {
        return .{
            .x = self.mouse_x,
            .y = self.mouse_y,
        };
    }

    pub fn isMouseInside(self: *const Self) bool {
        return self.mouse_inside;
    }

    pub fn isClosed(self: *const Self) bool {
        return self.closed;
    }

    pub fn requestRender(self: *Self) void {
        self.needs_redraw = true;
        self.scheduleFrame();
    }

    pub fn setScene(self: *Self, scene: *const scene_mod.Scene) void {
        self.scene = scene;
    }

    pub fn setTextAtlas(self: *Self, atlas: *const text_mod.Atlas) void {
        self.text_atlas = atlas;
    }

    /// Schedule a frame callback for the next vsync
    fn scheduleFrame(self: *Self) void {
        if (self.frame_callback != null) return; // Already scheduled
        if (self.wl_surface == null) return;

        self.frame_callback = wayland.surfaceFrame(self.wl_surface.?);
        if (self.frame_callback) |cb| {
            const callback_listener = wayland.CallbackListener{
                .done = frameCallback,
            };
            _ = wayland.callbackAddListener(cb, &callback_listener, self);
        }
        wayland.surfaceCommit(self.wl_surface.?);
    }

    /// Render the current frame
    pub fn renderFrame(self: *Self) void {
        if (!self.configured) return;
        if (!self.needs_redraw and !self.pending_resize) return;

        // Handle pending resize
        if (self.pending_resize) {
            self.width = self.pending_width;
            self.height = self.pending_height;
            self.renderer.resize(self.width, self.height);
            self.pending_resize = false;
        }

        // Get clear color in RGB
        const rgb = self.background_color.toRgba();

        // Render scene if available
        if (self.scene) |scene| {
            // Cast away const for the mutable scene pointer the renderer expects
            const mutable_scene: *scene_mod.Scene = @constCast(scene);
            self.renderer.render(
                mutable_scene,
                @floatFromInt(self.width),
                @floatFromInt(self.height),
                rgb[0],
                rgb[1],
                rgb[2],
                rgb[3],
            );
        } else {
            // Just clear to background color
            var empty_scene = scene_mod.Scene.init(self.allocator);
            defer empty_scene.deinit();
            self.renderer.render(
                &empty_scene,
                @floatFromInt(self.width),
                @floatFromInt(self.height),
                rgb[0],
                rgb[1],
                rgb[2],
                rgb[3],
            );
        }

        self.needs_redraw = false;
    }

    // =========================================================================
    // Wayland Callbacks
    // =========================================================================

    fn surfaceEnter(
        data: ?*anyopaque,
        surface: *wayland.Surface,
        output: *wayland.Output,
    ) callconv(.C) void {
        _ = surface;
        _ = output;
        const self: *Self = @ptrCast(@alignCast(data));
        self.mouse_inside = true;
    }

    fn surfaceLeave(
        data: ?*anyopaque,
        surface: *wayland.Surface,
        output: *wayland.Output,
    ) callconv(.C) void {
        _ = surface;
        _ = output;
        const self: *Self = @ptrCast(@alignCast(data));
        self.mouse_inside = false;
    }

    fn surfacePreferredScale(
        data: ?*anyopaque,
        surface: *wayland.Surface,
        factor: i32,
    ) callconv(.C) void {
        _ = surface;
        const self: *Self = @ptrCast(@alignCast(data));
        self.scale_factor = @floatFromInt(factor);
        self.requestRender();
    }

    fn xdgSurfaceConfigure(
        data: ?*anyopaque,
        xdg_surface: *wayland.XdgSurface,
        serial: u32,
    ) callconv(.C) void {
        const self: *Self = @ptrCast(@alignCast(data));

        // Acknowledge the configure
        wayland.xdgSurfaceAckConfigure(xdg_surface, serial);

        // Apply pending size changes
        if (self.pending_width > 0 and self.pending_height > 0) {
            self.pending_resize = true;
        }

        self.configured = true;
        self.requestRender();
    }

    fn xdgToplevelConfigure(
        data: ?*anyopaque,
        xdg_toplevel: *wayland.XdgToplevel,
        width: i32,
        height: i32,
        states: *anyopaque,
    ) callconv(.C) void {
        _ = xdg_toplevel;
        _ = states;
        const self: *Self = @ptrCast(@alignCast(data));

        // Width/height of 0 means we can choose our own size
        if (width > 0 and height > 0) {
            self.pending_width = @intCast(width);
            self.pending_height = @intCast(height);
        } else {
            self.pending_width = self.width;
            self.pending_height = self.height;
        }
    }

    fn xdgToplevelClose(
        data: ?*anyopaque,
        xdg_toplevel: *wayland.XdgToplevel,
    ) callconv(.C) void {
        _ = xdg_toplevel;
        const self: *Self = @ptrCast(@alignCast(data));
        self.closed = true;
        self.platform.quit();
    }

    fn frameCallback(
        data: ?*anyopaque,
        callback: *wayland.Callback,
        callback_data: u32,
    ) callconv(.C) void {
        _ = callback_data;
        const self: *Self = @ptrCast(@alignCast(data));

        // Destroy the callback
        wayland.callbackDestroy(callback);
        self.frame_callback = null;

        // Render the frame
        self.renderFrame();

        // Schedule next frame if we still need to redraw
        if (self.needs_redraw) {
            self.scheduleFrame();
        }
    }
};
