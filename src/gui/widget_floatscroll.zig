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

/// TODO not implemeted
/// This should be:
/// A scroll where all elements are built and exist in
///
/// Problems
/// If widgets are occluded we need to mask click events
/// Tab Focusing a occuleded iArea should move scroll
/// On redraw of any iArea inside floatscroll, apply scissor
///
pub const FloatScroll = struct {
    vt: iArea,

    pub fn build(gui: *Gui, area_o: ?Rect) ?*iArea {
        const area = area_o orelse return null;
        const self = gui.create(@This());

        self.* = .{
            .vt = iArea.init(gui, area),
        };
        self.vt.draw_fn = &draw;
        self.vt.deinit_fn = &deinit;
        return &self.vt;
    }

    pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        gui.alloc.destroy(self);
    }

    pub fn draw(vt: *iArea, d: g.DrawState) void {
        d.ctx.rect(vt.area, 0xff); //Black rect
    }
};
// Render scroll contenst to diff Window, then draw that to place
