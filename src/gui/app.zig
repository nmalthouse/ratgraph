const std = @import("std");
const graph = @import("../graphics.zig");
const G = @import("vtables.zig");
const layouts = @import("layouts.zig");
const builtin = @import("builtin");
const IS_DEBUG = builtin.mode == .Debug;

pub const Options = struct {
    display_scale: ?f32 = null,
    item_height: ?f32 = null,
    font_size: ?f32 = null,
    gui_scale: ?f32 = null,

    window_title: [*c]const u8 = "rgui window",

    window_opts: graph.SDL.Window.CreateOptions = .{
        .frame_sync = .adaptive_vsync,
        .gl_major_version = 4,
        .gl_minor_version = 5,
        .enable_debug = IS_DEBUG,
        .gl_flags = if (IS_DEBUG) &[_]u32{graph.c.SDL_GL_CONTEXT_DEBUG_FLAG} else &[_]u32{},
    },
};
const DpiPreset = struct {
    dpi: f32 = 1,
    fh: f32 = 25,
    ih: f32 = 14,
    scale: f32 = 2,

    pub fn distance(_: void, item: @This(), key: @This()) f32 {
        return @abs(item.dpi - key.dpi);
    }
};

const DPI_presets = [_]DpiPreset{
    .{ .dpi = 1, .fh = 14, .ih = 25, .scale = 1 },
    .{ .dpi = 1.7, .fh = 18, .ih = 28, .scale = 1 },
};

pub const GuiApp = struct {
    const Self = @This();
    alloc: std.mem.Allocator,
    main_window: graph.SDL.Window,
    font: graph.OnlineFont,
    drawctx: graph.ImmediateDrawingContext,
    gui: G.Gui,
    workspaces: *layouts.Layouts,

    pub fn initDefault(alloc: std.mem.Allocator, opts: Options) !*GuiApp {
        const self = try alloc.create(GuiApp);

        var win = try graph.SDL.Window.createWindow(opts.window_title, opts.window_opts, alloc);

        const sc = opts.display_scale orelse try win.dpiDetect();
        const dpi_preset = blk: {
            const default_scaled = DpiPreset{ .fh = 20 * sc, .ih = 25 * sc, .scale = 1 };
            const max_dpi_diff = 0.3;
            const index = nearest(DpiPreset, &DPI_presets, {}, DpiPreset.distance, .{ .dpi = sc }) orelse break :blk default_scaled;
            const p = DPI_presets[index];
            if (@abs(p.dpi - sc) > max_dpi_diff)
                break :blk default_scaled;
            break :blk p;
        };

        const scaled_item_height = opts.item_height orelse @trunc(dpi_preset.ih);
        const scaled_text_height = opts.font_size orelse @trunc(dpi_preset.fh);
        const gui_scale = opts.gui_scale orelse dpi_preset.scale;

        self.* = .{
            .main_window = win,
            .alloc = alloc,
            .font = try graph.OnlineFont.initFromBuffer(alloc, @embedFile("font/roboto.ttf"), scaled_text_height, .{}),
            .drawctx = graph.ImmediateDrawingContext.init(alloc),
            .gui = try G.Gui.init(alloc, &self.main_window, &self.font.font, &self.drawctx),
            .workspaces = undefined,
        };
        self.workspaces = layouts.Layouts.create(&self.gui);
        _ = try self.gui.addWindow(&self.workspaces.vt, .{ .x = 0, .y = 0, .w = 10, .h = 10 }, .{ .put_fbo = false });
        self.gui.dstate.scale = gui_scale;
        self.gui.dstate.nstyle.item_h = scaled_item_height;
        self.gui.dstate.nstyle.text_h = scaled_text_height;
        self.drawctx.preflush_cb = drawctx_preflush_cb;
        self.drawctx.preflush_cb_ptr = @ptrCast(self);
        return self;
    }

    //TODO less ugly solution
    pub fn drawctx_preflush_cb(ptr: ?*anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr orelse return));
        self.font.syncBitmapToGL();
    }

    pub fn deinit(self: *Self) void {
        self.drawctx.deinit();
        self.gui.deinit();
        self.font.deinit();
        self.main_window.destroyWindow();
        self.alloc.destroy(self);
    }

    pub fn run(self: *Self) !void {
        const gui = &self.gui;
        self.main_window.forcePoll();
        while (!self.main_window.should_exit) {
            try self.drawctx.begin(0xff, self.main_window.screen_dimensions.toF());
            self.main_window.pumpEvents(.wait);

            self.workspaces.area = .{
                .x0 = 0,
                .y0 = 0,
                .x1 = @floatFromInt(self.main_window.screen_dimensions.x),
                .y1 = @floatFromInt(self.main_window.screen_dimensions.y),
            };
            try self.workspaces.preGuiUpdate(gui);
            try gui.pre_update();
            try gui.update();
            try gui.draw(false);

            gui.drawFbos();

            try self.drawctx.end(null);

            self.main_window.swap();
        }
    }
};

pub fn nearest(comptime T: type, items: []const T, context: anytype, comptime distanceFn: fn (@TypeOf(context), item: T, key: T) f32, key: T) ?usize {
    var nearest_i: ?usize = null;
    var dist: f32 = std.math.floatMax(f32);
    for (items, 0..) |item, i| {
        const d = distanceFn(context, item, key);
        if (d < dist) {
            nearest_i = i;
            dist = d;
        }
    }
    return nearest_i;
}
