const std = @import("std");
pub const graph = @import("../graphics.zig");
const Os9Gui = @import("../gui_app.zig");
pub const Dctx = graph.ImmediateDrawingContext;
//TODO deprecate this style
pub const GuiConfig = Os9Gui.GuiConfig;
pub const Rect = graph.Rect;
pub const Rec = graph.Rec;
pub const Uid = u64;
const gl = graph.GL;
const ArrayList = std.ArrayListUnmanaged;
const AL = std.mem.Allocator;

pub const CbHandle = struct {};
const log = std.log.scoped(.rgui);

pub const Widget = struct {
    const tx = @import("widget_textbox.zig");
    pub const NumberDummy = tx.NumberDummy;
    pub const TextboxNumber = tx.TextboxNumber;
    pub const NumberDummyfn = tx.NumberDummyFn;
    pub const NumberParseFn = tx.NumberParseFn;
    pub const TextboxOptions = tx.TextboxOptions;
    pub const Textbox = tx.Textbox;

    pub const BtnContextWindow = @import("window_context.zig").BtnContextWindow;

    const bs = @import("widget_basic.zig");
    pub const VScroll = bs.VScroll;
    pub const Checkbox = bs.Checkbox;
    pub const Button = bs.Button;
    pub const ScrollBar = bs.ScrollBar;
    pub const Text = bs.Text;
    pub const NumberDisplay = bs.NumberDisplay;

    const co = @import("widget_combo.zig");
    pub const ComboOpts = co.ComboOpts;
    pub const Combo = co.Combo;
    pub const ComboUser = co.ComboUser;
    pub const ComboGeneric = co.ComboGeneric;

    pub const Colorpicker = @import("widget_colorpicker.zig").Colorpicker;

    const sl = @import("widget_slider.zig");
    pub const SliderOptions = sl.SliderOptions;
    pub const Slider = sl.Slider;
    pub const SliderGeneric = sl.SliderGeneric;

    pub const Tabs = @import("widget_tabs.zig").Tabs;
    pub const TextView = @import("widget_textviewer.zig").TextView;
    pub const DynamicTable = @import("widget_dynamic_table.zig").DynamicTable;
    pub const GLTexture = @import("widget_texture.zig").GLTexture;

    const st = @import("widget_static_slider.zig");
    pub const ALLOWED_CHAR = st.ALLOWED_CHAR;
    pub const Slide = st.Slide;
    pub const StaticSlider = st.StaticSlider;
    pub const StaticSliderOpts = st.StaticSliderOpts;

    const Fscroll = @import("widget_floatscroll.zig");
    pub const FloatScroll = Fscroll.FloatScroll;
    pub const FloatScrollOpts = Fscroll.Opts;
};

pub const TextCbState = struct {
    gui: *Gui,
    text: []const u8,

    //TODO, move this to some other event
    keys: []const graph.SDL.KeyState = &.{}, // Populated with keys just pressed, keydown events
    mod_state: graph.SDL.keycodes.KeymodMask = 0,
};

/// A helper to return function pointers not stored inside vtable
pub const NewVt = struct {
    pub const OnClick = *const fn (*iArea, MouseCbState, *iWindow) void;

    pub const Onscroll = *const fn (*iArea, *Gui, *iWindow, distance: f32) void;
    pub const FocusEvent = *const fn (*iArea, FocusedEvent) void;
    pub const Onpoll = *const fn (*iArea, *Gui, *iWindow) void;
    vt: *iArea,

    onclick: ?OnClick = null,
    onscroll: ?Onscroll = null,
    onpoll: ?Onpoll = null,
};

//TODO store a depth and sort to_draw by depth
pub const iArea = struct {
    draw_fn: ?*const fn (*iArea, DrawState) void = null,
    deinit_fn: *const fn (*iArea, *Gui, *iWindow) void,
    focusEvent: ?NewVt.FocusEvent = null,

    can_tab_focus: bool = false,
    is_dirty: bool = false,

    parent: ?*iArea = null,
    /// index of self as child of parent
    index: u32 = 0,
    area: Rect,
    children: ArrayList(*iArea) = .{},

    _scissor_id: ScissorId = .none,

    pub fn getLastChild(self: *@This()) ?*iArea {
        return self.children.getLastOrNull();
    }

    pub fn deinit(self: *@This(), gui: *Gui, win: *iWindow) void {
        self.clearChildren(gui, win);
        self.children.deinit(gui.alloc);
        self.deinit_fn(self, gui, win);
    }

    pub fn draw(self: *@This(), dctx: DrawState, window: *iWindow) void {
        if (dctx.gui.needsDraw(self, window)) {
            window.checkScissor(self, &dctx);
            if (self.draw_fn) |drawf|
                drawf(self, dctx);
            for (self.children.items) |child|
                child.draw(dctx, window);
        }
        self.is_dirty = false;
    }

    pub fn dirty(self: *@This(), gui: *Gui) void {
        if (!self.is_dirty) {
            if (gui.getWindow(self)) |win|
                gui.setDirty(self, win);
        }
        self.is_dirty = true;
    }

    pub fn addChildOpt(self: *@This(), gui: *Gui, win: *iWindow, vto: ?NewVt) void {
        if (vto) |vt|
            self.addChild(gui, win, vt);
    }

    pub fn addChild(self: *@This(), gui: *Gui, win: *iWindow, new: NewVt) void {
        if (self._scissor_id != .none and new.vt._scissor_id != .none) {
            log.err("Can't created nested scissors!", .{});
            return;
        }
        if (self.children.items.len >= std.math.maxInt(u32)) return;

        gui.register(new.vt, win);
        if (new.onclick) |onclick|
            gui.registerOnClick(new.vt, onclick, win) catch return;
        if (new.onscroll) |onscroll|
            gui.regOnScroll(new.vt, onscroll, win) catch return;
        if (new.onpoll) |onpoll|
            win.registerPoll(new.vt, onpoll) catch return;

        // Propogate the scissor. Default is .none so no need to check
        new.vt._scissor_id = self._scissor_id;

        new.vt.parent = self;
        new.vt.index = @intCast(self.children.items.len);
        self.children.append(gui.alloc, new.vt) catch return;

        gui.setDirty(new.vt, win);
    }

    pub fn deinitEmpty(vt: *iArea, gui: *Gui, _: *iWindow) void {
        gui.alloc.destroy(vt);
    }

    pub fn addEmpty(self: *@This(), gui: *Gui, win: *iWindow, area: Rect) *iArea {
        const vt = gui.alloc.create(iArea) catch unreachable; //I'll allow this because it only happens on oom and we don't support recovery from that
        vt.* = .{ .area = area, .deinit_fn = deinitEmpty };
        self.addChild(gui, win, .{ .vt = vt });
        return vt;
    }

    pub fn clearChildren(self: *@This(), gui: *Gui, window: *iWindow) void {
        for (self.children.items) |child| {
            gui.deregister(child, window);
            child.deinit(gui, window);
        }
        self.children.clearRetainingCapacity();
    }

    pub fn genericSetDirtyOnFocusChange(self: *iArea, gui: *Gui, is_focused: bool) void {
        _ = is_focused;
        self.dirty(gui);
    }
};

