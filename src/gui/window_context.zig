const std = @import("std");
const g = @import("vtables.zig");
const iArea = g.iArea;
const graph = g.graph;
const Gui = g.Gui;
const Rect = g.Rect;
const Rec = g.Rec;
const iWindow = g.iWindow;
const Widget = g.Widget;
const ArrayList = std.ArrayList;
const NewVt = g.NewVt;

pub const BtnContextWindow = struct {
    pub const ButtonList = []const ButtonMapping;
    pub const ButtonMapping = struct {
        u64, //Set this using buttonId() to give this button a name
        []const u8, // the button text
        union(enum) {
            btn,
            blank,
            checkbox: bool, //default value of checkbox
            child: struct {
                _active: bool = false,
                width: f32,
                height: f32,
                //cb funcs etc,
            },
        },
    };

    pub const Opts = struct {
        buttons: ButtonList,
        btn_cb: BtnCb,
        btn_vt: *g.CbHandle,
        user_id: g.Uid = 0,
        checkbox_cb: ?Widget.Checkbox.CommitCb = null,
    };
    const BtnCb = Widget.Button.ButtonCallbackT;
    vt: iWindow,

    opts: Opts,
    cbhandle: g.CbHandle = .{},

    buttons: ArrayList(ButtonMapping) = .{},

    pub fn buttonId(comptime name: []const u8) u64 {
        const h = std.hash.Wyhash.hash;
        return h(0, name);
    }

    pub fn buttonIdRuntime(name: []const u8) u64 {
        const h = std.hash.Wyhash.hash;
        return h(0, name);
    }

    pub fn create(gui: *Gui, pos: graph.Vec2f, opts: Opts) !*iWindow {
        const self = gui.create(@This());
        var max_w: f32 = 0;
        for (opts.buttons) |btn| {
            const dim = gui.dstate.font.textBounds(btn[1], gui.dstate.style.config.text_h);
            max_w = @max(max_w, dim.x);
        }
        const item_h = gui.dstate.style.config.default_item_h;

        const rec = graph.Rec(pos.x, pos.y, max_w + item_h, item_h * @as(f32, @floatFromInt(opts.buttons.len)));
        self.* = .{
            .vt = iWindow.init(build, gui, deinit, .{ .area = rec }, &self.vt),
            .opts = opts,
        };
        try self.buttons.resize(gui.alloc, opts.buttons.len);
        for (opts.buttons, 0..) |btn, i|
            self.buttons.items[i] = .{ btn[0], try gui.alloc.dupe(u8, btn[1]), btn[2] };

        build(&self.vt, gui, self.vt.area.area);

        return &self.vt;
    }

    pub fn build(vt: *iWindow, gui: *Gui, area: Rect) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        vt.area.area = area;
        vt.area.clearChildren(gui, vt);

        var ly = g.VerticalLayout{ .item_height = gui.dstate.style.config.default_item_h, .bounds = area };
        for (self.buttons.items, 0..) |btn, btn_i| {
            const ar = ly.getArea();
            _ = switch (btn[2]) {
                .btn => Widget.Button.build(&vt.area, ar, btn[1], .{
                    .cb_vt = &self.cbhandle,
                    .cb_fn = btn_wrap_cb,
                    .id = btn[0],
                }),
                .checkbox => |default| Widget.Checkbox.build(&vt.area, ar, btn[1], .{
                    .cb_vt = &self.cbhandle,
                    .cb_fn = checkbox_wrap_cb,
                    .user_id = btn[0],
                    .style = .check,
                }, default),
                .blank => {},
                .child => |child| {
                    _ = child;
                    _ = Widget.Button.build(&vt.area, ar, btn[1], .{
                        .cb_vt = &self.cbhandle,
                        .cb_fn = btn_toggle_child,
                        .id = btn_i,
                    });
                },
            };
        }
    }

    pub fn deinit(vt: *iWindow, gui: *Gui) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        vt.deinit(gui);

        for (self.buttons.items) |btn|
            gui.alloc.free(btn[1]);
        self.buttons.deinit(gui.alloc);

        gui.alloc.destroy(self); //second
    }

    pub fn draw(vt: *iArea, _: *g.Gui, d: *g.DrawState) void {
        const self: *@This() = @alignCast(@fieldParentPtr("area", vt));
        _ = self;
        _ = d;
    }

    fn btn_toggle_child(cb: *g.CbHandle, id: g.Uid, dat: g.MouseCbState, win: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("cbhandle", cb));
        switch (self.buttons.items[id][2]) {
            else => {},
            .child => |*child| {
                child._active = !child._active;
                const sign: f32 = if (child._active) 1 else -1;
                const ar = self.vt.area.area;
                dat.gui.updateWindowSize(win, ar.replace(
                    null,
                    null,
                    ar.w + child.width * sign,
                    ar.h + child.height * sign,
                )) catch {};
            },
        }
    }

    fn checkbox_wrap_cb(cb: *g.CbHandle, gui: *Gui, val: bool, id: g.Uid) void {
        const self: *@This() = @alignCast(@fieldParentPtr("cbhandle", cb));
        if (self.opts.checkbox_cb) |ch_cb| {
            ch_cb(self.opts.btn_vt, gui, val, id);
        }
        gui.deferTransientClose();
    }

    fn btn_wrap_cb(cb: *g.CbHandle, id: g.Uid, dat: g.MouseCbState, win: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("cbhandle", cb));
        self.opts.btn_cb(self.opts.btn_vt, id, dat, win);
        dat.gui.deferTransientClose();
    }

    pub fn deinit_area(_: *iArea, _: *Gui, _: *iWindow) void {}
};
