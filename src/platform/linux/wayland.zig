//! Wayland C bindings for Linux windowing
//!
//! These bindings wrap libwayland-client and related protocols to provide
//! native Wayland windowing support on Linux.
//!
//! Protocols used:
//! - wayland-client (core protocol)
//! - xdg-shell (window management)
//! - xdg-decoration (server-side decorations)

const std = @import("std");

// =============================================================================
// Basic Types
// =============================================================================

/// Wayland fixed-point number (24.8 format)
pub const Fixed = i32;

pub fn fixedToDouble(f: Fixed) f64 {
    return @as(f64, @floatFromInt(f)) / 256.0;
}

pub fn doubleToFixed(d: f64) Fixed {
    return @intFromFloat(d * 256.0);
}

// =============================================================================
// Opaque Handle Types
// =============================================================================

pub const Display = opaque {};
pub const Registry = opaque {};
pub const Callback = opaque {};
pub const Compositor = opaque {};
pub const Surface = opaque {};
pub const Region = opaque {};
pub const Buffer = opaque {};
pub const ShmPool = opaque {};
pub const Shm = opaque {};
pub const Seat = opaque {};
pub const Pointer = opaque {};
pub const Keyboard = opaque {};
pub const Touch = opaque {};
pub const Output = opaque {};
pub const Subcompositor = opaque {};
pub const Subsurface = opaque {};

// XDG Shell types
pub const XdgWmBase = opaque {};
pub const XdgSurface = opaque {};
pub const XdgToplevel = opaque {};
pub const XdgPopup = opaque {};
pub const XdgPositioner = opaque {};

// XDG Decoration types
pub const ZxdgDecorationManagerV1 = opaque {};
pub const ZxdgToplevelDecorationV1 = opaque {};

// =============================================================================
// Listener Structs
// =============================================================================

pub const RegistryListener = extern struct {
    global: ?*const fn (
        data: ?*anyopaque,
        registry: *Registry,
        name: u32,
        interface: [*:0]const u8,
        version: u32,
    ) callconv(.C) void = null,
    global_remove: ?*const fn (
        data: ?*anyopaque,
        registry: *Registry,
        name: u32,
    ) callconv(.C) void = null,
};

pub const SurfaceListener = extern struct {
    enter: ?*const fn (
        data: ?*anyopaque,
        surface: *Surface,
        output: *Output,
    ) callconv(.C) void = null,
    leave: ?*const fn (
        data: ?*anyopaque,
        surface: *Surface,
        output: *Output,
    ) callconv(.C) void = null,
    preferred_buffer_scale: ?*const fn (
        data: ?*anyopaque,
        surface: *Surface,
        factor: i32,
    ) callconv(.C) void = null,
    preferred_buffer_transform: ?*const fn (
        data: ?*anyopaque,
        surface: *Surface,
        transform: u32,
    ) callconv(.C) void = null,
};

pub const CallbackListener = extern struct {
    done: ?*const fn (
        data: ?*anyopaque,
        callback: *Callback,
        callback_data: u32,
    ) callconv(.C) void = null,
};

pub const SeatListener = extern struct {
    capabilities: ?*const fn (
        data: ?*anyopaque,
        seat: *Seat,
        capabilities: SeatCapability,
    ) callconv(.C) void = null,
    name: ?*const fn (
        data: ?*anyopaque,
        seat: *Seat,
        name: [*:0]const u8,
    ) callconv(.C) void = null,
};

pub const SeatCapability = packed struct(u32) {
    pointer: bool = false,
    keyboard: bool = false,
    touch: bool = false,
    _padding: u29 = 0,
};

