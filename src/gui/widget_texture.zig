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

pub const GLTexture = struct {
    pub const Opts = struct {
        tint: u32 = 0xffff_ffff,

        cb_vt: ?*g.CbHandle = null,
        cb_fn: ?Widget.Button.ButtonCallbackT = null,
        id: usize = 0,
    };
    vt: iArea,

    uv: Rect,
    tex: graph.Texture,
    opts: Opts,

    pub fn build(parent: *iArea, area_o: ?Rect, tex: graph.Texture, uv: Rect, opts: Opts) g.WgStatus {
        const gui = parent.win_ptr.gui_ptr;
        const area = area_o orelse return .failed;
        const self = gui.create(@This());

        self.* = .{
            .vt = .UNINITILIZED,
            .uv = uv,
            .tex = tex,
            .opts = opts,
        };
        parent.addChild(&self.vt, .{ .area = area, .deinit_fn = deinit, .draw_fn = draw, .onclick = onclick });
        return .good;
    }

    pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        gui.alloc.destroy(self);
    }

    pub fn draw(vt: *iArea, _: *g.Gui, d: *g.DrawState) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        const r = vt.area;
        d.ctx.rectTexTint(r, self.uv, self.opts.tint, self.tex);
    }

    pub fn onclick(vt: *iArea, cb: g.MouseCbState, win: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));

        vt.dirty(cb.gui);
        if (self.opts.cb_fn) |cbfn|
            cbfn(self.opts.cb_vt orelse return, self.opts.id, cb, win);
    }
};
