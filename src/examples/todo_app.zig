//! Todo List Example
//!
//! Demonstrates:
//! - Full CRUD operations on entities
//! - Filter state affecting views
//! - Observer pattern (footer counts active items)
//! - b.getContext() for stateful components (Phase 2)
//! - Text input with state binding

const std = @import("std");
const gooey = @import("gooey");
const ui = gooey.ui;

// =============================================================================
// Models
// =============================================================================

const Todo = struct {
    text: []const u8,
    completed: bool = false,

    pub fn toggle(self: *Todo, cx: *gooey.EntityContext(Todo)) void {
        self.completed = !self.completed;
        cx.notify();
    }
};

const Filter = enum {
    all,
    active,
    completed,

    fn matches(self: Filter, todo: *const Todo) bool {
        return switch (self) {
            .all => true,
            .active => !todo.completed,
            .completed => todo.completed,
        };
    }

    fn label(self: Filter) []const u8 {
        return switch (self) {
            .all => "All",
            .active => "Active",
            .completed => "Completed",
        };
    }
};

// =============================================================================
// Application State
// =============================================================================

const MaxTodos = 100;

const AppState = struct {
    todos: [MaxTodos]gooey.Entity(Todo) = [_]gooey.Entity(Todo){gooey.Entity(Todo).nil()} ** MaxTodos,
    todo_count: usize = 0,
    filter: Filter = .all,
    input_text: []const u8 = "",

    pub fn addTodo(self: *AppState, cx: *gooey.Context(AppState)) void {
        if (self.input_text.len == 0) return;
        if (self.todo_count >= MaxTodos) return;

        // Copy the string since input_text points to widget buffer
        const text_copy = cx.allocator().dupe(u8, self.input_text) catch return;

        const todo = cx.gooey.createEntity(Todo, .{
            .text = text_copy,
            .completed = false,
        }) catch return;

        self.todos[self.todo_count] = todo;
        self.todo_count += 1;

        // Clear the actual TextInput widget's buffer
        if (cx.gooey.textInput("todo-input")) |input| {
            input.clear();
        }
        self.input_text = "";

        cx.notify();
    }

    pub fn clearCompleted(self: *AppState, cx: *gooey.Context(AppState)) void {
        var write_idx: usize = 0;
        var read_idx: usize = 0;

        while (read_idx < self.todo_count) : (read_idx += 1) {
            const entity = self.todos[read_idx];
            if (cx.gooey.readEntity(Todo, entity)) |todo| {
                if (todo.completed) {
                    // Free the text
                    cx.allocator().free(todo.text);
                    // Remove entity (auto-cleanup!)
                    cx.gooey.getEntities().remove(entity.id);
                    continue;
                }
            }
            // Keep this todo
            self.todos[write_idx] = entity;
            write_idx += 1;
        }
        self.todo_count = write_idx;
        cx.notify();
    }

    // ... rest of methods unchanged ...

    fn activeCount(self: *const AppState, gooey_ctx: *gooey.Gooey) usize {
        var count: usize = 0;
        for (self.todos[0..self.todo_count]) |entity| {
            if (gooey_ctx.readEntity(Todo, entity)) |todo| {
                if (!todo.completed) count += 1;
            }
        }
        return count;
    }

    /// Get slice of active todos
    fn todosSlice(self: *const AppState) []const gooey.Entity(Todo) {
        return self.todos[0..self.todo_count];
    }

    pub fn setFilterAll(self: *AppState, cx: *gooey.Context(AppState)) void {
        self.filter = .all;
        cx.notify();
    }

    pub fn setFilterActive(self: *AppState, cx: *gooey.Context(AppState)) void {
        self.filter = .active;
        cx.notify();
    }

    pub fn setFilterCompleted(self: *AppState, cx: *gooey.Context(AppState)) void {
        self.filter = .completed;
        cx.notify();
    }
};

// =============================================================================
// Components
// =============================================================================

const TodoInput = struct {
    pub fn render(_: @This(), b: *ui.Builder) void {
        const cx = b.getContext(gooey.Context(AppState)) orelse return;
        const s = cx.state();

        b.hstack(.{ .gap = 12, .alignment = .center }, .{
            ui.input("todo-input", .{
                .placeholder = "What needs to be done?",
                .width = 300,
                .bind = &s.input_text,
            }),
            ui.buttonHandler("Add", cx.handler(AppState.addTodo)),
        });
    }
};

