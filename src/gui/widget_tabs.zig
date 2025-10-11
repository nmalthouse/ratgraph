const g = @import("vtables.zig");
const iArea = g.iArea;
const graph = g.graph;
const std = @import("std");
const Gui = g.Gui;
const Rect = g.Rect;
const Rec = g.Rec;
const iWindow = g.iWindow;
const Color = graph.Colori;
const VScroll = g.Widget.VScroll;
const Widget = g.Widget;

const Tab = []const u8;

//First, in build append all tab names!
//on draw, draw those, then we have a buildCB(tab_name, area)
//cool thats it.
pub const Tabs = struct {
    pub const BuildTabCb = *const fn (user_vt: *iArea, area_vt: *iArea, tab_name: []const u8, *Gui, *iWindow) void;
    pub const Opts = struct {
        build_cb: BuildTabCb,
        cb_vt: *iArea,
        index_ptr: ?*usize = null,
    };
    vt: iArea,

    tabs: std.ArrayList(Tab),
    __selected_tab_index: usize = 0,
    opts: Opts,

    pub fn build(gui: *Gui, area_o: ?Rect, tabs: []const Tab, win: *iWindow, opts: Opts) ?*iArea {
        const area = area_o orelse return null;
        const self = gui.create(@This());
        if (tabs.len == 0)
            return null;

        self.* = .{
            .vt = iArea.init(gui, area),
            .tabs = std.ArrayList(Tab).init(gui.alloc),
            .opts = opts,
        };
        if (opts.index_ptr == null)
            self.opts.index_ptr = &self.__selected_tab_index;
        self.tabs.appendSlice(tabs) catch return null; //free memory oops!
        self.vt.draw_fn = &draw;
        self.vt.deinit_fn = &deinit;
        var ly = g.VerticalLayout{ .item_height = gui.style.config.default_item_h, .bounds = area };
        const tab_area = ly.getArea() orelse return null;
        self.vt.addChild(gui, win, TabHeader.build(gui, tab_area, self));
        ly.pushRemaining();
        _ = self.vt.addEmpty(gui, win, ly.getArea() orelse return null);
        self.rebuild(gui, win);
        //build_cb(cb_vt, empty, tabs[0], gui, win);

        return &self.vt;
    }

    pub fn rebuild(self: *@This(), gui: *Gui, win: *iWindow) void {
        if (self.vt.children.items.len != 2)
            return;
        const index = self.opts.index_ptr.?.*;
        if (index >= self.tabs.items.len)
            return;
        self.vt.dirty(gui);
        const child = self.vt.children.items[1];
        child.clearChildren(gui, win);
        self.opts.build_cb(self.opts.cb_vt, child, self.tabs.items[index], gui, win);
    }

    pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        self.tabs.deinit();
        gui.alloc.destroy(self);
    }

    pub fn draw(vt: *iArea, d: g.DrawState) void {
        d.ctx.rect(vt.area, d.nstyle.color.bg);
    }
};

const TabHeader = struct {
    vt: iArea,

    parent: *Tabs,

    pub fn build(gui: *Gui, area: Rect, parent: *Tabs) *iArea {
        const self = gui.create(@This());
        self.* = .{
            .vt = iArea.init(gui, area),
            .parent = parent,
        };
        self.vt.draw_fn = &draw;
        self.vt.deinit_fn = &deinit;
        self.vt.onclick = &onclick;

        return &self.vt;
    }

    pub fn onclick(vt: *iArea, cb: g.MouseCbState, win: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        const tabs = self.parent.tabs.items;
        if (tabs.len == 0)
            return;
        var ly = g.HorizLayout{ .count = tabs.len, .bounds = vt.area };
        for (0..tabs.len) |i| {
            const a = ly.getArea() orelse return;
            if (a.containsPoint(cb.pos)) {
                self.parent.opts.index_ptr.?.* = i;
                self.parent.rebuild(cb.gui, win);
                return;
            }
        }
    }

    pub fn draw(vt: *iArea, d: g.DrawState) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        d.ctx.rect(vt.area, d.nstyle.color.bg);

        const bg = d.style.getRect(.tab_header_bg);
        d.ctx.nineSlice(vt.area, bg, d.style.texture, d.scale, d.tint);
        const tabs = self.parent.tabs.items;
        if (tabs.len == 0)
            return;
        const active = d.style.getRect(.tab_active);
        const inactive = d.style.getRect(.tab_inactive);
        var ly = g.HorizLayout{ .count = tabs.len, .bounds = vt.area };
        for (tabs, 0..) |tab, i| {
            const a = ly.getArea() orelse continue;
            const _9s = if (i == self.parent.opts.index_ptr.?.*) active else inactive;

            d.ctx.nineSlice(a, _9s, d.style.texture, d.scale, d.tint);
            const tarea = a.inset(d.scale * (_9s.w / 3));
            d.ctx.textClipped(tarea, "{s}", .{tab}, d.textP(null), .center);
        }
    }

    pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        gui.alloc.destroy(self);
    }
};
