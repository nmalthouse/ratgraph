const g = @import("vtables.zig");
const iArea = g.iArea;
const std = @import("std");
const Gui = g.Gui;
const Rect = g.Rect;
const iWindow = g.iWindow;
const GuiConfig = g.GuiConfig;
const VerticalLayout = g.VerticalLayout;
const DrawState = g.DrawState;
const MouseCbState = g.MouseCbState;
const Color = graph.Colori;
const Rec = g.Rec;
const graph = g.graph;
const getVt = g.getVt;
const CbHandle = g.CbHandle;
const NewVt = g.NewVt;

// Write a widget that is a static text box.
// Works like a tabs or whatever which holds all the alloc for string, so scrolling doesn't realloc

pub const VScroll = struct {
    pub const BuildCb = *const fn (*CbHandle, current_area: *iArea, index: usize, *Gui, *iWindow) void;
    pub const Opts = struct {
        build_cb: BuildCb,
        build_vt: *CbHandle,
        win: *iWindow,
        count: usize,
        item_h: f32,

        index_ptr: ?*usize = null,
        force_scroll: bool = false,
    };

    vt: iArea,

    __index: usize = 0,
    index_ptr: *usize,
    opts: Opts,
    sc_count: usize = 0,
    has_scroll: bool = false,

    pub fn build(gui: *Gui, area_o: ?Rect, opts: Opts) ?g.NewVt {
        const area = area_o orelse return null;
        const self = gui.create(@This());
        self.* = .{
            .vt = .{ .area = area, .deinit_fn = deinit, .draw_fn = draw },
            .opts = opts,
            .index_ptr = opts.index_ptr orelse &self.__index,
            .sc_count = opts.count,
        };

        const needs_scroll = opts.force_scroll or opts.item_h * @as(f32, @floatFromInt(opts.count)) > area.h;
        if (self.index_ptr.* >= self.opts.count) {
            self.index_ptr.* = if (self.opts.count > 0) self.opts.count - 1 else 0;
        }

        self.sc_count = self.getScrollableCount();
        //self.sc_count = opts.count - self.getFitted();

        const split = self.vt.area.split(.vertical, if (needs_scroll) getAreaW(self.vt.area.w, gui.scale) else self.vt.area.w);
        var onscroll: ?g.NewVt.Onscroll = null;
        _ = self.vt.addEmpty(gui, opts.win, split[0]);
        if (needs_scroll) {
            self.has_scroll = true;
            onscroll = onScroll;
            self.vt.addChildOpt(gui, opts.win, ScrollBar.build(
                gui,
                split[1],
                self.index_ptr,
                self.sc_count,
                opts.item_h,
                &self.vt,
                &notifyChange,
            ));
        } else {
            //self.index_ptr.* = 0;
            //_ = self.vt.addEmpty(gui, opts.win, split[1]);
        }

        self.rebuild(gui, opts.win);
        return .{ .vt = &self.vt, .onscroll = onscroll };
    }

    pub fn getAreaW(parent_w: f32, scale: f32) f32 {
        const SW = 15 * scale;
        return parent_w - SW;
    }

    pub fn getCount(self: *@This()) usize {
        return self.opts.count;
    }

    pub fn getScrollableCount(self: *@This()) usize {
        const fitted = @trunc(self.vt.area.h / self.opts.item_h) - 2; // -1 so user can see scroll has ended
        if (fitted > 1 and fitted < std.math.maxInt(usize)) {
            const fw: usize = @intFromFloat(fitted);
            if (fw < self.opts.count)
                return self.opts.count - fw;
        }
        return self.opts.count;
    }

    pub fn gotoBottom(self: *@This()) void {
        const fitted = @trunc(self.vt.area.h / self.opts.item_h);
        if (@as(f32, @floatFromInt(self.sc_count)) < fitted) {
            self.index_ptr.* = 0;
        } else {
            self.index_ptr.* = self.sc_count;
        }
    }

    pub fn updateCount(self: *@This(), new_count: usize) void {
        if (self.vt.children.items.len != 2) return;
        const scr: *ScrollBar = @alignCast(@fieldParentPtr("vt", self.vt.children.items[1]));
        self.opts.count = new_count;
        self.sc_count = self.getScrollableCount();
        scr.updateCount(self.sc_count);
        if (self.sc_count >= self.index_ptr.*)
            self.index_ptr.* = self.sc_count;
    }

    pub fn rebuild(self: *@This(), gui: *Gui, win: *iWindow) void {
        if (self.vt.children.items.len != 2)
            return;
        //TODO check if it needs the vscroll and add it

        self.vt.dirty(gui);
        const child = self.vt.children.items[0];
        child.clearChildren(gui, win);

        self.opts.build_cb(self.opts.build_vt, child, self.index_ptr.*, gui, win);
    }

    pub fn deinit(vt: *iArea, gui: *Gui, window: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        _ = window;
        gui.alloc.destroy(self);
    }

    pub fn draw(vt: *iArea, d: DrawState) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        d.ctx.rect(vt.area, d.nstyle.color.bg);
        _ = self;
    }

    pub fn notifyChange(vt: *iArea, gui: *Gui, win: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        self.rebuild(gui, win);
    }

    pub fn onScroll(vt: *iArea, gui: *Gui, win: *iWindow, dist: f32) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        if (self.sc_count == 0) {
            self.index_ptr.* = 0;
            return;
        }

        var fi: f32 = @floatFromInt(self.index_ptr.*);
        fi += dist * 4;
        fi = std.math.clamp(fi, 0, @as(f32, @floatFromInt(self.sc_count - 1)));
        self.index_ptr.* = @intFromFloat(fi);
        self.rebuild(gui, win);
    }
};

