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
const WgStatus = g.WgStatus;

pub const Colorpicker = struct {
    const CommitCb = *const fn (*CbHandle, *Gui, color: u32, user_id: usize) void;
    pub const Opts = struct {
        commit_vt: ?*CbHandle = null,
        commit_cb: ?CommitCb = null,
        user_id: usize = 0,
    };
    vt: iArea,

    color: u32,
    opts: Opts,

    color_hsv: graph.Hsva,

    pub fn build(parent: *iArea, area: Rect, color: u32, opts: Opts) WgStatus {
        const gui = parent.win_ptr.gui_ptr;
        const self = gui.create(@This());
        self.* = .{
            .vt = .UNINITILIZED,
            .opts = opts,
            .color = color,
            .color_hsv = graph.ptypes.Hsva.fromInt(color),
        };
        parent.addChild(&self.vt, .{ .area = area, .deinit_fn = deinit, .draw_fn = draw, .onclick = onclick });
        return .good;
    }

    pub fn draw(vt: *iArea, _: *g.Gui, d: *g.DrawState) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        d.ctx.rect(vt.area, self.color);
    }

    pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        gui.alloc.destroy(self);
    }

    pub fn commitColor(self: *@This(), gui: *Gui, new: u32) void {
        self.color = new;
        if (self.opts.commit_cb) |cb|
            cb(self.opts.commit_vt orelse return, gui, new, self.opts.user_id);
    }

    pub fn onclick(vt: *iArea, cb: g.MouseCbState, win: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));

        const sz = cb.gui.dstate.nstyle.color_picker_size;
        const new_r = Rec(vt.area.x, vt.area.y, sz.x * cb.gui.dstate.scale, sz.y * cb.gui.dstate.scale);
        _ = win;
        self.makeTransientWin(cb.gui, cb.gui.clampRectToWindow(new_r));
    }

    fn makeTransientWin(self: *@This(), gui: *Gui, area: Rect) void {
        const tr = gui.create(ColorpickerTransient);
        tr.* = .{
            .vt = iWindow.init(
                &ColorpickerTransient.build,
                gui,
                &ColorpickerTransient.deinit,
                .{ .area = area },
                &tr.vt,
            ),
            .parent_ptr = self,
        };
        //TODO don't do this
        tr.vt.area.draw_fn = ColorpickerTransient.draw;
        gui.setTransientWindow(&tr.vt);
        tr.vt.build_fn(&tr.vt, gui, area);
    }
};

