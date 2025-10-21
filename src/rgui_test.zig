const std = @import("std");
const graph = @import("graphics.zig");
const Dctx = graph.ImmediateDrawingContext;
const Os9Gui = @import("gui_app.zig");
const GuiConfig = Os9Gui.GuiConfig;
const GuiHelp = guis.GuiHelp;

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

        _ = Wg.Button.build(a, ly.getArea(), "My button", .{ .cb_vt = &self.cbhandle, .cb_fn = @This().btnCb, .id = 48 });
        _ = Wg.Button.build(a, ly.getArea(), "My button 2", .{});
        _ = Wg.Button.build(a, ly.getArea(), "My button 3", .{});
        _ = Wg.Colorpicker.build(a, ly.getArea() orelse return, self.color, .{});

        _ = Wg.Textbox.build(a, ly.getArea());
        _ = Wg.Textbox.build(a, ly.getArea());
        _ = Wg.TextboxNumber.build(a, ly.getArea(), &self.number, .{});
        _ = Wg.Slider.build(a, ly.getArea(), &self.number, -10, 10, .{});
        _ = Wg.Slider.build(a, ly.getArea(), &self.i32_n, -10, 10, .{});
        _ = Wg.Slider.build(a, ly.getArea(), &self.i32_n, 0, 10, .{});

        ly.pushRemaining();
        _ = Wg.Tabs.build(a, ly.getArea(), &.{ "main", "next", "third" }, vt, .{ .build_cb = &buildTabs, .cb_vt = &self.cbhandle });
    }

    fn staticSliderCb(cb: *CbHandle, _: *Gui, _: f32, _: usize, _: Wg.StaticSliderOpts.State) void {
        const self: *@This() = @alignCast(@fieldParentPtr("cbhandle", cb));
        self.vt.area.dirty();
    }

    fn staticSliderSet(cb: *CbHandle, _: *Gui, _: f32, _: usize) void {
        const self: *@This() = @alignCast(@fieldParentPtr("cbhandle", cb));
        self.vt.area.dirty();
    }

    pub fn buildTabs(cb: *CbHandle, vt: *iArea, tab_name: []const u8, gui: *Gui, win: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("cbhandle", cb));
        const eql = std.mem.eql;
        var ly = gui.dstate.vlayout(vt.area);
        ly.padding.top = 10;
        if (eql(u8, tab_name, "main")) {
            _ = Wg.Textbox.build(vt, ly.getArea());
            _ = Wg.Textbox.build(vt, ly.getArea());

            ly.pushRemaining();

            _ = Wg.FloatScroll.build(vt, ly.getArea(), .{
                .build_cb = &buildFloatScroll,
                .build_vt = &self.cbhandle,
                .win = win,
                .scroll_mul = gui.dstate.style.config.default_item_h * 4,
                .scroll_y = true,
                .scroll_x = false,
            });

            //if (ly.getArea()) |ar| {
            //    const empty = vt.addEmpty(gui, win, ar.split(.horizontal, ar.h / 2)[0]);
            //    win.registerScissor(empty) catch {};

            //    const big_area = graph.Rec(ar.x, ar.y, 1000, 1000);
            //    var ly2 = guis.VerticalLayout{ .item_height = gui.style.config.default_item_h, .bounds = big_area };
            //    for (0..10) |_| {
            //        //empty.addChildOpt(gui, win, Wg.Text.buildStatic(gui, big_area, "HELLO WIRLD", 0xff0000_ff));
            //        empty.addChildOpt(gui, win, Wg.Button.build(gui, ly2.getArea(), "My button 2", .{}));
            //    }
            //}

            return;
        }
        if (eql(u8, tab_name, "next")) {
            _ = Wg.Slider.build(vt, ly.getArea(), &self.number, -10, 10, .{});
            _ = Wg.Slider.build(vt, ly.getArea(), &self.i32_n, -10, 10, .{});
            _ = Wg.Slider.build(vt, ly.getArea(), &self.i32_n, 0, 10, .{});
        }
        if (eql(u8, tab_name, "third")) {
            ly.pushRemaining();
            _ = Wg.VScroll.build(vt, ly.getArea(), .{
                .build_cb = &buildScrollItems,
                .build_vt = &self.cbhandle,
                .win = win,
                .count = 10,
                .item_h = gui.dstate.style.config.default_item_h,
            });
        }
    }

    pub fn buildScrollItems(cb: *CbHandle, vt: *iArea, index: usize) void {
        const gui = vt.win_ptr.gui_ptr;

        const self: *@This() = @alignCast(@fieldParentPtr("cbhandle", cb));
        var ly = gui.dstate.vlayout(vt.area);
        for (index..10) |i| {
            _ = Wg.Text.build(vt, ly.getArea(), "item {d}", .{i});
        }
        _ = self;
    }

    pub fn buildFloatScroll(cb: *CbHandle, vt: *iArea, gui: *Gui, _: *iWindow, scr: *Wg.FloatScroll) void {
        const self: *@This() = @alignCast(@fieldParentPtr("cbhandle", cb));
        var ly = gui.dstate.vlayout(vt.area);
        _ = self;
        for (0..100) |i| {
            const ar = ly.getArea() orelse continue;
            _ = Wg.Text.build(vt, ar, "item {d}", .{i});
        }
        scr.hintBounds(ly.getUsed());
    }

    pub fn btnCb(_: *CbHandle, id: usize, _: guis.MouseCbState, _: *iWindow) void {
        std.debug.print("BUTTON CLICKED {d}\n", .{id});
    }
};

