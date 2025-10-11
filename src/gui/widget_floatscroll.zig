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
pub const BuildCb = *const fn (*CbHandle, current_area: *iArea, *Gui, *iWindow, *FloatScroll) void;
pub const Opts = struct {
    build_cb: BuildCb,
    build_vt: *CbHandle,
    win: *iWindow,
    scroll_mul: f32,

    scroll_x: bool,
    scroll_y: bool,
};

pub const FloatScroll = struct {
    const scroll_index = 0;
    const virtual_area_index = 1;
    const num_widget = 2;
    vt: iArea,

    cb: CbHandle = .{},
    opts: Opts,
    hinted_bounds: ?Rect = null,
    y: f32,
    y_ptr: *f32,

    scroll_ptr: ?*FloatScrollBar = null,

    pub fn build(gui: *Gui, area_o: ?Rect, opts: Opts) ?*iArea {
        const area = area_o orelse return null;
        const self = gui.create(@This());

        self.* = .{
            .vt = iArea.init(gui, area),
            .opts = opts,
            .y = 0,
            .y_ptr = &self.y,
        };
        self.vt.draw_fn = &draw;
        self.vt.deinit_fn = &deinit;
        self.vt.onscroll = onScroll;

        const split = self.vt.area.split(.vertical, getAreaW(self.vt.area.w, gui.scale));
        self.vt.area = split[0];

        if (FloatScrollBar.build(
            gui,
            split[1],
            self.y_ptr,
            area.h * 2, //Remeber to update this
            &self.cb,
            &notifyChange,
        )) |sbar| {
            self.vt.addChildOpt(gui, opts.win, &sbar.vt);
            self.scroll_ptr = sbar;
            std.debug.print("ADDED SCROLL\n", .{});
        } else {
            _ = self.vt.addEmpty(gui, opts.win, split[1]);
        }

        const virt = self.vt.addEmpty(gui, opts.win, Rect{
            .x = self.vt.area.x,
            .y = self.vt.area.y,
            .w = if (opts.scroll_x) std.math.floatMax(f32) else self.vt.area.w,
            .h = if (opts.scroll_y) std.math.floatMax(f32) else self.vt.area.h,
        });

        opts.win.registerScissor(virt, split[0]) catch {};

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

    pub fn getAreaW(parent_w: f32, scale: f32) f32 {
        const SW = 15 * scale;
        return parent_w - SW;
    }

    pub fn notifyChange(cb: *CbHandle, gui: *Gui, win: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("cb", cb));
        if (self.vt.children.items.len != num_widget) return;
        const child = self.vt.children.items[virtual_area_index];
        // area_y - y_ptr = child_y
        child.area.y = self.vt.area.y - self.y_ptr.*;
        self.rebuild(gui, win);
    }

    pub fn rebuild(self: *@This(), gui: *Gui, win: *iWindow) void {
        if (self.vt.children.items.len != num_widget) return;

        self.vt.dirty(gui);

        const child = self.vt.children.items[virtual_area_index];
        child.clearChildren(gui, win);

        self.opts.build_cb(self.opts.build_vt, child, gui, win, self);
    }

    pub fn hintBounds(self: *@This(), area_scroll_space: Rect) void {
        self.hinted_bounds = area_scroll_space;
        if (self.scroll_ptr) |ptr| {
            ptr.updateVirtH(area_scroll_space.h);
        }
    }

    pub fn onScroll(vt: *iArea, gui: *Gui, win: *iWindow, dist: f32) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));

        if (self.vt.children.items.len != num_widget) return;

        const child = self.vt.children.items[virtual_area_index];
        child.area.y += dist * self.opts.scroll_mul;

        if (self.hinted_bounds) |hbb| {
            var hb = hbb;
            hb.y = child.area.y; //Update hinted
            hb.x = child.area.x;
            if (self.opts.scroll_y) {
                if (hb.h <= vt.area.h) { //If the scroll area is less than the scissor region, don't scroll at all
                    child.area.y = vt.area.y;
                } else {
                    const top_dist = self.vt.area.y - hb.y;
                    const bot_dist = (self.vt.area.y + self.vt.area.h) - (hb.y + hb.h);
                    if (top_dist < 0) {
                        child.area.y = self.vt.area.y;
                    } else if (bot_dist > 0) {
                        child.area.y = self.vt.area.y - (hb.h - self.vt.area.h);
                    }
                }
            }
            if (self.opts.scroll_x) {
                if (hb.w <= vt.area.w) { //If the scroll area is less than the scissor region, don't scroll at all
                    child.area.x = vt.area.x;
                } else {
                    const top_dist = self.vt.area.x - hb.x;
                    const bot_dist = (self.vt.area.x + self.vt.area.w) - (hb.x + hb.w);
                    if (top_dist < 0) {
                        child.area.x = self.vt.area.x;
                    } else if (bot_dist > 0) {
                        child.area.x = self.vt.area.x - (hb.w - self.vt.area.w);
                    }
                }
            }
        }
        // area_y - y_ptr = child_y
        self.y_ptr.* = self.vt.area.y - child.area.y;

        self.rebuild(gui, win);
    }
};
// Render scroll contenst to diff Window, then draw that to place

