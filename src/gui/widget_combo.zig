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

pub const ComboOpts = struct {
    commit_cb: ?*const fn (*CbHandle, index: usize, user_id: g.Uid) void = null,
    commit_vt: ?*CbHandle = null,
    user_id: g.Uid = 0,
};

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

pub const ComboItem = struct {
    pub fn broken() @This() {
        return .{
            .name = "broken",
            .enabled = false,
        };
    }
    name: []const u8,
    enabled: bool = true,
    color: ?u32 = null,
};

pub const CommitParam = struct {
    pub const invalid_index = std.math.maxInt(usize);
    index: usize,
    /// User must copy if used
    search_string: []const u8 = "",
};
pub fn ComboUser(user_data: type) type {
    return struct {
        pub const ComboVt = struct {

            //build_cb: *const fn (user_vt: *iArea, widget_vt: *iArea, index: usize, *Gui, *iWindow) void,
            name_cb: *const fn (*CbHandle, index: usize, *Gui, ud: user_data) ComboItem,
            commit_cb: *const fn (*CbHandle, user_data, CommitParam) void,
            count: usize,
            current: usize,

            user_id: usize = 0,

            user_vt: *CbHandle,

            // send a bogus index to commit and the current search string
            commit_invalid: bool = false,
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
                ly.padding = .zero;
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

            pub fn textbox_cb(pop_vt: *CbHandle, p: Widget.Textbox.CommitParam) void {
                const self: *@This() = @alignCast(@fieldParentPtr("cbhandle", pop_vt));
                const parent: *ParentT = @alignCast(@fieldParentPtr("vt", self.parent_vt));
                if (parent.opts.commit_invalid and p.forced) {
                    parent.opts.commit_cb(parent.opts.user_vt, parent.user, .{
                        .index = CommitParam.invalid_index,
                        .search_string = p.string,
                    });
                    p.gui.deferTransientClose();
                    return;
                }

                self.search_string = p.string;
                if (self.vscroll_vt) |v| {
                    //This will call build_scroll_cb
                    v.index_ptr.* = 0;
                    v.rebuild(p.gui, &self.vt);
                }
            }

            pub fn build_scroll_cb(cb: *CbHandle, area: *iArea, index: usize) void {
                const gui = area.win_ptr.gui_ptr;

                const self: *@This() = @alignCast(@fieldParentPtr("cbhandle", cb));
                var ly = gui.dstate.vlayout(area.area);
                ly.padding = .zero;
                const p: *ParentT = @alignCast(@fieldParentPtr("vt", self.parent_vt));
                const total_count = p.opts.count;

                const do_search = self.search_string.len > 0;
                if (do_search) {
                    self.search_list.clearRetainingCapacity();
                    for (0..total_count) |i| {
                        const name = p.opts.name_cb(p.opts.user_vt, i, gui, p.user);
                        if (searchMatch(name.name, self.search_string))
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
                        name.name,
                        .{
                            .cb_vt = &p.cbhandle,
                            .cb_fn = &ParentT.buttonCb,
                            .id = i,
                            .tab_focus = true,
                            .disable = !name.enabled,
                        },
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
            drawCommon(vt.area, d, self.opts.name_cb(self.opts.user_vt, self.opts.current, gui, self.user).name);
        }

        pub fn onclick(vt: *iArea, cb: g.MouseCbState, win: *iWindow) void {
            const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
            _ = win;
            self.makeTransientWindow(cb.gui, Rec(vt.area.x, vt.area.y, vt.area.w, cb.gui.dstate.style.config.default_item_h * 10).round());
        }

        pub fn buttonCb(cb: *CbHandle, id: usize, dat: g.MouseCbState, _: *iWindow) void {
            const self: *@This() = @alignCast(@fieldParentPtr("cbhandle", cb));
            self.vt.dirty();
            self.opts.current = id;
            self.opts.commit_cb(self.opts.user_vt, self.user, .{ .index = id });
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
                ly.padding = .zero;
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
            drawCommon(vt.area, d, @tagName(self.enum_ptr.*));
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
            if (self.opts.commit_vt) |cvt| {
                if (self.opts.commit_cb) |cbfn|
                    cbfn(cvt, id, self.opts.user_id);
            }
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

fn drawCommon(area: Rect, d: *g.DrawState, text: []const u8) void {
    //d.ctx.rect(vt.area, 0x2ffff0ff);
    d.box(area, .{
        .bg = d.nstyle.color.combo_bg,
        .border = d.nstyle.color.combo_border,
        .text = text,
        .text_fg = d.nstyle.color.combo_text,
    });

    const bw = 1;
    const h = area.h;
    const pad = (area.h - h) / 2;
    const br = Rect.newV(.{ .x = area.x + bw, .y = area.y + pad }, .{ .x = h, .y = h }).inset(h / 4);

    const cent = br.center();

    const v = [3]graph.Vec2f{ br.topL(), cent, br.topR() };
    const cmass = cent.sub(v[0].add(v[1].add(v[2])).scale(1.0 / 3.0));
    d.ctx.triangle(v[0].add(cmass), v[1].add(cmass), v[2].add(cmass), d.nstyle.color.combo_arrow);
}
