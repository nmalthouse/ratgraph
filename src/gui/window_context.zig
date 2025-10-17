const std = @import("std");
const g = @import("vtables.zig");
const iArea = g.iArea;
const graph = g.graph;
const Gui = g.Gui;
const Rect = g.Rect;
const Rec = g.Rec;
const iWindow = g.iWindow;
const Widget = g.Widget;
const ArrayList = std.ArrayListUnmanaged;
const NewVt = g.NewVt;

pub const BtnContextWindow = struct {
    pub const Opts = struct {
        buttons: ButtonList,
        btn_cb: BtnCb,
        btn_vt: *g.CbHandle,
        user_id: g.Uid = 0,
    };
    const BtnCb = Widget.Button.ButtonCallbackT;
    pub const ButtonMapping = struct { u64, []const u8 };
    pub const ButtonList = []const ButtonMapping;
    vt: iWindow,
    area: iArea,

    opts: Opts,
    cbhandle: g.CbHandle = .{},
    //btn_cb: BtnCb,
    //btn_cb_vt: *iArea,

    buttons: ArrayList(ButtonMapping) = .{},

    pub fn buttonId(comptime name: []const u8) u64 {
        const h = std.hash.Wyhash.hash;
        return h(0, name);
    }

    pub fn create(gui: *Gui, pos: graph.Vec2f, opts: Opts) !*iWindow {
        const self = gui.create(@This());
        var max_w: f32 = 0;
        for (opts.buttons) |btn| {
            const dim = gui.font.textBounds(btn[1], gui.style.config.text_h);
            max_w = @max(max_w, dim.x);
        }
        const item_h = gui.style.config.default_item_h;

        const rec = graph.Rec(pos.x, pos.y, max_w + item_h, item_h * @as(f32, @floatFromInt(opts.buttons.len)));
        self.* = .{
            .area = .{ .area = gui.clampRectToWindow(rec), .draw_fn = draw, .deinit_fn = deinit_area },
            .vt = iWindow.init(build, gui, deinit, &self.area),
            .opts = opts,
        };
        try self.buttons.resize(gui.alloc, opts.buttons.len);
        for (opts.buttons, 0..) |btn, i|
            self.buttons.items[i] = .{ btn[0], try gui.alloc.dupe(u8, btn[1]) };

        build(&self.vt, gui, self.area.area);

        return &self.vt;
    }

    pub fn build(vt: *iWindow, gui: *Gui, area: Rect) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        self.area.area = area;
        self.area.clearChildren(gui, vt);

        var ly = g.VerticalLayout{ .item_height = gui.style.config.default_item_h, .bounds = area };
        for (self.buttons.items) |btn| {
            self.area.addChildOpt(gui, vt, Widget.Button.build(gui, ly.getArea(), btn[1], .{
                .cb_vt = &self.cbhandle,
                .cb_fn = btn_wrap_cb,
                .id = btn[0],
            }));
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

    pub fn draw(vt: *iArea, d: g.DrawState) void {
        const self: *@This() = @alignCast(@fieldParentPtr("area", vt));
        _ = self;
        _ = d;
    }

    fn btn_wrap_cb(cb: *g.CbHandle, id: g.Uid, dat: g.MouseCbState, win: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("cbhandle", cb));
        self.opts.btn_cb(self.opts.btn_vt, id, dat, win);
        dat.gui.deferTransientClose();
    }

    pub fn deinit_area(_: *iArea, _: *Gui, _: *iWindow) void {}
};

pub const SubMenuExpander = struct {
    vt: iArea,
    text: []const u8,

    pub fn build(gui: *Gui, area_o: ?Rect, text: []const u8) ?NewVt {
        const area = area_o orelse return null;
        const self = gui.create(@This());
        self.* = .{
            .vt = .{ .area = area, .deinit_fn = deinit, .draw_fn = draw },
            .text = gui.alloc.dupe(u8, text) catch return null,
        };
        return .{ .vt = &self.vt };
    }

    pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        gui.alloc.destroy(self);
    }

    pub fn draw(vt: *iArea, d: g.DrawState) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        //d.ctx.rect(vt.area, 0x5ffff0ff);
        d.ctx.rect(vt.area, self.bg_col);
        const texta = vt.area.inset(d.style.config.default_item_h / 10);
        d.ctx.textClipped(texta, "{s}", .{self.text}, d.textP(null), .left);
    }
};
