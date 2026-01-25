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
const CbHandle = g.CbHandle;

const Tab = []const u8;

//First, in build append all tab names!
//on draw, draw those, then we have a buildCB(tab_name, area)
//cool thats it.
pub const Tabs = struct {
    pub const BuildTabCb = *const fn (*CbHandle, area_vt: *iArea, tab_name: []const u8, index: usize, *Gui, *iWindow) void;
    pub const Opts = struct {
        build_cb: BuildTabCb,
        cb_vt: *CbHandle,
        index_ptr: ?*usize = null,
    };
    vt: iArea,

    tabs: std.ArrayList(Tab),
    __selected_tab_index: usize = 0,
    opts: Opts,

    pub fn build(parent: *iArea, area_o: ?Rect, tabs: []const Tab, win: *iWindow, opts: Opts) g.WgStatus {
        const gui = parent.win_ptr.gui_ptr;
        const area = area_o orelse return .failed;
        if (tabs.len == 0)
            return .failed;
        var ly = g.VerticalLayout{ .item_height = gui.dstate.style.config.default_item_h, .bounds = area };
        const tab_area = ly.getArea() orelse return .failed;
        ly.pushHeight(gui.dstate.nstyle.tab_spacing);
        _ = ly.getArea();
        ly.pushRemaining();
        const child_area = ly.getArea() orelse return .failed;

        const self = gui.create(@This());

        self.* = .{
            .vt = .UNINITILIZED,
            .tabs = .{},
            .opts = opts,
        };
        parent.addChild(
            &self.vt,
            .{ .area = area, .deinit_fn = deinit, .draw_fn = draw },
        );
        if (opts.index_ptr == null)
            self.opts.index_ptr = &self.__selected_tab_index;
        self.tabs.appendSlice(gui.alloc, tabs) catch {
            self.tabs.deinit(gui.alloc);
            gui.alloc.destroy(self);
            return .failed;
        };

        _ = TabHeader.build(&self.vt, tab_area, self);
        _ = self.vt.addEmpty(child_area);
        self.rebuild(gui, win);

        return .good;
    }

    pub fn rebuild(self: *@This(), gui: *Gui, win: *iWindow) void {
        if (self.vt.children.items.len != 2)
            return;
        const index = self.opts.index_ptr.?.*;
        if (index >= self.tabs.items.len)
            return;
        self.vt.dirty();
        const child = self.vt.children.items[1];
        child.clearChildren(gui, win);
        self.opts.build_cb(self.opts.cb_vt, child, self.tabs.items[index], index, gui, win);
    }

    pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        self.tabs.deinit(gui.alloc);
        gui.alloc.destroy(self);
    }

    pub fn draw(vt: *iArea, _: *Gui, d: *g.DrawState) void {
        d.ctx.rect(vt.area, d.nstyle.color.bg);
    }
};

const TabHeader = struct {
    vt: iArea,

    parent: *Tabs,

    pub fn build(pa: *iArea, area: Rect, parent: *Tabs) g.WgStatus {
        const gui = pa.win_ptr.gui_ptr;

        const self = gui.create(@This());
        self.* = .{
            .vt = .UNINITILIZED,
            .parent = parent,
        };
        pa.addChild(&self.vt, .{ .area = area, .deinit_fn = deinit, .draw_fn = draw, .onclick = onclick });
        return .good;
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

    pub fn draw(vt: *iArea, _: *Gui, d: *g.DrawState) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        const col = &d.nstyle.color;
        d.ctx.rect(vt.area, d.nstyle.color.bg);

        d.box(vt.area, .{
            .bg = d.nstyle.color.bg,
            .border = d.nstyle.color.tab_border,
            .border_mask = 0b0010,
        });
        const tabs = self.parent.tabs.items;
        if (tabs.len == 0)
            return;
        var ly = g.HorizLayout{ .count = tabs.len, .bounds = vt.area.insetV(d.nstyle.tab_spacing, 0), .paddingh = d.nstyle.tab_spacing };
        for (tabs, 0..) |tab, i| {
            const a = ly.getArea() orelse continue;
            const active = i == self.parent.opts.index_ptr.?.*;
            const border: u8 = if (active) 0b1101 else 0b1111;

            d.box(a, .{
                .bg = if (active) col.tab_active_bg else col.tab_bg,
                .border = col.tab_border,
                .text = tab,
                .text_fg = if (active) col.tab_active_text_fg else col.tab_text_fg,
                .border_mask = border,
            });
        }
    }

    pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        gui.alloc.destroy(self);
    }
};