pub fn main() !void {
    std.debug.print("The size is :  {d}\n", .{@sizeOf(guis.iArea)});
    var gpa = std.heap.GeneralPurposeAllocator(.{ .stack_trace_frames = 0 }){};
    defer _ = gpa.detectLeaks();
    const alloc = gpa.allocator();

    var env_map = try std.process.getEnvMap(alloc);
    const cache_dir_name = env_map.get("XDG_RUNTIME_DIR") orelse "";
    const cache_dir = try std.fs.cwd().openDir(cache_dir_name, .{});
    std.debug.print("{s}\n", .{cache_dir_name});
    env_map.deinit();

    var win = try graph.SDL.Window.createWindow("My window", .{
        // Optional, see Window.createWindow definition for full list of options
        .window_size = .{ .x = 1000, .y = 1000 },
    });
    defer win.destroyWindow();

    var draw = graph.ImmediateDrawingContext.init(alloc);
    defer draw.deinit();
    std.debug.print("VT SIZE {d}\n", .{@sizeOf(iArea)});

    const TEXT_H = 18;
    const hh = 28;
    var font = try graph.Font.init(alloc, std.fs.cwd(), "asset/fonts/roboto.ttf", TEXT_H, .{});
    defer font.deinit();

    const sc = 2;
    var gui = try Gui.init(alloc, &win, cache_dir, std.fs.cwd(), &font.font, &draw);
    defer gui.deinit();

    gui.dstate.style.config.default_item_h = hh;
    gui.dstate.style.config.text_h = TEXT_H;

    const window_area = Rect{ .x = 100, .y = 50, .w = 1000, .h = 1000 };

    gui.dstate.scale = sc;
    const inspector = MyInspector.create(&gui);
    const glview = MyGlView.create(&gui, &draw);
    _ = try gui.addWindow(inspector, window_area, .{});
    _ = try gui.addWindow(glview, window_area.replace(window_area.x + window_area.w, null, null, null), .{ .put_fbo = false });

    var timer = try std.time.Timer.start();

    try gui.active_windows.append(gui.alloc, inspector);
    try gui.active_windows.append(gui.alloc, glview);
    while (!win.should_exit) {
        try draw.begin(0xff, win.screen_dimensions.toF());
        win.pumpEvents(.wait);
        gui.clamp_window = Rec(0, 0, draw.screen_dimensions.x, draw.screen_dimensions.y);
        if (win.keyRising(.ESCAPE))
            win.should_exit = true;

        timer.reset();
        try gui.pre_update();
        try gui.update();
        try gui.draw(false);

        const took = timer.read();
        if (took > std.time.ns_per_ms * 16) {
            std.debug.print("Overtime {d} \n", .{took / std.time.ns_per_ms});
        }
        gui.drawFbos();

        try draw.flush(null, null); //Flush any draw commands

        try draw.end(null);

        win.swap();
    }
}