pub const Checkbox = struct {
    pub const CommitCb = *const fn (*iArea, *Gui, bool, user_id: g.Uid) void;
    pub const Opts = struct {
        bool_ptr: ?*bool = null,
        cb_fn: ?CommitCb = null,
        cb_vt: ?*iArea = null,
        user_id: g.Uid = 0,
        style: enum {
            ableton,
            check,
            dropdown,
        } = .ableton,

        cross_color: u32 = 0xff,
    };
    vt: iArea,

    __bool: bool = false,
    bool_ptr: *bool,
    opts: Opts,
    name: []const u8,

    pub fn build(gui: *Gui, area_o: ?Rect, name: []const u8, opts: Opts, set: ?bool) ?NewVt {
        const area = area_o orelse return null;
        const self = gui.create(@This());
        self.* = .{
            .vt = .{ .area = area, .deinit_fn = deinit },
            .opts = opts,
            .bool_ptr = opts.bool_ptr orelse &self.__bool,
            .name = name,
        };
        self.__bool = set orelse self.__bool;
        self.vt.can_tab_focus = true;
        self.vt.focusEvent = &fevent;
        self.vt.draw_fn = switch (opts.style) {
            .ableton => draw,
            .check => drawCheck,
            .dropdown => drawDropdown,
        };
        return .{
            .vt = &self.vt,
            .onclick = onclick,
        };
    }

    pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        gui.alloc.destroy(self);
    }

    pub fn fevent(vt: *iArea, ev: g.FocusedEvent) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        switch (ev.event) {
            .focusChanged => vt.dirty(ev.gui),
            .text_input => {},
            .keydown => |kev| {
                for (kev.keys) |k| {
                    switch (@as(graph.SDL.keycodes.Scancode, @enumFromInt(k.key_id))) {
                        else => {},
                        .SPACE => self.toggle(ev.gui, ev.window),
                    }
                }
            },
        }
    }

    fn toggle(self: *@This(), gui: *Gui, _: *iWindow) void {
        self.bool_ptr.* = !self.bool_ptr.*;
        self.vt.dirty(gui);
        if (self.opts.cb_fn) |cbfn| {
            cbfn(self.opts.cb_vt orelse return, gui, self.bool_ptr.*, self.opts.user_id);
        }
    }

    pub fn draw(vt: *iArea, d: DrawState) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));

        const GRAY = 0xddddddff;
        d.ctx.rect(vt.area, GRAY);
        const ins = @ceil(d.scale);
        const inset = vt.area.inset(ins);
        const ta = inset.inset(@ceil(d.style.config.textbox_inset * d.scale));
        const FILL_COLOR = 0xADD8E6ff;
        if (self.bool_ptr.*)
            d.ctx.rect(inset, FILL_COLOR);
        d.ctx.textClipped(ta, "{s}", .{self.name}, d.textP(null), .center);
        d.ctx.rectLine(inset, ins, 0xff);
    }

    pub fn drawCheck(vt: *iArea, d: DrawState) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        const is_focused = d.gui.isFocused(vt);

        const bw = 1;
        const area = vt.area;
        const h = area.h;
        const pad = (area.h - h) / 2;
        const br = Rect.newV(.{ .x = area.x + bw, .y = area.y + pad }, .{ .x = h, .y = h }).inset(h / 4);
        d.ctx.rect(vt.area, d.nstyle.color.bg);

        const ins = @ceil(d.scale);
        d.ctx.rectLine(br, ins, if (is_focused) d.style.config.colors.selected else 0xff);
        const inset = br.inset(ins);
        d.ctx.rect(inset, 0xffff_ffff);
        if (self.bool_ptr.*) {
            const inn = inset.inset(ins * 2);
            d.ctx.line(inn.topL(), inn.botR(), self.opts.cross_color, ins * 2);
            d.ctx.line(inn.topR(), inn.botL(), self.opts.cross_color, ins * 2);
        }
        //d.ctx.rectTex(
        //    br,
        //    cr,
        //    d.style.texture,
        //);
        const tarea = Rec(br.farX() + pad, area.y + pad, area.w - br.farX(), area.h);
        d.ctx.textClipped(tarea, "{s}{s}", .{ self.name, if (is_focused) " [space to toggle]" else "" }, d.textP(null), .left);

        //std.debug.print("{s} says: {any}\n", .{ self.name, self.bool_ptr.* });
    }

    pub fn drawDropdown(vt: *iArea, d: DrawState) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));

        const bw = 1;
        const area = vt.area;
        const h = area.h;
        const pad = (area.h - h) / 2;
        const br = Rect.newV(.{ .x = area.x + bw, .y = area.y + pad }, .{ .x = h, .y = h }).inset(h / 4);
        d.ctx.rect(vt.area, d.nstyle.color.bg);

        const dd = br;
        const center = dd.center();
        const v = if (self.bool_ptr.*) [3]graph.Vec2f{ dd.topL(), center, dd.topR() } else [3]graph.Vec2f{ dd.topL(), dd.botL(), center };
        const cmass = center.sub(v[0].add(v[1].add(v[2])).scale(1.0 / 3.0));
        d.ctx.triangle(v[0].add(cmass), v[1].add(cmass), v[2].add(cmass), self.opts.cross_color);

        const tarea = Rec(br.farX() + pad, area.y + pad, area.w - br.farX(), area.h);
        d.ctx.textClipped(tarea, "{s}", .{self.name}, d.textP(null), .left);

        //std.debug.print("{s} says: {any}\n", .{ self.name, self.bool_ptr.* });
    }

    //If we click, we need to redraw
    pub fn onclick(vt: *iArea, cb: MouseCbState, win: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        self.toggle(cb.gui, win);
    }
};