pub const PointerListener = extern struct {
    enter: ?*const fn (
        data: ?*anyopaque,
        pointer: *Pointer,
        serial: u32,
        surface: *Surface,
        surface_x: Fixed,
        surface_y: Fixed,
    ) callconv(.C) void = null,
    leave: ?*const fn (
        data: ?*anyopaque,
        pointer: *Pointer,
        serial: u32,
        surface: *Surface,
    ) callconv(.C) void = null,
    motion: ?*const fn (
        data: ?*anyopaque,
        pointer: *Pointer,
        time: u32,
        surface_x: Fixed,
        surface_y: Fixed,
    ) callconv(.C) void = null,
    button: ?*const fn (
        data: ?*anyopaque,
        pointer: *Pointer,
        serial: u32,
        time: u32,
        button: u32,
        state: PointerButtonState,
    ) callconv(.C) void = null,
    axis: ?*const fn (
        data: ?*anyopaque,
        pointer: *Pointer,
        time: u32,
        axis: PointerAxis,
        value: Fixed,
    ) callconv(.C) void = null,
    frame: ?*const fn (
        data: ?*anyopaque,
        pointer: *Pointer,
    ) callconv(.C) void = null,
    axis_source: ?*const fn (
        data: ?*anyopaque,
        pointer: *Pointer,
        axis_source: PointerAxisSource,
    ) callconv(.C) void = null,
    axis_stop: ?*const fn (
        data: ?*anyopaque,
        pointer: *Pointer,
        time: u32,
        axis: PointerAxis,
    ) callconv(.C) void = null,
    axis_discrete: ?*const fn (
        data: ?*anyopaque,
        pointer: *Pointer,
        axis: PointerAxis,
        discrete: i32,
    ) callconv(.C) void = null,
    axis_value120: ?*const fn (
        data: ?*anyopaque,
        pointer: *Pointer,
        axis: PointerAxis,
        value120: i32,
    ) callconv(.C) void = null,
    axis_relative_direction: ?*const fn (
        data: ?*anyopaque,
        pointer: *Pointer,
        axis: PointerAxis,
        direction: PointerAxisRelativeDirection,
    ) callconv(.C) void = null,
};

pub const PointerButtonState = enum(u32) {
    released = 0,
    pressed = 1,
};

pub const PointerAxis = enum(u32) {
    vertical_scroll = 0,
    horizontal_scroll = 1,
};

pub const PointerAxisSource = enum(u32) {
    wheel = 0,
    finger = 1,
    continuous = 2,
    wheel_tilt = 3,
};

pub const PointerAxisRelativeDirection = enum(u32) {
    identical = 0,
    inverted = 1,
};

pub const KeyboardListener = extern struct {
    keymap: ?*const fn (
        data: ?*anyopaque,
        keyboard: *Keyboard,
        format: KeyboardKeymapFormat,
        fd: i32,
        size: u32,
    ) callconv(.C) void = null,
    enter: ?*const fn (
        data: ?*anyopaque,
        keyboard: *Keyboard,
        serial: u32,
        surface: *Surface,
        keys: *anyopaque, // wl_array*
    ) callconv(.C) void = null,
    leave: ?*const fn (
        data: ?*anyopaque,
        keyboard: *Keyboard,
        serial: u32,
        surface: *Surface,
    ) callconv(.C) void = null,
    key: ?*const fn (
        data: ?*anyopaque,
        keyboard: *Keyboard,
        serial: u32,
        time: u32,
        key: u32,
        state: KeyState,
    ) callconv(.C) void = null,
    modifiers: ?*const fn (
        data: ?*anyopaque,
        keyboard: *Keyboard,
        serial: u32,
        mods_depressed: u32,
        mods_latched: u32,
        mods_locked: u32,
        group: u32,
    ) callconv(.C) void = null,
    repeat_info: ?*const fn (
        data: ?*anyopaque,
        keyboard: *Keyboard,
        rate: i32,
        delay: i32,
    ) callconv(.C) void = null,
};

pub const KeyboardKeymapFormat = enum(u32) {
    no_keymap = 0,
    xkb_v1 = 1,
};

pub const KeyState = enum(u32) {
    released = 0,
    pressed = 1,
};

pub const OutputListener = extern struct {
    geometry: ?*const fn (
        data: ?*anyopaque,
        output: *Output,
        x: i32,
        y: i32,
        physical_width: i32,
        physical_height: i32,
        subpixel: i32,
        make: [*:0]const u8,
        model: [*:0]const u8,
        transform: i32,
    ) callconv(.C) void = null,
    mode: ?*const fn (
        data: ?*anyopaque,
        output: *Output,
        flags: u32,
        width: i32,
        height: i32,
        refresh: i32,
    ) callconv(.C) void = null,
    done: ?*const fn (
        data: ?*anyopaque,
        output: *Output,
    ) callconv(.C) void = null,
    scale: ?*const fn (
        data: ?*anyopaque,
        output: *Output,
        factor: i32,
    ) callconv(.C) void = null,
    name: ?*const fn (
        data: ?*anyopaque,
        output: *Output,
        name: [*:0]const u8,
    ) callconv(.C) void = null,
    description: ?*const fn (
        data: ?*anyopaque,
        output: *Output,
        description: [*:0]const u8,
    ) callconv(.C) void = null,
};