pub const ScissorId = enum(u8) { none = std.math.maxInt(u8), _ };

pub fn label(lay: *iArea, gui: *Gui, win: *iWindow, area_o: ?Rect, comptime fmt: []const u8, args: anytype) ?Rect {
    const area = area_o orelse return null;
    const sp = area.split(.vertical, area.w / 2);
    lay.addChildOpt(gui, win, Widget.Text.build(gui, sp[0], fmt, args));
    return sp[1];
}

pub const iWindow = struct {
    const BuildfnT = *const fn (*iWindow, *Gui, Rect) void;

    build_fn: BuildfnT,
    deinit_fn: *const fn (*iWindow, *Gui) void,
    update_fn: ?*const fn (*iWindow, *Gui) void = null,

    area: *iArea,
    alloc: std.mem.Allocator,

    click_listeners: ArrayList(struct { *iArea, NewVt.OnClick }) = .{},
    scroll_list: ArrayList(struct { *iArea, NewVt.Onscroll }) = .{},
    poll_listeners: ArrayList(struct { ?*iArea, NewVt.Onpoll }) = .{},

    cache_map: std.AutoArrayHashMapUnmanaged(*iArea, void) = .{},
    to_draw: ArrayList(*iArea) = .{},
    draws_since_cached: i32 = 0,
    needs_rebuild: bool = false,

    /// ScissorId indexes into this
    scissors: ArrayList(?struct { *iArea, Rect }) = .{},

    draw_scissor_state: ScissorId = .none,

    pub fn draw(self: *iWindow, dctx: DrawState) void {
        self.area.draw(dctx, self);
    }

    pub fn checkScissor(self: *iWindow, vt: *iArea, dctx: *const DrawState) void {
        if (vt._scissor_id != self.draw_scissor_state) {
            dctx.ctx.flush(self.area.area, null) catch {}; //Flush existing
            self.draw_scissor_state = vt._scissor_id;
            if (self.getScissorRect(self.draw_scissor_state)) |sz| {
                const wa = self.area.area;
                const new_x = sz.x - wa.x;
                const new_y = wa.h - (sz.y - wa.y + sz.h);
                gl.enable(.scissor_test);
                graph.c.glScissor(
                    @as(i32, @intFromFloat(new_x)),
                    @as(i32, @intFromFloat(new_y)),
                    @as(i32, @intFromFloat(sz.w)),
                    @as(i32, @intFromFloat(sz.h)),
                );
            } else {
                gl.disable(.scissor_test);
            }
        }
    }

    pub fn init(build_fn: BuildfnT, gui: *Gui, deinit_fn: *const fn (*iWindow, *Gui) void, area: *iArea) iWindow {
        return .{
            .alloc = gui.alloc,
            .deinit_fn = deinit_fn,
            .build_fn = build_fn,
            .area = area,
        };
    }

    // the implementers deinit fn should call this first
    pub fn deinit(self: *iWindow, gui: *Gui) void {
        //self.layout.vt.deinit_fn(&self.layout.vt, gui, self);
        gui.deregister(self.area, self);
        self.area.deinit(gui, self);
        if (self.click_listeners.items.len != 0)
            std.debug.print("BROKEN\n", .{});
        if (self.scroll_list.items.len != 0)
            std.debug.print("BROKEN\n", .{});
        self.click_listeners.deinit(self.alloc);
        self.poll_listeners.deinit(self.alloc);
        self.scroll_list.deinit(self.alloc);
        self.to_draw.deinit(self.alloc);
        self.cache_map.deinit(self.alloc);
        self.scissors.deinit(self.alloc);
    }

    /// Returns true if this window contains the mouse
    pub fn dispatchClick(win: *iWindow, cb: MouseCbState) bool {
        if (!win.area.area.containsPoint(cb.pos)) return false;
        for (win.click_listeners.items) |click| {
            if (click[0].area.containsPoint(cb.pos)) {
                if (win.getScissorRect(click[0]._scissor_id)) |sz| {
                    if (!sz.containsPoint(cb.pos))
                        continue; // Skip this cb and keep checking
                }
                click[1](click[0], cb, win);
                return true;
            }
        }
        return true;
    }

    /// Returns true if this window contains the mouse
    pub fn dispatchScroll(win: *iWindow, coord: Vec2f, gui: *Gui, dist: f32) bool {
        if (!win.area.area.containsPoint(coord)) return false;
        var i: usize = win.scroll_list.items.len;
        while (i > 0) : (i -= 1) { //Iterate backwards so that deeper scroll's have priority
            const listener = win.scroll_list.items[i - 1];
            const vt = listener[0];
            if (vt.area.containsPoint(coord)) {
                if (win.getScissorRect(vt._scissor_id)) |sz| {
                    if (!sz.containsPoint(coord))
                        continue;
                }
                listener[1](vt, gui, win, dist);
                return true;
            }
        }
        return true;
    }

    pub fn dispatchPoll(win: *iWindow, gui: *Gui) void {
        var i: usize = win.poll_listeners.items.len;
        while (i > 0) : (i -= 1) {
            if (win.poll_listeners.items[i - 1][0] == null)
                _ = win.poll_listeners.swapRemove(i - 1);
        }
        for (win.poll_listeners.items) |item_o| {
            const item = item_o[0] orelse continue;
            item_o[1](item, gui, win);
        }
    }

    pub fn registerPoll(win: *iWindow, vt: *iArea, onpoll: NewVt.Onpoll) !void {
        try win.poll_listeners.append(win.alloc, .{ vt, onpoll });
    }

    pub fn unregisterPoll(win: *iWindow, vt: *iArea) void {
        for (win.poll_listeners.items, 0..) |item_o, i| {
            const item = item_o[0] orelse continue;
            if (item == vt) {
                win.poll_listeners.items[i][0] = null;
                return;
            }
        }
    }

    /// User must call this when creating a scissor
    pub fn registerScissor(win: *iWindow, vt: *iArea, region: Rect) !void {
        if (vt._scissor_id != .none) return error.nestedScissor;
        for (win.scissors.items, 0..) |pot, i| {
            if (pot == null) {
                win.scissors.items[i] = .{ vt, region };
                vt._scissor_id = @enumFromInt(i);
                return;
            }
        }
        if (win.scissors.items.len >= @intFromEnum(ScissorId.none))
            return error.tooManyScissor;

        const new_id: ScissorId = @enumFromInt(win.scissors.items.len);
        try win.scissors.append(win.alloc, .{ vt, region });
        vt._scissor_id = new_id;
        return;
    }

    pub fn unregisterScissor(win: *iWindow, vt: *iArea) void {
        if (vt._scissor_id != .none) {
            const index: usize = @intFromEnum(vt._scissor_id);
            if (index < win.scissors.items.len) {
                if (win.scissors.items[index]) |owner_vt| {
                    if (owner_vt[0] == vt) {
                        win.scissors.items[index] = null;
                    }
                }
            }
        }
    }

    fn getScissorRect(self: *iWindow, id: ScissorId) ?Rect {
        if (id == .none) return null;
        const index: usize = @intFromEnum(id);
        if (index < self.scissors.items.len) {
            if (self.scissors.items[index]) |owner_vt| {
                return owner_vt[1];
            }
        }
        return null;
    }
};