pub const Button = struct {
    pub const ButtonCallbackT = *const fn (*CbHandle, g.Uid, *Gui, *iWindow) void;
    pub const Opts = struct {
        cb_vt: ?*CbHandle = null,
        cb_fn: ?ButtonCallbackT = null,
        id: g.Uid = 0,
        custom_draw: ?*const fn (*iArea, DrawState) void = null,
        user_1: u32 = 0,
    };
    vt: iArea,

    text: []const u8,
    is_down: bool = false,
    opts: Opts,

    pub fn build(gui: *Gui, area_o: ?Rect, name: []const u8, opts: Opts) ?NewVt {
        const area = area_o orelse return null;
        const self = gui.create(@This());
        self.* = .{
            .vt = .{ .area = area, .deinit_fn = deinit, .draw_fn = opts.custom_draw orelse draw, .focusEvent = fevent },
            .text = gui.alloc.dupe(u8, name) catch return null,
            .opts = opts,
        };
        return .{ .vt = &self.vt, .onclick = onclick };
    }
    pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        gui.alloc.free(self.text);
        gui.alloc.destroy(self);
    }

    pub fn mouseGrabbed(vt: *iArea, cb: MouseCbState, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        const old = self.is_down;
        self.is_down = switch (cb.state) {
            .high, .rising => true,
            .falling, .low => false,
        };
        if (self.is_down != old)
            vt.dirty(cb.gui);
    }

    pub fn draw(vt: *iArea, d: DrawState) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        //d.ctx.rect(vt.area, 0x5ffff0ff);
        const sl = if (self.is_down) d.style.getRect(.button_clicked) else d.style.getRect(.button);
        const is_focused = d.gui.isFocused(vt);
        const color = d.style.config.colors.button_text;

        //const bw = 1;
        const tint = if (!is_focused) d.tint else 0xdddd_ddff;
        d.ctx.nineSlice(vt.area, sl, d.style.texture, d.scale, tint);
        //if (is_focused)
        //d.ctx.rectBorder(vt.area, bw, d.style.config.colors.selected);

        const ta = vt.area.inset(3 * d.scale);
        d.ctx.textClipped(ta, "{s}", .{self.text}, d.textP(color), .center);
    }

    pub fn onclick(vt: *iArea, cb: MouseCbState, win: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        vt.dirty(cb.gui);
        self.is_down = true;
        cb.gui.grabMouse(&@This().mouseGrabbed, vt, win, cb.btn);
        self.sendClickCb(cb.gui, win);
    }

    fn sendClickCb(self: *@This(), gui: *Gui, win: *iWindow) void {
        if (self.opts.cb_fn) |cbfn| {
            cbfn(self.opts.cb_vt orelse return, self.opts.id, gui, win);
        }
    }

    pub fn fevent(vt: *iArea, ev: g.FocusedEvent) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        switch (ev.event) {
            .focusChanged => vt.dirty(ev.gui),
            .text_input => {},
            .keydown => |kev| {
                for (kev.keys) |k| {
                    switch (@as(graph.SDL.keycodes.Scancode, @enumFromInt(k.key_id))) {
                        else => {},
                        .SPACE, .RETURN => self.sendClickCb(ev.gui, ev.window),
                    }
                }
            },
        }
    }

    pub fn customButtonDraw_listitem(vt: *iArea, d: DrawState) void {
        const self: *Button = @alignCast(@fieldParentPtr("vt", vt));
        d.ctx.rect(vt.area, 0xffff_ffff);
        if (self.opts.user_1 == 1) {
            const SELECTED_FIELD_COLOR = 0x6097dbff;
            d.ctx.rect(vt.area, SELECTED_FIELD_COLOR);
        }
        const ta = vt.area.inset(3 * d.scale);
        d.ctx.textClipped(ta, "{s}", .{self.text}, d.textP(0xff), .center);
    }
};

