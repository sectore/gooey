//! WidgetStore - Simple retained storage for stateful widgets

const std = @import("std");
const TextInput = @import("../elements/text_input.zig").TextInput;
const Bounds = @import("../elements/text_input.zig").Bounds;
const Checkbox = @import("../elements/checkbox.zig").Checkbox;
const ScrollContainer = @import("../elements/scroll_container.zig").ScrollContainer;

pub const WidgetStore = struct {
    allocator: std.mem.Allocator,
    text_inputs: std.StringHashMap(*TextInput),
    checkboxes: std.StringHashMap(*Checkbox),
    scroll_containers: std.StringHashMap(*ScrollContainer),
    accessed_this_frame: std.StringHashMap(void),
    default_text_input_bounds: Bounds = .{ .x = 0, .y = 0, .width = 200, .height = 36 },

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .text_inputs = std.StringHashMap(*TextInput).init(allocator),
            .checkboxes = std.StringHashMap(*Checkbox).init(allocator),
            .scroll_containers = std.StringHashMap(*ScrollContainer).init(allocator),
            .accessed_this_frame = std.StringHashMap(void).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        // Clean up TextInputs
        var it = self.text_inputs.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
            self.allocator.free(entry.key_ptr.*);
        }
        self.text_inputs.deinit();

        // Clean up Checkboxes
        var cb_it = self.checkboxes.iterator();
        while (cb_it.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
            self.allocator.free(entry.key_ptr.*);
        }
        self.checkboxes.deinit();

        // Clean up ScrollContainers
        var sc_it = self.scroll_containers.iterator();
        while (sc_it.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
            self.allocator.free(entry.key_ptr.*);
        }
        self.scroll_containers.deinit();

        self.accessed_this_frame.deinit();
    }

    // =========================================================================
    // TextInput (existing code)
    // =========================================================================

    pub fn textInput(self: *Self, id: []const u8) ?*TextInput {
        if (self.text_inputs.get(id)) |existing| {
            self.accessed_this_frame.put(id, {}) catch {};
            return existing;
        }

        const input = self.allocator.create(TextInput) catch return null;
        errdefer self.allocator.destroy(input);

        input.* = TextInput.initWithId(self.allocator, self.default_text_input_bounds, id);

        const owned_key = self.allocator.dupe(u8, id) catch {
            input.deinit();
            self.allocator.destroy(input);
            return null;
        };
        errdefer self.allocator.free(owned_key);

        self.text_inputs.put(owned_key, input) catch {
            input.deinit();
            self.allocator.destroy(input);
            self.allocator.free(owned_key);
            return null;
        };

        self.accessed_this_frame.put(owned_key, {}) catch {};
        return input;
    }

    pub fn textInputOrPanic(self: *Self, id: []const u8) *TextInput {
        return self.textInput(id) orelse @panic("Failed to allocate TextInput");
    }

    // =========================================================================
    // Checkbox
    // =========================================================================

    pub fn checkbox(self: *Self, id: []const u8) ?*Checkbox {
        if (self.checkboxes.get(id)) |existing| {
            self.accessed_this_frame.put(id, {}) catch {};
            return existing;
        }

        const cb = self.allocator.create(Checkbox) catch return null;
        errdefer self.allocator.destroy(cb);

        cb.* = Checkbox.init(self.allocator, id);

        const owned_key = self.allocator.dupe(u8, id) catch {
            cb.deinit();
            self.allocator.destroy(cb);
            return null;
        };
        errdefer self.allocator.free(owned_key);

        self.checkboxes.put(owned_key, cb) catch {
            cb.deinit();
            self.allocator.destroy(cb);
            self.allocator.free(owned_key);
            return null;
        };

        self.accessed_this_frame.put(owned_key, {}) catch {};
        return cb;
    }

    pub fn getCheckbox(self: *Self, id: []const u8) ?*Checkbox {
        return self.checkboxes.get(id);
    }

    // =========================================================================
    // ScrollContainer
    // =========================================================================

    pub fn scrollContainer(self: *Self, id: []const u8) ?*ScrollContainer {
        if (self.scroll_containers.get(id)) |existing| {
            self.accessed_this_frame.put(id, {}) catch {};
            return existing;
        }

        const sc = self.allocator.create(ScrollContainer) catch return null;
        errdefer self.allocator.destroy(sc);

        sc.* = ScrollContainer.init(self.allocator, id);

        const owned_key = self.allocator.dupe(u8, id) catch {
            sc.deinit();
            self.allocator.destroy(sc);
            return null;
        };
        errdefer self.allocator.free(owned_key);

        self.scroll_containers.put(owned_key, sc) catch {
            sc.deinit();
            self.allocator.destroy(sc);
            self.allocator.free(owned_key);
            return null;
        };

        self.accessed_this_frame.put(owned_key, {}) catch {};
        return sc;
    }

    pub fn getScrollContainer(self: *Self, id: []const u8) ?*ScrollContainer {
        return self.scroll_containers.get(id);
    }

    // =========================================================================
    // Frame Lifecycle
    // =========================================================================

    pub fn beginFrame(self: *Self) void {
        self.accessed_this_frame.clearRetainingCapacity();
    }

    pub fn endFrame(_: *Self) void {}

    // =========================================================================
    // TextInput helpers (existing)
    // =========================================================================

    pub fn removeTextInput(self: *Self, id: []const u8) void {
        if (self.text_inputs.fetchRemove(id)) |kv| {
            _ = self.accessed_this_frame.remove(kv.key);
            kv.value.deinit();
            self.allocator.destroy(kv.value);
            self.allocator.free(kv.key);
        }
    }

    pub fn getTextInput(self: *Self, id: []const u8) ?*TextInput {
        return self.text_inputs.get(id);
    }

    pub fn hasTextInput(self: *Self, id: []const u8) bool {
        return self.text_inputs.contains(id);
    }

    pub fn textInputCount(self: *Self) usize {
        return self.text_inputs.count();
    }

    pub fn getFocusedTextInput(self: *Self) ?*TextInput {
        var it = self.text_inputs.valueIterator();
        while (it.next()) |input| {
            if (input.*.isFocused()) {
                return input.*;
            }
        }
        return null;
    }

    pub fn focusTextInput(self: *Self, id: []const u8) void {
        if (self.getFocusedTextInput()) |current| {
            current.blur();
        }
        if (self.text_inputs.get(id)) |input| {
            input.focus();
        }
    }

    pub fn blurAll(self: *Self) void {
        var it = self.text_inputs.valueIterator();
        while (it.next()) |input| {
            input.*.blur();
        }
    }
};