const ColorpickerTransient = struct {
    vt: iWindow,
    cbhandle: CbHandle = .{},

    parent_ptr: *Colorpicker,

    sv_handle: graph.Vec2f = .{ .x = 10, .y = 10 },
    hue_handle: f32 = 0,

    pub fn build(win: *iWindow, gui: *Gui, area: Rect) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", win));
        self.vt.area.area = area;
        win.area.dirty();
        self.vt.area.clearChildren(gui, win);
        const a = &win.area;

        var ly = g.HorizLayout{ .count = 2, .bounds = g.GuiHelp.insetAreaForWindowFrame(gui, win.area.area) };
        const ar = ly.getArea() orelse return;
        const pad = gui.dstate.scale * 5;
        const slider_w = 40 * gui.dstate.scale;
        const sv_area = Rec(ar.x, ar.y, ar.w - (slider_w + pad) * 1, ar.h);
        const sv = win.area.addEmpty(sv_area);
        _ = WarpArea.build(
            sv,
            sv_area,
            &self.sv_handle.x,
            &self.sv_handle.y,
            &self.cbhandle,
            &warpNotify,
            .{ .x = 10, .y = 10 },
        );
        const color = self.parent_ptr.color_hsv;
        self.sv_handle.x = color.s * sv_area.w;
        self.sv_handle.y = (1.0 - color.v) * sv_area.h;

        const h_area = Rec(sv_area.x + sv_area.w + pad, ar.y, slider_w, ar.h);
        const hue = win.area.addEmpty(h_area);

        self.hue_handle = color.h / 360.0 * h_area.h;

        _ = WarpArea.build(
            hue,
            h_area,
            null,
            &self.hue_handle,
            &self.cbhandle,
            &warpNotify,
            .{ .x = h_area.w, .y = 10 },
        );

        var vy = gui.dstate.vlayout(ly.getArea() orelse return);

        _ = Widget.Button.build(
            a,
            vy.getArea(),
            "Done",
            .{ .cb_vt = &self.cbhandle, .cb_fn = &closeBtnCb, .id = 0 },
        );

        const Help = struct {
            fn valueGroup(cb: *CbHandle, a1: anytype, layout: anytype, ptr: *f32, name: []const u8, min: f32, max: f32, nudge: f32) void {
                const hue_s = layout.getArea() orelse return;
                var vy2 = g.HorizLayout{ .count = 2, .bounds = hue_s };
                _ = Widget.Text.build(a1, vy2.getArea(), "{s}", .{name}, .{});

                _ = Widget.StaticSlider.build(a1, vy2.getArea(), ptr, .{
                    .display_bounds_while_editing = false,
                    .clamp_edits = true,
                    .default = max,
                    .min = min,
                    .max = max,
                    .slide = .{ .snap = nudge },
                    .commit_cb = ssliderCbCommit,
                    .slide_cb = ssliderCb,
                    .commit_vt = cb,
                });
            }
        };

        Help.valueGroup(&self.cbhandle, a, &vy, &self.parent_ptr.color_hsv.h, "Hue", 0, 360, 5);
        Help.valueGroup(&self.cbhandle, a, &vy, &self.parent_ptr.color_hsv.s, "Saturation", 0, 1, 0.02);
        Help.valueGroup(&self.cbhandle, a, &vy, &self.parent_ptr.color_hsv.v, "Value", 0, 1, 0.02);
        Help.valueGroup(&self.cbhandle, a, &vy, &self.parent_ptr.color_hsv.a, "Alpha", 0, 1, 0.02);

        _ = Widget.Textbox.buildOpts(a, vy.getArea(), .{
            .commit_cb = &pastedTextboxCb,
            .commit_vt = &self.cbhandle,
        });
    }

    pub fn pastedTextboxCb(cb: *CbHandle, p: Widget.Textbox.CommitParam) void {
        const self: *@This() = @alignCast(@fieldParentPtr("cbhandle", cb));
        if (p.string.len > 0) {
            _ = blk: {
                const newcolor = ((std.fmt.parseInt(u32, p.string, 0) catch |err| switch (err) {
                    else => break :blk,
                } << 8) | 0xff);

                self.parent_ptr.commitColor(p.gui, newcolor);
                self.parent_ptr.color_hsv = graph.ptypes.Hsva.fromInt(newcolor);
                self.parent_ptr.vt.dirty();
                self.vt.area.dirty();
                //std.debug.print("Setting color to {x}\n", .{newcolor});
            };
        }
    }

    pub fn deinit(vt: *iWindow, gui: *Gui) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        vt.deinit(gui);
        gui.alloc.destroy(self);
    }

    fn warpNotify(vt: *CbHandle, _: *Gui) void {
        const self: *@This() = @alignCast(@fieldParentPtr("cbhandle", vt));
        const w = self.vt.area.children.items;
        if (w.len < 2)
            return;
        const sv_area = w[0].area;
        const h_area = w[1].area;
        self.vt.area.dirty();
        const color = &self.parent_ptr.color_hsv;
        color.s = self.sv_handle.x / sv_area.w;
        color.v = (1.0 - (self.sv_handle.y) / sv_area.h);
        color.s = std.math.clamp(color.s, 0, 1);
        color.v = std.math.clamp(color.v, 0, 1);
        color.h = (self.hue_handle) / h_area.h * 360.0;
    }

    fn closeBtnCb(cb: *CbHandle, id: usize, dat: g.MouseCbState, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("cbhandle", cb));

        self.parent_ptr.commitColor(dat.gui, self.parent_ptr.color_hsv.toInt());
        self.parent_ptr.vt.dirty();
        _ = id;
        dat.gui.deferTransientClose();
    }

    pub fn draw(vt: *iArea, gui: *g.Gui, d: *g.DrawState) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", @as(*iWindow, @alignCast(@fieldParentPtr("area", vt)))));
        const w = vt.children.items;
        if (w.len < 2)
            return;
        const sv_area = w[0].area;
        g.GuiHelp.drawWindowFrame(d, vt.area);
        const col = self.parent_ptr.color_hsv.toInt();
        const inset = g.GuiHelp.insetAreaForWindowFrame(gui, vt.area);
        d.ctx.rect(inset, col);
        d.ctx.rectVertexColors(sv_area, &.{ Color.Black, Color.Black, Color.Black, Color.Black });
        const color = &self.parent_ptr.color_hsv;
        const temp = (graph.Hsva{ .h = color.h, .s = 1, .v = 1, .a = 1 }).toInt();
        const black_trans = 0;
        if (true) {
            d.ctx.rectVertexColors(sv_area, &.{ Color.White, Color.White, temp, temp });
            d.ctx.rectVertexColors(sv_area, &.{ black_trans, Color.Black, Color.Black, black_trans });
        }

        //Ported from Nuklear
        { //Hue slider
            const h_area = w[1].area;
            const hue_colors: [7]u32 = .{ 0xff0000ff, 0xffff00ff, 0x00ff00ff, 0x00ffffff, 0xffff, 0xff00ffff, 0xff0000ff };
            var i: u32 = 0;
            while (i < 6) : (i += 1) {
                const fi = @as(f32, @floatFromInt(i));
                const r = Rect.new(h_area.x, h_area.y + fi * h_area.h / 6.0, h_area.w, h_area.h / 6.0);
                d.ctx.rectVertexColors(r, &.{
                    hue_colors[i], // 1
                    hue_colors[i + 1], //3
                    hue_colors[i + 1], //4
                    hue_colors[i], //2
                });
            }
        }
    }

    pub fn deinit_area(_: *iArea, _: *Gui, _: *iWindow) void {}

    fn ssliderCb(cb: *CbHandle, _: *Gui, _: f32, _: usize, _: Widget.StaticSliderOpts.State) void {
        const self: *@This() = @alignCast(@fieldParentPtr("cbhandle", cb));
        self.vt.area.dirty();
    }

    fn ssliderCbCommit(cb: *CbHandle, _: *Gui, _: f32, _: usize) void {
        const self: *@This() = @alignCast(@fieldParentPtr("cbhandle", cb));
        self.vt.area.dirty();
    }
};