pub const DrawState = struct {
    ctx: *Dctx,
    gui: *Gui,
    font: *graph.FontInterface,
    style: *GuiConfig,
    nstyle: *const Style,
    scale: f32 = 2,
    tint: u32 = 0xffff_ffff, //Tint for textures

    /// return params for black text with config.text_h
    pub fn textP(self: *const @This(), color: ?u32) graph.ImmediateDrawingContext.TextParam {
        return .{
            .do_newlines = false,
            .font = self.font,
            .color = color orelse self.nstyle.color.text_fg,
            .px_size = self.style.config.text_h,
        };
    }
};

pub const MouseCbState = struct {
    pub const Btn = enum { left, middle, right };
    pos: Vec2f,
    delta: Vec2f,
    gui: *Gui,
    state: graph.SDL.ButtonState,
    btn: Btn,
};

pub const KeydownState = struct {
    keys: []const graph.SDL.KeyState,
    mod_state: graph.SDL.keycodes.KeymodMask = 0,
};

pub const FocusedEvent = struct {
    pub const Event = union(enum) {
        focusChanged: bool,
        text_input: TextCbState,
        keydown: KeydownState,
    };
    gui: *Gui,
    window: *iWindow,

    event: Event,
};

const ButtonState = graph.SDL.ButtonState;
pub const UpdateState = struct {
    tab: ButtonState,
    shift: ButtonState,
    mouse: struct { pos: Vec2f, delta: Vec2f, left: ButtonState, right: ButtonState, middle: ButtonState, scroll: Vec2f },
    text: []const u8,
    mod: graph.SDL.keycodes.KeymodMask,
    keys: []const graph.SDL.KeyState,
};

//Two options for this, we use a button widget which registers itself for onclick
//or we listen for onclick and determine which was clicked

//What happens when area changes?
//rebuild everyone
//start with a window
//call to register window, that window has a "build" vfunc?

pub const HorizLayout = struct {
    count: usize,
    paddingh: f32 = 20,
    index: usize = 0,
    current_w: f32 = 0,
    hidden: bool = false,
    count_override: ?usize = null,

    bounds: Rect,

    pub fn getArea(self: *@This()) ?Rect {
        defer self.index += if (self.count_override) |co| co else 1;
        const fc: f32 = @floatFromInt(self.count);
        const w = ((self.bounds.w - self.paddingh * (fc - 1)) / fc) * @as(f32, @floatFromInt(if (self.count_override) |co| co else 1));
        self.count_override = null;

        defer self.current_w += w + self.paddingh;

        return .{ .x = self.bounds.x + self.current_w, .y = self.bounds.y, .w = w, .h = self.bounds.h };
    }

    pub fn pushCount(self: *HorizLayout, next_count: usize) void {
        self.count_override = next_count;
    }
};

pub const TableLayout = struct {
    const Self = @This();
    hidden: bool = false,

    //Config
    columns: u32,
    item_height: f32,

    //State
    current_y: f32 = 0,
    column_index: u32 = 0,
    bounds: Rect,

    pub fn getArea(self: *Self) ?Rect {
        const bounds = self.bounds;
        if (self.current_y + self.item_height > bounds.h) return null;

        const col_w = bounds.w / @as(f32, @floatFromInt(self.columns));

        const ci = @as(f32, @floatFromInt(self.column_index));
        const area = graph.Rec(bounds.x + col_w * ci, bounds.y + self.current_y, col_w, self.item_height);
        self.column_index += 1;
        if (self.column_index >= self.columns) {
            self.column_index = 0;
            self.current_y += self.item_height;
        }

        return area;
    }
};