// =============================================================================
// XDG Shell Listeners
// =============================================================================

pub const XdgWmBaseListener = extern struct {
    ping: ?*const fn (
        data: ?*anyopaque,
        xdg_wm_base: *XdgWmBase,
        serial: u32,
    ) callconv(.C) void = null,
};

pub const XdgSurfaceListener = extern struct {
    configure: ?*const fn (
        data: ?*anyopaque,
        xdg_surface: *XdgSurface,
        serial: u32,
    ) callconv(.C) void = null,
};

pub const XdgToplevelListener = extern struct {
    configure: ?*const fn (
        data: ?*anyopaque,
        xdg_toplevel: *XdgToplevel,
        width: i32,
        height: i32,
        states: *anyopaque, // wl_array*
    ) callconv(.C) void = null,
    close: ?*const fn (
        data: ?*anyopaque,
        xdg_toplevel: *XdgToplevel,
    ) callconv(.C) void = null,
    configure_bounds: ?*const fn (
        data: ?*anyopaque,
        xdg_toplevel: *XdgToplevel,
        width: i32,
        height: i32,
    ) callconv(.C) void = null,
    wm_capabilities: ?*const fn (
        data: ?*anyopaque,
        xdg_toplevel: *XdgToplevel,
        capabilities: *anyopaque, // wl_array*
    ) callconv(.C) void = null,
};

pub const XdgToplevelState = enum(u32) {
    maximized = 1,
    fullscreen = 2,
    resizing = 3,
    activated = 4,
    tiled_left = 5,
    tiled_right = 6,
    tiled_top = 7,
    tiled_bottom = 8,
    suspended = 9,
};

// =============================================================================
// XDG Decoration Listeners
// =============================================================================

pub const ZxdgToplevelDecorationV1Listener = extern struct {
    configure: ?*const fn (
        data: ?*anyopaque,
        decoration: *ZxdgToplevelDecorationV1,
        mode: ZxdgToplevelDecorationV1Mode,
    ) callconv(.C) void = null,
};

pub const ZxdgToplevelDecorationV1Mode = enum(u32) {
    undefined = 0,
    client_side = 1,
    server_side = 2,
};

// =============================================================================
// Interface Structs (for wl_proxy_marshal_* calls)
// =============================================================================

pub const Interface = extern struct {
    name: [*:0]const u8,
    version: c_int,
    method_count: c_int,
    methods: ?*const Message,
    event_count: c_int,
    events: ?*const Message,
};

pub const Message = extern struct {
    name: [*:0]const u8,
    signature: [*:0]const u8,
    types: ?*const ?*const Interface,
};

// =============================================================================
// Core Wayland C Functions (libwayland-client.so)
// =============================================================================

// Display
pub extern "wayland-client" fn wl_display_connect(name: ?[*:0]const u8) ?*Display;
pub extern "wayland-client" fn wl_display_disconnect(display: *Display) void;
pub extern "wayland-client" fn wl_display_dispatch(display: *Display) c_int;
pub extern "wayland-client" fn wl_display_dispatch_pending(display: *Display) c_int;
pub extern "wayland-client" fn wl_display_roundtrip(display: *Display) c_int;
pub extern "wayland-client" fn wl_display_flush(display: *Display) c_int;
pub extern "wayland-client" fn wl_display_get_fd(display: *Display) c_int;
pub extern "wayland-client" fn wl_display_get_registry(display: *Display) ?*Registry;

// Proxy (base for all Wayland objects)
pub extern "wayland-client" fn wl_proxy_add_listener(
    proxy: *anyopaque,
    implementation: *const anyopaque,
    data: ?*anyopaque,
) c_int;
pub extern "wayland-client" fn wl_proxy_destroy(proxy: *anyopaque) void;
pub extern "wayland-client" fn wl_proxy_marshal_flags(proxy: *anyopaque, opcode: u32, interface: ?*const Interface, version: u32, flags: u32, ...) ?*anyopaque;
pub extern "wayland-client" fn wl_proxy_get_version(proxy: *anyopaque) u32;

// =============================================================================
// Protocol Interface Declarations (linked from protocol libraries)
// =============================================================================

