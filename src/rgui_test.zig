const std = @import("std");
const graph = @import("graphics.zig");
const Dctx = graph.ImmediateDrawingContext;
const Os9Gui = @import("gui_app.zig");
const GuiConfig = Os9Gui.GuiConfig;
const GuiHelp = guis.GuiHelp;
const app = @import("gui/app.zig");

const Rect = graph.Rect;
const Rec = graph.Rec;
const AL = std.mem.Allocator;

const guis = @import("gui/vtables.zig");
const iWindow = guis.iWindow;
const iArea = guis.iArea;
const DrawState = guis.DrawState;

const Gui = guis.Gui;
const Wg = guis.Widget;
const CbHandle = guis.CbHandle;

pub const Styler = struct {
    vt: iWindow,
    cbhandle: CbHandle = .{},

    pub fn create(gui: *Gui) *iWindow {
        const self = gui.create(@This());
        self.* = .{
            .vt = iWindow.init(build, gui, deinit, .{}, &self.vt),
        };

        return &self.vt;
    }

    fn deinit_area(_: *iArea, _: *Gui, _: *iWindow) void {}

    pub fn deinit(vt: *iWindow, gui: *Gui) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        //self.layout.deinit(gui, vt);
        vt.deinit(gui);
        gui.alloc.destroy(self); //second
    }

    pub fn draw(vt: *iArea, _: *Gui, d: *DrawState) void {
        GuiHelp.drawWindowFrame(d, vt.area);
    }

    pub fn build(vt: *iWindow, gui: *Gui, area: Rect) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        self.vt.area.area = area;
        self.vt.area.clearChildren(gui, vt);
        //self.layout.reset(gui, vt);
        //start a vlayout
        //var ly = Vert{ .area = vt.area };
        var ly = gui.dstate.vlayout(GuiHelp.insetAreaForWindowFrame(gui, vt.area.area));
        ly.padding.left = 10;
        ly.padding.right = 10;
        const a = &self.vt.area;

        inline for (@typeInfo(guis.Colorscheme).@"struct".fields, 0..) |field, fi| {
            if (guis.label(a, ly.getArea(), "{s}", .{field.name})) |ar| {
                if (@typeInfo(field.type) == .int)
                    _ = Wg.Colorpicker.build(a, ar, @field(gui.dstate.nstyle.color, field.name), .{
                        .user_id = fi,
                        .commit_vt = &self.cbhandle,
                        .commit_cb = commit_color,
                    });
            }
        }
    }

    fn commit_color(cb: *CbHandle, _: *Gui, color: u32, id: usize) void {
        const self: *@This() = @alignCast(@fieldParentPtr("cbhandle", cb));

        inline for (@typeInfo(guis.Colorscheme).@"struct".fields, 0..) |f, i| {
            if (i == id and @typeInfo(f.type) == .int) {
                @field(
                    self.vt.gui_ptr.dstate.nstyle.color,
                    f.name,
                ) = color;
                return;
            }
        }
    }
};

pub const MyGlView = struct {
    vt: iWindow,
    cbhandle: CbHandle = .{},

    draw_ctx: *graph.ImmediateDrawingContext,

    pub fn create(gui: *Gui, draw_ctx: *graph.ImmediateDrawingContext) *iWindow {
        const self = gui.create(@This());
        self.* = .{
            .draw_ctx = draw_ctx,
            .vt = iWindow.init(&@This().build, gui, &@This().deinit, .{}, &self.vt),
        };
        self.vt.update_fn = update;

        return &self.vt;
    }

    pub fn update(vt: *iWindow, gui: *Gui) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));

        const can_grab = gui.canGrabMouseOverride(vt);

        if (can_grab) {
            self.draw_ctx.rect(self.vt.area.area, 0x00ffff);
            //const mstate = gui.sdl_win.mouse.left;
            if (gui.sdl_win.keyRising(.LSHIFT)) {
                const center = self.vt.area.area.center();
                graph.c.SDL_WarpMouseInWindow(gui.sdl_win.win, center.x, center.y);
            }
            gui.setGrabOverride(vt, gui.sdl_win.keystate(.LSHIFT) == .low, .{ .hide_pointer = true });
        } else {
            self.draw_ctx.rect(self.vt.area.area, 0xff00ffff);
        }
    }

    pub fn deinit(vt: *iWindow, gui: *Gui) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        //self.layout.deinit(gui, vt);
        vt.deinit(gui);
        gui.alloc.destroy(self); //second
    }

    pub fn draw(vt: *iArea, _: *Gui, d: *DrawState) void {
        GuiHelp.drawWindowFrame(d, vt.area);
    }

    pub fn build(vt: *iWindow, gui: *Gui, area: Rect) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        _ = gui;
        //TODO MOVE THIS OUT
        self.vt.area.area = area;
    }
};

