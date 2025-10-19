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
const NewVt = g.NewVt;
pub const ALLOWED_CHAR = "0123456789abcdef.-inx";
pub const StaticSliderOpts = struct {
    pub const State = graph.SDL.ButtonState;
    min: f32,
    max: f32,
    default: f32,
    ///Not allocated
    unit: []const u8 = "",

    display_kind: enum { raw, percent, integer } = .raw,
    display_bounds_while_editing: bool = false,
    clamp_edits: bool = false,
    slide: Slide = .{},

    commit_cb: ?*const fn (*CbHandle, *Gui, f32, user_id: usize) void = null,
    slide_cb: ?*const fn (*CbHandle, *Gui, f32, user_id: usize, State) void = null, // Called while holding the slider
    commit_vt: ?*CbHandle = null,
    user_id: usize = 0,
};

pub const Slide = struct {
    mapping: enum { linear } = .linear,
    snap: f32 = 1,

    _snap_del: f32 = 0,

    pub fn map(s: *Slide, area: graph.Vec2f, mouse_delta: graph.Vec2f, value: f32, dist: f32) f32 {
        var new = value + s._snap_del;
        switch (s.mapping) {
            .linear => {
                const factor = dist / area.x;
                const yfac = dist / area.y / 6;

                new += mouse_delta.x * factor - yfac * mouse_delta.y;
            },
        }
        const old = new;
        new = s.snapIt(new);
        s._snap_del = old - new;

        return new;
    }

    fn snapIt(s: Slide, value: f32) f32 {
        var new = value;
        if (s.snap > 0) {
            new = @round(new / s.snap) * s.snap;
        }
        return new;
    }
};

