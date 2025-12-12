//! Dynamic Counters Example
//!
//! Demonstrates:
//! - Dynamic entity creation and deletion
//! - Auto-cleanup when entities are removed (Phase 4)
//! - Aggregate observer (total watches all counters)
//! - b.entityContext() for clean component code (Phase 3)

const std = @import("std");
const gooey = @import("gooey");
const ui = gooey.ui;

// =============================================================================
// Models
// =============================================================================

const Counter = struct {
    count: i32 = 0,
    label: []const u8 = "Counter",

    pub fn increment(self: *Counter, cx: *gooey.EntityContext(Counter)) void {
        self.count += 1;
        cx.notify();
    }

    pub fn decrement(self: *Counter, cx: *gooey.EntityContext(Counter)) void {
        self.count -= 1;
        cx.notify();
    }
};

// =============================================================================
// Application State
// =============================================================================
const MaxCounters = 10;
const AppState = struct {
    counters: [MaxCounters]gooey.Entity(Counter) = [_]gooey.Entity(Counter){gooey.Entity(Counter).nil()} ** MaxCounters,
    counter_count: usize = 0,
    next_label: u8 = 'A',

    pub fn addCounter(self: *AppState, cx: *gooey.EntityContext(AppState)) void {
        if (self.counter_count >= 10) return; // Max 10 counters

        const label: []const u8 = switch (self.next_label) {
            'A' => "Counter A",
            'B' => "Counter B",
            'C' => "Counter C",
            'D' => "Counter D",
            'E' => "Counter E",
            'F' => "Counter F",
            'G' => "Counter G",
            'H' => "Counter H",
            'I' => "Counter I",
            'J' => "Counter J",
            else => "Counter",
        };

        const counter = cx.create(Counter, .{ .count = 0, .label = label }) catch return;
        self.counters[self.counter_count] = counter;
        self.counter_count += 1;
        self.next_label += 1;
        cx.notify();
    }

    pub fn removeCounter(self: *AppState, cx: *gooey.EntityContext(AppState)) void {
        if (self.counter_count == 0) return;

        self.counter_count -= 1;
        const entity = self.counters[self.counter_count];
        cx.remove(entity.id); // Auto-cleanup of observers!
        self.next_label -= 1;
        cx.notify();
    }

    fn countersSlice(self: *const AppState) []const gooey.Entity(Counter) {
        return self.counters[0..self.counter_count];
    }
};

var app_state_entity: gooey.Entity(AppState) = gooey.Entity(AppState).nil();
var initialized = false;

// =============================================================================
// Components
// =============================================================================

/// Individual counter card
const CounterCard = struct {
    counter: gooey.Entity(Counter),

    pub fn render(self: @This(), b: *ui.Builder) void {
        const data = b.readEntity(Counter, self.counter) orelse return;
        var cx = b.entityContext(Counter, self.counter) orelse return;

        b.box(.{
            .padding = .{ .all = 16 },
            .gap = 8,
            .background = ui.Color.white,
            .corner_radius = 8,
            .direction = .column,
            .min_width = 120,
            .shadow = .{ .blur_radius = 8, .color = ui.Color.rgba(0, 0, 0, 0.1) },
        }, .{
            ui.text(data.label, .{ .size = 12, .color = ui.Color.rgb(0.5, 0.5, 0.5) }),
            ui.textFmt("{}", .{data.count}, .{ .size = 32 }),
            b.hstack(.{ .gap = 8 }, .{
                ui.buttonHandler("-", cx.handler(Counter.decrement)),
                ui.buttonHandler("+", cx.handler(Counter.increment)),
            }),
        });
    }
};

/// Shows total of all counters - demonstrates aggregate observation
const TotalDisplay = struct {
    app: gooey.Entity(AppState),

    pub fn render(self: @This(), b: *ui.Builder) void {
        const g = b.getGooey() orelse return;
        const state = g.readEntity(AppState, self.app) orelse return;

        var total: i32 = 0;
        for (state.countersSlice()) |counter_entity| {
            if (g.readEntity(Counter, counter_entity)) |counter| {
                total += counter.count;
            }
        }

        b.box(.{
            .padding = .{ .all = 16 },
            .background = ui.Color.rgb(0.2, 0.6, 0.9),
            .corner_radius = 8,
        }, .{
            ui.textFmt("Total: {}", .{total}, .{ .size = 24, .color = ui.Color.white }),
        });
    }
};

/// Control buttons for adding/removing counters
const ControlPanel = struct {
    app: gooey.Entity(AppState),

    pub fn render(self: @This(), b: *ui.Builder) void {
        var cx = b.entityContext(AppState, self.app) orelse return;
        const state = b.readEntity(AppState, self.app) orelse return;

        b.hstack(.{ .gap = 12, .alignment = .center }, .{
            ui.buttonHandler("+ Add Counter", cx.handler(AppState.addCounter)),
            ui.buttonHandler("- Remove Counter", cx.handler(AppState.removeCounter)),
            ui.textFmt("({}/10)", .{state.countersSlice().len}, .{ .size = 14, .color = ui.Color.rgb(0.5, 0.5, 0.5) }),
        });
    }
};

// =============================================================================
// Entry Point
// =============================================================================

pub fn main() !void {
    try gooey.run(.{
        .title = "Dynamic Counters",
        .width = 600,
        .height = 400,
        .render = render,
    });
}

fn render(g: *gooey.UI) void {
    const gooey_ctx = g.gooey;

    // Initialize on first frame
    if (!initialized) {
        initialized = true;
        app_state_entity = gooey_ctx.createEntity(AppState, .{}) catch return;
    }

    const size = g.windowSize();

    g.box(.{
        .width = size.width,
        .height = size.height,
        .background = ui.Color.rgb(0.95, 0.95, 0.95),
        .padding = .{ .all = 24 },
        .gap = 24,
        .direction = .column,
    }, .{
        ui.text("Dynamic Counters", .{ .size = 24 }),
        ui.text("Add/remove counters - observers auto-cleanup!", .{ .size = 14, .color = ui.Color.rgb(0.5, 0.5, 0.5) }),

        ControlPanel{ .app = app_state_entity },
        CounterGrid{ .app = app_state_entity },
        TotalDisplay{ .app = app_state_entity },
    });
}

/// Grid of counter cards
const CounterGrid = struct {
    app: gooey.Entity(AppState),

    pub fn render(self: @This(), b: *ui.Builder) void {
        b.hstack(.{ .gap = 12 }, .{
            CounterItems{ .app = self.app },
        });
    }
};

const CounterItems = struct {
    app: gooey.Entity(AppState),

    pub fn render(self: @This(), b: *ui.Builder) void {
        const g = b.getGooey() orelse return;
        const state = g.readEntity(AppState, self.app) orelse return;

        for (state.countersSlice()) |counter_entity| {
            b.box(.{}, .{
                CounterCard{ .counter = counter_entity },
            });
        }
    }
};