pub const MyInspector = struct {
    const BtnId = enum(guis.Uid) {
        add,
        reset,
        many,
        bottom,
        pop,
    };
    const MyEnum = enum {
        hello,
        world,
        this,
        is,
        a,
        enum_,
        that,
        has,
        fields,
    };

    vt: iWindow,
    cbhandle: CbHandle = .{},

    inspector_state: u32 = 0,
    bool1: bool = false,
    bool2: bool = false,
    i32_n: i32 = 3,
    number: f32 = 488.8,
    my_enum: MyEnum = .hello,
    fenum: std.fs.File.Kind = .file,
    color: u32 = 0xff_ff,
    num_scroll_items: u32 = 10,

    tab_index: usize = 3,
    scroll_index: usize = 0,

    vscroll_vt: ?*iArea = null,
    //This subscribes to onScroll
    //has two child layouts,
    //the act of splitting is not the Layouts job

    pub fn create(gui: *Gui) *iWindow {
        const self = gui.create(@This());
        self.* = .{
            .vt = iWindow.init(build, gui, deinit, .{}, &self.vt),
        };

        return &self.vt;
    }

    fn deinit_area(_: *iArea, _: *Gui, _: *iWindow) void {}

    pub fn deinit(vt: *iWindow, gui: *Gui) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        //self.layout.deinit(gui, vt);
        vt.deinit(gui);
        gui.alloc.destroy(self); //second
    }

    pub fn draw(vt: *iArea, _: *Gui, d: *DrawState) void {
        GuiHelp.drawWindowFrame(d, vt.area);
    }

    pub fn build(vt: *iWindow, gui: *Gui, area: Rect) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        self.vt.area.area = area;
        self.vt.area.clearChildren(gui, vt);
        self.vscroll_vt = null;
        //self.layout.reset(gui, vt);
        //start a vlayout
        //var ly = Vert{ .area = vt.area };
        var ly = gui.dstate.vlayout(GuiHelp.insetAreaForWindowFrame(gui, vt.area.area));
        ly.padding.left = 10;
        ly.padding.right = 10;
        ly.padding.top = 10;
        const a = &self.vt.area;

        _ = Wg.Checkbox.build(a, ly.getArea(), "first button", .{
            .bool_ptr = &self.bool1,
        }, null);
        _ = Wg.Checkbox.build(a, ly.getArea(), "secnd button", .{ .bool_ptr = &self.bool2 }, null);
        _ = Wg.StaticSlider.build(a, ly.getArea(), null, .{
            .default = 0,
            .min = -1000,
            .max = 1000,
            .unit = "degrees",
            .slide = .{ .snap = 1 },
            .slide_cb = staticSliderCb,
            .commit_cb = staticSliderSet,
            .commit_vt = &self.cbhandle,
        });
        _ = Wg.Combo.build(a, ly.getArea() orelse return, &self.my_enum, .{});
        _ = Wg.Combo.build(a, ly.getArea() orelse return, &self.fenum, .{});

        _ = Wg.Button.build(a, ly.getArea(), "pop", .{ .cb_vt = &self.cbhandle, .cb_fn = @This().btnCb, .id = @intFromEnum(BtnId.pop) });
        _ = Wg.Button.build(a, ly.getArea(), "Add item", .{ .cb_vt = &self.cbhandle, .cb_fn = @This().btnCb, .id = @intFromEnum(BtnId.add) });
        _ = Wg.Button.build(a, ly.getArea(), "reset list", .{ .cb_vt = &self.cbhandle, .cb_fn = @This().btnCb, .id = @intFromEnum(BtnId.reset) });
        _ = Wg.Button.build(a, ly.getArea(), "add many", .{ .cb_vt = &self.cbhandle, .cb_fn = @This().btnCb, .id = @intFromEnum(BtnId.many) });
        _ = Wg.Button.build(a, ly.getArea(), "bottom", .{ .cb_vt = &self.cbhandle, .cb_fn = @This().btnCb, .id = @intFromEnum(BtnId.bottom) });

        _ = Wg.Textbox.build(a, ly.getArea());
        _ = Wg.Textbox.build(a, ly.getArea());
        _ = Wg.TextboxNumber.build(a, ly.getArea(), &self.number, .{});

        ly.pushRemaining();
        _ = Wg.Tabs.build(a, ly.getArea(), &.{ "main", "next", "third", "tv" }, vt, .{ .build_cb = &buildTabs, .cb_vt = &self.cbhandle, .index_ptr = &self.tab_index });
    }

    fn staticSliderCb(cb: *CbHandle, _: *Gui, _: f32, _: usize, _: Wg.StaticSliderOpts.State) void {
        const self: *@This() = @alignCast(@fieldParentPtr("cbhandle", cb));
        self.vt.area.dirty();
    }

    fn staticSliderSet(cb: *CbHandle, _: *Gui, _: f32, _: usize) void {
        const self: *@This() = @alignCast(@fieldParentPtr("cbhandle", cb));
        self.vt.area.dirty();
    }

    pub fn buildTabs(cb: *CbHandle, vt: *iArea, tab_name: []const u8, _: usize, gui: *Gui, win: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("cbhandle", cb));
        self.vscroll_vt = null;
        const eql = std.mem.eql;
        var ly = gui.dstate.vlayout(vt.area);
        ly.padding.top = 10;
        if (eql(u8, tab_name, "tv")) {
            ly.pushRemaining();
            _ = Wg.TextView.build(vt, ly.getArea(), &.{ "Hello\n", "World\n", "my name is niklas" }, win, .{
                .mode = .split_on_space,
            });
        }
        if (eql(u8, tab_name, "main")) {
            _ = Wg.Textbox.build(vt, ly.getArea());
            _ = Wg.Textbox.build(vt, ly.getArea());

            ly.pushRemaining();

            _ = Wg.FloatScroll.build(vt, ly.getArea(), .{
                .build_cb = &buildFloatScroll,
                .build_vt = &self.cbhandle,
                .win = win,
                .scroll_mul = gui.dstate.nstyle.item_h * 4,
                .scroll_y = true,
                .scroll_x = false,
            });

            //if (ly.getArea()) |ar| {
            //    const empty = vt.addEmpty(gui, win, ar.split(.horizontal, ar.h / 2)[0]);
            //    win.registerScissor(empty) catch {};

            //    const big_area = graph.Rec(ar.x, ar.y, 1000, 1000);
            //    var ly2 = guis.VerticalLayout{ .item_height = gui.nstyle.item_h, .bounds = big_area };
            //    for (0..10) |_| {
            //        //empty.addChildOpt(gui, win, Wg.Text.buildStatic(gui, big_area, "HELLO WIRLD", 0xff0000_ff));
            //        empty.addChildOpt(gui, win, Wg.Button.build(gui, ly2.getArea(), "My button 2", .{}));
            //    }
            //}

            return;
        }
        if (eql(u8, tab_name, "next")) {}
        if (eql(u8, tab_name, "third")) {
            ly.pushRemaining();
            if (Wg.VScroll.build(vt, ly.getArea(), .{
                .build_cb = &buildScrollItems,
                .build_vt = &self.cbhandle,
                .win = win,
                .count = self.num_scroll_items,
                .item_h = gui.dstate.nstyle.item_h,
                .index_ptr = &self.scroll_index,
            }) == .good) {
                self.vscroll_vt = vt.getLastChild();
            }
        }
    }

    pub fn buildScrollItems(cb: *CbHandle, vt: *iArea, index: usize) void {
        const gui = vt.win_ptr.gui_ptr;

        const self: *@This() = @alignCast(@fieldParentPtr("cbhandle", cb));
        var ly = gui.dstate.vlayout(vt.area);
        for (index..self.num_scroll_items) |i| {
            _ = Wg.Text.build(vt, ly.getArea(), "item {d}", .{i}, .{});
        }
    }

    pub fn buildFloatScroll(cb: *CbHandle, vt: *iArea, gui: *Gui, _: *iWindow, scr: *Wg.FloatScroll) void {
        const self: *@This() = @alignCast(@fieldParentPtr("cbhandle", cb));
        var ly = gui.dstate.vlayout(vt.area);
        _ = self;
        for (0..100) |i| {
            const ar = ly.getArea() orelse continue;
            _ = Wg.Text.build(vt, ar, "item {d}", .{i}, .{});
        }
        scr.hintBounds(ly.getUsed());
    }

    pub fn btnCb(cb: *CbHandle, id: guis.Uid, cbs: guis.MouseCbState, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("cbhandle", cb));
        const en = std.meta.intToEnum(BtnId, id) catch return;
        switch (en) {
            .pop => {
                const child = cbs.gui.sdl_win.createChildWindow("popup", 100, 100) catch return;
                _ = child;
            },
            .add => self.num_scroll_items += 1,
            .reset => self.num_scroll_items = 10,
            .many => self.num_scroll_items += 100,
            .bottom => {
                if (self.vscroll_vt) |vscr| {
                    const scr: *Wg.VScroll = @alignCast(@fieldParentPtr("vt", vscr));
                    scr.gotoBottom();
                }
            },
        }
        self.vt.needs_rebuild = true;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.detectLeaks();
    const alloc = gpa.allocator();

    if (true) {
        const out = try std.fs.cwd().openDir("/tmp/asswipe", .{});
        const indir = try std.fs.cwd().openDir("/home/tony/testpng", .{ .iterate = true });
        var it = indir.iterate();
        var out_buf: [2048]u8 = undefined;
        while (try it.next()) |file| {
            if (file.kind != .file) continue;

            var bmp = try graph.Bitmap.initFromPngFile(alloc, indir, file.name);
            defer bmp.deinit();

            var outfile = try out.createFile(file.name, .{});
            var wr = outfile.writer(&out_buf);

            try bmp.writeQoi(&wr.interface);
            try wr.interface.flush();
            outfile.close();

            //var out = try std.fs.cwd().createFile("/tmp/ass.bmp", .{});
            //defer out.close();
        }
        //var out = try std.fs.cwd().createFile("/tmp/ass.bmp", .{});
        //defer out.close();
        //var wr = out.writer(&out_buf);
        //var bmp = try graph.Bitmap.initBlank(alloc, 10, 10, .rgb_8);
        //defer bmp.deinit();

        //try bmp.write(&wr.interface, .bmp);
        //try wr.interface.flush();
        return;
    }

    const gg = try app.GuiApp.initDefault(alloc, .{});
    defer gg.deinit();
    const gui = &gg.gui;

    const window_area = Rect{ .x = 0, .y = 0, .w = 1000, .h = 1000 };

    const inspector = MyInspector.create(gui);
    const styler = Styler.create(gui);
    _ = try gui.addWindow(inspector, window_area, .{});
    _ = try gui.addWindow(styler, window_area.replace(window_area.x + window_area.w, null, null, null), .{ .put_fbo = true });

    try gui.active_windows.append(gui.alloc, inspector);
    try gui.active_windows.append(gui.alloc, styler);

    try gg.run();
}