pub const TableLayoutCustom = struct {
    const Self = @This();
    hidden: bool = false,

    //Config
    column_widths: []const f32, // user must verify sum of widths <= bounsds.w!
    item_height: f32,

    //State
    current_y: f32 = 0,
    column_index: u32 = 0,
    current_x: f32 = 0,
    bounds: Rect,

    pub fn getArea(self: *Self) ?Rect {
        const bounds = self.bounds;
        if (self.current_y + self.item_height > bounds.h) return null;

        const col_w = self.column_widths[self.column_index];

        const area = graph.Rec(bounds.x + self.current_x, bounds.y + self.current_y, col_w, self.item_height);
        self.column_index += 1;
        self.current_x += col_w;
        if (self.column_index >= self.column_widths.len) {
            self.column_index = 0;
            self.current_x = 0;
            self.current_y += self.item_height;
        }

        return area;
    }
};

pub const VerticalLayout = struct {
    const Self = @This();
    padding: graph.Padding = .{ .top = 0, .bottom = 0, .left = 0, .right = 0 },
    item_height: f32,
    current_h: f32 = 0,
    next_height: ?f32 = null,
    give_remaining: bool = false,

    bounds: Rect,

    pub fn getArea(self: *Self) ?Rect {
        const bounds = self.bounds;
        const h = if (self.next_height) |nh| nh else self.item_height;
        self.next_height = null;

        //We don't add h yet because the last element can be partially displayed. (if clipped)
        //nvm we do
        if (self.current_h + self.padding.top + h > bounds.h)
            return null;

        if (self.give_remaining) {
            defer self.current_h = bounds.h;
            return .{
                .x = bounds.x + self.padding.left,
                .y = bounds.y + self.current_h + self.padding.top,
                .w = bounds.w - self.padding.horizontal(),
                .h = bounds.h - (self.current_h + self.padding.top) - self.padding.bottom,
            };
        }

        defer self.current_h += h + self.padding.vertical();
        return .{
            .x = bounds.x + self.padding.left,
            .y = bounds.y + self.current_h + self.padding.top,
            .w = bounds.w - self.padding.horizontal(),
            .h = h,
        };
    }

    pub fn getUsed(self: *Self) Rect {
        return Rect{ .x = self.bounds.x, .y = self.bounds.y, .w = self.bounds.w, .h = self.current_h };
    }

    pub fn pushHeight(self: *Self, h: f32) void {
        self.next_height = h;
    }

    pub fn pushCount(self: *Self, count: anytype) void {
        self.next_height = self.item_height * count;
    }

    pub fn countLeft(self: *Self) usize {
        if (self.item_height <= 0) return 0;

        const count = (self.bounds.h - self.current_h) / (self.padding.vertical() + self.item_height);
        return @intFromFloat(@trunc(count));
    }

    /// The next requested area will be the rest of the available space
    pub fn pushRemaining(self: *Self) void {
        self.give_remaining = true;
    }
};

pub const Demo = struct {
    alloc: std.mem.Allocator,
    jobj: std.json.Parsed([]const UpdateState),
    slice: []const u8,

    index: usize = 0,

    pub fn init(alloc: std.mem.Allocator, dir: std.fs.Dir, filename: []const u8) !@This() {
        const file = try dir.openFile(filename, .{});
        const slice = try file.reader().readAllAlloc(alloc, std.math.maxInt(usize));
        const parsed = try std.json.parseFromSlice([]const UpdateState, alloc, slice, .{});
        return .{
            .slice = slice,
            .alloc = alloc,
            .jobj = parsed,
        };
    }

    pub fn next(self: *@This()) ?*const UpdateState {
        if (self.index < self.jobj.value.len) {
            defer self.index += 1;
            return &self.jobj.value[self.index];
        }
        return null;
    }

    pub fn deinit(self: *@This()) void {
        self.jobj.deinit();
        self.alloc.free(self.slice);
    }
};

const Vec2f = graph.Vec2f;

pub const WindowId = enum(u32) {
    none = std.math.maxInt(u32),
    _,
};

