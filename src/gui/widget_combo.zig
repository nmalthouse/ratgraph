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

pub const ComboOpts = struct {};

pub const Combo = struct {
    pub fn build(gui: *Gui, area_o: ?Rect, enum_ptr: anytype, opts: ComboOpts) ?*iArea {
        const info = @typeInfo(@TypeOf(enum_ptr));
        if (info != .pointer) @compileError("expected a pointer to enum");
        if (info.pointer.is_const or info.pointer.size != .one) @compileError("invalid pointer");
        const child_info = @typeInfo(info.pointer.child);
        if (child_info != .@"enum") @compileError("Expected an enum");

        const Gen = ComboGeneric(info.pointer.child);
        const area = area_o orelse return null;
        return Gen.build(gui, area, enum_ptr, opts);
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
            name_cb: *const fn (user_vt: *iArea, index: usize, *Gui, ud: user_data) []const u8,
            commit_cb: *const fn (user_vt: *iArea, index: usize, ud: user_data) void,
            count: usize,
            current: usize,

            user_id: usize = 0,

            user_vt: *iArea,
        };
        const ParentT = @This();
        pub const PoppedWindow = struct {
            vt: iWindow,
            area: iArea,

            parent_vt: *iArea,
            name: []const u8,

            search_string: []const u8 = "", //This string is allocated by the textbox
            vscroll_vt: ?*VScroll = null,

            pub fn buildWindow(vt: *iWindow, gui: *Gui, area: Rect) void {
                const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
                self.area.area = area;
                self.area.clearChildren(gui, vt);
                self.vscroll_vt = null;
                vt.area.dirty(gui);
                const p: *ParentT = @alignCast(@fieldParentPtr("vt", self.parent_vt));
                var ly = g.VerticalLayout{ .item_height = gui.style.config.default_item_h, .bounds = area };
                self.area.addChildOpt(
                    gui,
                    vt,
                    Widget.Textbox.buildOpts(gui, ly.getArea(), .{
                        .commit_cb = &textbox_cb,
                        .commit_vt = vt.area,
                        .commit_when = .on_change,
                    }),
                );
                ly.pushRemaining();
                const vscroll = VScroll.build(gui, ly.getArea(), .{
                    .build_cb = &build_scroll_cb,
                    .build_vt = &self.area,
                    .win = vt,
                    .item_h = gui.style.config.default_item_h,
                    .count = p.opts.count,
                    .index_ptr = &p.index,
                }) orelse return;
                self.area.addChild(gui, vt, vscroll);
                self.vscroll_vt = @alignCast(@fieldParentPtr("vt", vscroll));
            }

            pub fn textbox_cb(pop_vt: *iArea, gui: *Gui, str: []const u8, _: usize) void {
                const self: *@This() = @alignCast(@fieldParentPtr("area", pop_vt));
                self.search_string = str;
                if (self.vscroll_vt) |v| {
                    //This will call build_scroll_cb
                    v.index_ptr.* = 0;
                    v.rebuild(gui, gui.getWindow(pop_vt) orelse return);
                }
            }

            pub fn build_scroll_cb(vt: *iArea, area: *iArea, index: usize, gui: *Gui, win: *iWindow) void {
                const self: *@This() = @alignCast(@fieldParentPtr("area", vt));
                var ly = g.VerticalLayout{ .item_height = gui.style.config.default_item_h, .bounds = area.area };
                const p: *ParentT = @alignCast(@fieldParentPtr("vt", self.parent_vt));
                const count = p.opts.count;
                if (index >= count) return;
                const do_search = self.search_string.len > 0;
                for (index..count) |i| {
                    const name = p.opts.name_cb(p.opts.user_vt, i, gui, p.user);
                    //if (do_search and !std.mem.containsAtLeast(u8, name, 1, self.search_string)) continue;
                    if (do_search and !searchMatch(name, self.search_string)) continue;
                    area.addChild(gui, win, Widget.Button.build(
                        gui,
                        ly.getArea(),
                        name,
                        .{ .cb_vt = self.parent_vt, .cb_fn = &ParentT.buttonCb, .id = i },
                    ) orelse return);
                }
            }

            pub fn deinit(vt: *iWindow, gui: *Gui) void {
                const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
                vt.deinit(gui);
                gui.alloc.destroy(self);
            }

            pub fn draw(vt: *iArea, d: g.DrawState) void {
                const self: *@This() = @alignCast(@fieldParentPtr("area", vt));
                _ = d;
                _ = self;
            }

            pub fn deinit_area(vt: *iArea, _: *Gui, _: *iWindow) void {
                _ = vt;
            }
        };

        vt: iArea,

        opts: ComboVt,
        index: usize = 0,
        current: usize = 0,
        user: user_data,

        pub fn build(gui: *Gui, area: Rect, opts: ComboVt, user: user_data) *iArea {
            const self = gui.create(@This());
            self.* = .{
                .vt = iArea.init(gui, area),
                .opts = opts,
                .user = user,
            };
            self.vt.onclick = &onclick;
            self.vt.draw_fn = &draw;
            self.vt.deinit_fn = &deinit;
            return &self.vt;
        }

        pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
            const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
            gui.alloc.destroy(self);
        }

        pub fn draw(vt: *iArea, d: g.DrawState) void {
            const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
            d.ctx.rect(vt.area, 0x2ffff0ff);

            const cb = d.style.getRect(.combo_background);
            d.ctx.nineSlice(vt.area, cb, d.style.texture, d.scale, d.tint);
            const texta = vt.area.inset(cb.w / 3 * d.scale);
            d.ctx.textClipped(texta, "{s}", .{self.opts.name_cb(self.opts.user_vt, self.opts.current, d.gui, self.user)}, d.textP(null), .center);
            //self.gui.drawTextFmt(fmt, args, texta, self.style.config.text_h, 0xff, .{ .justify = .center }, self.font);
            const cbb = d.style.getRect(.combo_button);
            const da = d.style.getRect(.down_arrow);
            const cbbr = vt.area.replace(vt.area.x + vt.area.w - cbb.w * d.scale, null, cbb.w * d.scale, null).centerR(da.w * d.scale, da.h * d.scale);
            d.ctx.rectTex(cbbr, da, d.style.texture);
        }

        pub fn onclick(vt: *iArea, cb: g.MouseCbState, win: *iWindow) void {
            const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
            _ = win;
            self.makeTransientWindow(cb.gui, Rec(vt.area.x, vt.area.y, vt.area.w, cb.gui.style.config.default_item_h * 10));
        }

        pub fn buttonCb(vt: *iArea, id: usize, gui: *Gui, _: *iWindow) void {
            const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
            vt.dirty(gui);
            self.opts.current = id;
            self.opts.commit_cb(self.opts.user_vt, id, self.user);
            gui.deferTransientClose();
        }

        pub fn makeTransientWindow(self: *@This(), gui: *Gui, area: Rect) void {
            const popped = gui.create(PoppedWindow);
            popped.* = .{
                .parent_vt = &self.vt,
                .vt = iWindow.init(
                    &PoppedWindow.buildWindow,
                    gui,
                    &PoppedWindow.deinit,
                    &popped.area,
                ),
                .area = iArea.init(gui, area),
                .name = "noname",
            };
            popped.area.draw_fn = &PoppedWindow.draw;
            popped.area.deinit_fn = &PoppedWindow.deinit_area;
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
            area: iArea,

            parent_vt: *iArea,
            name: []const u8,

            pub fn build(
                vt: *iWindow,
                gui: *Gui,
                area: Rect,
            ) void {
                const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
                self.area.area = area;
                self.area.clearChildren(gui, vt);
                const info = @typeInfo(enumT);
                vt.area.dirty(gui);
                self.area.addChildOpt(gui, vt, VScroll.build(gui, area, .{
                    .build_cb = &build_cb,
                    .build_vt = &self.area,
                    .win = vt,
                    .count = info.@"enum".fields.len,
                    .item_h = gui.style.config.default_item_h,
                }));
            }

            pub fn build_cb(vt: *iArea, area: *iArea, index: usize, gui: *Gui, win: *iWindow) void {
                const self: *@This() = @alignCast(@fieldParentPtr("area", vt));
                var ly = g.VerticalLayout{ .item_height = gui.style.config.default_item_h, .bounds = area.area };
                const info = @typeInfo(enumT);
                inline for (info.@"enum".fields, 0..) |field, i| {
                    if (i >= index) {
                        area.addChild(gui, win, Widget.Button.build(
                            gui,
                            ly.getArea(),
                            field.name,
                            .{ .cb_vt = self.parent_vt, .cb_fn = &ParentT.buttonCb, .id = field.value },
                        ) orelse return);
                    }
                }
            }

            pub fn deinit(vt: *iWindow, gui: *Gui) void {
                const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
                vt.deinit(gui);
                gui.alloc.destroy(self);
            }

            pub fn draw(vt: *iArea, d: g.DrawState) void {
                const self: *@This() = @alignCast(@fieldParentPtr("area", vt));
                _ = d;
                _ = self;
            }

            pub fn deinit_area(vt: *iArea, _: *Gui, _: *iWindow) void {
                _ = vt;
            }
        };

        vt: iArea,

        enum_ptr: *enumT,
        opts: ComboOpts,

        pub fn build(gui: *Gui, area: Rect, enum_ptr: *enumT, opts: ComboOpts) *iArea {
            const self = gui.create(@This());
            self.* = .{
                .vt = iArea.init(gui, area),
                .enum_ptr = enum_ptr,
                .opts = opts,
            };
            self.vt.onclick = &onclick;
            self.vt.draw_fn = &draw;
            self.vt.deinit_fn = &deinit;
            return &self.vt;
        }

        pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
            const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
            gui.alloc.destroy(self);
        }

        pub fn draw(vt: *iArea, d: g.DrawState) void {
            const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
            //d.ctx.rect(vt.area, 0x2ffff0ff);

            const cb = d.style.getRect(.combo_background);
            const btn_a = vt.area;
            d.ctx.nineSlice(btn_a, cb, d.style.texture, d.scale, d.tint);
            const texta = btn_a.inset(cb.w / 3 * d.scale);
            d.ctx.textClipped(texta, "{s}", .{@tagName(self.enum_ptr.*)}, d.textP(null), .center);
            //self.gui.drawTextFmt(fmt, args, texta, self.style.config.text_h, 0xff, .{ .justify = .center }, self.font);
            const cbb = d.style.getRect(.combo_button);
            const da = d.style.getRect(.down_arrow);
            const cbbr = btn_a.replace(btn_a.x + btn_a.w - cbb.w * d.scale, null, cbb.w * d.scale, null).centerR(da.w * d.scale, da.h * d.scale);
            d.ctx.rectTex(cbbr, da, d.style.texture);
        }

        pub fn onclick(vt: *iArea, cb: g.MouseCbState, win: *iWindow) void {
            const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
            const btn_a = vt.area;
            _ = win;
            self.makeTransientWindow(cb.gui, Rec(btn_a.x, btn_a.y, btn_a.w, cb.gui.style.config.default_item_h * 4));
        }

        pub fn buttonCb(vt: *iArea, id: usize, gui: *Gui, _: *iWindow) void {
            const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
            vt.dirty(gui);
            self.enum_ptr.* = @enumFromInt(id);
            gui.deferTransientClose();
        }

        pub fn makeTransientWindow(self: *@This(), gui: *Gui, area: Rect) void {
            const popped = gui.create(PoppedWindow);
            popped.* = .{
                .parent_vt = &self.vt,
                .vt = iWindow.init(
                    &PoppedWindow.build,
                    gui,
                    &PoppedWindow.deinit,
                    &popped.area,
                ),
                .area = iArea.init(gui, area),
                .name = "noname",
            };
            popped.area.draw_fn = &PoppedWindow.draw;
            popped.area.deinit_fn = &PoppedWindow.deinit_area;
            gui.setTransientWindow(&popped.vt);
            popped.vt.build_fn(&popped.vt, gui, area);
        }
    };
}
