// Positions windows on screen

//Layouts:
//  list of workspaces
//  one workspace is active at a time
//  each workspace:
//      list of windows
//      how the windows are positioned
//
// Are iWindows instances exclusive to a single workspace?
//
// Orientations MUST alternate, having a child of the same orientation should instead insert it into parent

const std = @import("std");
const Gui = @import("vtables.zig");
const graph = @import("../graphics.zig");
const Orientation = graph.Orientation;
const RectBound = graph.RectBound;

pub const Layouts = struct {};

pub const Workspace = struct {
    const Handle = struct {
        min: f32,
        max: f32,
        handle_ptr: *f32,
        orientation: Orientation,

        y0: f32,
        y1: f32,
    };
    const Self = @This();
    //windows: std.ArrayList(Gui.WindowId),

    pane: Pane,

    handles: std.ArrayList(Handle) = .{},

    pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
        self.pane.deinit(alloc);
        self.handles.deinit(alloc);
    }

    pub fn updateArea(self: *Self, alloc: std.mem.Allocator, new_area: RectBound) !void {
        try self.pane.updateArea(alloc, new_area);
    }

    pub fn rebuildHandles(self: *Self, alloc: std.mem.Allocator) !void {
        self.handles.clearRetainingCapacity();
        try self.pane.buildHandle(alloc, &self.handles);
    }
};

pub const Pane = union(enum) {
    split: struct {
        area: RectBound = .zero,
        orientation: Orientation,
        children: std.ArrayList(Pane) = .{},
        handles: std.ArrayList(f32) = .{}, //Relative to splits .x/y depending on orientation

        pub fn append(self: *@This(), alloc: std.mem.Allocator, child: Pane) !void {
            if (child == .split and child.split.orientation == self.orientation) return error.recursiveSplit;
            try self.children.append(alloc, child);
            try self.handles.append(alloc, 0);
        }

        fn width(self: *const @This(), area: RectBound) f32 {
            return switch (self.orientation) {
                .vertical => area.x1 - area.x0,
                .horizontal => area.y1 - area.y0,
            };
        }

        fn x(self: *const @This(), area: RectBound) f32 {
            return switch (self.orientation) {
                .vertical => area.x0,
                .horizontal => area.y0,
            };
        }

        fn x1(self: *const @This(), area: RectBound) f32 {
            return switch (self.orientation) {
                .vertical => area.x1,
                .horizontal => area.y1,
            };
        }

        pub fn childArea(self: *const @This(), area: RectBound, child_index: usize) RectBound {
            const xx = self.x(area);
            const start = if (child_index == 0) xx else self.handles.items[child_index - 1];
            const end = if (child_index == self.children.items.len - 1) self.x1(area) else self.handles.items[child_index];

            return switch (self.orientation) {
                .vertical => RectBound{ .x0 = start, .y0 = area.y0, .x1 = end, .y1 = area.y1 },
                .horizontal => RectBound{ .y0 = start, .x0 = area.x0, .y1 = end, .x1 = area.x1 },
            };
        }
    },
    window: Gui.WindowId,

    pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
        switch (self.*) {
            .window => {},
            .split => |*s| {
                for (s.children.items) |*child|
                    child.deinit(alloc);
                s.children.deinit(alloc);
                s.handles.deinit(alloc);
            },
        }
    }

    pub fn updateArea(self: *@This(), alloc: std.mem.Allocator, new_area: RectBound) !void {
        switch (self.*) {
            .window => {},
            .split => |*sp| {
                const old_area = sp.area;
                sp.area = new_area;
                if (sp.children.items.len == 0) return;

                var valid = true;
                if (sp.handles.items.len != sp.children.items.len - 1) {
                    try sp.handles.resize(alloc, sp.children.items.len - 1);
                    valid = false;
                }
                const width = sp.width(new_area);

                // split is valid if each handle is greater than the last
                if (valid) {
                    var current_handle: f32 = 0;
                    for (sp.handles.items) |hand| {
                        if (hand < current_handle or hand > width) {
                            valid = false;
                            break;
                        }
                        current_handle = hand;
                    }
                }

                if (!valid) { //Default to equal sizes
                    std.debug.print("INvalid split, rebuilding\n", .{});
                    const each_w = sp.width(new_area) / @as(f32, @floatFromInt(sp.children.items.len));
                    var pos: f32 = sp.x(new_area);
                    for (sp.handles.items) |*hand| {
                        pos += each_w;
                        hand.* = pos;
                    }
                } else { //Scale by ratio
                    const ratio = sp.width(new_area) / sp.width(old_area);
                    for (sp.handles.items) |*hand| {
                        hand.* *= ratio;
                    }
                }

                for (sp.children.items, 0..) |*child, i| {
                    try child.updateArea(alloc, sp.childArea(new_area, i));
                }
            },
        }
    }

    pub fn buildHandle(self: *const @This(), alloc: std.mem.Allocator, handles: *std.ArrayList(Workspace.Handle)) !void {
        switch (self.*) {
            .window => {},
            .split => |*sp| {
                var start: f32 = if (sp.orientation == .vertical) sp.area.x0 else sp.area.y0;
                const end: f32 = if (sp.orientation == .vertical) sp.area.x1 else sp.area.y1;
                const y0: f32 = if (sp.orientation == .vertical) sp.area.y0 else sp.area.x0;
                const y1: f32 = if (sp.orientation == .vertical) sp.area.y1 else sp.area.x1;
                for (sp.handles.items, 0..) |*hand, i| {
                    try handles.append(alloc, .{
                        .orientation = sp.orientation,
                        .min = start,
                        .handle_ptr = hand,
                        .max = if (i == sp.handles.items.len - 1) end else sp.handles.items[i + 1],
                        .y0 = y0,
                        .y1 = y1,
                    });
                    start = hand.*;
                }

                for (sp.children.items) |*child| {
                    try child.buildHandle(alloc, handles);
                }
            },
        }
    }
};

// Recursive N split
// resize is not proportianal. Resize looks for n-1 and n+1 split of boundry and prevents movement passed that
//
// A WINDOW resize proportionally scales the splits
//
// num handles =  children.len - 1