pub extern "wayland-client" var wl_registry_interface: Interface;
pub extern "wayland-client" var wl_compositor_interface: Interface;
pub extern "wayland-client" var wl_surface_interface: Interface;
pub extern "wayland-client" var wl_region_interface: Interface;
pub extern "wayland-client" var wl_callback_interface: Interface;
pub extern "wayland-client" var wl_seat_interface: Interface;
pub extern "wayland-client" var wl_pointer_interface: Interface;
pub extern "wayland-client" var wl_keyboard_interface: Interface;
pub extern "wayland-client" var wl_output_interface: Interface;
pub extern "wayland-client" var wl_shm_interface: Interface;

// XDG shell interfaces (from xdg-shell protocol)
pub extern "wayland-client" var xdg_wm_base_interface: Interface;
pub extern "wayland-client" var xdg_surface_interface: Interface;
pub extern "wayland-client" var xdg_toplevel_interface: Interface;
pub extern "wayland-client" var xdg_positioner_interface: Interface;

// XDG decoration interfaces
pub extern "wayland-client" var zxdg_decoration_manager_v1_interface: Interface;
pub extern "wayland-client" var zxdg_toplevel_decoration_v1_interface: Interface;

// =============================================================================
// Higher-Level Wrapper Functions
// =============================================================================

const MARSHAL_FLAG_DESTROY: u32 = 1;

// Registry operations
pub fn registryAddListener(registry: *Registry, listener: *const RegistryListener, data: ?*anyopaque) bool {
    return wl_proxy_add_listener(@ptrCast(registry), @ptrCast(listener), data) == 0;
}

pub fn registryBind(registry: *Registry, name: u32, interface: *const Interface, version: u32) ?*anyopaque {
    return wl_proxy_marshal_flags(
        @ptrCast(registry),
        0, // WL_REGISTRY_BIND
        interface,
        version,
        0,
        name,
        interface.name,
        version,
        @as(?*anyopaque, null),
    );
}

pub fn registryDestroy(registry: *Registry) void {
    wl_proxy_destroy(@ptrCast(registry));
}

// Compositor operations
pub fn compositorCreateSurface(compositor: *Compositor) ?*Surface {
    const result = wl_proxy_marshal_flags(
        @ptrCast(compositor),
        0, // WL_COMPOSITOR_CREATE_SURFACE
        &wl_surface_interface,
        wl_proxy_get_version(@ptrCast(compositor)),
        0,
        @as(?*anyopaque, null),
    );
    return @ptrCast(@alignCast(result));
}

pub fn compositorCreateRegion(compositor: *Compositor) ?*Region {
    const result = wl_proxy_marshal_flags(
        @ptrCast(compositor),
        1, // WL_COMPOSITOR_CREATE_REGION
        &wl_region_interface,
        wl_proxy_get_version(@ptrCast(compositor)),
        0,
        @as(?*anyopaque, null),
    );
    return @ptrCast(@alignCast(result));
}

pub fn compositorDestroy(compositor: *Compositor) void {
    wl_proxy_destroy(@ptrCast(compositor));
}

// Surface operations
pub fn surfaceAddListener(surface: *Surface, listener: *const SurfaceListener, data: ?*anyopaque) bool {
    return wl_proxy_add_listener(@ptrCast(surface), @ptrCast(listener), data) == 0;
}

pub fn surfaceDestroy(surface: *Surface) void {
    _ = wl_proxy_marshal_flags(
        @ptrCast(surface),
        0, // WL_SURFACE_DESTROY
        null,
        wl_proxy_get_version(@ptrCast(surface)),
        MARSHAL_FLAG_DESTROY,
    );
}

pub fn surfaceCommit(surface: *Surface) void {
    _ = wl_proxy_marshal_flags(
        @ptrCast(surface),
        6, // WL_SURFACE_COMMIT
        null,
        wl_proxy_get_version(@ptrCast(surface)),
        0,
    );
}

pub fn surfaceFrame(surface: *Surface) ?*Callback {
    const result = wl_proxy_marshal_flags(
        @ptrCast(surface),
        3, // WL_SURFACE_FRAME
        &wl_callback_interface,
        wl_proxy_get_version(@ptrCast(surface)),
        0,
        @as(?*anyopaque, null),
    );
    return @ptrCast(@alignCast(result));
}

