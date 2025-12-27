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
pub const ComboOpts = struct {};

pub const Combo = struct {
    pub fn build(parent: *iArea, area_o: ?Rect, enum_ptr: anytype, opts: ComboOpts) g.WgStatus {
        const info = @typeInfo(@TypeOf(enum_ptr));
        if (info != .pointer) @compileError("expected a pointer to enum");
        if (info.pointer.is_const or info.pointer.size != .one) @compileError("invalid pointer");
        const child_info = @typeInfo(info.pointer.child);
        if (child_info != .@"enum") @compileError("Expected an enum");

        const Gen = ComboGeneric(info.pointer.child);
        const area = area_o orelse return .failed;
        return Gen.build(parent, area, enum_ptr, opts);
    }
};

fn searchMatch(string: []const u8, query: []const u8) bool {
    return std.ascii.indexOfIgnoreCase(string, query) != null;
}

//TODO is this used
pub fn ComboUser(user_data: type) type {
    return struct {
        pub const ComboVt = struct {
            //build_cb: *const fn (user_vt: *iArea, widget_vt: *iArea, index: usize, *Gui, *iWindow) void,
            name_cb: *const fn (*CbHandle, index: usize, *Gui, ud: user_data) []const u8,
            commit_cb: *const fn (*CbHandle, index: usize, ud: user_data) void,
            count: usize,
            current: usize,

            user_id: usize = 0,

            user_vt: *CbHandle,
        };
        const ParentT = @This();
        pub const PoppedWindow = struct {
            vt: iWindow,
            cbhandle: CbHandle = .{},

            parent_vt: *iArea,
            name: []const u8,

            search_string: []const u8 = "", //This string is allocated by the textbox
            vscroll_vt: ?*VScroll = null,

            search_list: std.ArrayList(usize),

            pub fn buildWindow(vt: *iWindow, gui: *Gui, area: Rect) void {
                const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
                vt.area.area = area;
                vt.area.clearChildren(gui, vt);
                self.vscroll_vt = null;
                vt.area.dirty();
                const p: *ParentT = @alignCast(@fieldParentPtr("vt", self.parent_vt));
                var ly = gui.dstate.vlayout(area.inset(gui.dstate.scale));
                _ = Widget.Textbox.buildOpts(&vt.area, ly.getArea(), .{
                    .commit_cb = &textbox_cb,
                    .commit_vt = &self.cbhandle,
                    .commit_when = .on_change,
                });
                if (vt.area.children.items.len > 0) {
                    gui.grabFocus(vt.area.children.items[0], vt);
                }
                ly.pushRemaining();
                if (VScroll.build(&vt.area, ly.getArea(), .{
                    .build_cb = &build_scroll_cb,
                    .build_vt = &self.cbhandle,
                    .win = vt,
                    .item_h = gui.dstate.style.config.default_item_h,
                    .count = p.opts.count,
                    .index_ptr = &p.index,
                }) != .good) return;
                self.vscroll_vt = @alignCast(@fieldParentPtr("vt", vt.area.getLastChild() orelse return));
            }

            pub fn textbox_cb(pop_vt: *CbHandle, gui: *Gui, str: []const u8, _: usize) void {
                const self: *@This() = @alignCast(@fieldParentPtr("cbhandle", pop_vt));
                self.search_string = str;
                if (self.vscroll_vt) |v| {
                    //This will call build_scroll_cb
                    v.index_ptr.* = 0;
                    v.rebuild(gui, &self.vt);
                }
            }

            pub fn build_scroll_cb(cb: *CbHandle, area: *iArea, index: usize) void {
                const gui = area.win_ptr.gui_ptr;

                const self: *@This() = @alignCast(@fieldParentPtr("cbhandle", cb));
                var ly = gui.dstate.vlayout(area.area);
                const p: *ParentT = @alignCast(@fieldParentPtr("vt", self.parent_vt));
                const total_count = p.opts.count;

                const do_search = self.search_string.len > 0;
                if (do_search) {
                    self.search_list.clearRetainingCapacity();
                    for (0..total_count) |i| {
                        const name = p.opts.name_cb(p.opts.user_vt, i, gui, p.user);
                        if (searchMatch(name, self.search_string))
                            self.search_list.append(gui.alloc, i) catch return;
                    }
                }

                const count = if (do_search) self.search_list.items.len else total_count;

                if (self.vscroll_vt) |vscr|
                    vscr.updateCount(count);
                if (index >= count) return;

                for (index..count) |pre_i| {
                    if (do_search and pre_i >= self.search_list.items.len) continue; //Sanity
                    const i = if (do_search) self.search_list.items[pre_i] else pre_i;
                    const name = p.opts.name_cb(p.opts.user_vt, i, gui, p.user);
                    //if (do_search and !std.mem.containsAtLeast(u8, name, 1, self.search_string)) continue;
                    _ = Widget.Button.build(
                        area,
                        ly.getArea(),
                        name,
                        .{ .cb_vt = &p.cbhandle, .cb_fn = &ParentT.buttonCb, .id = i, .tab_focus = true },
                    );
                }
            }

            pub fn deinit(vt: *iWindow, gui: *Gui) void {
                const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
                vt.deinit(gui);
                self.search_list.deinit(gui.alloc);
                gui.alloc.destroy(self);
            }

            pub fn draw(vt: *iArea, _: *g.Gui, d: *g.DrawState) void {
                const self: *@This() = @alignCast(@fieldParentPtr("area", vt));
                _ = self;
                d.ctx.rectLine(vt.area, @ceil(d.scale), 0xff);
            }

            pub fn deinit_area(vt: *iArea, _: *Gui, _: *iWindow) void {
                _ = vt;
            }
        };

        vt: iArea,

        cbhandle: CbHandle = .{},
        opts: ComboVt,
        index: usize = 0,
        current: usize = 0,
        user: user_data,

        pub fn build(parent: *iArea, area: Rect, opts: ComboVt, user: user_data) g.WgStatus {
            const gui = parent.win_ptr.gui_ptr;
            const self = gui.create(@This());
            self.* = .{
                .vt = .UNINITILIZED,
                .opts = opts,
                .user = user,
            };
            parent.addChild(&self.vt, .{ .area = area, .deinit_fn = deinit, .draw_fn = draw, .onclick = onclick });
            return .good;
        }

        pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
            const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
            gui.alloc.destroy(self);
        }

        pub fn draw(vt: *iArea, gui: *g.Gui, d: *g.DrawState) void {
            const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
            d.ctx.rect(vt.area, 0x2ffff0ff);

            d.ctx.rect(vt.area, d.nstyle.color.combo_bg);
            const texta = d.textArea(vt.area);
            d.ctx.textClipped(texta, "{s}", .{self.opts.name_cb(self.opts.user_vt, self.opts.current, gui, self.user)}, d.textP(null), .center);
            //self.gui.drawTextFmt(fmt, args, texta, self.style.config.text_h, 0xff, .{ .justify = .center }, self.font);
            const cbb = d.style.getRect(.combo_button);
            const da = d.style.getRect(.down_arrow);
            const cbbr = vt.area.replace(vt.area.x + vt.area.w - cbb.w * d.scale, null, cbb.w * d.scale, null).centerR(da.w * d.scale, da.h * d.scale);
            d.ctx.rectTex(cbbr, da, d.style.texture);
        }

        pub fn onclick(vt: *iArea, cb: g.MouseCbState, win: *iWindow) void {
            const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
            _ = win;
            self.makeTransientWindow(cb.gui, Rec(vt.area.x, vt.area.y, vt.area.w, cb.gui.dstate.style.config.default_item_h * 10));
        }

        pub fn buttonCb(cb: *CbHandle, id: usize, dat: g.MouseCbState, _: *iWindow) void {
            const self: *@This() = @alignCast(@fieldParentPtr("cbhandle", cb));
            self.vt.dirty();
            self.opts.current = id;
            self.opts.commit_cb(self.opts.user_vt, id, self.user);
            dat.gui.deferTransientClose();
        }

        pub fn makeTransientWindow(self: *@This(), gui: *Gui, area: Rect) void {
            const popped = gui.create(PoppedWindow);
            popped.* = .{
                .parent_vt = &self.vt,
                .vt = iWindow.init(
                    &PoppedWindow.buildWindow,
                    gui,
                    &PoppedWindow.deinit,
                    .{ .area = area },
                    &popped.vt,
                ),
                .search_list = .{},
                .name = "noname",
            };
            gui.setTransientWindow(&popped.vt);
            popped.vt.build_fn(&popped.vt, gui, area);
        }
    };
}