pub const ScrollBar = struct {
    const NotifyFn = *const fn (*iArea, *Gui, *iWindow) void;
    const shuttle_min_w = 50;
    vt: iArea,

    parent_vt: *iArea,
    notify_fn: NotifyFn,

    count: usize,
    index_ptr: *usize,
    shuttle_h: f32 = 0,
    shuttle_pos: f32 = 0,
    item_h: f32,
    usable_h: f32,

    pub fn build(gui: *Gui, area_o: ?Rect, index_ptr: *usize, count: usize, item_h: f32, parent_vt: *iArea, notify_fn: NotifyFn) ?g.NewVt {
        const area = area_o orelse return null;
        const self = gui.create(@This());

        self.* = .{
            .parent_vt = parent_vt,
            .notify_fn = notify_fn,
            .vt = .{ .area = area, .draw_fn = draw, .deinit_fn = deinit },
            .index_ptr = index_ptr,
            .count = count,
            .usable_h = @trunc(area.h / item_h) * item_h,
            .item_h = item_h,
            .shuttle_h = calculateShuttleW(count, item_h, self.usable_h, shuttle_min_w),
            .shuttle_pos = calculateShuttlePos(index_ptr.*, count, self.usable_h, self.shuttle_h),
        };
        return .{ .vt = &self.vt, .onclick = onclick };
    }

    pub fn updateCount(self: *@This(), new_count: usize) void {
        self.count = new_count;
        self.shuttle_h = calculateShuttleW(new_count, self.item_h, self.usable_h, shuttle_min_w);
        self.shuttle_pos = calculateShuttlePos(self.index_ptr.*, new_count, self.usable_h, self.shuttle_h);
    }

    fn calculateShuttleW(count: usize, item_h: f32, area_w: f32, min_w: f32) f32 {
        const area_used = @as(f32, @floatFromInt(count)) * item_h;
        const dist = area_used - area_w;
        if (dist <= 0)
            return area_w; //No scroll

        if (dist < area_w - min_w) { // do dynamic scroll size
            const sw = area_w - dist;
            return sw;
        }
        return min_w;
    }

    pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        gui.alloc.destroy(self);
    }

    fn calculateShuttlePos(index: usize, count: usize, width: f32, shuttle_w: f32) f32 {
        if (count < 2) //Pos is undefined
            return 0;
        const usable_width = width - shuttle_w;
        const indexf: f32 = @floatFromInt(index);
        const countf: f32 = @floatFromInt(count - 1);

        const perc_pos = indexf / countf;
        return usable_width * perc_pos;
    }

    fn shuttleRect(area: Rect, pos: f32, h: f32) Rect {
        return graph.Rec(area.x, pos + area.y, area.w, h);
    }

    pub fn onclick(vt: *iArea, cb: MouseCbState, win: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));

        const actual_pos = calculateShuttlePos(self.index_ptr.*, self.count, self.usable_h, self.shuttle_h);
        const handle = shuttleRect(vt.area.replace(null, null, null, self.usable_h), actual_pos, self.shuttle_h);
        if (handle.containsPoint(cb.pos)) {
            self.shuttle_pos = actual_pos;
            cb.gui.grabMouse(&mouseGrabbed, vt, win, cb.btn);
        }
    }

    pub fn mouseGrabbed(vt: *iArea, cb: MouseCbState, win: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        if (self.count < 2)
            return;
        const usable_width = self.usable_h - self.shuttle_h;
        if (usable_width <= 0)
            return;
        const countf: f32 = @floatFromInt(self.count - 1);
        const screen_space_per_value_space = usable_width / countf;
        self.shuttle_pos += cb.delta.y;

        self.shuttle_pos = std.math.clamp(self.shuttle_pos, 0, usable_width);

        var indexf = self.shuttle_pos / screen_space_per_value_space;

        if (cb.pos.y >= vt.area.y + vt.area.h)
            indexf = countf;
        if (cb.pos.y < vt.area.y)
            indexf = 0;

        if (indexf < 0)
            return;
        self.index_ptr.* = std.math.clamp(@as(usize, @intFromFloat(indexf)), 0, self.count);
        self.notify_fn(self.parent_vt, cb.gui, win);
    }

    pub fn draw(vt: *iArea, d: DrawState) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        const sp = calculateShuttlePos(self.index_ptr.*, self.count, self.usable_h, self.shuttle_h);
        //d.ctx.rect(vt.area, 0x5ffff0ff);
        //d.ctx.nineSlice(vt.area, sl, d.style.texture, d.scale, 0xffffffff);
        const ar = vt.area.replace(null, null, null, self.usable_h);
        d.ctx.nineSlice(ar, d.style.getRect(.slider_box), d.style.texture, d.scale, d.tint);
        const handle = shuttleRect(ar, sp, self.shuttle_h);

        d.ctx.nineSlice(handle, d.style.getRect(.slider_shuttle), d.style.texture, d.scale, d.tint);
    }
};

