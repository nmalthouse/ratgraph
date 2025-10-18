//// Copy this as a starting point for new widgets.
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

pub const Template = struct {
    vt: iArea,

    // Widget build functions are not part of the vtable and thus can have any arguments. They must return a ?*iArea or *iArea.
    // having the area:?Rect be optional and then returning a ? removes excessive boiler plate "orelse return" when layouting.
    // if an error occurs in build, free any resources and return null.
    pub fn build(gui: *Gui, area_o: ?Rect) ?*iArea {
        const area = area_o orelse return null;
        const self = gui.create(@This());

        self.* = .{
            .vt = iArea.init(gui, area),
        };
        self.vt.draw_fn = &draw;
        self.vt.deinit_fn = &deinit; //we must free our memory !
        return &self.vt;
    }

    pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        gui.alloc.destroy(self);
    }

    pub fn draw(vt: *iArea, _: *g.Gui, d: *g.DrawState) void {
        d.ctx.rect(vt.area, 0xff); //Black rect
    }
};