/// A box that when clicked allows allows manipulation of a value by moving mouse in +- x
pub const StaticSlider = struct {
    vt: iArea,

    opts: StaticSliderOpts,
    _num: f32 = 0,
    num: *f32,

    state: enum { editing, display },
    //2**64 in base 10 is 20 digits, this should be more than enough
    buf: [32]u8 = undefined,
    fbs: std.io.FixedBufferStream([]u8),

    pub fn build(parent: *iArea, area_o: ?Rect, number: ?*f32, opts: StaticSliderOpts) g.WgStatus {
        const gui = parent.win_ptr.gui_ptr;
        const area = area_o orelse return .failed;
        const self = gui.create(@This());
        self.* = .{
            .vt = .UNINITILIZED,
            .opts = opts,
            ._num = opts.default,
            .num = number orelse &self._num,
            .state = .display,
            .fbs = .{ .buffer = &self.buf, .pos = 0 },
        };
        parent.addChild(&self.vt, .{
            .area = area,
            .deinit_fn = deinit,
            .draw_fn = draw,
            .focus_ev_fn = fevent,

            .onclick = onclick,
            .onscroll = scroll,
        });
        if (opts.max == opts.min) {
            std.debug.print("Static slider has invalid max min \n", .{});
        }
        return .good;
    }

    pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        gui.alloc.destroy(self);
    }

    fn clamp(self: *@This()) void {
        const min = @min(self.opts.min, self.opts.max);
        const max = @max(self.opts.min, self.opts.max);
        self.num.* = @max(min, @min(self.num.*, max));
    }

    pub fn draw(vt: *iArea, _: *g.Gui, d: *g.DrawState) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        d.ctx.rect(vt.area, d.nstyle.color.static_slider_bg);
        const ins = @ceil(d.scale);
        const inset = vt.area.inset(ins);
        //const ta = inset.inset(@ceil(d.style.config.textbox_inset * d.scale));
        const ta = d.textArea(vt.area);
        if (self.opts.max == self.opts.min) return;
        const FILL_COLOR = 0xf7a41dff;
        switch (self.state) {
            .display => {
                const perc = std.math.clamp((self.num.* - self.opts.min) / @abs(self.opts.max - self.opts.min), 0, 1);
                d.ctx.rect(inset.replace(null, null, inset.w * perc, null), FILL_COLOR);
                switch (self.opts.display_kind) {
                    .raw => d.ctx.textClipped(ta, "{d:.2} {s}", .{ self.num.*, self.opts.unit }, d.textP(null), .center),
                    .percent => d.ctx.textClipped(ta, "{d:.2} % {s}", .{ perc * 100, self.opts.unit }, d.textP(null), .center),
                    .integer => d.ctx.textClipped(ta, "{d:.0} {s}", .{ self.num.*, self.opts.unit }, d.textP(null), .center),
                }
            },
            .editing => {
                if (self.opts.display_bounds_while_editing) {
                    d.ctx.textClipped(ta, "{d:.2}", .{self.opts.min}, d.textP(null), .left);
                    d.ctx.textClipped(ta, "{d:.2}", .{self.opts.max}, d.textP(null), .right);
                }
                d.ctx.textClipped(ta, "edit: {s}", .{self.fbs.getWritten()}, d.textP(null), .center);
            },
        }
        d.ctx.rectLine(inset, ins, 0xff);
    }

    fn cancelEdit(self: *@This(), gui: *Gui) void {
        self.state = .display;
        gui.stopTextInput();
        self.vt.dirty(gui);
    }

    fn startEdit(self: *@This(), gui: *Gui) void {
        self.state = .editing;
        self.fbs.reset();
        gui.startTextinput(self.vt.area);
        self.vt.dirty(gui);
    }

    pub fn mouseGrabbed(vt: *iArea, cb: g.MouseCbState, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));

        const old_num = self.num.*;
        const dist = self.opts.max - self.opts.min;
        self.num.* = self.opts.slide.map(vt.area.dim(), cb.delta, self.num.*, dist);

        self.clamp();
        if (old_num != self.num.* or cb.state == .falling) {
            self.slideCb(cb.gui, cb.state);
            if (cb.state == .falling)
                self.commitCb(cb.gui);
            vt.dirty(cb.gui);
        }
    }

    pub fn scroll(vt: *iArea, gui: *Gui, _: *iWindow, dist: f32) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        var d = dist;
        if (self.opts.slide.snap > 0) d *= self.opts.slide.snap;
        const old_num = self.num.*;
        self.num.* += d;
        self.clamp();
        if (old_num != self.num.*) {
            self.commitCb(gui);
            vt.dirty(gui);
        }
    }

    pub fn commitCb(self: *@This(), gui: *Gui) void {
        if (self.opts.commit_cb) |cb| {
            cb(self.opts.commit_vt orelse return, gui, self.num.*, self.opts.user_id);
        }
    }

    pub fn slideCb(self: *@This(), gui: *Gui, st: StaticSliderOpts.State) void {
        if (self.opts.slide_cb) |cb| {
            cb(self.opts.commit_vt orelse return, gui, self.num.*, self.opts.user_id, st);
        }
    }

    pub fn onclick(vt: *iArea, cb: g.MouseCbState, win: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        switch (cb.btn) {
            .left => {
                self.cancelEdit(cb.gui);
                cb.gui.grabMouse(&@This().mouseGrabbed, vt, win, cb.btn);
                self.slideCb(cb.gui, .rising);
            },
            .middle => self.num.* = self.opts.default,
            .right => {
                switch (self.state) {
                    .editing => {
                        self.commitEdit(cb.gui);
                    },
                    .display => {
                        cb.gui.grabFocus(vt, win);
                        self.startEdit(cb.gui);
                    },
                }
            },
        }
        vt.dirty(cb.gui);
    }

    pub fn fevent(vt: *iArea, ev: g.FocusedEvent) void {
        fevent_err(vt, ev) catch return;
    }

    fn commitEdit(self: *@This(), gui: *Gui) void {
        self.state = .display;
        gui.stopTextInput();
        self.num.* = std.fmt.parseFloat(f32, self.fbs.getWritten()) catch self.num.*;
        if (self.opts.clamp_edits)
            self.clamp();
        self.commitCb(gui);
        self.vt.dirty(gui);
    }

    pub fn fevent_err(vt: *iArea, ev: g.FocusedEvent) !void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        switch (ev.event) {
            .focusChanged => |focused| {
                if (!focused) {
                    ev.gui.stopTextInput();
                    self.state = .display;
                }
                //self.state = .editing;
                vt.dirty(ev.gui);
            },
            .text_input => |st| {
                const w = self.fbs.writer();
                const view = std.unicode.Utf8View.init(st.text) catch return;
                vt.dirty(ev.gui);
                var it = view.iterator();
                while (it.nextCodepointSlice()) |codepoint| {
                    const char = if (codepoint.len == 1) codepoint[0] else continue;
                    if (std.mem.indexOfScalar(u8, ALLOWED_CHAR, char) != null) {
                        w.writeByte(char) catch return;
                    }
                }
            },
            .keydown => |kev| {
                vt.dirty(ev.gui);
                for (kev.keys) |key| {
                    switch (@as(graph.SDL.keycodes.Scancode, @enumFromInt(key.key_id))) {
                        .BACKSPACE => {
                            if (self.fbs.pos > 0) //All numerals are ascii so we can do this
                                self.fbs.pos -= 1;
                        },
                        .RETURN => {
                            self.commitEdit(ev.gui);
                        },
                        else => {},
                    }
                }
            },
        }
    }
};