const ENABLE_TEST_BUILDER = true;
pub const Gui = struct {
    const TestBuilder = struct {
        output_file: if (ENABLE_TEST_BUILDER) ?std.fs.File else void = if (ENABLE_TEST_BUILDER) null else {},
        outj: if (ENABLE_TEST_BUILDER) std.json.WriteStream(std.fs.File.Writer, .{ .checked_to_fixed_depth = 256 }) else void = undefined,

        fn emit(self: *@This(), updates: UpdateState) void {
            if (ENABLE_TEST_BUILDER) {
                if (self.output_file) |_|
                    self.outj.write(updates) catch return;
            }
        }
    };
    const Self = @This();
    pub const MouseGrabFn = *const fn (*iArea, MouseCbState, *iWindow) void;
    pub const TextinputFn = *const fn (*iArea, TextCbState, *iWindow) void;

    tracker: struct {
        register_count: usize = 0,
        deregister_count: usize = 0,

        fn reset(self: *@This()) void {
            self.register_count = 0;
            self.deregister_count = 0;
        }
        fn print(self: *@This()) void {
            if (self.register_count == 0 and self.deregister_count == 0)
                return;
            std.debug.print("{}\n", .{self});
        }
    } = .{},

    test_builder: TestBuilder = .{},

    alloc: std.mem.Allocator,
    /// All the registered windows
    windows: ArrayList(*iWindow) = .{},

    /// Windows that are active this frame put themselves in here
    active_windows: ArrayList(*iWindow) = .{},

    transient_should_close: bool = false,
    transient_window: ?*iWindow = null,

    mouse_grab: ?struct {
        win: *iWindow,
        kind: union(enum) {
            btn: struct {
                cb: MouseGrabFn,
                vt: *iArea,
                btn: MouseCbState.Btn,
            },
            override: struct { hide_pointer: bool },
        },
    } = null,

    focused: ?struct {
        vt: *iArea,
        win: *iWindow,
    } = null,

    fbos: std.AutoHashMap(*iWindow, graph.RenderTexture),
    transient_fbo: graph.RenderTexture,

    area_window_map: std.AutoArrayHashMapUnmanaged(*iArea, *iWindow) = .{},

    draws_since_cached: i32 = 0,
    max_cached_before_full_flush: i32 = 60 * 10, //Ten seconds
    cached_drawing: bool = true,
    clamp_window: Rect,

    text_input_enabled: bool = false,
    sdl_win: *graph.SDL.Window,

    style: GuiConfig,
    nstyle: Style,
    scale: f32 = 2,

    font: *graph.FontInterface,
    tint: u32 = 0xffff_ffff,

    pub fn init(alloc: AL, win: *graph.SDL.Window, cache_dir: std.fs.Dir, style_dir: std.fs.Dir, font: *graph.FontInterface) !Self {
        return Gui{
            .alloc = alloc,
            .font = font,
            .clamp_window = graph.Rec(0, 0, win.screen_dimensions.x, win.screen_dimensions.y),
            .transient_fbo = try graph.RenderTexture.init(100, 100),
            .fbos = std.AutoHashMap(*iWindow, graph.RenderTexture).init(alloc),
            .sdl_win = win,
            .style = try GuiConfig.init(alloc, style_dir, "asset/os9gui", cache_dir),
            .nstyle = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.windows.items) |win|
            win.deinit_fn(win, self);

        {
            var it = self.fbos.valueIterator();
            while (it.next()) |item|
                item.deinit();
        }
        self.transient_fbo.deinit();
        self.fbos.deinit();
        self.windows.deinit(self.alloc);
        self.active_windows.deinit(self.alloc);
        self.closeTransientWindow();
        self.area_window_map.deinit(self.alloc);
        self.style.deinit();
    }

    pub fn openTestBuilder(self: *Self, dir: std.fs.Dir, filename: []const u8) !void {
        if (ENABLE_TEST_BUILDER) {
            self.test_builder = .{
                .output_file = try dir.createFile(filename, .{}),
                .outj = undefined,
            };

            self.test_builder.outj = std.json.writeStream(self.test_builder.output_file.?.writer(), .{});

            try self.test_builder.outj.beginArray();
        }
    }

    pub fn closeTestBuilder(self: *Self) void {
        if (ENABLE_TEST_BUILDER) {
            if (self.test_builder.output_file) |_| {
                self.test_builder.outj.endArray() catch return;
            }
        }
    }

    /// Wrapper around alloc.create that never fails
    /// Graceful handling of OOM is not a concern for us
    pub fn create(self: *Self, T: type) *T {
        return self.alloc.create(T) catch std.process.exit(1);
    }

    pub fn needsDraw(self: *Self, vt: *iArea, window: *iWindow) bool {
        if (!self.cached_drawing)
            return true;
        if (!window.cache_map.contains(vt)) {
            window.cache_map.put(window.alloc, vt, {}) catch return true;
            return true;
        }
        return false;
    }

    //Traversal of the tree for tab.
    //Starting at the currently focused,
    //get parent, iterate children until we find ourself.
    //iterate through rest of children,if child has child, recur. if can_tab_focus, return that node
    //get parents parent, do the same, finding ourself.
    //sounds complicated?

    pub fn tabFocus(self: *Self, fwd: bool) void {
        if (self.focused) |f| {
            if (fwd) {
                if (findNextFocusTarget(f.vt)) |next| {
                    self.grabFocus(next, f.win);
                } else if (findFocusTargetNoBacktrack(f.win.area)) |next| { //Start from the root of the window
                    self.grabFocus(next, f.win);
                }
            } else {
                if (findPrevFocusTarget(f.vt)) |prev| {
                    self.grabFocus(prev, f.win);
                }
            }
        }
    }

    fn findNextFocusTarget(vt: *iArea) ?*iArea {
        const parent = vt.parent orelse return null;
        if (vt.index >= parent.children.items.len) return null;
        for (parent.children.items[vt.index + 1 ..]) |next| {
            return findFocusTargetNoBacktrack(next) orelse continue;
        }
        // None found in children,
        return findNextFocusTarget(parent);
    }

    fn findFocusTargetNoBacktrack(vt: *iArea) ?*iArea {
        if (vt.can_tab_focus)
            return vt;
        for (vt.children.items) |child| {
            return findFocusTargetNoBacktrack(child) orelse continue;
        }
        return null;
    }

    fn findPrevFocusTarget(vt: *iArea) ?*iArea {
        const parent = vt.parent orelse return null;
        if (vt.index >= parent.children.items.len) return null;

        var index = vt.index;
        while (index > 0) : (index -= 1) {
            const nvt = parent.children.items[index - 1];
            return findPrevFocusNoBacktrack(nvt) orelse continue;
        }
        return null;
    }

    fn findPrevFocusNoBacktrack(vt: *iArea) ?*iArea {
        var index = vt.children.items.len;
        while (index > 0) : (index -= 1) {
            return findPrevFocusNoBacktrack(vt.children.items[index - 1]) orelse continue;
        }
        if (vt.can_tab_focus)
            return vt;
        return null;
    }

    pub fn registerOnClick(_: *Self, vt: *iArea, onclick: NewVt.OnClick, window: *iWindow) !void {
        try window.click_listeners.append(window.alloc, .{ vt, onclick });
    }

    pub fn setDirty(self: *Self, vt: *iArea, win: *iWindow) void {
        if (self.cached_drawing) {
            win.to_draw.append(win.alloc, vt) catch return;
        }
    }

    pub fn pre_update(self: *Self) !void {
        if (false) {
            self.tracker.print();
            self.tracker.reset();
        }

        if (self.mouse_grab) |mg| {
            if (!self.isWindowActive(mg.win))
                self.clearGrab();
        }
        if (self.focused) |f| {
            if (!self.isWindowActive(f.win))
                self.focused = null;
        }
        for (self.active_windows.items) |win| {
            win.to_draw.clearRetainingCapacity();
            win.cache_map.clearRetainingCapacity();
            if (win.needs_rebuild) {
                win.needs_rebuild = false;
                win.draws_since_cached = 0;
                //var time = try std.time.Timer.start();
                win.build_fn(win, self, win.area.area);
                //std.debug.print("Built win in: {d:.2} us\n", .{time.read() / std.time.ns_per_us});
            }

            if (win.update_fn) |upfn|
                upfn(win, self);
        }
        if (self.transient_window) |tw| {
            tw.to_draw.clearRetainingCapacity();
            tw.cache_map.clearRetainingCapacity();
        }
        if (self.transient_should_close) {
            self.transient_should_close = false;
            self.closeTransientWindow();
        }
    }

    pub fn update(self: *Self) !void {
        try self.handleSdlEvents(self.active_windows.items);
    }

    /// If transient windows destroy themselves, the program will crash as used memory is freed.
    /// Defer the close till next update
    pub fn deferTransientClose(self: *Self) void {
        self.transient_should_close = true;
    }

    pub fn regOnScroll(_: *Self, vt: *iArea, onscroll: NewVt.Onscroll, window: *iWindow) !void {
        try window.scroll_list.append(window.alloc, .{ vt, onscroll });
    }

    pub fn register(self: *Self, vt: *iArea, window: *iWindow) void {
        self.tracker.register_count += 1;
        self.area_window_map.put(self.alloc, vt, window) catch return;
    }

    pub fn getWindow(self: *Self, vt: *iArea) ?*iWindow {
        return self.area_window_map.get(vt);
    }

    pub fn getWindowId(self: *Self, id: WindowId) ?*iWindow {
        if (id == .none) return null;
        const index: usize = @intFromEnum(id);
        if (index >= self.windows.items.len) return null;
        return self.windows.items[index];
    }

    fn isWindowActive(self: *Self, id: *iWindow) bool {
        if (self.transient_window != null and self.transient_window.? == id) return true;
        return std.mem.indexOfScalar(*iWindow, self.active_windows.items, id) != null;
    }

    pub fn canGrabMouseOverride(self: *Self, win: *iWindow) bool {
        if (self.mouse_grab) |mg| {
            switch (mg.kind) {
                else => return false,
                .override => return mg.win == win,
            }
            return;
        }
        if (win.area.area.containsPoint(self.sdl_win.mouse.pos)) {
            if (self.transient_window) |tr| {
                if (tr != win)
                    return false;
            }

            return true;
        }
        return false;
    }

    pub fn setGrabOverride(self: *Self, win: *iWindow, grab: bool, opts: struct { hide_pointer: bool }) void {
        if (self.canGrabMouseOverride(win)) {
            if (grab) {
                self.mouse_grab = .{
                    .win = win,
                    .kind = .{ .override = .{ .hide_pointer = opts.hide_pointer } },
                };
                self.sdl_win.grabMouse(opts.hide_pointer);
            } else {
                self.clearGrab();
            }
        }
    }

    fn clearGrab(self: *Self) void {
        if (self.mouse_grab) |mg| {
            switch (mg.kind) {
                .btn => {},
                .override => |ov| {
                    if (ov.hide_pointer)
                        self.sdl_win.grabMouse(false);
                },
            }
        }
        self.mouse_grab = null;
    }

    pub fn deregister(self: *Self, vt: *iArea, window: *iWindow) void {
        self.tracker.deregister_count += 1;
        _ = self.area_window_map.swapRemove(vt);
        for (window.scroll_list.items, 0..) |item, index| {
            if (item[0] == vt) {
                _ = window.scroll_list.swapRemove(index);
                break;
            }
        }
        for (window.click_listeners.items, 0..) |item, index| {
            if (item[0] == vt) {
                _ = window.click_listeners.swapRemove(index);
                break;
            }
        }
        for (window.to_draw.items, 0..) |item, index| {
            if (item == vt) {
                _ = window.to_draw.swapRemove(index);
                break;
            }
        }
        for (window.poll_listeners.items, 0..) |item, index| {
            if (item[0] == vt) {
                window.poll_listeners.items[index][0] = null;
                break;
            }
        }

        window.unregisterScissor(vt);

        if (self.mouse_grab) |g| {
            switch (g.kind) {
                else => {},
                .btn => |b| {
                    if (b.vt == vt)
                        self.clearGrab();
                },
            }
        }
        if (self.focused) |f| {
            if (f.vt == vt)
                self.focused = null;
        }
    }

    pub fn grabFocus(self: *Self, vt: *iArea, win: *iWindow) void {
        if (self.focused) |f| {
            if (f.vt != vt and f.vt.focusEvent != null)
                f.vt.focusEvent.?(f.vt, .{ .gui = self, .window = win, .event = .{ .focusChanged = false } });
        }
        self.focused = .{
            .vt = vt,
            .win = win,
        };
        if (vt.focusEvent) |fc|
            fc(vt, .{ .gui = self, .window = win, .event = .{ .focusChanged = true } });
    }

    pub fn clampRectToWindow(self: *const Self, area: Rect) Rect {
        const wr = self.clamp_window.toAbsoluteRect();
        var other = area.toAbsoluteRect();
        //TODO do y axis aswell

        if (other.w > wr.w) {
            const diff = other.w - wr.w;
            other.w = wr.w;
            other.x -= diff;
        }

        if (other.x < wr.x)
            other.x = wr.x;

        if (other.h > wr.h) {
            const diff = other.h - wr.h;
            other.h = wr.h;
            other.y -= diff;
        }

        if (other.y < wr.y)
            other.y = wr.y;
        return graph.Rec(other.x, other.y, other.w - other.x, other.h - other.y);
    }

    pub fn isFocused(self: *Self, vt: *iArea) bool {
        if (self.focused) |f| {
            return f.vt == vt;
        }
        return false;
    }

    pub fn setTransientWindow(self: *Self, win: *iWindow) void {
        self.closeTransientWindow();
        self.transient_window = win;
        self.register(win.area, win);
        _ = self.transient_fbo.setSize(win.area.area.w, win.area.area.h) catch return;
    }

    pub fn closeTransientWindow(self: *Self) void {
        if (self.transient_window) |tw| {
            tw.deinit_fn(tw, self);
        }
        self.transient_window = null;
    }

    pub fn dispatchTextinput(self: *Self, cb: TextCbState) void {
        if (self.focused) |f| {
            if (f.vt.focusEvent) |func| {
                func(f.vt, .{ .gui = self, .window = f.win, .event = .{
                    .text_input = cb,
                } });
            }
        }
    }

    pub fn dispatchKeydown(self: *Self, state: KeydownState) void {
        self.dispatchFocusedEvent(.{ .keydown = state });
    }

    pub fn dispatchFocusedEvent(self: *Self, event: FocusedEvent.Event) void {
        if (self.focused) |f| {
            if (f.vt.focusEvent) |func|
                func(f.vt, .{ .gui = self, .window = f.win, .event = event });
        }
    }

    pub fn dispatchClick(self: *Self, mstate: MouseCbState, windows: []const *iWindow) void {
        if (self.transient_window) |tw| {
            if (tw.dispatchClick(mstate)) {
                return; //Don't click top level windows
            } else {
                //Close the window, we clicked outside
                self.closeTransientWindow();
            }
        }
        for (windows) |win| {
            if (win.dispatchClick(mstate))
                break;
        }
    }

    pub fn startTextinput(self: *Self, rect: Rect) void {
        self.text_input_enabled = true;
        self.sdl_win.startTextInput(rect);
    }

    pub fn stopTextInput(self: *Self) void {
        self.text_input_enabled = false;
        self.sdl_win.stopTextInput();
    }

    pub fn dispatchScroll(self: *Self, pos: Vec2f, dist: f32, windows: []const *iWindow) void {
        if (self.transient_window) |tw| {
            if (tw.dispatchScroll(pos, self, dist)) {
                return; //Don't click top level windows
            } else {
                //Close the window, we clicked outside
                self.closeTransientWindow();
            }
        }
        for (windows) |win| {
            if (win.dispatchScroll(pos, self, dist))
                break;
        }
    }

    ///TODO be carefull with this ptr,
    ///if the widget who gave this ptr is destroyed while mouse is grabbed we crash.
    ///how to solve?
    ///name vtables with ids
    ///on vt destroy, check and unset
    pub fn grabMouse(self: *Self, cb: MouseGrabFn, vt: *iArea, win: *iWindow, btn: MouseCbState.Btn) void {
        self.mouse_grab = .{ .win = win, .kind = .{ .btn = .{
            .cb = cb,
            .vt = vt,
            .btn = btn,
        } } };
    }

    pub fn addWindow(self: *Self, window: *iWindow, area: Rect, opts: struct { put_fbo: bool = true }) !WindowId {
        window.build_fn(window, self, area); //Rebuild it
        if (opts.put_fbo)
            try self.fbos.put(window, try graph.RenderTexture.init(area.w, area.h));
        self.register(window.area, window);
        try self.windows.append(self.alloc, window);

        return @enumFromInt(self.windows.items.len - 1);
    }

    pub fn updateWindowSize(self: *Self, window: *iWindow, area: Rect) !void {
        if (window.area.area.eql(area))
            return;
        if (self.fbos.getPtr(window)) |fbo| {
            _ = try fbo.setSize(area.w, area.h);
        }
        window.build_fn(window, self, area);
    }

    //pub fn updateSpecific(self: *Self, windows: []const *iWindow)!void{ }

    pub fn drawFbos(self: *Self, ctx: *Dctx) void {
        for (self.active_windows.items) |w| {
            const fbo = self.fbos.getPtr(w) orelse continue;
            drawFbo(w.area.area, fbo, ctx, self.tint);
        }

        if (self.transient_window) |tw| {
            drawFbo(tw.area.area, &self.transient_fbo, ctx, self.tint);
        }
    }

    pub fn draw(self: *Self, dctx: DrawState, force_redraw: bool) !void {
        defer {
            graph.c.glBindFramebuffer(graph.c.GL_FRAMEBUFFER, 0);
            graph.c.glViewport(0, 0, @intFromFloat(dctx.ctx.screen_dimensions.x), @intFromFloat(dctx.ctx.screen_dimensions.y));
            gl.disable(.scissor_test);
        }
        try dctx.ctx.flush(null, null);
        gl.enable(.depth_test);
        gl.enable(.blend);
        graph.c.glBlendFunc(graph.c.GL_SRC_ALPHA, graph.c.GL_ONE_MINUS_SRC_ALPHA);
        graph.c.glBlendEquation(graph.c.GL_FUNC_ADD);
        for (self.active_windows.items) |win| {
            const fbo = self.fbos.getPtr(win) orelse continue;
            try self.drawWindow(win, dctx, force_redraw, fbo);
        }
        if (self.transient_window) |tw| {
            try self.drawWindow(tw, dctx, force_redraw, &self.transient_fbo);
        }
    }

    fn drawWindow(self: *Self, win: *iWindow, dctx: DrawState, force_redraw: bool, fbo: *graph.RenderTexture) !void {
        gl.disable(.scissor_test);
        if (self.cached_drawing and !force_redraw) {
            if (win.draws_since_cached < 1 or win.draws_since_cached > self.max_cached_before_full_flush)
                return self.draw_all_window(dctx, win, fbo);

            fbo.bind(false);
            win.draw_scissor_state = .none;
            for (win.to_draw.items) |draw_area| {
                draw_area.draw(dctx, win);
            }
            try dctx.ctx.flush(win.area.area, null);
        } else {
            try self.draw_all_window(dctx, win, fbo);
        }
    }

    fn draw_all_window(self: *Self, dctx: DrawState, window: *iWindow, fbo: *graph.RenderTexture) !void {
        _ = self;
        window.draws_since_cached = 1;
        fbo.bind(true);
        window.draw_scissor_state = .none;
        window.draw(dctx);
        try dctx.ctx.flush(window.area.area, null);
    }

    pub fn drawFbo(area: Rect, fbo: *graph.RenderTexture, dctx: *Dctx, tint: u32) void {
        dctx.rectTexTint(
            area,
            graph.Rec(0, 0, area.w, -area.h),
            tint,
            fbo.texture,
        );
    }

    pub fn handleEvent(self: *Self, us: *const UpdateState, windows: []const *iWindow) !void {
        for (windows) |win|
            win.dispatchPoll(self);
        if (us.tab == .rising)
            self.tabFocus(!(us.shift == .high));

        const states = [_]ButtonState{ us.mouse.left, us.mouse.middle, us.mouse.right };
        const kinds = [states.len]MouseCbState.Btn{ .left, .middle, .right };

        if (self.mouse_grab) |grab| {
            if (grab.kind == .btn) {
                const btn = grab.kind.btn.btn;
                const gr = grab.kind.btn;
                for (states, 0..) |state, si| {
                    if (btn != kinds[si]) //When a mouse is grabbed, only eval that state
                        continue;
                    const mstate = MouseCbState{
                        .gui = self,
                        .pos = us.mouse.pos,
                        .delta = us.mouse.delta,
                        .state = state,
                        .btn = kinds[si],
                    };
                    switch (mstate.state) {
                        .rising => {
                            self.dispatchClick(mstate, windows);
                            break; //Only emit a single click event per update
                        },
                        .low => {
                            self.clearGrab();
                        },
                        .falling => {
                            gr.cb(gr.vt, mstate, grab.win);
                        },
                        .high => {
                            gr.cb(gr.vt, mstate, grab.win);
                            break;
                        },
                    }
                }
            }
        } else {
            for (states, 0..) |state, si| {
                if (state == .rising) {
                    const mstate = MouseCbState{ .gui = self, .pos = us.mouse.pos, .delta = us.mouse.delta, .state = state, .btn = kinds[si] };
                    self.dispatchClick(mstate, windows);
                    break;
                }
            }
        }

        {
            const keys = us.keys;
            if (keys.len > 0) {
                self.dispatchKeydown(.{ .keys = keys, .mod_state = us.mod });
            }
        }
        if (self.text_input_enabled and us.text.len > 0) {
            self.dispatchTextinput(.{
                .gui = self,
                .text = us.text,
                .mod_state = us.mod,
                .keys = us.keys,
            });
        }
        if (us.mouse.scroll.y != 0)
            self.dispatchScroll(us.mouse.pos, us.mouse.scroll.y, windows);
    }

    pub fn handleSdlEvents(self: *Self, windows: []const *iWindow) !void {
        const win = self.sdl_win;
        const us = UpdateState{
            .tab = win.keystate(.TAB),
            .shift = win.keystate(.LSHIFT),
            .mouse = .{
                .pos = win.mouse.pos,
                .delta = win.mouse.delta,
                .left = win.mouse.left,
                .right = win.mouse.right,
                .middle = win.mouse.middle,
                .scroll = win.mouse.wheel_delta,
            },
            .text = win.text_input,
            .mod = win.mod,
            .keys = win.keys.slice(),
        };
        if (ENABLE_TEST_BUILDER) {
            self.test_builder.emit(us);
        }
        try self.handleEvent(&us, windows);
    }
};

