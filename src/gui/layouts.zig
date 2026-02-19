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
const guis = @import("vtables.zig");
const graph = @import("../graphics.zig");
const Rect = graph.Rect;
const iArea = guis.iArea;
const iWindow = guis.iWindow;
const Orientation = graph.Orientation;
const RectBound = graph.RectBound;

pub const WorkspaceId = enum(u32) {
    none = std.math.maxInt(u32),
    _,
};

//It does its thing,
//when layout changes, clear gui window list and insert anew.
pub const Layouts = struct {
    const Self = @This();

    vt: guis.iWindow,
    alloc: std.mem.Allocator,
    area: RectBound,
    built_area: RectBound,
    workspaces: std.ArrayList(Workspace),

    set_ws: WorkspaceId = .none,
    active_ws: WorkspaceId = .none,

    grab_index: usize = 0,
    drag_start: graph.Vec2f = .zero,

    pub fn create(gui: *guis.Gui) *Self {
        const self = gui.create(@This());
        self.* = .{
            .vt = iWindow.init(build, gui, deinit, .{}, &self.vt),
            .area = .zero,
            .built_area = .zero,
            .alloc = gui.alloc,
            .workspaces = .{},
        };
        gui.registerOnClick(&self.vt.area, onclick, &self.vt) catch {};
        return self;
    }

    pub fn deinit(vt: *iWindow, gui: *guis.Gui) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        for (self.workspaces.items) |*ws| {
            ws.deinit(self.alloc);
        }
        self.workspaces.deinit(self.alloc);
        vt.deinit(gui);
        gui.alloc.destroy(self);
    }

    /// This function should not be called during gui update
    /// TODO allocated each workspace to have pointer stability.
    pub fn addWorkspace(self: *Self, ws: Pane) !WorkspaceId {
        const id: WorkspaceId = @enumFromInt(self.workspaces.items.len);

        try self.workspaces.append(self.alloc, .{ .pane = ws });
        self.set_ws = .none; //Set to none to force a rebuild as all pointers are now invalid

        return id;
    }

    pub fn getWorkspace(self: *Self, ws_id: WorkspaceId) ?*Workspace {
        if (@intFromEnum(ws_id) >= self.workspaces.items.len) return null;
        return &self.workspaces.items[@intFromEnum(ws_id)];
    }

    pub fn build(vt: *iWindow, gui: *guis.Gui, area: graph.Rect) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        self.vt.area.area = area;
        std.debug.print("Update area {any}\n", .{area});
        _ = gui;
        //self.ws.updateArea(gui.alloc, area.toAbsoluteRect()) catch {};
        //self.ws.rebuildHandles(gui.alloc) catch {};
    }

    pub fn preGuiUpdate(self: *Self, gui: *guis.Gui) !void {
        //TODO check if area is changed
        if (self.set_ws == self.active_ws and self.built_area.eql(self.area)) return;
        self.set_ws = self.active_ws;
        self.built_area = self.area;
        gui.active_windows.clearRetainingCapacity();
        defer {
            gui.updateWindowSize(&self.vt, self.area.toRect()) catch {};
            gui.active_windows.append(gui.alloc, &self.vt) catch {};
        }

        if (self.set_ws == .none) return;
        const ws = &self.workspaces.items[@intFromEnum(self.set_ws)];
        try ws.updateArea(self.alloc, self.area);
        try ws.rebuildHandles(self.alloc);
        for (ws.windows.items) |win| {
            const win_ptr = gui.getWindowId(win[1]) orelse return error.invalidWindow;
            try gui.active_windows.append(gui.alloc, win_ptr);
            try gui.updateWindowSize(win_ptr, win[0]);
            win_ptr.needs_rebuild = true;
        }
    }

    pub fn onclick(vt: *iArea, mcb: guis.MouseCbState, win: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", @as(*iWindow, @alignCast(@fieldParentPtr("area", vt)))));

        const ws = self.getWorkspace(self.set_ws) orelse return;
        std.debug.print("HAD CLICK\n", .{});

        const p = 10;
        switch (mcb.state) {
            else => {},
            .rising => for (ws.handles.items, 0..) |hand, h_i| {
                const r = switch (hand.orientation) {
                    .vertical => graph.Rec(hand.handle_ptr.* - p, hand.y0, p * 2, hand.y1 - hand.y0),
                    .horizontal => graph.Rec(hand.y0, hand.handle_ptr.* - p, hand.y1 - hand.y0, p * 2),
                };
                if (r.containsPoint(mcb.pos)) {
                    self.grab_index = h_i;
                    self.drag_start = mcb.pos;
                    mcb.gui.grabMouse(onGrab, vt, win, .left);
                }
            },
        }
    }

    pub fn onGrab(vt: *iArea, mcb: guis.MouseCbState, win: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", @as(*iWindow, @alignCast(@fieldParentPtr("area", vt)))));
        _ = win;

        const ws = self.getWorkspace(self.set_ws) orelse return;
        switch (mcb.state) {
            .high, .rising, .rising_repeat => {
                if (self.grab_index >= ws.handles.items.len) return;
                const min_w = 30;
                const hand = ws.handles.items[self.grab_index];
                if (hand.min >= hand.max) return;

                const x = if (hand.orientation == .vertical) mcb.pos.x else mcb.pos.y;

                hand.handle_ptr.* = std.math.clamp(x, hand.min + min_w, hand.max - min_w);
                self.set_ws = .none;
            },
            .falling => {
                ws.updateArea(self.vt.gui_ptr.alloc, ws.pane.split.area) catch {};
                ws.rebuildHandles(self.vt.gui_ptr.alloc) catch {};
                self.set_ws = .none;
            },
            .low => {},
        }
    }
};

const WindowItem = struct { graph.Rect, guis.WindowId };
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
    windows: std.ArrayList(WindowItem) = .{},

    pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
        self.pane.deinit(alloc);
        self.handles.deinit(alloc);
        self.windows.deinit(alloc);
    }

    pub fn updateArea(self: *Self, alloc: std.mem.Allocator, new_area: RectBound) !void {
        self.windows.clearRetainingCapacity();
        try self.pane.updateArea(alloc, new_area, &self.windows);
    }

    //TODO Should this be merged into updateArea
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
    window: guis.WindowId,

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

    pub fn updateArea(self: *@This(), alloc: std.mem.Allocator, new_area: RectBound, windows: *std.ArrayList(WindowItem)) !void {
        switch (self.*) {
            .window => |wid| {
                try windows.append(alloc, .{ new_area.toRect().inset(20), wid });
            },
            .split => |*sp| {
                const old_area = sp.area;
                sp.area = new_area;
                if (sp.children.items.len == 0) return;

                var valid = true;
                if (sp.handles.items.len != sp.children.items.len - 1) {
                    try sp.handles.resize(alloc, sp.children.items.len - 1);
                    valid = false;
                }
                const x1 = sp.x1(new_area);

                // split is valid if each handle is greater than the last
                if (valid) {
                    var current_handle: f32 = 0;
                    for (sp.handles.items) |hand| {
                        if (hand < current_handle or hand > x1) {
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
                    try child.updateArea(alloc, sp.childArea(new_area, i), windows);
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
