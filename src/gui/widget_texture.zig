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

        cb_vt: ?*iArea = null,
        cb_fn: ?Widget.Button.ButtonCallbackT = null,
        id: usize = 0,
    };
    vt: iArea,

    uv: Rect,
    tex: graph.Texture,
    opts: Opts,

    pub fn build(gui: *Gui, area_o: ?Rect, tex: graph.Texture, uv: Rect, opts: Opts) ?*iArea {
        const area = area_o orelse return null;
        const self = gui.create(@This());

        self.* = .{
            .vt = iArea.init(gui, area),
            .uv = uv,
            .tex = tex,
            .opts = opts,
        };
        self.vt.draw_fn = &draw;
        self.vt.deinit_fn = &deinit;
        self.vt.onclick = &onclick;
        return &self.vt;
    }

    pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        gui.alloc.destroy(self);
    }

    pub fn draw(vt: *iArea, d: g.DrawState) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        const r = vt.area;
        d.ctx.rectTexTint(r, self.uv, self.opts.tint, self.tex);
    }

    pub fn onclick(vt: *iArea, cb: g.MouseCbState, win: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));

        vt.dirty(cb.gui);
        if (self.opts.cb_fn) |cbfn|
            cbfn(self.opts.cb_vt orelse return, self.opts.id, cb.gui, win);
    }
};
