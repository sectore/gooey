//! Context - Typed application context for stateful UI
//!
//! ## Handler Patterns
//!
//! | API | Signature | Use Case | Testable? |
//! |-----|-----------|----------|-----------|
//! | `cx.update(m)` | `fn(*State) void` | Pure state mutation | ✅ Yes |
//! | `cx.updateWith(arg, m)` | `fn(*State, Arg) void` | Pure with data | ✅ Yes |
//! | `cx.command(m)` | `fn(*State, *Gooey) void` | Framework operations | ⚠️ Needs Gooey |
//! | `cx.commandWith(arg, m)` | `fn(*State, *Gooey, Arg) void` | Framework ops + data | ⚠️ Needs Gooey |
//!
//! ## Pure State Pattern (Recommended)
//!
//! Keep state pure (no UI knowledge) and use `update()` for mutations:
//!
//! ```zig
//! // State is pure - no cx, no notify, just data + logic
//! const AppState = struct {
//!     count: i32 = 0,
//!     page: Page = .home,
//!
//!     pub fn increment(self: *AppState) void {
//!         self.count += 1;
//!     }
//!
//!     pub fn goToPage(self: *AppState, page: Page) void {
//!         self.page = page;
//!     }
//! };
//!
//! fn render(cx: *gooey.Context(AppState)) void {
//!     cx.vstack(.{}, .{
//!         gooey.ui.textFmt("{d}", .{cx.state().count}, .{}),
//!         // cx.update() calls the method, then auto-notifies
//!         gooey.ui.buttonHandler("+", cx.update(AppState.increment)),
//!         gooey.ui.buttonHandler("Home", cx.updateWith(.home, AppState.goToPage)),
//!     });
//! }
//!
//! // Testing state is easy - no mocking!
//! test "increment works" {
//!     var state = AppState{};
//!     state.increment();
//!     try std.testing.expectEqual(1, state.count);
//! }
//! ```
//!
//! ## Command Pattern (Framework Access)
//!
//! Use `command()` when you need framework operations (focus, window, etc.):
//!
//! ```zig
//! const AppState = struct {
//!     page: Page = .home,
//!
//!     // COMMAND - needs framework for focus/window operations
//!     pub fn goToFormsWithFocus(self: *AppState, g: *Gooey) void {
//!         self.page = .forms;
//!         g.focusTextInput("form_name");
//!     }
//!
//!     pub fn openSettings(self: *AppState, g: *Gooey) void {
//!         _ = self;
//!         g.window.setTitle("Settings");
//!     }
//! };
//!
//! fn render(cx: *gooey.Context(AppState)) void {
//!     cx.vstack(.{}, .{
//!         // Command handlers (need framework access)
//!         gooey.ui.buttonHandler("Forms", cx.command(AppState.goToFormsWithFocus)),
//!         gooey.ui.buttonHandler("Settings", cx.command(AppState.openSettings)),
//!     });
//! }
//! ```
//!
//! ## Window Operations
//!
//! Access window operations through `cx.window()`:
//!
//! ```zig
//! fn handleClick(self: *AppState, g: *Gooey) void {
//!     _ = self;
//!     // Namespaced window operations
//!     const win = WindowOps{ .gooey = g };
//!     win.setTitle("New Title");
//!     const size = win.size();
//!     _ = size;
//! }
//! ```

const std = @import("std");

// Forward declarations for dependencies
const Gooey = @import("gooey.zig").Gooey;
const ui_mod = @import("../ui/ui.zig");
const Builder = ui_mod.Builder;
// Handler support
const handler_mod = @import("handler.zig");
pub const HandlerRef = handler_mod.HandlerRef;
pub const EntityId = handler_mod.EntityId;

