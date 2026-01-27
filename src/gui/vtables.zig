const std = @import("std");
pub const graph = @import("../graphics.zig");
const Os9Gui = @import("../gui_app.zig");
pub const Dctx = graph.ImmediateDrawingContext;
const builtin = @import("builtin");
const IS_DEBUG = builtin.mode == .Debug;
//TODO deprecate this style
pub const GuiConfig = Os9Gui.GuiConfig;
pub const Rect = graph.Rect;
pub const Rec = graph.Rec;
pub const Uid = u64;
const gl = graph.GL;
const ArrayList = std.ArrayList;
const AL = std.mem.Allocator;

// To support nested child windows:
//
// add a child: ?*iWindow field to iWindow
//
// store a window depth?
//
// depth = 0
//
// only a single window of any depth > 0 can exist at any time
//
// this implies only a single root window can have children at a time
//

pub const CbHandle = struct {
    pub fn cast(self: *@This(), comptime T: type, comptime name: []const u8) *T {
        return @alignCast(@fieldParentPtr(name, self));
    }
};
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
    pub const ComboItem = co.ComboItem;
    pub const ComboUser = co.ComboUser;
    pub const ComboVoid = co.ComboUser(void);
    pub const ComboCommitParam = co.CommitParam;
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

pub const WgStatus = enum {
    failed,
    good,
};
//TODO store a depth and sort to_draw by depth
pub const iArea = struct {
    /// Decl'd so we can grep for undefined and not get confused
    pub const UNINITILIZED: iArea = undefined;
    pub const Args = struct {
        deinit_fn: DeinitFn,
        area: Rect = .Empty,
        draw_fn: ?DrawFn = null,
        focus_ev_fn: ?FocusEventFn = null,

        onclick: ?OnClick = null,
        onscroll: ?Onscroll = null,
        onpoll: ?Onpoll = null,

        can_tab_focus: bool = false,
    };
    pub const OnClick = *const fn (*iArea, MouseCbState, *iWindow) void;
    pub const Onscroll = *const fn (*iArea, *Gui, *iWindow, distance: f32) void;
    pub const FocusEventFn = *const fn (*iArea, FocusedEvent) void;
    pub const Onpoll = *const fn (*iArea, *Gui, *iWindow) void;
    pub const DrawFn = *const fn (*iArea, *Gui, *DrawState) void;
    pub const DeinitFn = *const fn (*iArea, *Gui, *iWindow) void;

    deinit_fn: DeinitFn,
    area: Rect,
    children: ArrayList(*iArea) = .{},

    draw_fn: ?DrawFn = null,
    focus_ev_fn: ?FocusEventFn = null,

    can_tab_focus: bool = false,
    is_dirty: bool = false,

    parent: ?*iArea = null,
    /// index of self as child of parent
    index: u32 = 0,
    depth: u16 = 0,

    _scissor_id: ScissorId = .none,

    win_ptr: *iWindow,

    /// Use as follows:
    /// self.* = .{.vt = .UNINITILIZED, .my_other = 0};
    /// parent.addChild(&self.vt, .{.deinit_fn = deinit});
    pub fn addChild(parent: *iArea, reserved_memory: *iArea, args: Args) void {
        reserved_memory.* = .{
            .depth = parent.depth + 1,
            .deinit_fn = args.deinit_fn,
            .area = args.area,
            .draw_fn = args.draw_fn,
            .focus_ev_fn = args.focus_ev_fn,
            .win_ptr = parent.win_ptr,
            ._scissor_id = parent._scissor_id,
            .index = @intCast(parent.children.items.len),
            .parent = parent,
            .can_tab_focus = args.can_tab_focus,
        };
        const gui = parent.win_ptr.gui_ptr;
        const win = parent.win_ptr;
        const new = reserved_memory;
        // Propogate the scissor. Default is .none so no need to check
        if (parent.children.items.len >= std.math.maxInt(u32)) @panic("too many widgets");

        parent.children.append(gui.alloc, new) catch @panic("failed to attach child");
        gui.register(new, win);
        gui.setDirty(new, win);

        if (args.onclick) |onclick|
            gui.registerOnClick(new, onclick, win) catch return;
        if (args.onscroll) |onscroll|
            gui.regOnScroll(new, onscroll, win) catch return;
        if (args.onpoll) |onpoll|
            win.registerPoll(new, onpoll) catch return;
    }

    pub fn getLastChild(self: *@This()) ?*iArea {
        return self.children.getLastOrNull();
    }

    pub fn deinit(self: *@This(), gui: *Gui, win: *iWindow) void {
        self.clearChildren(gui, win);
        self.children.deinit(gui.alloc);
        self.deinit_fn(self, gui, win);
    }

    pub fn draw(self: *@This(), gui: *Gui, dctx: *DrawState, window: *iWindow) void {
        if (gui.needsDraw(self, window)) {
            window.checkScissor(self, dctx);
            if (self.draw_fn) |drawf|
                drawf(self, gui, dctx);
            for (self.children.items) |child|
                child.draw(gui, dctx, window);
        }
        self.is_dirty = false;
    }

    pub fn dirty(self: *@This()) void {
        if (!self.is_dirty) {
            self.win_ptr.gui_ptr.setDirty(self, self.win_ptr);
        }
        self.is_dirty = true;
    }

    pub fn deinitEmpty(vt: *iArea, gui: *Gui, _: *iWindow) void {
        gui.alloc.destroy(vt);
    }

    pub fn addEmpty(self: *@This(), area: Rect) *iArea {
        const gui = self.win_ptr.gui_ptr;
        const vt = gui.alloc.create(iArea) catch unreachable;
        self.addChild(vt, .{
            .area = area,
            .deinit_fn = deinitEmpty,
        });
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

    fn depthLessThan(_: void, lhs: *iArea, rhs: *iArea) bool {
        return lhs.depth < rhs.depth;
    }
};

pub const ScissorId = enum(u8) { none = std.math.maxInt(u8), _ };

pub fn label(lay: *iArea, area_o: ?Rect, comptime fmt: []const u8, args: anytype) ?Rect {
    const area = area_o orelse return null;
    const sp = area.split(.vertical, area.w / 2);
    _ = Widget.Text.build(lay, sp[0], fmt, args, .{});
    return sp[1];
}

pub const iWindow = struct {
    const Background = union(enum) {
        window,
        color: u32,
        none,
    };
    pub const InitArgs = struct {
        area: Rect = .Empty,
        bg: Background = .{ .window = {} },
    };
    const BuildfnT = *const fn (*iWindow, *Gui, Rect) void;

    build_fn: BuildfnT,
    deinit_fn: *const fn (*iWindow, *Gui) void,
    update_fn: ?*const fn (*iWindow, *Gui) void = null,

    area: iArea,
    alloc: std.mem.Allocator,
    gui_ptr: *Gui,

    click_listeners: ArrayList(struct { *iArea, iArea.OnClick }) = .{},
    scroll_list: ArrayList(struct { *iArea, iArea.Onscroll }) = .{},
    poll_listeners: ArrayList(struct { ?*iArea, iArea.Onpoll }) = .{},

    cache_map: std.AutoArrayHashMapUnmanaged(*iArea, void) = .{},
    to_draw: ArrayList(*iArea) = .{},
    draws_since_cached: i32 = 0,
    needs_rebuild: bool = false,

    /// ScissorId indexes into this
    scissors: ArrayList(?struct { *iArea, Rect }) = .{},

    draw_scissor_state: ScissorId = .none,
    bg: Background,

    pub fn draw(self: *iWindow, gui: *Gui, dctx: *DrawState) void {
        self.area.draw(gui, dctx, self);
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
                graph.gl.Scissor(
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

    /// Use as follows:
    /// const mywin = alloc.create(MyWin);
    /// mywin.* = .{.vt = .init(build, gui, deinit, .{}, &mywin.vt)};
    ///
    /// Returning the pointer.* is goofy, but it means we can avoid setting .vt = undefined
    /// optimizer hopefully removes the copy
    pub fn init(build_fn: BuildfnT, gui: *Gui, deinit_fn: *const fn (*iWindow, *Gui) void, args: InitArgs, reserved_memory: *iWindow) iWindow {
        reserved_memory.* = .{
            .gui_ptr = gui,
            .bg = args.bg,
            .alloc = gui.alloc,
            .deinit_fn = deinit_fn,
            .build_fn = build_fn,
            .area = .{ .deinit_fn = deinit_area, .area = args.area, .draw_fn = draw_area, .win_ptr = reserved_memory },
        };
        return reserved_memory.*;
    }

    fn deinit_area(_: *iArea, _: *Gui, _: *iWindow) void {}
    fn draw_area(vt: *iArea, _: *Gui, dctx: *DrawState) void {
        const self: *iWindow = @alignCast(@fieldParentPtr("area", vt));
        switch (self.bg) {
            .window => GuiHelp.drawWindowFrame(dctx, self.area.area),
            .none => {},
            .color => |col| dctx.ctx.rect(self.area.area, col),
        }
        //GuiHelp.drawWindowFrame(d, vt.area);
    }

    // the implementers deinit fn should call this first
    pub fn deinit(self: *iWindow, gui: *Gui) void {
        //self.layout.vt.deinit_fn(&self.layout.vt, gui, self);
        gui.deregister(&self.area, self);
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

    fn pre_update(win: *iWindow, gui: *Gui) void {
        win.to_draw.clearRetainingCapacity();
        win.cache_map.clearRetainingCapacity();
        if (win.needs_rebuild) {
            win.needs_rebuild = false;
            win.draws_since_cached = 0;
            //var time = try std.time.Timer.start();
            win.build_fn(win, gui, win.area.area);
            //std.debug.print("Built win in: {d:.2} us\n", .{time.read() / std.time.ns_per_us});
        }

        if (win.update_fn) |upfn|
            upfn(win, gui);
    }

    /// Returns true if this window contains the mouse
    pub fn dispatchClick(win: *iWindow, cb: MouseCbState) bool {
        if (!win.area.area.containsPoint(cb.pos)) return false;
        var i: usize = win.click_listeners.items.len;
        //Iterate backwards so deeper widgets have priority
        while (i > 0) : (i -= 1) {
            const click = win.click_listeners.items[i - 1];
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

    pub fn registerPoll(win: *iWindow, vt: *iArea, onpoll: iArea.Onpoll) !void {
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
    font: *graph.FontInterface,
    style: GuiConfig,
    nstyle: Style,
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

    pub fn minWidgetWidth(self: *const @This(), string: []const u8) f32 {
        const bound = self.font.textBounds(string, self.style.config.text_h);

        const inset = @max((self.style.config.default_item_h - self.style.config.text_h), 0);
        return bound.x + inset;
    }

    pub fn textArea(self: *const @This(), area: Rect) Rect {
        const inset = @max((area.h - self.style.config.text_h) / 2, 0);
        return area.inset(inset);
    }

    pub fn vlayout(self: *const @This(), area: Rect) VerticalLayout {
        return .{
            .item_height = self.style.config.default_item_h,
            .bounds = area,
            .padding = self.nstyle.vlayout_padding,
        };
    }

    pub fn hlayout(_: *const @This(), area: Rect, count: usize) HorizLayout {
        return .{ .bounds = area, .count = count };
    }

    pub fn tlayout(self: *const @This(), area: Rect, count: u32) TableLayout {
        return .{
            .item_height = self.style.config.default_item_h,
            .bounds = area,
            .columns = count,
        };
    }

    pub fn box(
        self: *const @This(),
        area: Rect,
        opts: struct {
            bg: u32 = 0,
            inner: u32 = 0,
            border: u32 = 0,
            text: []const u8 = "",
            text_fg: u32 = 0xff,
            border_mask: u8 = 0b1111, //top right bottom left
        },
    ) void {
        if (opts.bg > 0) self.ctx.rect(area, opts.bg);
        const bw = @ceil(self.scale);
        const inset = area.inset(bw);

        if (opts.inner > 0) self.ctx.rect(inset, opts.inner);

        if (opts.text.len > 0) {
            const ta = self.textArea(area);
            self.ctx.textClipped(ta, "{s}", .{opts.text}, self.textP(opts.text_fg), .center);
        }

        if (opts.border > 0) {
            for (0..4) |bi| {
                if (opts.border_mask & (@as(u8, 1) << @as(u3, @intCast(bi))) == 0) continue;
                const col = opts.border;
                const r = area;
                switch (bi) {
                    3 => self.ctx.rect(.{ .x = r.x, .y = r.y, .w = r.w, .h = bw }, col),
                    0 => self.ctx.rect(.{ .x = r.x + r.w - bw, .y = r.y, .w = bw, .h = r.h }, col),
                    1 => self.ctx.rect(.{ .x = r.x, .y = r.y + r.h - bw, .w = r.w, .h = bw }, col),
                    2 => self.ctx.rect(.{ .x = r.x, .y = r.y, .w = bw, .h = r.h }, col),
                    else => {},
                }
            }
        }
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

pub const Gui = struct {
    const Self = @This();
    pub const MouseGrabFn = *const fn (*iArea, MouseCbState, *iWindow) void;
    pub const TextinputFn = *const fn (*iArea, TextCbState, *iWindow) void;
    const Focused = struct {
        vt: *iArea,
        win: *iWindow,
    };

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

    focused: ?Focused = null,

    fbos: std.AutoHashMap(*iWindow, graph.RenderTexture),
    transient_fbo: graph.RenderTexture,

    area_window_map: std.AutoArrayHashMapUnmanaged(*iArea, *iWindow) = .{},

    draws_since_cached: i32 = 0,
    max_cached_before_full_flush: i32 = 60 * 10, //Ten seconds
    cached_drawing: bool = true,
    clamp_window: Rect,

    text_input_enabled: bool = false,
    sdl_win: *graph.SDL.Window,

    dstate: DrawState,

    pub fn init(alloc: AL, win: *graph.SDL.Window, cache_dir: std.fs.Dir, style_dir: std.fs.Dir, font: *graph.FontInterface, dctx: *graph.ImmediateDrawingContext) !Self {
        return Gui{
            .alloc = alloc,
            .clamp_window = graph.Rec(0, 0, win.screen_dimensions.x, win.screen_dimensions.y),
            .transient_fbo = try graph.RenderTexture.init(100, 100),
            .fbos = std.AutoHashMap(*iWindow, graph.RenderTexture).init(alloc),
            .sdl_win = win,
            .dstate = .{
                .ctx = dctx,
                .font = font,
                .style = try GuiConfig.init(alloc, style_dir, "asset/os9gui", cache_dir),
                .nstyle = .{},
                .scale = 1,
                .tint = 0xffff_ffff,
            },
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
        self.dstate.style.deinit();
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
        if (self.getFocused()) |f| {
            if (fwd) {
                if (findNextFocusTarget(f.vt)) |next| {
                    self.grabFocus(next, f.win);
                } else if (findFocusTargetNoBacktrack(&f.win.area)) |next| { //Start from the root of the window
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

    pub fn registerOnClick(_: *Self, vt: *iArea, onclick: iArea.OnClick, window: *iWindow) !void {
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
            if (!self.isWindowActive(f.win)) {
                //send lost focus event to widget in non active window
                self.dispatchFocusedEvent(.{ .focusChanged = false });
                self.focused = null;
            }
        }
        for (self.active_windows.items) |win| {
            win.pre_update(self);
        }
        if (self.transient_window) |tw| {
            tw.pre_update(self);
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

    pub fn regOnScroll(_: *Self, vt: *iArea, onscroll: iArea.Onscroll, window: *iWindow) !void {
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
            if (f.vt != vt and f.vt.focus_ev_fn != null)
                f.vt.focus_ev_fn.?(f.vt, .{ .gui = self, .window = win, .event = .{ .focusChanged = false } });
        }
        self.focused = .{
            .vt = vt,
            .win = win,
        };
        if (vt.focus_ev_fn) |fc|
            fc(vt, .{ .gui = self, .window = win, .event = .{ .focusChanged = true } });
    }

    pub fn clampRectToWindow(self: *const Self, area: Rect) Rect {
        const wr = self.clamp_window.toAbsoluteRect();
        var other = area.toAbsoluteRect();

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

    fn getFocused(self: *Self) ?Focused {
        if (self.mouse_grab) |mg| {
            if (mg.kind == .override)
                return null;
        }

        return self.focused;
    }

    pub fn isFocused(self: *Self, vt: *iArea) bool {
        if (self.getFocused()) |f| {
            return f.vt == vt;
        }
        return false;
    }

    pub fn setTransientWindow(self: *Self, win: *iWindow) void {
        self.closeTransientWindow();
        self.transient_window = win;
        win.area.area.x = @round(win.area.area.x);
        win.area.area.y = @round(win.area.area.y);
        win.area.area.w = @round(win.area.area.w);
        win.area.area.h = @round(win.area.area.h);
        self.register(&win.area, win);
        _ = self.transient_fbo.setSize(win.area.area.w, win.area.area.h) catch return;
    }

    pub fn closeTransientWindow(self: *Self) void {
        if (self.transient_window) |tw| {
            tw.deinit_fn(tw, self);
        }
        self.transient_window = null;
    }

    pub fn dispatchTextinput(self: *Self, cb: TextCbState) void {
        if (self.getFocused()) |f| {
            if (f.vt.focus_ev_fn) |func| {
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
        if (self.getFocused()) |f| {
            if (f.vt.focus_ev_fn) |func|
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
        self.register(&window.area, window);
        try self.windows.append(self.alloc, window);

        return @enumFromInt(self.windows.items.len - 1);
    }

    pub fn updateWindowSize(self: *Self, window: *iWindow, ar: Rect) !void {
        const area: Rect = .new(@round(ar.x), @round(ar.y), @round(ar.w), @round(ar.h));
        if (window.area.area.eql(area))
            return;
        if (self.fbos.getPtr(window)) |fbo| {
            _ = try fbo.setSize(area.w, area.h);
        }
        if (self.transient_window != null and self.transient_window.? == window) {
            _ = try self.transient_fbo.setSize(area.w, area.h);
        }
        window.build_fn(window, self, area);
    }

    //pub fn updateSpecific(self: *Self, windows: []const *iWindow)!void{ }

    pub fn drawFbos(self: *Self) void {
        for (self.active_windows.items) |w| {
            const fbo = self.fbos.getPtr(w) orelse continue;
            drawFbo(w.area.area, fbo, self.dstate.ctx, self.dstate.tint);
        }

        if (self.transient_window) |tw| {
            drawFbo(tw.area.area, &self.transient_fbo, self.dstate.ctx, self.dstate.tint);
        }
    }

    pub fn draw(self: *Self, force_redraw: bool) !void {
        const dctx = &self.dstate;
        defer {
            graph.gl.BindFramebuffer(graph.gl.FRAMEBUFFER, 0);
            graph.gl.Viewport(0, 0, @intFromFloat(dctx.ctx.screen_dimensions.x), @intFromFloat(dctx.ctx.screen_dimensions.y));
            gl.disable(.scissor_test);
        }
        try dctx.ctx.flush(null, null);
        gl.enable(.depth_test);
        gl.enable(.blend);
        graph.gl.BlendFunc(graph.gl.SRC_ALPHA, graph.gl.ONE_MINUS_SRC_ALPHA);
        graph.gl.BlendEquation(graph.gl.FUNC_ADD);
        for (self.active_windows.items) |win| {
            const fbo = self.fbos.getPtr(win) orelse continue;
            try self.drawWindow(win, dctx, force_redraw, fbo);
        }
        if (self.transient_window) |tw| {
            try self.drawWindow(tw, dctx, force_redraw, &self.transient_fbo);
        }
    }

    fn drawWindow(self: *Self, win: *iWindow, dctx: *DrawState, force_redraw: bool, fbo: *graph.RenderTexture) !void {
        gl.disable(.scissor_test);
        if (self.cached_drawing and !force_redraw) {
            if (win.draws_since_cached < 1 or win.draws_since_cached > self.max_cached_before_full_flush)
                return self.draw_all_window(dctx, win, fbo);

            fbo.bind(false);
            win.draw_scissor_state = .none;

            // prevent out of order calls to .dirty from creating bad draws
            std.sort.heap(*iArea, win.to_draw.items, {}, iArea.depthLessThan);

            for (win.to_draw.items) |draw_area| {
                draw_area.draw(self, dctx, win);
            }
            try dctx.ctx.flush(win.area.area, null);
        } else {
            try self.draw_all_window(dctx, win, fbo);
        }
    }

    fn draw_all_window(self: *Self, dctx: *DrawState, window: *iWindow, fbo: *graph.RenderTexture) !void {
        window.draws_since_cached = 1;
        fbo.bind(true);
        window.draw_scissor_state = .none;
        window.draw(self, dctx);
        try dctx.ctx.flush(window.area.area, null);
    }

    pub fn drawFbo(area: Rect, fbo: *graph.RenderTexture, dctx: *Dctx, tint: u32) void {
        if (@as(i32, @intFromFloat(area.w)) != fbo.w or @as(i32, @intFromFloat(area.h)) != fbo.h) {
            if (IS_DEBUG)
                std.debug.print("Fbo is mismatched size {d} {d} {d} {d}\n", .{ area.w, area.h, fbo.w, fbo.h });
        }
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
            self.dispatchScroll(us.mouse.pos, us.mouse.scroll.y * -1, windows);
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
        try self.handleEvent(&us, windows);
    }
};

pub const GuiHelp = struct {
    pub fn drawWindowFrame(d: *DrawState, area: Rect) void {
        d.box(area, .{
            .bg = d.nstyle.color.window_bg,
            //.border = d.nstyle.color.window_border,
        });
        //const _br = d.style.getRect(.window);
        //d.ctx.nineSlice(area, _br, d.style.texture, d.scale, d.tint);
    }

    pub fn insetAreaForWindowFrame(gui: *Gui, area: Rect) Rect {
        const _br = gui.dstate.style.getRect(.window);
        const border_area = area.inset((_br.h / 3) * gui.dstate.scale);
        return border_area;
    }
};

fn gray(value: u8) u32 {
    const v: u32 = value;
    return 0xff | v << 24 | v << 16 | v << 8;
}

const shade = [_]u32{
    gray(0),
    gray(0x22),
    gray(0x40),
    gray(0x60),
    gray(0x80),
    gray(0xa0),
    gray(0xc0),
    gray(0xee),
    gray(0xff),
};
const ms = shade.len - 1;

const BoxScheme = struct {
    bg: u32 = 0,
    border: u32 = 0,
    text: u32 = 0,
    inner: u32 = 0,
};

const DarkText = 0xeeeeee_ff;
const DarkBg: u32 = 0x4f4f4f_ff;
const DarkBg2: u32 = 0x222222_ff;
pub const Colorscheme = struct {
    window_bg: u32 = shade[1],
    window_border: u32 = shade[0],
    bg: u32 = shade[1],
    bg2: u32 = shade[2],
    //text_fg: u32 = 0xdbe0e0_ff,
    text_fg: u32 = 0xeeeeee_ff,
    text_bg: u32 = 0x333333_ff,
    text_disabled: u32 = shade[5],
    text_highlight: u32 = 0xc655c1_88,
    textbox_bg: u32 = 0x333333_ff,
    textbox_border: u32 = 0xff,
    drop_down_arrow: u32 = 0xe0e0e0_ff,
    caret: u32 = 0xaaaaaaff,

    selection: u32 = 0x274e91ff,

    table_bg: u32 = 0x333333_ff,
    static_slider_bg: u32 = 0x333333_ff,
    //static_slider_fill: u32 = 0xf7a41dff,
    static_slider_fill: u32 = 0xb57527_ff,

    ableton_checkbox: struct {
        true: BoxScheme = .{
            .bg = shade[4],
            .inner = 0x294677_ff,
            .text = shade[7],
            .border = 0x4d7dd1_ff,
        },
        false: BoxScheme = .{
            .bg = shade[4],
            .text = shade[0],
            .border = shade[5],
        },
    } = .{},

    ableton_checkbox_bg: u32 = shade[4],
    ableton_checkbox_fill: u32 = 0x274e91ff,
    ableton_checkbox_text: u32 = shade[0],
    ableton_checkbox_text_fill: u32 = shade[7],
    ableton_checkbox_border: u32 = shade[6],
    ableton_checkbox_border_fill: u32 = shade[7],

    combo_bg: u32 = shade[2],
    combo_border: u32 = shade[0],
    combo_arrow: u32 = shade[6],
    combo_text: u32 = shade[7],

    button_bg: u32 = shade[2],
    button_active_bg: u32 = shade[1],
    button_focused_bg: u32 = shade[3],
    button_border: u32 = shade[0],
    button_text: u32 = shade[7],
    button_text_disable: u32 = shade[5],

    tab_bg: u32 = shade[2],
    tab_active_bg: u32 = shade[1],
    tab_active_text_fg: u32 = shade[7],
    tab_text_fg: u32 = shade[6],
    tab_border: u32 = shade[5],

    scrollbar_bg: u32 = DarkBg2,
    scrollbar_border: u32 = 0xff,

    shuttle_bg: u32 = 0x6f6f6f_ff,
    shuttle_border: u32 = 0xff,
};

pub const DarkColorscheme = Colorscheme{
    .bg = 0x4f4f4fff,
    .text_fg = DarkText,
    .text_bg = 0x333333_ff,
    .textbox_bg = 0x333333_ff,
    .textbox_border = 0xff,
    .drop_down_arrow = 0xe0e0e0_ff,
    .caret = 0xaaaaaaff,

    .table_bg = 0x333333_ff,
    .static_slider_bg = 0x333333_ff,

    .ableton_checkbox_bg = 0x222222_ff,
    .ableton_checkbox_fill = 0x08538c_ff,
    .ableton_checkbox_text = DarkText,
    .ableton_checkbox_border = 0xff,
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
    vlayout_padding: graph.Padding = .{
        .top = 1,
        .bottom = 1,
        .left = 0,
        .right = 0,
    },

    caret_width: f32 = 2,

    tab_spacing: f32 = 20,

    color: Colorscheme = .{},
};
