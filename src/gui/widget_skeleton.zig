//// Copy this as a starting point for new widgets.
/// Example of a widget
pub const Template = struct {
    /// The vtable, should NOT be initilized directly
    vt: iArea,

    /// Widget build functions are not a part of the vtable so can have any form
    /// but the first two arguments should be the parent and the area.
    /// Widgets cannot be created without attaching them to a parent.
    pub fn build(parent: *iArea, area_o: ?Rect) g.WgStatus {
        const gui = parent.win_ptr.gui_ptr;
        const area = area_o orelse return .failed;
        const self = gui.create(@This());

        self.* = .{
            .vt = .UNINITILIZED,
        };
        // This call fills out the vtable and registers all the callbacks
        parent.addChild(&self.vt, .{ .area = area, .deinit_fn = deinit, .draw_fn = draw });
        return .good;
    }

    pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        gui.alloc.destroy(self);
    }

    pub fn draw(vt: *iArea, _: *g.Gui, d: *g.DrawState) void {
        d.ctx.rect(vt.area, 0xff); //Black rect
    }
};

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