/// Context wraps UI + user state, providing typed access to application state
/// and convenience methods for UI operations.
///
/// The `State` type parameter is the user's application state struct.
pub fn Context(comptime State: type) type {
    return struct {
        const Self = @This();

        // =====================================================================
        // Core References
        // =====================================================================

        /// The underlying Gooey context (layout, scene, widgets, etc.)
        gooey: *Gooey,

        /// The builder for layout operations (only valid during render)
        builder: *Builder,

        /// Pointer to the user's application state
        user_state: *State,

        // =====================================================================
        // State Access
        // =====================================================================

        /// Get mutable access to the application state
        pub fn state(self: *Self) *State {
            return self.user_state;
        }

        /// Get read-only access to the application state
        pub fn stateConst(self: *const Self) *const State {
            return self.user_state;
        }

        // =====================================================================
        // Reactivity
        // =====================================================================

        /// Trigger a UI re-render
        ///
        /// Call this after modifying state to ensure the UI updates.
        /// Note: When using `update()`, `updateWith()`, `command()`, or `commandWith()`,
        /// notification is automatic.
        pub fn notify(self: *Self) void {
            self.gooey.requestRender();
        }

        // =====================================================================
        // PURE HANDLERS - update / updateWith
        // =====================================================================

        /// Create a handler from a pure state method.
        ///
        /// The method should be `fn(*State) void` - no context parameter.
        /// After the method is called, the UI automatically re-renders.
        ///
        /// This is the recommended pattern because:
        /// - State stays pure and testable
        /// - No UI coupling in state methods
        /// - Framework handles the notification glue
        pub fn update(
            self: *Self,
            comptime method: fn (*State) void,
        ) HandlerRef {
            _ = self;

            const Wrapper = struct {
                fn invoke(gooey: *Gooey, _: EntityId) void {
                    const state_ptr = handler_mod.getRootState(State) orelse {
                        std.debug.print("Handler error: state not found\n", .{});
                        return;
                    };
                    method(state_ptr);
                    gooey.requestRender();
                }
            };

            return .{
                .callback = Wrapper.invoke,
                .entity_id = EntityId.invalid,
            };
        }

        /// Create a handler from a pure state method that takes an argument.
        ///
        /// The method should be `fn(*State, ArgType) void`.
        /// The argument is captured and passed when the handler is invoked.
        /// After the method is called, the UI automatically re-renders.
        ///
        /// **Note:** The argument must fit in 8 bytes (u64).
        pub fn updateWith(
            self: *Self,
            arg: anytype,
            comptime method: fn (*State, @TypeOf(arg)) void,
        ) HandlerRef {
            _ = self;
            const Arg = @TypeOf(arg);

            comptime {
                if (@sizeOf(Arg) > @sizeOf(u64)) {
                    @compileError("updateWith: argument type '" ++ @typeName(Arg) ++ "' exceeds 8 bytes. Use a pointer or index instead.");
                }
            }

            const packed_entity_id = packArg(Arg, arg);

            const Wrapper = struct {
                fn invoke(gooey: *Gooey, packed_arg: EntityId) void {
                    const state_ptr = handler_mod.getRootState(State) orelse {
                        std.debug.print("Handler error: state not found\n", .{});
                        return;
                    };
                    const unpacked = unpackArg(Arg, packed_arg);
                    method(state_ptr, unpacked);
                    gooey.requestRender();
                }
            };

            return .{
                .callback = Wrapper.invoke,
                .entity_id = packed_entity_id,
            };
        }

        // =====================================================================
        // COMMAND HANDLERS - command / commandWith
        // =====================================================================

        /// Create a command handler that has framework access.
        ///
        /// The method should be `fn(*State, *Gooey) void`.
        /// Use this when you need to perform framework operations like:
        /// - Focus management (`g.focusTextInput()`, `g.blurAll()`)
        /// - Window operations (`g.window.setTitle()`)
        /// - Future: opening windows, dialogs, etc.
        ///
        /// After the method is called, the UI automatically re-renders.
        pub fn command(
            self: *Self,
            comptime method: fn (*State, *Gooey) void,
        ) HandlerRef {
            _ = self;

            const Wrapper = struct {
                fn invoke(gooey: *Gooey, _: EntityId) void {
                    const state_ptr = handler_mod.getRootState(State) orelse {
                        std.debug.print("Handler error: state not found\n", .{});
                        return;
                    };
                    method(state_ptr, gooey);
                    gooey.requestRender();
                }
            };

            return .{
                .callback = Wrapper.invoke,
                .entity_id = EntityId.invalid,
            };
        }

        /// Create a command handler with an argument that has framework access.
        ///
        /// The method should be `fn(*State, *Gooey, ArgType) void`.
        /// Combines `command()` with argument passing like `updateWith()`.
        ///
        /// **Note:** The argument must fit in 8 bytes (u64).
        pub fn commandWith(
            self: *Self,
            arg: anytype,
            comptime method: fn (*State, *Gooey, @TypeOf(arg)) void,
        ) HandlerRef {
            _ = self;
            const Arg = @TypeOf(arg);

            comptime {
                if (@sizeOf(Arg) > @sizeOf(u64)) {
                    @compileError("commandWith: argument type '" ++ @typeName(Arg) ++ "' exceeds 8 bytes. Use a pointer or index instead.");
                }
            }

            const packed_entity_id = packArg(Arg, arg);

            const Wrapper = struct {
                fn invoke(gooey: *Gooey, packed_arg: EntityId) void {
                    const state_ptr = handler_mod.getRootState(State) orelse {
                        std.debug.print("Handler error: state not found\n", .{});
                        return;
                    };
                    const unpacked = unpackArg(Arg, packed_arg);
                    method(state_ptr, gooey, unpacked);
                    gooey.requestRender();
                }
            };

            return .{
                .callback = Wrapper.invoke,
                .entity_id = packed_entity_id,
            };
        }

        // =====================================================================
        // DEPRECATED - handler()
        // =====================================================================

        /// DEPRECATED: Use `command()` instead.
        ///
        /// `command()` is cleaner (uses `*Gooey` instead of `*Context`) and auto-notifies.
        /// `handler()` required manual `cx.notify()` calls.
        pub fn handler(
            self: *Self,
            comptime method: fn (*State, *Self) void,
        ) HandlerRef {
            handler_mod.setRootState(State, self.user_state);

            const Wrapper = struct {
                fn invoke(gooey: *Gooey, _: EntityId) void {
                    const state_ptr = handler_mod.getRootState(State) orelse {
                        std.debug.print("Handler error: state not found\n", .{});
                        return;
                    };
                    var cx = Self{
                        .gooey = gooey,
                        .builder = undefined,
                        .user_state = state_ptr,
                    };
                    method(state_ptr, &cx);
                }
            };

            return .{
                .callback = Wrapper.invoke,
                .entity_id = EntityId.invalid,
            };
        }

        // =====================================================================
        // WINDOW OPERATIONS
        // =====================================================================

        /// Access window operations through a namespaced API.
        pub fn window(self: *Self) WindowOps {
            return .{ .gooey = self.gooey };
        }

        /// Window operations namespace
        pub const WindowOps = struct {
            gooey: *Gooey,

            /// Set the window title
            pub fn setTitle(self: WindowOps, title: []const u8) void {
                self.gooey.window.setTitle(title);
            }

            /// Get window dimensions (logical pixels)
            pub fn size(self: WindowOps) struct { width: f32, height: f32 } {
                return .{
                    .width = self.gooey.width,
                    .height = self.gooey.height,
                };
            }

            /// Get scale factor (e.g., 2.0 for Retina displays)
            pub fn scaleFactor(self: WindowOps) f32 {
                return self.gooey.scale_factor;
            }

            /// Close the window
            pub fn close(self: WindowOps) void {
                _ = self;
                @panic("TODO: implement window close");
            }

            /// Minimize the window
            pub fn minimize(self: WindowOps) void {
                _ = self;
                @panic("TODO: implement window minimize");
            }

            /// Bring window to front
            pub fn activate(self: WindowOps) void {
                _ = self;
                @panic("TODO: implement window activate");
            }
        };

        // =====================================================================
        // Resource Access
        // =====================================================================

        /// Get the allocator used by Gooey
        pub fn allocator(self: *Self) std.mem.Allocator {
            return self.gooey.allocator;
        }

        /// Get window dimensions (convenience, same as window().size())
        pub fn windowSize(self: *Self) struct { width: f32, height: f32 } {
            return .{
                .width = self.gooey.width,
                .height = self.gooey.height,
            };
        }

        // =====================================================================
        // Layout Shortcuts (delegate to builder)
        // =====================================================================

        pub fn vstack(self: *Self, style: ui_mod.StackStyle, children: anytype) void {
            self.builder.vstack(style, children);
        }

        pub fn hstack(self: *Self, style: ui_mod.StackStyle, children: anytype) void {
            self.builder.hstack(style, children);
        }

        pub fn box(self: *Self, style: ui_mod.BoxStyle, children: anytype) void {
            self.builder.box(style, children);
        }

        pub fn boxWithId(self: *Self, id: []const u8, style: ui_mod.BoxStyle, children: anytype) void {
            self.builder.boxWithId(id, style, children);
        }

        pub fn center(self: *Self, style: ui_mod.CenterStyle, children: anytype) void {
            self.builder.center(style, children);
        }

        pub fn when(self: *Self, condition: bool, children: anytype) void {
            self.builder.when(condition, children);
        }

        pub fn maybe(self: *Self, optional: anytype, comptime render_fn: anytype) void {
            self.builder.maybe(optional, render_fn);
        }

        pub fn each(self: *Self, items: anytype, comptime render_fn: anytype) void {
            self.builder.each(items, render_fn);
        }

        pub fn scroll(self: *Self, id: []const u8, style: ui_mod.ScrollStyle, children: anytype) void {
            self.builder.scroll(id, style, children);
        }

        // =====================================================================
        // Focus Operations (convenience pass-through)
        // =====================================================================

        pub fn textInput(self: *Self, id: []const u8) ?*@import("../elements/text_input.zig").TextInput {
            return self.gooey.textInput(id);
        }

        pub fn focusTextInput(self: *Self, id: []const u8) void {
            self.gooey.focusTextInput(id);
        }

        pub fn focusNext(self: *Self) void {
            self.gooey.focusNext();
        }

        pub fn focusPrev(self: *Self) void {
            self.gooey.focusPrev();
        }

        pub fn blurAll(self: *Self) void {
            self.gooey.blurAll();
        }

        pub fn isElementFocused(self: *Self, id: []const u8) bool {
            return self.gooey.isElementFocused(id);
        }

        pub fn scrollContainer(self: *Self, id: []const u8) ?*@import("../elements/scroll_container.zig").ScrollContainer {
            return self.gooey.widgets.scrollContainer(id);
        }
    };
}

