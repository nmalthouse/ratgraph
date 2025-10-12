const g = @import("vtables.zig");
const iArea = g.iArea;
const graph = g.graph;
const std = @import("std");
const Gui = g.Gui;
const Rect = g.Rect;
const iWindow = g.iWindow;
const Color = graph.Colori;
const CbHandle = g.CbHandle;

fn charsetForNum(comptime T: type) []const u8 {
    const info = @typeInfo(T);
    switch (info) {
        .float => return "ainf.-0123456789",
        .int => |int| switch (int.signedness) {
            .signed => return "-0123456789xabcdefABCDEF",
            .unsigned => return "0123456789xabcdefABCDEF",
        },
        else => @compileError("invalid number type"),
    }
}
fn getNumtype(comptime T: type) enum { float, int, uint } {
    return switch (@typeInfo(T)) {
        .float => .float,
        .int => |int| switch (int.signedness) {
            .signed => .int,
            .unsigned => .uint,
        },
        else => @compileError("invalid number type"),
    };
}

pub fn NumberDummy(comptime T: type) type {
    return struct {
        const charset = charsetForNum(T);
        const num_type = getNumtype(T);
        vt: iArea,

        __value: T,
        ptr: *T,

        pub fn build(gui: *Gui, area: Rect, number: ?*T, default: T) g.NewVt {
            const self = gui.create(@This());
            self.* = .{
                .__value = default,
                .ptr = number orelse &self.__value,
                .vt = .{ .area = area, .deinit_fn = deinit },
            };
            return .{ .vt = &self.vt };
        }

        pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
            const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
            gui.alloc.destroy(self);
        }

        pub fn printTo(vt: *iArea, arraylist: *std.ArrayList(u8)) void {
            const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
            arraylist.writer().print("{d:.2}", .{self.ptr.*}) catch return;
        }

        pub fn parseFrom(vt: *iArea, slice: []const u8) error{invalid}!void {
            const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
            self.ptr.* = switch (num_type) {
                .float => std.fmt.parseFloat(T, slice) catch return error.invalid,
                .uint, .int => std.fmt.parseInt(T, slice, 0) catch return error.invalid,
            };
        }
    };
}

pub const TextboxNumber = struct {
    pub fn build(gui: *Gui, area_o: ?Rect, number: anytype, win: *iWindow, opts: TextboxOptions) ?g.NewVt {
        const area = area_o orelse return null;
        //const invalid_type_error = "wrong type for textbox number!";
        const pinfo = @typeInfo(@TypeOf(number));
        const is_pointer = (pinfo == .pointer);
        const number_type = if (is_pointer) pinfo.pointer.child else @TypeOf(number);
        const ND = NumberDummy(number_type);

        var opt = opts;
        opt.restricted_charset = charsetForNum(number_type);
        const dummy = ND.build(gui, area, if (is_pointer) number else null, if (is_pointer) 0 else number);
        dummy.vt.addChild(gui, win, Textbox.buildNumber(
            gui,
            area,
            dummy.vt,
            &ND.printTo,
            &ND.parseFrom,

            opt,
        ) orelse return dummy);

        return dummy;
    }
};

pub const NumberPrintFn = *const fn (*iArea, *std.ArrayList(u8)) void;
pub const NumberParseFn = *const fn (*iArea, []const u8) error{invalid}!void;

pub const TextboxOptions = struct {
    commit_cb: ?*const fn (*CbHandle, *Gui, []const u8, user_id: usize) void = null,
    commit_vt: ?*CbHandle = null,
    user_id: usize = 0,

    init_string: []const u8 = "",
    commit_when: enum { on_enter, never, on_change } = .on_enter,

    clear_on_commit: bool = false,

    restricted_charset: ?[]const u8 = null,
    invert_restriction: bool = false,
};

