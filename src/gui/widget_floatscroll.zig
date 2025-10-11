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

/// TODO not implemeted
/// This should be:
/// A scroll where all elements are built and exist in
///
/// Problems
/// If widgets are occluded we need to mask click events
/// Tab Focusing a occuleded iArea should move scroll
/// On redraw of any iArea inside floatscroll, apply scissor
pub const BuildCb = *const fn (*CbHandle, current_area: *iArea, *Gui, *iWindow) void;
pub const Opts = struct {
    build_cb: BuildCb,
    build_vt: *CbHandle,
    win: *iWindow,
    scroll_mul: f32,
};
pub const FloatScroll = struct {
    vt: iArea,

    opts: Opts,

    pub fn build(gui: *Gui, area_o: ?Rect, opts: Opts) ?*iArea {
        const area = area_o orelse return null;
        const self = gui.create(@This());

        self.* = .{
            .vt = iArea.init(gui, area),
            .opts = opts,
        };
        self.vt.draw_fn = &draw;
        self.vt.deinit_fn = &deinit;
        self.vt.onscroll = onScroll;
        opts.win.registerScissor(&self.vt) catch {};

        _ = self.vt.addEmpty(gui, opts.win, area);

        self.rebuild(gui, opts.win);
        return &self.vt;
    }

    pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        gui.alloc.destroy(self);
    }

    pub fn draw(vt: *iArea, d: g.DrawState) void {
        d.ctx.rect(vt.area, 0xff); //Black rect
    }

    pub fn rebuild(self: *@This(), gui: *Gui, win: *iWindow) void {
        if (self.vt.children.items.len != 1) return;

        self.vt.dirty(gui);

        const child = self.vt.children.items[0];
        child.clearChildren(gui, win);

        self.opts.build_cb(self.opts.build_vt, child, gui, win);
    }

    pub fn onScroll(vt: *iArea, gui: *Gui, win: *iWindow, dist: f32) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));

        if (self.vt.children.items.len != 1) return;

        const child = self.vt.children.items[0];
        child.area.y += dist * self.opts.scroll_mul;

        self.rebuild(gui, win);
    }
};
// Render scroll contenst to diff Window, then draw that to place