pub fn surfaceSetOpaqueRegion(surface: *Surface, region: ?*Region) void {
    _ = wl_proxy_marshal_flags(
        @ptrCast(surface),
        5, // WL_SURFACE_SET_OPAQUE_REGION
        null,
        wl_proxy_get_version(@ptrCast(surface)),
        0,
        @as(?*anyopaque, @ptrCast(region)),
    );
}

// Callback operations
pub fn callbackAddListener(callback: *Callback, listener: *const CallbackListener, data: ?*anyopaque) bool {
    return wl_proxy_add_listener(@ptrCast(callback), @ptrCast(listener), data) == 0;
}

pub fn callbackDestroy(callback: *Callback) void {
    wl_proxy_destroy(@ptrCast(callback));
}

// Region operations
pub fn regionAdd(region: *Region, x: i32, y: i32, width: i32, height: i32) void {
    _ = wl_proxy_marshal_flags(
        @ptrCast(region),
        1, // WL_REGION_ADD
        null,
        wl_proxy_get_version(@ptrCast(region)),
        0,
        x,
        y,
        width,
        height,
    );
}

pub fn regionDestroy(region: *Region) void {
    _ = wl_proxy_marshal_flags(
        @ptrCast(region),
        0, // WL_REGION_DESTROY
        null,
        wl_proxy_get_version(@ptrCast(region)),
        MARSHAL_FLAG_DESTROY,
    );
}

// Seat operations
pub fn seatAddListener(seat: *Seat, listener: *const SeatListener, data: ?*anyopaque) bool {
    return wl_proxy_add_listener(@ptrCast(seat), @ptrCast(listener), data) == 0;
}

pub fn seatGetPointer(seat: *Seat) ?*Pointer {
    const result = wl_proxy_marshal_flags(
        @ptrCast(seat),
        0, // WL_SEAT_GET_POINTER
        &wl_pointer_interface,
        wl_proxy_get_version(@ptrCast(seat)),
        0,
        @as(?*anyopaque, null),
    );
    return @ptrCast(@alignCast(result));
}

pub fn seatGetKeyboard(seat: *Seat) ?*Keyboard {
    const result = wl_proxy_marshal_flags(
        @ptrCast(seat),
        1, // WL_SEAT_GET_KEYBOARD
        &wl_keyboard_interface,
        wl_proxy_get_version(@ptrCast(seat)),
        0,
        @as(?*anyopaque, null),
    );
    return @ptrCast(@alignCast(result));
}

pub fn seatDestroy(seat: *Seat) void {
    wl_proxy_destroy(@ptrCast(seat));
}

// Pointer operations
pub fn pointerAddListener(pointer: *Pointer, listener: *const PointerListener, data: ?*anyopaque) bool {
    return wl_proxy_add_listener(@ptrCast(pointer), @ptrCast(listener), data) == 0;
}

pub fn pointerDestroy(pointer: *Pointer) void {
    _ = wl_proxy_marshal_flags(
        @ptrCast(pointer),
        1, // WL_POINTER_RELEASE
        null,
        wl_proxy_get_version(@ptrCast(pointer)),
        MARSHAL_FLAG_DESTROY,
    );
}

// Keyboard operations
pub fn keyboardAddListener(keyboard: *Keyboard, listener: *const KeyboardListener, data: ?*anyopaque) bool {
    return wl_proxy_add_listener(@ptrCast(keyboard), @ptrCast(listener), data) == 0;
}

pub fn keyboardDestroy(keyboard: *Keyboard) void {
    _ = wl_proxy_marshal_flags(
        @ptrCast(keyboard),
        1, // WL_KEYBOARD_RELEASE
        null,
        wl_proxy_get_version(@ptrCast(keyboard)),
        MARSHAL_FLAG_DESTROY,
    );
}

// Output operations
pub fn outputAddListener(output: *Output, listener: *const OutputListener, data: ?*anyopaque) bool {
    return wl_proxy_add_listener(@ptrCast(output), @ptrCast(listener), data) == 0;
}

pub fn outputDestroy(output: *Output) void {
    wl_proxy_destroy(@ptrCast(output));
}

// =============================================================================
// XDG Shell Wrapper Functions
// =============================================================================

// XDG WM Base
pub fn xdgWmBaseAddListener(wm_base: *XdgWmBase, listener: *const XdgWmBaseListener, data: ?*anyopaque) bool {
    return wl_proxy_add_listener(@ptrCast(wm_base), @ptrCast(listener), data) == 0;
}