//Can we stick some kind of comptime thing as a child of this that gets set with number?
//onFocus, needs to call printNumber
const utf8 = @import("../utf8.zig");
pub const Textbox = struct {
    const Utf8It = utf8.BiDirectionalUtf8Iterator;
    const Self = @This();
    const uni = std.unicode;
    const M = graph.SDL.keycodes.Keymod;
    const None = M.mask(&.{.NONE});
    //TODO make this configurable
    const edit_keys_list = graph.Bind(&.{
        .{ .name = "commit", .bind = .{ .RETURN, None } },
        .{ .name = "backspace", .bind = .{ .BACKSPACE, None } },
        .{ .name = "delete", .bind = .{ .DELETE, None } },
        .{ .name = "delete_word_right", .bind = .{ .DELETE, M.mask(&.{.LCTRL}) } },
        .{ .name = "delete_word_left", .bind = .{ .BACKSPACE, M.mask(&.{.LCTRL}) } },
        .{ .name = "move_left", .bind = .{ .LEFT, None } },
        .{ .name = "move_word_left", .bind = .{ .LEFT, M.mask(&.{.LCTRL}) } },
        .{ .name = "move_right", .bind = .{ .RIGHT, None } },
        .{ .name = "move_word_right", .bind = .{ .RIGHT, M.mask(&.{.LCTRL}) } },
        .{ .name = "select_right", .bind = .{ .RIGHT, M.mask(&.{.LSHIFT}) } },
        .{ .name = "select_left", .bind = .{ .LEFT, M.mask(&.{.LSHIFT}) } },
        .{ .name = "select_word_right", .bind = .{ .RIGHT, M.mask(&.{ .LCTRL, .LSHIFT }) } },
        .{ .name = "select_word_left", .bind = .{ .LEFT, M.mask(&.{ .LCTRL, .LSHIFT }) } },
        //TODO Should "A" be a keycode not a scancode? On dvorak ctrl-a,z,x,c,v are all remapped. What happens with non english keyboard layouts.
        .{ .name = "select_all", .bind = .{ .A, M.mask(&.{.LCTRL}) } },
        .{ .name = "copy", .bind = .{ .C, M.mask(&.{.LCTRL}) } },
        .{ .name = "paste", .bind = .{ .V, M.mask(&.{.LCTRL}) } },
    });

    //TODO These should be configurable
    const setClipboard: fn (std.mem.Allocator, []const u8) std.mem.Allocator.Error!void = graph.SDL.Window.setClipboard;
    const getClipboard: fn (std.mem.Allocator) std.mem.Allocator.Error![]const u8 = graph.SDL.Window.getClipboard;

    const SingleLineMovement = enum {
        left,
        right,
        next_word_end,
        prev_word_end,
        start,
        end,
    };

    vt: iArea,
    cbhandle: CbHandle = .{},
    codepoints: std.ArrayList(u8),

    options: struct {
        max_len: ?usize = null,
    } = .{},

    opts: TextboxOptions = .{},

    number: ?struct {
        print_cb: NumberPrintFn,
        parse_cb: NumberParseFn,
        vt: *iArea,
    } = null,

    head: usize,
    tail: usize,
    /// start drawing at this codepoint, for text that overflows the box
    draw_start: usize = 0,
    changed: bool = false,

    fn select_to(self: *Self, movement: SingleLineMovement) void {
        const indexOfScalar = std.mem.indexOfScalar;
        switch (movement) {
            .left => {
                _ = Utf8It.prevCodepointSlice(&self.head, self.codepoints.items);
            },
            .right => {
                _ = Utf8It.nextCodepointSlice(&self.head, self.codepoints.items);
            },
            .prev_word_end => { //Move the caret to the first letter of the current word.
                while (Utf8It.prevCodepoint(&self.head, self.codepoints.items)) |cp| {
                    _ = indexOfScalar(u21, &utf8.unicode_space_seperator, cp) orelse break;
                } //This moves head backward to the first non whitespace character

                while (Utf8It.currentCodepoint(self.head, self.codepoints.items)) |cp| {
                    if (indexOfScalar(u21, &utf8.unicode_space_seperator, cp)) |_| {
                        _ = Utf8It.nextCodepointSlice(&self.head, self.codepoints.items);
                        break;
                    }
                    _ = Utf8It.prevCodepointSlice(&self.head, self.codepoints.items) orelse break;
                }
            },
            .next_word_end => {
                //First, skip over any whitespace, then seek till first whitespace or last char
                while (Utf8It.currentCodepoint(self.head, self.codepoints.items)) |cp| {
                    _ = indexOfScalar(u21, &utf8.unicode_space_seperator, cp) orelse break;
                    _ = Utf8It.nextCodepointSlice(&self.head, self.codepoints.items);
                } //This moves head forward to the first non whitespace character or end of string (len)

                while (Utf8It.currentCodepoint(self.head, self.codepoints.items)) |cp| {
                    if (indexOfScalar(u21, &utf8.unicode_space_seperator, cp)) |_| break;
                    _ = Utf8It.nextCodepointSlice(&self.head, self.codepoints.items);
                } //This moves head forward to the first whitespace character or eos
            },
            .start => self.head = 0,
            .end => self.head = self.codepoints.items.len,
        }
    }

    fn move_to(self: *Self, movement: SingleLineMovement) void {
        self.select_to(movement);
        self.tail = self.head;
    }

    fn delete_to(self: *Self, movement: SingleLineMovement) !void {
        self.select_to(movement);
        try self.deleteSelection();
    }

    //pub fn init(alloc: std.mem.Allocator) Self {
    //    return Self{ .codepoints = std.ArrayList(u8).init(alloc), .head = 0, .tail = 0 };
    //}

    pub fn build(gui: *Gui, area_o: ?Rect) ?g.NewVt {
        return buildOpts(gui, area_o, .{});
    }

    pub fn buildOpts(gui: *Gui, area_o: ?Rect, opts: TextboxOptions) ?g.NewVt {
        const area = area_o orelse return null;
        const self = gui.create(@This());
        self.* = .{
            .vt = .{ .area = area, .deinit_fn = deinit, .draw_fn = draw, .focusEvent = fevent },
            .codepoints = std.ArrayList(u8).init(gui.alloc),
            .opts = opts,
            .head = 0,
            .tail = 0,
        };
        self.codepoints.appendSlice(opts.init_string) catch return null;
        self.vt.can_tab_focus = true;
        return .{ .vt = &self.vt, .onclick = onclick };
    }

    pub fn buildNumber(gui: *Gui, area: Rect, num_vt: *iArea, num_print: NumberPrintFn, num_parse: NumberParseFn, opts: TextboxOptions) ?g.NewVt {
        const newvt = buildOpts(gui, area, opts) orelse return null;
        const self: *@This() = @alignCast(@fieldParentPtr("vt", newvt.vt));
        newvt.vt.dirty(gui);
        self.reset("") catch return newvt;
        num_print(num_vt, &self.codepoints);
        self.number = .{
            .print_cb = num_print,
            .parse_cb = num_parse,
            .vt = num_vt,
        };
        return newvt;
    }

    pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        self.codepoints.deinit();
        gui.alloc.destroy(self);
    }

    pub fn focusChanged(vt: *iArea, gui: *Gui, _: bool) void {
        vt.dirty(gui);
    }

    pub fn fevent(vt: *iArea, ev: g.FocusedEvent) void {
        fevent_err(vt, ev) catch return;
    }

    fn calculateDrawStart(self: *@This(), text_area: Rect, text_h: f32, gui: *Gui) void {
        const old_draw_start = self.draw_start;
        defer {
            if (old_draw_start != self.draw_start)
                self.vt.dirty(gui);
        }
        if (self.head < self.draw_start) {
            self.draw_start = self.head;
        } else {
            const ar = textArea(text_area, gui);
            if (gui.font.nearestGlyphX(self.getVisibleSlice(), text_h, .{ .x = ar.w, .y = 0 }, false)) |u_i| {
                const final_glyph = u_i;
                if (self.head > final_glyph) { // the head is occluded

                    self.draw_start = self.head - final_glyph;
                }
            }
        }

        //The head always must be visible!
        //if the head is less than the draw_start, set draw_start to head
        //else
        //measure text with current, if it lays outside,
    }

    fn setNumber(self: *@This()) void {
        if (self.number) |num| {
            self.reset("") catch return;
            num.print_cb(num.vt, &self.codepoints);
        }
    }

    fn commitNumber(self: *@This()) void {
        if (self.number) |num| {
            num.parse_cb(num.vt, self.codepoints.items) catch return;
        }
    }

    fn commitChange(self: *@This(), ev: g.FocusedEvent) void {
        if (self.opts.commit_when == .on_change) {
            self.sendCommit(ev.gui);
        }
    }

    fn sendCommit(self: *@This(), gui: *Gui) void {
        if (self.opts.commit_vt) |cvt|
            self.opts.commit_cb.?(cvt, gui, self.codepoints.items, self.opts.user_id);
        if (self.opts.clear_on_commit)
            self.reset("") catch return;
        self.changed = false;
    }

    pub fn fevent_err(vt: *iArea, ev: g.FocusedEvent) !void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        switch (ev.event) {
            .focusChanged => |focused| {
                if (focused) ev.gui.startTextinput(vt.area) else ev.gui.stopTextInput();
                if (focused) self.setNumber() else self.commitNumber();

                vt.dirty(ev.gui);
            },
            .text_input => |st| {
                textinput_cb(vt, st, ev.window);
                self.changed = true;
                self.commitChange(ev);
            },
            .keydown => |kev| {
                vt.dirty(ev.gui);
                const mod = kev.mod_state & ~M.mask(&.{ .SCROLL, .NUM, .CAPS });
                const tb = self;
                const StaticData = struct {
                    var are_binds_init: bool = false;
                    var key_binds: edit_keys_list = undefined;
                };
                if (!StaticData.are_binds_init) {
                    StaticData.are_binds_init = true;
                    StaticData.key_binds = edit_keys_list.init();
                }
                var should_commit = false;
                for (kev.keys) |key| {
                    const kb = StaticData.key_binds.getWithMod(@enumFromInt(key.key_id), mod) orelse continue;
                    switch (kb) {
                        .delete, .delete_word_right, .delete_word_left, .paste, .backspace => should_commit = true,
                        else => {},
                    }
                    switch (kb) {
                        .commit => {
                            self.commitNumber();
                            if (self.opts.commit_when != .never)
                                self.sendCommit(ev.gui);
                            //if (self.opts.commit_vt) |cvt| {
                            //    if (self.opts.commit_when != .never)
                            //        self.opts.commit_cb.?(cvt, ev.gui, self.codepoints.items, self.opts.user_id);
                            //}
                        },
                        .move_left => tb.move_to(.left),
                        .move_right => tb.move_to(.right),
                        .move_word_right => tb.move_to(.next_word_end),
                        .move_word_left => tb.move_to(.prev_word_end),
                        .backspace => {
                            if (tb.tail != tb.head) {
                                try tb.deleteSelection();
                            } else {
                                try tb.delete_to(.left);
                            }
                        },
                        .delete => try tb.delete_to(.right),
                        .delete_word_right => try tb.delete_to(.next_word_end),
                        .delete_word_left => try tb.delete_to(.prev_word_end),
                        .select_left => tb.select_to(.left),
                        .select_right => tb.select_to(.right),
                        .select_word_right => tb.select_to(.next_word_end),
                        .select_word_left => tb.select_to(.prev_word_end),
                        .select_all => {
                            tb.tail = 0;
                            tb.head = @intCast(tb.codepoints.items.len);
                            //_ = Utf8It.lastCodepointSlice(&tb.head, tb.codepoints.items);
                        },
                        .copy => {
                            try setClipboard(tb.codepoints.allocator, tb.getSelectionSlice());
                        },
                        .paste => {
                            try self.paste();
                        },
                    }
                }
                if (should_commit) {
                    self.changed = true;
                    self.commitChange(ev);
                }
            },
        }
        self.calculateDrawStart(textArea(vt.area, ev.gui), ev.gui.style.config.text_h, ev.gui);
    }

    fn paste(self: *Self) !void {
        self.changed = true;
        try self.deleteSelection();
        const clip = try getClipboard(self.codepoints.allocator);
        defer self.codepoints.allocator.free(clip);
        // creating a utf8view ensures the paste contains valid unicode and allows us to find the length
        if (std.unicode.Utf8View.init(clip)) |clip_view| {
            var clip_it = clip_view.iterator();
            var len: usize = 0;
            while (clip_it.nextCodepointSlice()) |_|
                len += 1;
            if (self.options.max_len) |ml| { //If the paste will exceed bounds don't paste anything
                if (self.codepoints.items.len + len > ml)
                    return;
            }
            try self.codepoints.insertSlice(@intCast(self.head), clip);
            self.head += @intCast(clip.len);
            self.tail = self.head;
        } else |err| switch (err) {
            //error.InvalidUtf8 => Context.log.err("Paste was not valid unicode!", .{}),
            error.InvalidUtf8 => std.debug.print("Paste was not valid unicode!", .{}),
        }
    }

    pub fn draw(vt: *iArea, d: g.DrawState) void {
        const s: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        const is_focused = d.gui.isFocused(vt);
        d.ctx.rect(vt.area, if (is_focused) 0xff00ffff else 0x222222ff);

        const text_h = d.style.config.text_h;
        //const inset = d.style.config.textbox_inset * d.scale;
        const tr = textArea(vt.area, d.gui);
        //const tr = vt.area.inset(inset);
        //d.ctx.nineSlice(vt.area, d.style.getRect(.basic_inset), d.style.texture, d.scale, d.tint);
        d.ctx.rect(vt.area, d.nstyle.color.textbox_bg);
        //if (params.invalid)
        //    gui.drawRectFilled(tr, self.style.config.colors.textbox_invalid);
        var selection_pos_min: f32 = 0;
        var selection_pos_max: f32 = 0;
        if (s.draw_start > s.codepoints.items.len or s.head < s.draw_start)
            return;
        const head = s.head - s.draw_start;
        const sl = s.codepoints.items[s.draw_start..];
        const caret_x = d.font.textBounds(sl[0..head], text_h).x;
        if (s.head != s.tail and is_focused) {
            const tail_x = if (s.tail < s.draw_start) 0 else d.font.textBounds(sl[0..(s.tail - s.draw_start)], text_h).x;
            selection_pos_max = @min(@max(caret_x, tail_x), tr.w);
            selection_pos_min = @max(@min(caret_x, tail_x), 0);
        }
        d.ctx.rect(Rect.new(
            selection_pos_min + tr.x,
            tr.y,
            selection_pos_max - selection_pos_min,
            tr.h,
        ), d.style.config.colors.text_highlight);
        d.ctx.textClipped(tr, "{s}", .{sl}, d.textP(null), .left);
        if (is_focused) {
            d.ctx.rect(
                Rect.new(caret_x + tr.x, tr.y + 2, d.nstyle.caret_width, tr.h - 4),
                d.nstyle.color.caret,
            );
        }
        const THICK = 2 * d.scale;
        if (s.changed) {
            d.ctx.rect(Rect.new(tr.x, tr.y + tr.h - THICK, tr.w, THICK), d.style.config.colors.uncommited);
        }
    }

    fn textArea(widget_area: Rect, d: *const Gui) Rect {
        const inset = d.style.config.textbox_inset * d.scale;
        return widget_area.inset(inset);
    }

    fn getVisibleSlice(self: *const @This()) []const u8 {
        if (self.draw_start >= self.codepoints.items.len) return self.codepoints.items;

        return self.codepoints.items[self.draw_start..];
    }

    pub fn onclick(vt: *iArea, cb: g.MouseCbState, win: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        cb.gui.grabFocus(vt, win);
        vt.dirty(cb.gui);

        const sz = cb.gui.style.config.text_h;
        const ar = textArea(vt.area, cb.gui);
        const rel = cb.pos.sub(ar.pos()).sub(.{ .x = sz / 2, .y = 0 });
        const nearest_glyph = (cb.gui.font.nearestGlyphX(self.getVisibleSlice(), sz, rel, false));
        switch (cb.btn) {
            .left => {
                if (nearest_glyph) |u_i| {
                    self.setHead(u_i, 0, true);
                    cb.gui.grabMouse(&mouseGrabbed, vt, win, cb.btn);
                }
                self.calculateDrawStart(textArea(vt.area, cb.gui), cb.gui.style.config.text_h, cb.gui);
            },
            .middle => {
                if (nearest_glyph) |u_i| {
                    self.setHead(u_i, 0, true);
                }
                self.paste() catch {};
            },
            .right => {
                const bi = g.Widget.BtnContextWindow.buttonId;
                const r_win = g.Widget.BtnContextWindow.create(
                    cb.gui,
                    cb.pos,
                    .{
                        .buttons = &.{ .{ bi("copy"), "Copy" }, .{ bi("paste"), "Paste" } },
                        .btn_cb = rightClickMenuBtn,
                        .btn_vt = &self.cbhandle,
                    },
                ) catch return;
                cb.gui.setTransientWindow(r_win);
            },
        }
    }

    fn rightClickMenuBtn(cb: *CbHandle, id: g.Uid, gui: *Gui, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("cbhandle", cb));
        self.vt.dirty(gui);
        const bi = g.Widget.BtnContextWindow.buttonId;
        switch (id) {
            bi("copy") => setClipboard(self.codepoints.allocator, self.getSelectionSlice()) catch return,
            bi("paste") => self.paste() catch return,
            else => {},
        }
    }

    pub fn mouseGrabbed(vt: *iArea, cb: g.MouseCbState, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        const sz = cb.gui.style.config.text_h;
        const ar = textArea(vt.area, cb.gui);
        const rel = cb.pos.sub(ar.pos()).sub(.{ .x = sz / 2, .y = 0 });
        if (cb.gui.font.nearestGlyphX(self.getVisibleSlice(), sz, rel, false)) |u_i| {
            self.setHead(u_i, 0, false);
            vt.dirty(cb.gui);
        }
        self.calculateDrawStart(textArea(vt.area, cb.gui), cb.gui.style.config.text_h, cb.gui);
    }

    pub fn getSlice(self: *Self) []const u8 {
        return self.codepoints.items;
    }

    pub fn setHead(self: *Self, pos: usize, codepoint_offset: i32, sync_tail: bool) void {
        if (pos > self.codepoints.items.len) return;
        //If the caret position isn't at the start of a codepoint, do nothing.
        if (pos < self.codepoints.items.len) // pos == len is always a valid codepoint
            _ = std.unicode.utf8ByteSequenceLength(self.codepoints.items[pos]) catch return;

        self.head = pos;
        if (codepoint_offset != 0) {
            if (codepoint_offset > 0) {
                for (0..@abs(codepoint_offset)) |_| {
                    _ = Utf8It.nextCodepointSlice(&self.head, self.codepoints.items) orelse break;
                }
            } else {
                for (0..@abs(codepoint_offset)) |_| {
                    _ = Utf8It.prevCodepointSlice(&self.head, self.codepoints.items) orelse break;
                }
            }
        }
        if (sync_tail)
            self.tail = self.head;
    }

    pub fn reset(self: *Self, new_str: []const u8) !void {
        try self.codepoints.resize(0);
        try self.codepoints.appendSlice(new_str);
        self.head = 0;
        self.tail = 0;
    }

    pub fn getSelectionSlice(self: *Self) []const u8 {
        const min = @min(self.tail, self.head);
        const max = @max(self.tail, self.head);
        return self.codepoints.items[@intCast(min)..@intCast(max)];
    }

    pub fn deleteSelection(self: *Self) !void {
        if (self.tail == self.head) return;
        const min = @min(self.tail, self.head);
        const max = @max(self.tail, self.head);
        try self.codepoints.replaceRange(@intCast(min), @intCast(max - min), "");
        self.head = min;
        self.tail = min;
    }

    pub fn resetFmt(self: *Self, comptime fmt: []const u8, args: anytype) !void {
        try self.reset("");
        try self.codepoints.writer().print(fmt, args);
        self.head = self.codepoints.items.len;
        self.tail = self.head;
    }

    pub fn textinput_cb(vt: *iArea, d: g.TextCbState, win: *iWindow) void {
        textinput_cb_err(vt, d, win) catch return;
    }

    pub fn textinput_cb_err(vt: *iArea, d: g.TextCbState, _: *iWindow) !void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));

        const view = try std.unicode.Utf8View.init(d.text);
        var it = view.iterator();
        vt.dirty(d.gui);

        outer: while (it.nextCodepointSlice()) |new_cp| {
            var new_len: usize = self.codepoints.items.len;
            if (self.opts.restricted_charset) |cset| {
                restricted_blk: {
                    const cp = try std.unicode.utf8Decode(new_cp);
                    for (cset) |achar| {
                        if (achar == cp) {
                            if (self.opts.invert_restriction)
                                continue :outer;
                            break :restricted_blk;
                        }
                    }
                    if (!self.opts.invert_restriction)
                        continue;
                }
            }
            if (self.head != self.tail) {
                try self.deleteSelection();
                new_len = self.codepoints.items.len;
            }
            if (self.options.max_len) |ml| {
                if (new_len >= ml)
                    break;
            }
            try self.codepoints.insertSlice(@intCast(self.head), new_cp);
            self.head += new_cp.len;
            self.tail = self.head;
        }
    }

    //pub fn handleEvents(tb: *TextInput, text_input: []const u8, input_state: InputState) !void {
    //    try tb.handleEventsOpts(text_input, input_state, .{});
    //}
};
