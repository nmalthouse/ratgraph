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

pub const SliderOptions = struct {
    nudge: f32 = 1,
    snap_mod: ?f32 = null,
    snap_thresh: f32 = 1,
};

fn numberTypeFromPtr(comptime T: type) type {
    const invalid_type_error = "Slider: " ++ "Argument \'ptr\' expects a mutable pointer to an int or float. Recieved: " ++ @typeName(@TypeOf(T));
    const info = @typeInfo(T);
    switch (info) {
        .pointer => |p| {
            if (p.is_const or p.size != .one) @compileError(invalid_type_error);
            const cinfo = @typeInfo(p.child);
            switch (cinfo) {
                .int, .float => return p.child,
                else => @compileError(invalid_type_error),
            }
        },
        else => @compileError(invalid_type_error),
    }
}

pub const Slider = struct {
    pub fn build(parent: *iArea, area_o: ?Rect, ptr: anytype, min: anytype, max: anytype, opts: SliderOptions) g.WgStatus {
        const Gen = SliderGeneric(numberTypeFromPtr(@TypeOf(ptr)));
        return Gen.build(parent, area_o, ptr, min, max, opts);
    }
};

pub fn SliderGeneric(comptime number_T: type) type {
    const info = @typeInfo(number_T);
    switch (info) {
        .int, .float => {},
        else => @compileError("invalid type for slider widget: " ++ @typeName(number_T)),
    }

    return struct {
        vt: iArea,

        shuttle_rect: Rect,
        ptr: *number_T,
        min: number_T,
        max: number_T,
        nudge_dist: f32,
        opts: SliderOptions,

        pub fn build(parent: *iArea, area_o: ?Rect, ptr: *number_T, min: anytype, max: anytype, opts: SliderOptions) g.WgStatus {
            const gui = parent.win_ptr.gui_ptr;
            const area = area_o orelse return .failed;
            if (min >= max) return .failed;
            const self = gui.create(@This());

            self.* = .{
                .vt = .UNINITILIZED,
                .ptr = ptr,
                .shuttle_rect = Rec(0, 0, 16 * gui.dstate.scale, area.h),
                .min = std.math.lossyCast(number_T, min),
                .max = std.math.lossyCast(number_T, max),
                .nudge_dist = opts.nudge,
                .opts = opts,
            };
            parent.addChild(&self.vt, .{
                .area = area,
                .deinit_fn = deinit,
                .draw_fn = draw,
                .focus_ev_fn = fevent,

                .can_tab_focus = true,
                .onclick = onclick,
            });
            self.shuttle_rect.x = self.valueToShuttlePos();
            return .good;
        }

        pub fn fevent(vt: *iArea, ev: g.FocusedEvent) void {
            const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
            switch (ev.event) {
                .focusChanged => vt.dirty(ev.gui),
                else => {},
                .keydown => |kev| {
                    for (kev.keys) |k| {
                        switch (@as(graph.SDL.keycodes.Scancode, @enumFromInt(k.key_id))) {
                            else => {},
                            .LEFT => {
                                vt.dirty(ev.gui);
                                self.nudge(-self.nudge_dist);
                            },
                            .RIGHT => {
                                vt.dirty(ev.gui);
                                self.nudge(self.nudge_dist);
                            },
                        }
                    }
                },
            }
        }

        fn nudge(self: *@This(), amount: f32) void {
            var float: f32 = std.math.lossyCast(f32, self.ptr.*);
            float += amount;

            float = std.math.clamp(float, std.math.lossyCast(f32, self.min), std.math.lossyCast(f32, self.max));
            self.ptr.* = std.math.lossyCast(number_T, float);
            self.shuttle_rect.x = self.valueToShuttlePos();
        }

        fn shuttlePosToValue(self: *const @This()) number_T {
            const ss_per_val = self.ss_per_v();
            if (ss_per_val == 0)
                return self.ptr.*;

            //Add back self.min as shuttle.x always starts at 0
            return std.math.lossyCast(number_T, self.shuttle_rect.x / ss_per_val) + self.min;
        }

        fn ss_per_v(self: *const @This()) f32 {
            const vdist = std.math.lossyCast(f32, self.max - self.min);
            const ss_dist = self.vt.area.w - self.shuttle_rect.w;
            if (ss_dist < 0)
                return 0;

            return ss_dist / vdist;
        }

        fn valueToShuttlePos(self: *const @This()) f32 {
            const ss_per_value = self.ss_per_v();
            if (ss_per_value == 0)
                return 0;

            //Subtract self.min so value is measured from 0
            const pos = std.math.lossyCast(f32, self.ptr.* - self.min) * ss_per_value;
            return std.math.clamp(pos, 0, self.vt.area.w - self.shuttle_rect.w);
        }

        pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
            const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
            gui.alloc.destroy(self);
        }

        fn shuttleSS(self: *@This()) Rect {
            const sr = self.shuttle_rect;
            const ar = self.vt.area;
            return Rec(sr.x + ar.x, sr.y + ar.y, sr.w, sr.h);
        }

        pub fn onclick(vt: *iArea, cb: g.MouseCbState, win: *iWindow) void {
            const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
            if (self.shuttleSS().containsPoint(cb.pos)) {
                vt.dirty(cb.gui);
                cb.gui.grabFocus(vt, win);
                cb.gui.grabMouse(&mouseGrabbed, vt, win, cb.btn);
            }
        }

        pub fn mouseGrabbed(vt: *iArea, cb: g.MouseCbState, _: *iWindow) void {
            const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
            if (self.shuttle_rect.w >= vt.area.w) return; //Just give up
            const old = self.shuttle_rect.x;
            self.shuttle_rect.x += cb.delta.x;
            self.shuttle_rect.x = std.math.clamp(self.shuttle_rect.x, 0, vt.area.w - self.shuttle_rect.w);
            if (cb.pos.x >= vt.area.x + vt.area.w)
                self.shuttle_rect.x = vt.area.w - self.shuttle_rect.w;
            if (cb.pos.x <= vt.area.x)
                self.shuttle_rect.x = 0;

            if (old != self.shuttle_rect.x) {
                vt.dirty(cb.gui);
                self.ptr.* = self.shuttlePosToValue();
                if (self.opts.snap_mod) |snap| {
                    if (info == .float) {
                        const snapped = @round(self.ptr.* / snap) * snap;
                        const dist = @abs(self.ptr.* - snapped);
                        if (dist < self.opts.snap_thresh) {
                            self.ptr.* = std.math.clamp(snapped, self.min, self.max);
                        }
                    }
                }
            }
        }

        pub fn draw(vt: *iArea, gui: *g.Gui, d: *g.DrawState) void {
            const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
            const box = d.style.getRect(.slider_box);
            d.ctx.nineSlice(vt.area, box, d.style.texture, d.scale, d.tint);

            const textb = vt.area.inset(d.scale * box.h / 3);
            const shuttle = d.style.getRect(.slider_shuttle);

            const MAX_DIV = 50;
            if (info == .int and self.max - self.min < MAX_DIV) {
                const count = self.max - self.min;
                if (count > 0) {
                    const icount: usize = @intCast(count);
                    const diff = vt.area.w / std.math.lossyCast(f32, icount);
                    for (1..icount) |i| { //Skip the first, it overlaps bounds of box
                        const fi: f32 = @floatFromInt(i);
                        const x = fi * diff + 1;
                        const start = graph.Vec2f.new(vt.area.x + x, vt.area.y);
                        const end = start.add(.{ .x = 0, .y = vt.area.h / 3 });
                        d.ctx.line(start, end, 0x222222ff, d.scale);
                    }
                }
            }
            const is_focused = gui.isFocused(vt);

            //const hr = Rec(vt.area.w / 3, 0, 16 * d.scale, vt.area.h);
            d.ctx.nineSlice(
                self.shuttleSS(),
                shuttle,
                d.style.texture,
                d.scale,
                if (is_focused) d.style.config.colors.selected else d.tint,
            );

            d.ctx.textClipped(textb, "{d:.2}", .{self.ptr.*}, d.textP(null), .center);
        }
    };
}