pub fn xdgWmBasePong(wm_base: *XdgWmBase, serial: u32) void {
    _ = wl_proxy_marshal_flags(
        @ptrCast(wm_base),
        1, // XDG_WM_BASE_PONG
        null,
        wl_proxy_get_version(@ptrCast(wm_base)),
        0,
        serial,
    );
}

pub fn xdgWmBaseGetXdgSurface(wm_base: *XdgWmBase, surface: *Surface) ?*XdgSurface {
    const result = wl_proxy_marshal_flags(
        @ptrCast(wm_base),
        2, // XDG_WM_BASE_GET_XDG_SURFACE
        &xdg_surface_interface,
        wl_proxy_get_version(@ptrCast(wm_base)),
        0,
        @as(?*anyopaque, null),
        @as(*anyopaque, @ptrCast(surface)),
    );
    return @ptrCast(@alignCast(result));
}

pub fn xdgWmBaseDestroy(wm_base: *XdgWmBase) void {
    _ = wl_proxy_marshal_flags(
        @ptrCast(wm_base),
        0, // XDG_WM_BASE_DESTROY
        null,
        wl_proxy_get_version(@ptrCast(wm_base)),
        MARSHAL_FLAG_DESTROY,
    );
}

// XDG Surface
pub fn xdgSurfaceAddListener(xdg_surface: *XdgSurface, listener: *const XdgSurfaceListener, data: ?*anyopaque) bool {
    return wl_proxy_add_listener(@ptrCast(xdg_surface), @ptrCast(listener), data) == 0;
}

pub fn xdgSurfaceGetToplevel(xdg_surface: *XdgSurface) ?*XdgToplevel {
    const result = wl_proxy_marshal_flags(
        @ptrCast(xdg_surface),
        1, // XDG_SURFACE_GET_TOPLEVEL
        &xdg_toplevel_interface,
        wl_proxy_get_version(@ptrCast(xdg_surface)),
        0,
        @as(?*anyopaque, null),
    );
    return @ptrCast(@alignCast(result));
}

pub fn xdgSurfaceAckConfigure(xdg_surface: *XdgSurface, serial: u32) void {
    _ = wl_proxy_marshal_flags(
        @ptrCast(xdg_surface),
        4, // XDG_SURFACE_ACK_CONFIGURE
        null,
        wl_proxy_get_version(@ptrCast(xdg_surface)),
        0,
        serial,
    );
}

pub fn xdgSurfaceSetWindowGeometry(xdg_surface: *XdgSurface, x: i32, y: i32, width: i32, height: i32) void {
    _ = wl_proxy_marshal_flags(
        @ptrCast(xdg_surface),
        3, // XDG_SURFACE_SET_WINDOW_GEOMETRY
        null,
        wl_proxy_get_version(@ptrCast(xdg_surface)),
        0,
        x,
        y,
        width,
        height,
    );
}

pub fn xdgSurfaceDestroy(xdg_surface: *XdgSurface) void {
    _ = wl_proxy_marshal_flags(
        @ptrCast(xdg_surface),
        0, // XDG_SURFACE_DESTROY
        null,
        wl_proxy_get_version(@ptrCast(xdg_surface)),
        MARSHAL_FLAG_DESTROY,
    );
}

// XDG Toplevel
pub fn xdgToplevelAddListener(toplevel: *XdgToplevel, listener: *const XdgToplevelListener, data: ?*anyopaque) bool {
    return wl_proxy_add_listener(@ptrCast(toplevel), @ptrCast(listener), data) == 0;
}

pub fn xdgToplevelSetTitle(toplevel: *XdgToplevel, title: [*:0]const u8) void {
    _ = wl_proxy_marshal_flags(
        @ptrCast(toplevel),
        2, // XDG_TOPLEVEL_SET_TITLE
        null,
        wl_proxy_get_version(@ptrCast(toplevel)),
        0,
        title,
    );
}

pub fn xdgToplevelSetAppId(toplevel: *XdgToplevel, app_id: [*:0]const u8) void {
    _ = wl_proxy_marshal_flags(
        @ptrCast(toplevel),
        3, // XDG_TOPLEVEL_SET_APP_ID
        null,
        wl_proxy_get_version(@ptrCast(toplevel)),
        0,
        app_id,
    );
}