const WarpArea = struct {
    const WarpNotifyFn = *const fn (*CbHandle, *Gui) void;
    vt: iArea,
    xptr: ?*f32,
    yptr: ?*f32,

    notify_vt: *CbHandle,
    notify_fn: WarpNotifyFn,

    handle_dim: graph.Vec2f,

    pub fn build(parent: *iArea, area: Rect, x: ?*f32, y: ?*f32, warp_notify_vt: *CbHandle, warp_notify_fn: WarpNotifyFn, handle_dim: graph.Vec2f) WgStatus {
        const gui = parent.win_ptr.gui_ptr;

        const self = gui.create(@This());
        self.* = .{
            .vt = .UNINITILIZED,
            .xptr = x,
            .yptr = y,
            .notify_vt = warp_notify_vt,
            .notify_fn = warp_notify_fn,
            .handle_dim = handle_dim,
        };
        parent.addChild(&self.vt, .{ .area = area, .deinit_fn = deinit, .draw_fn = draw, .onclick = onclick });
        return .good;
    }

    pub fn onclick(vt: *iArea, cb: g.MouseCbState, win: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));

        if (self.xptr) |x|
            x.* = cb.pos.x - vt.area.x;
        if (self.yptr) |y|
            y.* = cb.pos.y - vt.area.y;

        cb.gui.grabMouse(&@This().mouseGrabbed, vt, win, cb.btn);
        //IMPORTANT
        //with the current drawing algo, swapping the order will prevent warp from showing!
        self.notify_fn(self.notify_vt, cb.gui);
        vt.dirty();
    }

    pub fn mouseGrabbed(vt: *iArea, cb: g.MouseCbState, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        if (self.xptr) |x| {
            if (cb.pos.x >= vt.area.x and cb.pos.x <= vt.area.x + vt.area.w) {
                x.* += cb.delta.x;
            }
            x.* = std.math.clamp(x.*, 0, vt.area.w);
            if (cb.pos.x >= vt.area.x + vt.area.w)
                x.* = vt.area.w;
            if (cb.pos.x <= vt.area.x)
                x.* = 0;
        }

        if (self.yptr) |x| {
            if (cb.pos.y >= vt.area.y and cb.pos.y <= vt.area.y + vt.area.h) {
                x.* += cb.delta.y;
            }
            x.* = std.math.clamp(x.*, 0, vt.area.h);
            if (cb.pos.y >= vt.area.y + vt.area.h)
                x.* = vt.area.h;
            if (cb.pos.y <= vt.area.y)
                x.* = 0;
        }
        self.notify_fn(self.notify_vt, cb.gui);
        vt.dirty();
    }

    pub fn draw(vt: *iArea, _: *g.Gui, d: *g.DrawState) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        const x = if (self.xptr) |o| o.* else vt.area.w / 2;
        const y = if (self.yptr) |o| o.* else vt.area.h / 2;

        const w = self.handle_dim.x;
        const hw = w / 2;

        const h = self.handle_dim.y;
        const hh = h / 2;

        d.ctx.rect(Rec(x + vt.area.x - hw, y + vt.area.y - hh, w, h), 0xffffffff);
    }

    pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        gui.alloc.destroy(self);
    }
};