pub fn ComboGeneric(comptime enumT: type) type {
    return struct {
        const ParentT = @This();
        pub const PoppedWindow = struct {
            vt: iWindow,
            cbhandle: CbHandle = .{},

            parent_vt: *iArea,
            name: []const u8,

            pub fn build(
                vt: *iWindow,
                gui: *Gui,
                area: Rect,
            ) void {
                const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
                vt.area.area = area;
                vt.area.clearChildren(gui, vt);
                const info = @typeInfo(enumT);
                vt.area.dirty();
                _ = VScroll.build(&vt.area, area, .{
                    .build_cb = &build_cb,
                    .build_vt = &self.cbhandle,
                    .win = vt,
                    .count = info.@"enum".fields.len,
                    .item_h = gui.dstate.style.config.default_item_h,
                });
            }

            pub fn build_cb(cb: *CbHandle, area: *iArea, index: usize) void {
                const gui = area.win_ptr.gui_ptr;
                const self: *@This() = @alignCast(@fieldParentPtr("cbhandle", cb));
                const p: *ParentT = @alignCast(@fieldParentPtr("vt", self.parent_vt));
                var ly = gui.dstate.vlayout(area.area);
                const info = @typeInfo(enumT);
                inline for (info.@"enum".fields, 0..) |field, i| {
                    if (i >= index) {
                        _ = Widget.Button.build(
                            area,
                            ly.getArea(),
                            field.name,
                            .{ .cb_vt = &p.cbhandle, .cb_fn = &ParentT.buttonCb, .id = field.value },
                        );
                    }
                }
            }

            pub fn deinit(vt: *iWindow, gui: *Gui) void {
                const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
                vt.deinit(gui);
                gui.alloc.destroy(self);
            }

            pub fn draw(vt: *iArea, _: *g.Gui, d: *g.DrawState) void {
                const self: *@This() = @alignCast(@fieldParentPtr("area", vt));
                _ = d;
                _ = self;
            }

            pub fn deinit_area(vt: *iArea, _: *Gui, _: *iWindow) void {
                _ = vt;
            }
        };

        vt: iArea,
        cbhandle: CbHandle = .{},

        enum_ptr: *enumT,
        opts: ComboOpts,

        pub fn build(parent: *iArea, area: Rect, enum_ptr: *enumT, opts: ComboOpts) g.WgStatus {
            const gui = parent.win_ptr.gui_ptr;
            const self = gui.create(@This());
            self.* = .{
                .vt = .UNINITILIZED,
                .enum_ptr = enum_ptr,
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
            //d.ctx.rect(vt.area, 0x2ffff0ff);

            const btn_a = vt.area;
            d.ctx.rect(btn_a, d.nstyle.color.combo_bg);
            const texta = d.textArea(vt.area);
            d.ctx.textClipped(texta, "{s}", .{@tagName(self.enum_ptr.*)}, d.textP(null), .center);
            //self.gui.drawTextFmt(fmt, args, texta, self.style.config.text_h, 0xff, .{ .justify = .center }, self.font);
            //const cbb = d.style.getRect(.combo_button);
            //const da = d.style.getRect(.down_arrow);
            //const cbbr = btn_a.replace(btn_a.x + btn_a.w - cbb.w * d.scale, null, cbb.w * d.scale, null).centerR(da.w * d.scale, da.h * d.scale);
            //d.ctx.rectTex(cbbr, da, d.style.texture);

            const thick = @ceil(d.scale);
            const aw = d.style.config.text_h;
            const br = btn_a.replace(btn_a.x + btn_a.w - aw, null, aw, null).centerR(aw, aw);
            const cent = br.center();

            const v = [3]graph.Vec2f{ br.topL(), cent, br.topR() };
            const cmass = cent.sub(v[0].add(v[1].add(v[2])).scale(1.0 / 3.0));
            d.ctx.triangle(v[0].add(cmass), v[1].add(cmass), v[2].add(cmass), d.nstyle.color.combo_arrow);

            const inset = vt.area.inset(thick);
            d.ctx.rectLine(inset, thick, d.nstyle.color.combo_border);
        }

        pub fn onclick(vt: *iArea, cb: g.MouseCbState, win: *iWindow) void {
            const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
            const btn_a = vt.area;
            _ = win;
            self.makeTransientWindow(cb.gui, Rec(btn_a.x, btn_a.y, btn_a.w, cb.gui.dstate.style.config.default_item_h * 4));
        }

        pub fn buttonCb(cb: *CbHandle, id: usize, dat: g.MouseCbState, _: *iWindow) void {
            const self: *@This() = @alignCast(@fieldParentPtr("cbhandle", cb));
            self.vt.dirty();
            self.enum_ptr.* = @enumFromInt(id);
            dat.gui.deferTransientClose();
        }

        pub fn makeTransientWindow(self: *@This(), gui: *Gui, area: Rect) void {
            const popped = gui.create(PoppedWindow);
            popped.* = .{
                .parent_vt = &self.vt,
                .vt = iWindow.init(
                    &PoppedWindow.build,
                    gui,
                    &PoppedWindow.deinit,
                    .{ .area = area },
                    &popped.vt,
                ),
                .name = "noname",
            };
            gui.setTransientWindow(&popped.vt);
            popped.vt.build_fn(&popped.vt, gui, area);
        }
    };
}