pub const GuiHelp = struct {
    pub fn drawWindowFrame(d: DrawState, area: Rect) void {
        const _br = d.style.getRect(.window);
        d.ctx.nineSlice(area, _br, d.style.texture, d.scale, d.tint);
    }

    pub fn insetAreaForWindowFrame(gui: *Gui, area: Rect) Rect {
        const _br = gui.style.getRect(.window);
        const border_area = area.inset((_br.h / 3) * gui.scale);
        return border_area;
    }
};

pub const Colorscheme = struct {
    bg: u32 = 0x4f4f4fff,
    //text_fg: u32 = 0xdbe0e0_ff,
    text_fg: u32 = 0xeeeeee_ff,
    text_bg: u32 = 0x333333_ff,
    textbox_bg: u32 = 0x333333_ff,
    drop_down_arrow: u32 = 0xe0e0e0_ff,
    caret: u32 = 0xaaaaaaff,

    table_bg: u32 = 0x333333_ff,
    static_slider_bg: u32 = 0x333333_ff,
};

pub const DarkColorscheme = Colorscheme{
    .bg = 0x4f4f4fff,
    .text_fg = 0xeeeeee_ff,
    .text_bg = 0x333333_ff,
    .textbox_bg = 0x333333_ff,
    .drop_down_arrow = 0xe0e0e0_ff,
    .caret = 0xaaaaaaff,

    .table_bg = 0x333333_ff,
    .static_slider_bg = 0x333333_ff,
};

pub const LightColorscheme = Colorscheme{
    .bg = 0xd8d8d8ff,
    .text_fg = 0xff,
    .text_bg = 0xd8d8d8ff,
    .textbox_bg = 0xa8a8a8ff,
    .drop_down_arrow = 0xff,
    .caret = 0xff,

    .table_bg = 0xd8d8d8ff,
    .static_slider_bg = 0xd8d8d8ff,
};

pub const Style = struct {
    caret_width: f32 = 2,
    color: Colorscheme = LightColorscheme,
};