// =============================================================================
// Helper Functions for Argument Packing
// =============================================================================

fn packArg(comptime T: type, arg: T) EntityId {
    var result: u64 = 0;
    const arg_bytes = std.mem.asBytes(&arg);
    const result_bytes = std.mem.asBytes(&result);
    @memcpy(result_bytes[0..@sizeOf(T)], arg_bytes);
    return .{ .id = result };
}

fn unpackArg(comptime T: type, packed_entity_id: EntityId) T {
    var result: T = undefined;
    const result_bytes = std.mem.asBytes(&result);
    const packed_bytes = std.mem.asBytes(&packed_entity_id.id);
    @memcpy(result_bytes, packed_bytes[0..@sizeOf(T)]);
    return result;
}

// =============================================================================
// Tests
// =============================================================================

test "Context creation and state access" {
    const TestState = struct {
        count: i32 = 0,
        name: []const u8 = "test",
    };

    const test_state = TestState{ .count = 42 };
    const ContextType = Context(TestState);
    _ = ContextType;
    try std.testing.expectEqual(@as(i32, 42), test_state.count);
}

test "packArg/unpackArg roundtrip" {
    // Test with usize
    {
        const original: usize = 42;
        const packed_entity_id = packArg(usize, original);
        const unpacked = unpackArg(usize, packed_entity_id);
        try std.testing.expectEqual(original, unpacked);
    }

    // Test with i32
    {
        const original: i32 = -123;
        const packed_entity_id = packArg(i32, original);
        const unpacked = unpackArg(i32, packed_entity_id);
        try std.testing.expectEqual(original, unpacked);
    }

    // Test with small struct
    {
        const Point = struct { x: i16, y: i16 };
        const original = Point{ .x = 100, .y = -50 };
        const packed_entity_id = packArg(Point, original);
        const unpacked = unpackArg(Point, packed_entity_id);
        try std.testing.expectEqual(original.x, unpacked.x);
        try std.testing.expectEqual(original.y, unpacked.y);
    }

    // Test with enum
    {
        const Color = enum(u8) { red, green, blue };
        const original = Color.green;
        const packed_entity_id = packArg(Color, original);
        const unpacked = unpackArg(Color, packed_entity_id);
        try std.testing.expectEqual(original, unpacked);
    }
}