pub fn xdgToplevelSetMinSize(toplevel: *XdgToplevel, width: i32, height: i32) void {
    _ = wl_proxy_marshal_flags(
        @ptrCast(toplevel),
        7, // XDG_TOPLEVEL_SET_MIN_SIZE
        null,
        wl_proxy_get_version(@ptrCast(toplevel)),
        0,
        width,
        height,
    );
}

pub fn xdgToplevelSetMaxSize(toplevel: *XdgToplevel, width: i32, height: i32) void {
    _ = wl_proxy_marshal_flags(
        @ptrCast(toplevel),
        8, // XDG_TOPLEVEL_SET_MAX_SIZE
        null,
        wl_proxy_get_version(@ptrCast(toplevel)),
        0,
        width,
        height,
    );
}

pub fn xdgToplevelDestroy(toplevel: *XdgToplevel) void {
    _ = wl_proxy_marshal_flags(
        @ptrCast(toplevel),
        0, // XDG_TOPLEVEL_DESTROY
        null,
        wl_proxy_get_version(@ptrCast(toplevel)),
        MARSHAL_FLAG_DESTROY,
    );
}

// =============================================================================
// XDG Decoration Wrapper Functions
// =============================================================================

pub fn zxdgDecorationManagerV1GetToplevelDecoration(
    manager: *ZxdgDecorationManagerV1,
    toplevel: *XdgToplevel,
) ?*ZxdgToplevelDecorationV1 {
    const result = wl_proxy_marshal_flags(
        @ptrCast(manager),
        1, // ZXDG_DECORATION_MANAGER_V1_GET_TOPLEVEL_DECORATION
        &zxdg_toplevel_decoration_v1_interface,
        wl_proxy_get_version(@ptrCast(manager)),
        0,
        @as(?*anyopaque, null),
        @as(*anyopaque, @ptrCast(toplevel)),
    );
    return @ptrCast(@alignCast(result));
}

pub fn zxdgDecorationManagerV1Destroy(manager: *ZxdgDecorationManagerV1) void {
    _ = wl_proxy_marshal_flags(
        @ptrCast(manager),
        0, // ZXDG_DECORATION_MANAGER_V1_DESTROY
        null,
        wl_proxy_get_version(@ptrCast(manager)),
        MARSHAL_FLAG_DESTROY,
    );
}

pub fn zxdgToplevelDecorationV1AddListener(
    decoration: *ZxdgToplevelDecorationV1,
    listener: *const ZxdgToplevelDecorationV1Listener,
    data: ?*anyopaque,
) bool {
    return wl_proxy_add_listener(@ptrCast(decoration), @ptrCast(listener), data) == 0;
}

pub fn zxdgToplevelDecorationV1SetMode(decoration: *ZxdgToplevelDecorationV1, mode: ZxdgToplevelDecorationV1Mode) void {
    _ = wl_proxy_marshal_flags(
        @ptrCast(decoration),
        1, // ZXDG_TOPLEVEL_DECORATION_V1_SET_MODE
        null,
        wl_proxy_get_version(@ptrCast(decoration)),
        0,
        @intFromEnum(mode),
    );
}

pub fn zxdgToplevelDecorationV1Destroy(decoration: *ZxdgToplevelDecorationV1) void {
    _ = wl_proxy_marshal_flags(
        @ptrCast(decoration),
        0, // ZXDG_TOPLEVEL_DECORATION_V1_DESTROY
        null,
        wl_proxy_get_version(@ptrCast(decoration)),
        MARSHAL_FLAG_DESTROY,
    );
}

// =============================================================================
// Helper Constants
// =============================================================================

/// Linux button codes (from linux/input-event-codes.h)
pub const BTN_LEFT: u32 = 0x110;
pub const BTN_RIGHT: u32 = 0x111;
pub const BTN_MIDDLE: u32 = 0x112;

/// Interface name constants for registry binding
pub const WL_COMPOSITOR_INTERFACE_NAME = "wl_compositor";
pub const WL_SHM_INTERFACE_NAME = "wl_shm";
pub const WL_SEAT_INTERFACE_NAME = "wl_seat";
pub const WL_OUTPUT_INTERFACE_NAME = "wl_output";
pub const XDG_WM_BASE_INTERFACE_NAME = "xdg_wm_base";
pub const ZXDG_DECORATION_MANAGER_V1_INTERFACE_NAME = "zxdg_decoration_manager_v1";