const TodoItem = struct {
    todo: gooey.Entity(Todo),

    pub fn render(self: @This(), b: *ui.Builder) void {
        const g = b.getGooey() orelse return;
        const data = g.writeEntity(Todo, self.todo) orelse return;

        const text_color = if (data.completed)
            ui.Color.rgb(0.7, 0.7, 0.7)
        else
            ui.Color.rgb(0.2, 0.2, 0.2);

        // Generate unique checkbox ID from entity ID
        var id_buf: [32]u8 = undefined;
        const checkbox_id = std.fmt.bufPrint(&id_buf, "todo-{}", .{self.todo.id.id}) catch "todo-fallback";

        b.hstack(.{ .gap = 12, .alignment = .center }, .{
            ui.checkbox(checkbox_id, .{
                .bind = &data.completed,
            }),
            ui.text(data.text, .{ .size = 16, .color = text_color }),
        });
    }
};

const TodoList = struct {
    pub fn render(_: @This(), b: *ui.Builder) void {
        b.box(.{
            .padding = .{ .all = 16 },
            .gap = 8,
            .direction = .column,
            .background = ui.Color.white,
            .corner_radius = 8,
            .min_height = 200,
        }, .{
            TodoItems{},
        });
    }
};

/// Inner component that renders filtered todo items
const TodoItems = struct {
    pub fn render(_: @This(), b: *ui.Builder) void {
        const cx = b.getContext(gooey.Context(AppState)) orelse return;
        const s = cx.stateConst();

        for (s.todosSlice()) |entity| {
            if (cx.gooey.readEntity(Todo, entity)) |todo| {
                if (s.filter.matches(todo)) {
                    b.box(.{ .padding = .{ .symmetric = .{ .x = 0, .y = 4 } } }, .{
                        TodoItem{ .todo = entity },
                    });
                }
            }
        }
    }
};

const FilterBar = struct {
    pub fn render(_: @This(), b: *ui.Builder) void {
        const cx = b.getContext(gooey.Context(AppState)) orelse return;
        const s = cx.stateConst();

        b.hstack(.{ .gap = 8, .alignment = .center }, .{
            FilterButton{ .filter = .all, .current = s.filter },
            FilterButton{ .filter = .active, .current = s.filter },
            FilterButton{ .filter = .completed, .current = s.filter },
        });
    }
};

const FilterButton = struct {
    filter: Filter,
    current: Filter,

    pub fn render(self: @This(), b: *ui.Builder) void {
        const cx = b.getContext(gooey.Context(AppState)) orelse return;
        const is_active = self.filter == self.current;

        const handler = switch (self.filter) {
            .all => cx.handler(AppState.setFilterAll),
            .active => cx.handler(AppState.setFilterActive),
            .completed => cx.handler(AppState.setFilterCompleted),
        };

        b.box(.{
            .padding = .{ .symmetric = .{ .x = 12, .y = 6 } },
            .background = if (is_active) ui.Color.rgb(0.2, 0.6, 0.9) else ui.Color.rgb(0.9, 0.9, 0.9),
            .corner_radius = 4,
        }, .{
            ui.buttonHandler(self.filter.label(), handler),
        });
    }
};

const Footer = struct {
    pub fn render(_: @This(), b: *ui.Builder) void {
        const cx = b.getContext(gooey.Context(AppState)) orelse return;
        const s = cx.stateConst();
        const active = s.activeCount(cx.gooey);

        b.hstack(.{ .gap = 16, .alignment = .center }, .{
            ui.textFmt("{} items left", .{active}, .{ .size = 14, .color = ui.Color.rgb(0.5, 0.5, 0.5) }),
            FilterBar{},
            ui.buttonHandler("Clear completed", cx.handler(AppState.clearCompleted)),
        });
    }
};

// =============================================================================
// Entry Point
// =============================================================================

pub fn main() !void {
    var app_state = AppState{};

    try gooey.runWithState(AppState, .{
        .title = "Todo List",
        .width = 500,
        .height = 500,
        .state = &app_state,
        .render = render,
    });
}

fn render(cx: *gooey.Context(AppState)) void {
    const size = cx.windowSize();

    cx.box(.{
        .width = size.width,
        .height = size.height,
        .background = ui.Color.rgb(0.95, 0.95, 0.95),
        .padding = .{ .all = 32 },
        .gap = 24,
        .direction = .column,
        .alignment = .{ .cross = .center },
    }, .{
        ui.text("todos", .{ .size = 48, .color = ui.Color.rgb(0.9, 0.7, 0.7) }),
        TodoInput{},
        TodoList{},
        Footer{},
    });
}
