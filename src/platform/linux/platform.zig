//! LinuxPlatform - Platform implementation for Linux/Wayland
//!
//! Provides the main event loop and platform lifecycle for Linux systems
//! using Wayland as the display server protocol.

const std = @import("std");
const wayland = @import("wayland.zig");
const interface_mod = @import("../interface.zig");

pub const LinuxPlatform = struct {
    running: bool = true,
    display: ?*wayland.Display = null,

    // Global Wayland objects
    registry: ?*wayland.Registry = null,
    compositor: ?*wayland.Compositor = null,
    xdg_wm_base: ?*wayland.XdgWmBase = null,
    decoration_manager: ?*wayland.ZxdgDecorationManagerV1 = null,
    seat: ?*wayland.Seat = null,
    pointer: ?*wayland.Pointer = null,
    keyboard: ?*wayland.Keyboard = null,

    // Input state
    pointer_x: f64 = 0,
    pointer_y: f64 = 0,
    pointer_buttons: u32 = 0,
    last_key_serial: u32 = 0,

    // Scale factor from output
    scale_factor: i32 = 1,

    const Self = @This();

    /// Platform capabilities for Linux/Wayland
    pub const capabilities = interface_mod.PlatformCapabilities{
        .high_dpi = true,
        .multi_window = true,
        .gpu_accelerated = true,
        .display_link = false, // Uses frame callbacks
        .can_close_window = true,
        .glass_effects = false, // Compositor-dependent
        .clipboard = true,
        .file_dialogs = false, // Need portal integration
        .ime = true,
        .custom_cursors = true,
        .window_drag_by_content = false,
        .name = "Linux/Wayland",
        .graphics_backend = "Vulkan (wgpu-native)",
    };

    pub fn init() !Self {
        var self = Self{};

        // Connect to Wayland display
        self.display = wayland.wl_display_connect(null) orelse {
            return error.FailedToConnectToDisplay;
        };

        // Get registry
        self.registry = wayland.wl_display_get_registry(self.display.?) orelse {
            return error.FailedToGetRegistry;
        };

        // Set up registry listener
        const registry_listener = wayland.RegistryListener{
            .global = registryGlobal,
            .global_remove = registryGlobalRemove,
        };
        _ = wayland.registryAddListener(self.registry.?, &registry_listener, &self);

        // Roundtrip to get all globals
        _ = wayland.wl_display_roundtrip(self.display.?);

        // Verify we have required globals
        if (self.compositor == null) {
            return error.MissingCompositor;
        }
        if (self.xdg_wm_base == null) {
            return error.MissingXdgWmBase;
        }

        // Set up XDG WM base listener for ping/pong
        const wm_base_listener = wayland.XdgWmBaseListener{
            .ping = xdgWmBasePing,
        };
        _ = wayland.xdgWmBaseAddListener(self.xdg_wm_base.?, &wm_base_listener, &self);

        return self;
    }

    pub fn deinit(self: *Self) void {
        if (self.keyboard) |kb| wayland.keyboardDestroy(kb);
        if (self.pointer) |ptr| wayland.pointerDestroy(ptr);
        if (self.seat) |seat| wayland.seatDestroy(seat);
        if (self.decoration_manager) |dm| wayland.zxdgDecorationManagerV1Destroy(dm);
        if (self.xdg_wm_base) |wm| wayland.xdgWmBaseDestroy(wm);
        if (self.compositor) |comp| wayland.compositorDestroy(comp);
        if (self.registry) |reg| wayland.registryDestroy(reg);
        if (self.display) |disp| wayland.wl_display_disconnect(disp);

        self.running = false;
    }

    /// Run the platform event loop (blocking)
    pub fn run(self: *Self) void {
        while (self.running) {
            // Dispatch Wayland events
            if (wayland.wl_display_dispatch(self.display.?) < 0) {
                // Connection error
                self.running = false;
                break;
            }
        }
    }

    /// Run a single iteration of the event loop (non-blocking)
    pub fn poll(self: *Self) bool {
        if (!self.running) return false;

        // Flush outgoing requests
        _ = wayland.wl_display_flush(self.display.?);

        // Dispatch pending events
        if (wayland.wl_display_dispatch_pending(self.display.?) < 0) {
            self.running = false;
            return false;
        }

        return self.running;
    }

    /// Signal the platform to quit
    pub fn quit(self: *Self) void {
        self.running = false;
    }

    pub fn isRunning(self: *const Self) bool {
        return self.running;
    }

    /// Get the Wayland display pointer (for wgpu surface creation)
    pub fn getDisplay(self: *Self) ?*anyopaque {
        return @ptrCast(self.display);
    }

    /// Get the compositor for creating surfaces
    pub fn getCompositor(self: *Self) ?*wayland.Compositor {
        return self.compositor;
    }

    /// Get the XDG WM base for window management
    pub fn getXdgWmBase(self: *Self) ?*wayland.XdgWmBase {
        return self.xdg_wm_base;
    }

    /// Get the decoration manager (may be null if not supported)
    pub fn getDecorationManager(self: *Self) ?*wayland.ZxdgDecorationManagerV1 {
        return self.decoration_manager;
    }

    /// Get current scale factor
    pub fn getScaleFactor(self: *const Self) f64 {
        return @floatFromInt(self.scale_factor);
    }

    /// Get interface for runtime polymorphism
    pub fn interface(self: *Self) interface_mod.PlatformVTable {
        return interface_mod.makePlatformVTable(Self, self);
    }

    // =========================================================================
    // Wayland Callbacks
    // =========================================================================

    fn registryGlobal(
        data: ?*anyopaque,
        registry: *wayland.Registry,
        name: u32,
        iface: [*:0]const u8,
        version: u32,
    ) callconv(.C) void {
        const self: *Self = @ptrCast(@alignCast(data));
        const interface_name = std.mem.span(iface);

        if (std.mem.eql(u8, interface_name, wayland.WL_COMPOSITOR_INTERFACE_NAME)) {
            self.compositor = @ptrCast(@alignCast(wayland.registryBind(
                registry,
                name,
                &wayland.wl_compositor_interface,
                @min(version, 6),
            )));
        } else if (std.mem.eql(u8, interface_name, wayland.XDG_WM_BASE_INTERFACE_NAME)) {
            self.xdg_wm_base = @ptrCast(@alignCast(wayland.registryBind(
                registry,
                name,
                &wayland.xdg_wm_base_interface,
                @min(version, 6),
            )));
        } else if (std.mem.eql(u8, interface_name, wayland.ZXDG_DECORATION_MANAGER_V1_INTERFACE_NAME)) {
            self.decoration_manager = @ptrCast(@alignCast(wayland.registryBind(
                registry,
                name,
                &wayland.zxdg_decoration_manager_v1_interface,
                @min(version, 1),
            )));
        } else if (std.mem.eql(u8, interface_name, wayland.WL_SEAT_INTERFACE_NAME)) {
            self.seat = @ptrCast(@alignCast(wayland.registryBind(
                registry,
                name,
                &wayland.wl_seat_interface,
                @min(version, 8),
            )));

            if (self.seat) |seat| {
                const seat_listener = wayland.SeatListener{
                    .capabilities = seatCapabilities,
                    .name = null,
                };
                _ = wayland.seatAddListener(seat, &seat_listener, self);
            }
        }
    }

    fn registryGlobalRemove(
        data: ?*anyopaque,
        registry: *wayland.Registry,
        name: u32,
    ) callconv(.C) void {
        _ = data;
        _ = registry;
        _ = name;
        // Handle global removal if needed
    }

    fn xdgWmBasePing(
        data: ?*anyopaque,
        xdg_wm_base: *wayland.XdgWmBase,
        serial: u32,
    ) callconv(.C) void {
        _ = data;
        wayland.xdgWmBasePong(xdg_wm_base, serial);
    }

    fn seatCapabilities(
        data: ?*anyopaque,
        seat: *wayland.Seat,
        caps: wayland.SeatCapability,
    ) callconv(.C) void {
        const self: *Self = @ptrCast(@alignCast(data));

        // Handle pointer
        if (caps.pointer and self.pointer == null) {
            self.pointer = wayland.seatGetPointer(seat);
            if (self.pointer) |ptr| {
                const pointer_listener = wayland.PointerListener{
                    .enter = pointerEnter,
                    .leave = pointerLeave,
                    .motion = pointerMotion,
                    .button = pointerButton,
                    .axis = pointerAxis,
                    .frame = null,
                    .axis_source = null,
                    .axis_stop = null,
                    .axis_discrete = null,
                    .axis_value120 = null,
                    .axis_relative_direction = null,
                };
                _ = wayland.pointerAddListener(ptr, &pointer_listener, self);
            }
        } else if (!caps.pointer and self.pointer != null) {
            wayland.pointerDestroy(self.pointer.?);
            self.pointer = null;
        }

        // Handle keyboard
        if (caps.keyboard and self.keyboard == null) {
            self.keyboard = wayland.seatGetKeyboard(seat);
            if (self.keyboard) |kb| {
                const keyboard_listener = wayland.KeyboardListener{
                    .keymap = null,
                    .enter = keyboardEnter,
                    .leave = keyboardLeave,
                    .key = keyboardKey,
                    .modifiers = keyboardModifiers,
                    .repeat_info = null,
                };
                _ = wayland.keyboardAddListener(kb, &keyboard_listener, self);
            }
        } else if (!caps.keyboard and self.keyboard != null) {
            wayland.keyboardDestroy(self.keyboard.?);
            self.keyboard = null;
        }
    }

    fn pointerEnter(
        data: ?*anyopaque,
        pointer: *wayland.Pointer,
        serial: u32,
        surface: *wayland.Surface,
        surface_x: wayland.Fixed,
        surface_y: wayland.Fixed,
    ) callconv(.C) void {
        _ = pointer;
        _ = serial;
        _ = surface;
        const self: *Self = @ptrCast(@alignCast(data));
        self.pointer_x = wayland.fixedToDouble(surface_x);
        self.pointer_y = wayland.fixedToDouble(surface_y);
    }

    fn pointerLeave(
        data: ?*anyopaque,
        pointer: *wayland.Pointer,
        serial: u32,
        surface: *wayland.Surface,
    ) callconv(.C) void {
        _ = data;
        _ = pointer;
        _ = serial;
        _ = surface;
    }

    fn pointerMotion(
        data: ?*anyopaque,
        pointer: *wayland.Pointer,
        time: u32,
        surface_x: wayland.Fixed,
        surface_y: wayland.Fixed,
    ) callconv(.C) void {
        _ = pointer;
        _ = time;
        const self: *Self = @ptrCast(@alignCast(data));
        self.pointer_x = wayland.fixedToDouble(surface_x);
        self.pointer_y = wayland.fixedToDouble(surface_y);
    }

    fn pointerButton(
        data: ?*anyopaque,
        pointer: *wayland.Pointer,
        serial: u32,
        time: u32,
        button: u32,
        state: wayland.PointerButtonState,
    ) callconv(.C) void {
        _ = pointer;
        _ = serial;
        _ = time;
        const self: *Self = @ptrCast(@alignCast(data));

        const button_bit: u32 = switch (button) {
            wayland.BTN_LEFT => 1,
            wayland.BTN_RIGHT => 2,
            wayland.BTN_MIDDLE => 4,
            else => 0,
        };

        if (state == .pressed) {
            self.pointer_buttons |= button_bit;
        } else {
            self.pointer_buttons &= ~button_bit;
        }
    }

    fn pointerAxis(
        data: ?*anyopaque,
        pointer: *wayland.Pointer,
        time: u32,
        axis: wayland.PointerAxis,
        value: wayland.Fixed,
    ) callconv(.C) void {
        _ = data;
        _ = pointer;
        _ = time;
        _ = axis;
        _ = value;
        // TODO: Handle scroll events
    }

    fn keyboardEnter(
        data: ?*anyopaque,
        keyboard: *wayland.Keyboard,
        serial: u32,
        surface: *wayland.Surface,
        keys: *anyopaque,
    ) callconv(.C) void {
        _ = data;
        _ = keyboard;
        _ = serial;
        _ = surface;
        _ = keys;
    }

    fn keyboardLeave(
        data: ?*anyopaque,
        keyboard: *wayland.Keyboard,
        serial: u32,
        surface: *wayland.Surface,
    ) callconv(.C) void {
        _ = data;
        _ = keyboard;
        _ = serial;
        _ = surface;
    }

    fn keyboardKey(
        data: ?*anyopaque,
        keyboard: *wayland.Keyboard,
        serial: u32,
        time: u32,
        key: u32,
        state: wayland.KeyState,
    ) callconv(.C) void {
        _ = keyboard;
        _ = time;
        _ = key;
        _ = state;
        const self: *Self = @ptrCast(@alignCast(data));
        self.last_key_serial = serial;
        // TODO: Convert Linux keycode to gooey KeyCode and dispatch
    }

    fn keyboardModifiers(
        data: ?*anyopaque,
        keyboard: *wayland.Keyboard,
        serial: u32,
        mods_depressed: u32,
        mods_latched: u32,
        mods_locked: u32,
        group: u32,
    ) callconv(.C) void {
        _ = data;
        _ = keyboard;
        _ = serial;
        _ = mods_depressed;
        _ = mods_latched;
        _ = mods_locked;
        _ = group;
        // TODO: Track modifier state
    }
};
