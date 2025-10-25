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

pub const DynamicTable = struct {
    pub const Opts = struct {
        /// Mutable slice of floats. Each float is between 0-1 and represents the position of the column divider
        /// as a absolute percentage of the table width.
        column_positions: []f32,
        column_names: []const []const u8,
        build_cb: *const fn (*g.CbHandle, area_vt: *iArea, *Gui, *iWindow) void,
        build_vt: *g.CbHandle,
    };
    vt: iArea,

    opts: Opts,

    pub fn build(parent: *iArea, area_o: ?Rect, win: *iWindow, opts: Opts) g.WgStatus {
        const gui = parent.win_ptr.gui_ptr;
        const area = area_o orelse return .failed;
        var ly = gui.dstate.vlayout(area);
        const tab_area = ly.getArea() orelse return .failed;

        ly.pushRemaining();
        const table_area = ly.getArea() orelse return .failed;

        const self = gui.create(@This());

        self.* = .{
            .vt = .UNINITILIZED,
            .opts = opts,
        };
        parent.addChild(&self.vt, .{ .area = area, .deinit_fn = deinit, .draw_fn = draw });

        _ = TableHeader.build(&self.vt, tab_area, self);

        _ = self.vt.addEmpty(table_area);
        self.rebuild(gui, win);

        return .good;
    }

    pub fn rebuild(self: *@This(), gui: *Gui, win: *iWindow) void {
        if (self.vt.children.items.len != 2)
            return;
        self.vt.dirty();
        const child = self.vt.children.items[1];
        child.clearChildren(gui, win);

        self.opts.build_cb(self.opts.build_vt, child, gui, win);
    }

    pub fn calcLayout(column_percs: []const f32, widths: []f32, area: Rect, gui: *Gui) ?g.TableLayoutCustom {
        if (column_percs.len + 1 != widths.len) return null;

        var last_pos: f32 = 0;
        for (column_percs, 0..) |pos, i| {
            const new_pos = pos * area.w;

            const width = new_pos - last_pos;
            widths[i] = width;

            last_pos = new_pos;
        }
        widths[widths.len - 1] = area.w - last_pos;

        return g.TableLayoutCustom{ .bounds = area, .column_widths = widths, .item_height = gui.dstate.style.config.default_item_h };
    }

    pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        gui.alloc.destroy(self);
    }

    pub fn draw(vt: *iArea, _: *g.Gui, d: *g.DrawState) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        d.ctx.rect(vt.area, d.nstyle.color.table_bg);
        const y = vt.area.y;
        const y1 = vt.area.y + vt.area.h;
        for (self.opts.column_positions) |pos| {
            const x = pos * vt.area.w + vt.area.x;
            d.ctx.line(.{ .x = x, .y = y }, .{ .x = x, .y = y1 }, 0xff, d.scale);
        }
    }
};

const TableHeader = struct {
    vt: iArea,

    parent: *DynamicTable,
    grab_index: ?usize = null,

    pub fn build(par: *iArea, area: Rect, parent: *DynamicTable) g.WgStatus {
        const gui = par.win_ptr.gui_ptr;
        const self = gui.create(@This());
        self.* = .{
            .vt = .UNINITILIZED,
            .parent = parent,
        };
        par.addChild(&self.vt, .{ .area = area, .deinit_fn = deinit, .draw_fn = draw, .onclick = onclick });
        return .good;
    }

    pub fn onclick(vt: *iArea, cb: g.MouseCbState, win: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));

        const click_pad = 2 * cb.gui.dstate.scale;
        for (self.parent.opts.column_positions, 0..) |pos, i| {
            const x = vt.area.x + vt.area.w * pos - click_pad;
            const click_area = graph.Rec(x, vt.area.y, click_pad * 2, vt.area.h);
            if (click_area.containsPoint(cb.pos)) {
                self.grab_index = i;
                cb.gui.grabMouse(&grabbed, vt, win, cb.btn);
            }
        }
    }

    pub fn grabbed(vt: *iArea, cb: g.MouseCbState, win: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        const pad = (4 * cb.gui.dstate.scale) / vt.area.w;
        const ind = self.grab_index orelse return;
        const cpos = self.parent.opts.column_positions;
        if (ind >= cpos.len) return;
        const delta_perc = cb.delta.x / vt.area.w;

        const manip = cpos[ind];
        const min_perc = (if (ind > 0) cpos[ind - 1] else 0) + pad;
        const max_perc = (if (ind + 1 < cpos.len) cpos[ind + 1] else vt.area.w) - pad;

        if (min_perc > max_perc) return;
        const new = std.math.clamp(manip + delta_perc, min_perc, max_perc);
        cpos[ind] = new;
        self.parent.rebuild(cb.gui, win);
        vt.dirty(); //TODO fix the dirty setting stuff
    }

    pub fn draw(vt: *iArea, _: *g.Gui, d: *g.DrawState) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        d.ctx.rect(vt.area, d.nstyle.color.bg);
        const dat = self.parent.opts;
        if (dat.column_positions.len == 0 or dat.column_positions.len + 1 != dat.column_names.len)
            return;
        //const active = d.style.getRect(.tab_active);
        //const inactive = d.style.getRect(.tab_inactive);

        const a = vt.area;
        var last_pos: f32 = 0;
        for (dat.column_names, 0..) |name, i| {
            const pos = if (i >= dat.column_positions.len) a.w else dat.column_positions[i] * a.w;
            const width = pos - last_pos;
            const rect = graph.Rec(a.x + last_pos, a.y, width, a.h);

            d.ctx.textClipped(rect, "{s}", .{name}, d.textP(null), .center);
            last_pos = pos;
        }
        for (dat.column_positions) |pos| {
            const x = pos * a.w + a.x;
            d.ctx.line(.{ .x = x, .y = a.y }, .{ .x = x, .y = a.y + a.h }, 0xff, d.scale);
        }
    }

    pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        gui.alloc.destroy(self);
    }
};