pub const Text = struct {
    vt: iArea,

    is_alloced: bool,
    text: []const u8,
    bg_col: u32,

    /// The passed in string is not copied or freed.
    pub fn buildStatic(gui: *Gui, area_o: ?Rect, owned_string: []const u8, bg_col: ?u32) ?NewVt {
        const area = area_o orelse return null;
        const self = gui.create(@This());
        self.* = .{
            .vt = .{ .area = area, .deinit_fn = deinit, .draw_fn = draw },
            .is_alloced = false,
            .bg_col = bg_col orelse gui.nstyle.color.bg,
            .text = owned_string,
        };
        return .{ .vt = &self.vt };
    }

    pub fn build(gui: *Gui, area_o: ?Rect, comptime fmt: []const u8, args: anytype) ?NewVt {
        const area = area_o orelse return null;
        const self = gui.create(@This());
        var vec = std.ArrayList(u8).initCapacity(gui.alloc, 30) catch return null;
        vec.writer().print(fmt, args) catch {
            vec.deinit();
            gui.alloc.destroy(self);
            return null;
        };

        self.* = .{
            .vt = .{ .area = area, .deinit_fn = deinit, .draw_fn = draw },
            .bg_col = gui.nstyle.color.bg,
            .is_alloced = true,
            .text = vec.toOwnedSlice() catch return null,
        };
        return .{ .vt = &self.vt };
    }

    pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        if (self.is_alloced)
            gui.alloc.free(self.text);
        gui.alloc.destroy(self);
    }

    pub fn draw(vt: *iArea, d: DrawState) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        //d.ctx.rect(vt.area, 0x5ffff0ff);
        d.ctx.rect(vt.area, self.bg_col);
        const texta = vt.area.inset(d.style.config.default_item_h / 10);
        d.ctx.textClipped(texta, "{s}", .{self.text}, d.textP(null), .left);
    }
};

pub const NumberDisplay = struct {
    vt: iArea,

    num_ptr: *usize,
    last_drawn: usize = 0,
    bg_col: u32,

    pub fn build(gui: *Gui, area_o: ?Rect, number_ptr: *usize) ?NewVt {
        const area = area_o orelse return null;
        const self = gui.create(@This());
        self.* = .{
            .vt = .{ .area = area, .deinit_fn = deinit, .draw_fn = draw },
            .bg_col = gui.nstyle.color.bg,
            .num_ptr = number_ptr,
        };
        return .{ .vt = &self.vt, .onpoll = pollNumber };
    }

    pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        gui.alloc.destroy(self);
    }

    pub fn draw(vt: *iArea, d: DrawState) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        //d.ctx.rect(vt.area, 0x5ffff0ff);
        d.ctx.rect(vt.area, self.bg_col);
        const texta = vt.area.inset(d.style.config.default_item_h / 10);
        d.ctx.textClipped(texta, "{d}", .{self.num_ptr.*}, d.textP(null), .left);
        self.last_drawn = self.num_ptr.*;
    }

    pub fn pollNumber(vt: *iArea, gui: *Gui, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));

        if (self.last_drawn != self.num_ptr.*) {
            vt.dirty(gui);
        }
    }
};