test "pure state methods are testable" {
    const TestState = struct {
        count: i32 = 0,
        items: [4]i32 = [_]i32{0} ** 4,

        pub fn increment(self: *@This()) void {
            self.count += 1;
        }

        pub fn decrement(self: *@This()) void {
            self.count -= 1;
        }

        pub fn incrementAt(self: *@This(), index: usize) void {
            self.items[index] += 1;
        }
    };

    var s = TestState{};

    s.increment();
    try std.testing.expectEqual(@as(i32, 1), s.count);

    s.decrement();
    try std.testing.expectEqual(@as(i32, 0), s.count);

    s.incrementAt(2);
    try std.testing.expectEqual(@as(i32, 1), s.items[2]);
    try std.testing.expectEqual(@as(i32, 0), s.items[0]);
}

test "command handler signature compatibility" {
    const TestState = struct {
        value: i32 = 0,

        pub fn doSomething(self: *@This(), g: *Gooey) void {
            self.value += 1;
            _ = g;
        }

        pub fn setValue(self: *@This(), g: *Gooey, value: i32) void {
            self.value = value;
            _ = g;
        }
    };

    const ContextType = Context(TestState);
    _ = ContextType;

    const s = TestState{};
    try std.testing.expectEqual(@as(i32, 0), s.value);
}
