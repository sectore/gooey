//! WidgetStore - Simple retained storage for stateful widgets
//!
//! Provides persistent widget instances across frames without the complexity
//! of the Entity system. Widgets are stored by string ID and created on first access.
//!
//! Example:
//! ```zig
//! var store = WidgetStore.init(allocator);
//! defer store.deinit();
//!
//! // Get or create a text input - same ID returns same instance
//! var username = store.textInput("username");
//! username.setPlaceholder("Enter username");
//! ```

const std = @import("std");
const TextInput = @import("../elements/text_input.zig").TextInput;
const Bounds = @import("../elements/text_input.zig").Bounds;

pub const WidgetStore = struct {
    allocator: std.mem.Allocator,
    text_inputs: std.StringHashMap(*TextInput),
    /// Track which widgets were accessed this frame (uses same keys as text_inputs, no separate allocation)
    accessed_this_frame: std.StringHashMap(void),
    default_text_input_bounds: Bounds = .{ .x = 0, .y = 0, .width = 200, .height = 36 },

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .text_inputs = std.StringHashMap(*TextInput).init(allocator),
            .accessed_this_frame = std.StringHashMap(void).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        // Clean up all TextInput instances and their keys
        var it = self.text_inputs.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
            self.allocator.free(entry.key_ptr.*);
        }
        self.text_inputs.deinit();

        // accessed_this_frame shares keys with text_inputs, so just deinit the map
        self.accessed_this_frame.deinit();
    }

    /// Get or create a TextInput by ID - persists across frames
    /// Returns null on allocation failure instead of panicking
    pub fn textInput(self: *Self, id: []const u8) ?*TextInput {
        // Check if already exists
        if (self.text_inputs.get(id)) |existing| {
            // Mark as accessed this frame (reuse existing key, no allocation needed)
            self.accessed_this_frame.put(id, {}) catch {};
            return existing;
        }

        // Create new TextInput
        const input = self.allocator.create(TextInput) catch return null;
        errdefer self.allocator.destroy(input);

        input.* = TextInput.initWithId(self.allocator, self.default_text_input_bounds, id);

        // Allocate owned key for the hashmap
        const owned_key = self.allocator.dupe(u8, id) catch {
            input.deinit();
            self.allocator.destroy(input);
            return null;
        };
        errdefer self.allocator.free(owned_key);

        // Store in text_inputs map
        self.text_inputs.put(owned_key, input) catch {
            input.deinit();
            self.allocator.destroy(input);
            self.allocator.free(owned_key);
            return null;
        };

        // Mark as accessed (use owned_key which is now in text_inputs)
        self.accessed_this_frame.put(owned_key, {}) catch {};

        return input;
    }

    /// Get or create a TextInput, panicking on allocation failure
    /// Use this when you're confident memory is available
    pub fn textInputOrPanic(self: *Self, id: []const u8) *TextInput {
        return self.textInput(id) orelse @panic("Failed to allocate TextInput");
    }

    pub fn beginFrame(self: *Self) void {
        // Clear accessed set - keys are borrowed from text_inputs, no freeing needed
        self.accessed_this_frame.clearRetainingCapacity();
    }

    pub fn endFrame(_: *Self) void {
        // No-op - widgets persist until explicitly removed
    }

    pub fn removeTextInput(self: *Self, id: []const u8) void {
        if (self.text_inputs.fetchRemove(id)) |kv| {
            // Also remove from accessed set if present
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