// let vH = virt_area.h
// let sh = scrollbar_travel;
// let wh = screen_area_h;
// let min_sb = min_shuttle_w;
//
// let dist = vH - wh
// if(dist < 0) return noScroll
//
// if(dist < scrollbar_travel - min_sb)
//      // Do dynamic scrollbar size
//      shuttle_w = scrollbar_travel - dist
//
//      travel = scrollbar_travel - shuttle_w
//      mult = vH / travel
// else
//      // use minimum scrollbar size
//      travel = scrollbar_travel - min_shuttle_w
//      mult = vH / travel
//
// mult =
//
pub const FloatScrollBar = struct {
    const NotifyFn = *const fn (*CbHandle, *Gui, *iWindow) void;
    const shuttle_min_w = 50;
    vt: iArea,

    parent_vt: *CbHandle,
    notify_fn: NotifyFn,

    area_h: f32,
    y_ptr: *f32,

    shuttle_h: f32 = 0,
    shuttle_pos: f32 = 0,

    pub fn build(gui: *Gui, area_o: ?Rect, y_ptr: *f32, area_h: f32, parent_vt: *CbHandle, notify_fn: NotifyFn) ?*FloatScrollBar {
        const area = area_o orelse return null;
        const self = gui.create(@This());

        self.* = .{
            .parent_vt = parent_vt,
            .notify_fn = notify_fn,
            .vt = iArea.init(gui, area),
            .y_ptr = y_ptr,

            .area_h = area_h,
        };
        self.vt.draw_fn = &draw;
        self.vt.deinit_fn = &deinit;
        self.vt.onclick = &onclick;
        return self;
    }

    pub fn updateVirtH(self: *@This(), new_h: f32) void {
        self.area_h = new_h;
        self.shuttle_h = calculateShuttleW(new_h, self.vt.area.h, self.vt.area.h, shuttle_min_w);
        self.shuttle_pos = calculateShuttlePos(new_h, self.y_ptr.*, self.vt.area.h, self.shuttle_h);
    }

    pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        gui.alloc.destroy(self);
    }

    pub fn onclick(vt: *iArea, cb: g.MouseCbState, win: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));

        const actual_pos = calculateShuttlePos(self.area_h, self.y_ptr.*, self.vt.area.h, self.shuttle_h);
        const handle = shuttleRect(vt.area.replace(null, null, null, self.vt.area.h), actual_pos, self.shuttle_h);
        if (handle.containsPoint(cb.pos)) {
            self.shuttle_pos = actual_pos;
            cb.gui.grabMouse(&mouseGrabbed, vt, win, cb.btn);
        }
    }

    pub fn mouseGrabbed(vt: *iArea, cb: g.MouseCbState, win: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        const travel = self.vt.area.h - self.shuttle_h;
        const vtravel = self.area_h - self.vt.area.h;
        if (travel <= 0 or vtravel <= 0) return;

        const value_per_screen = vtravel / travel;
        self.shuttle_pos += cb.delta.y;

        self.shuttle_pos = std.math.clamp(self.shuttle_pos, 0, travel);

        self.y_ptr.* = self.shuttle_pos * value_per_screen;

        //if (cb.pos.y >= vt.area.y + vt.area.h)
        //    indexf = ;
        //if (cb.pos.y < vt.area.y)
        //    indexf = 0;

        //if (indexf < 0)
        //    return;
        self.notify_fn(self.parent_vt, cb.gui, win);
    }

    pub fn draw(vt: *iArea, d: g.DrawState) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        const sp = calculateShuttlePos(self.area_h, self.y_ptr.*, self.vt.area.h, self.shuttle_h);
        d.ctx.rect(vt.area, 0x5ffff0ff);
        //d.ctx.nineSlice(vt.area, sl, d.style.texture, d.scale, 0xffffffff);
        const ar = vt.area.replace(null, null, null, self.vt.area.h);
        d.ctx.nineSlice(ar, d.style.getRect(.slider_box), d.style.texture, d.scale, d.tint);
        const handle = shuttleRect(ar, sp, self.shuttle_h);

        d.ctx.nineSlice(handle, d.style.getRect(.slider_shuttle), d.style.texture, d.scale, d.tint);
    }
};

fn calculateShuttleW(virt_h: f32, scroll_h: f32, screen_h: f32, min_shuttle_h: f32) f32 {
    const dist = virt_h - screen_h;
    if (dist <= 0) return scroll_h; //No scroll

    if (dist < scroll_h - min_shuttle_h) { //Dynamic size
        const dyn_shuttle_h = scroll_h - dist;
        return dyn_shuttle_h;
    }
    return min_shuttle_h;
}

fn calculateShuttlePos(virt_h: f32, virt_y: f32, scroll_h: f32, shuttle_h: f32) f32 {
    const travel = scroll_h - shuttle_h;
    const vh = virt_h - scroll_h;
    if (travel <= 0 or vh <= 0) return 0;
    const mult = vh / travel;

    return virt_y / mult;
}

fn shuttleRect(area: Rect, pos: f32, h: f32) Rect {
    return graph.Rec(area.x, pos + area.y, area.w, h);
}
