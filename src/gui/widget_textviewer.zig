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

pub const TextView = struct {
    pub const INSET_AMOUNT = 5;
    pub fn heightForN(gui: *const Gui, count: anytype) f32 {
        const inset_amount = 2 * INSET_AMOUNT * gui.dstate.scale;
        const item_h = gui.dstate.nstyle.item_h;
        return item_h * std.math.lossyCast(f32, count) + inset_amount;
    }

    pub const Opts = struct {
        mode: enum { simple, split_on_space },
        force_scroll: bool = false,
        bg_col: ?u32 = null,
        index_ptr: ?*usize = null,
    };
    pub var __cbhandle = g.cbReg("cbhandle");
    pub var __iArea = g.iAreaReg("vt");
    vt: iArea,
    cbhandle: CbHandle = .init(@This()),

    cat_string: []const u8, //Alloced by gui
    lines: std.ArrayList([]const u8), //slices into cat_string
    opts: Opts,

    scroll_area: Rect = .{},

    selection: struct {
        state: enum { init, point0, point1 } = .init,
        start_line: usize = 0,
        start_char: usize = 0,
        end_line: usize = 0,
        end_char: usize = 0,
    } = .{},

    pub fn build(parent: *iArea, area_o: ?Rect, text: []const []const u8, win: *iWindow, opts: Opts) g.WgStatus {
        const gui = parent.win_ptr.gui_ptr;
        const area = area_o orelse return .failed;
        const self = gui.create(@This());

        self.* = .{
            .cat_string = catStrings(gui.alloc, text) catch return .failed,
            .vt = .UNINITILIZED,
            .lines = .{},
            .opts = opts,
        };
        parent.addChild(&self.vt, .{
            .area = area,
            .deinit_fn = deinit,
            .draw_fn = draw,
            .onclick = onclick,
            .focus_ev_fn = fevent,
        });

        const inset = area.inset(INSET_AMOUNT * gui.dstate.scale);

        //First, walk through string with xWalker and stick in a buffer of lines
        const extra_margin = gui.dstate.nstyle.text_h / 3;
        const tw = VScroll.getAreaW(inset.w - extra_margin, gui.dstate.scale);
        switch (opts.mode) {
            .split_on_space => self.buildLinesSpaceSplit(gui.dstate.font, tw, gui.dstate.nstyle.text_h, self.cat_string) catch return .failed,
            .simple => self.buildLines(gui.dstate.font, tw, gui.dstate.nstyle.text_h, self.cat_string) catch return .failed,
        }
        if (opts.index_ptr) |ind|
            ind.* = std.math.maxInt(usize); //push it to the bottom
        return VScroll.build(&self.vt, inset, .{
            .build_vt = &self.cbhandle,
            .build_cb = &buildScroll,
            .win = win,
            .item_h = gui.dstate.nstyle.item_h,
            .count = self.lines.items.len,
            .index_ptr = opts.index_ptr,
            .force_scroll = opts.force_scroll,
            .bg_col = null,
            //.bg_col = gui.dstate.nstyle.color.text_bg,
        });
    }

    pub fn fevent(vt: *iArea, ev: g.FocusedEvent) void {
        const self = vt.cast(@This());
        switch (ev.event) {
            .keydown => {
                const b = &Gui.binds.global;
                if (ev.gui.sdl_win.isBindState(b.copy, .rising)) {
                    self.copySelection(ev.gui) catch {};
                }
            },
            else => {},
        }
    }

    //Every selection can be drawn with 0-3 rectangles
    pub fn onclick(vt: *iArea, cb: g.MouseCbState, win: *iWindow) void {
        const self = vt.cast(@This());
        const font = cb.gui.dstate.font;
        switch (cb.btn) {
            .left => {
                cb.gui.grabFocus(vt, win);

                self.selection.state = .init;
                vt.dirty();
                if (self.opts.index_ptr) |ind| {
                    if (ind.* >= self.lines.items.len) return;
                    var lay = scrollLay(self.scroll_area, cb.gui);
                    for (self.lines.items[ind.*..], ind.*..) |line, l_i| {
                        const ar = lay.getArea() orelse return;
                        if (ar.containsPoint(cb.pos)) {
                            const glyph_index = font.nearestGlyphX(
                                line,
                                cb.gui.dstate.nstyle.text_h,
                                cb.pos.sub(ar.pos()),
                                false,
                            ) orelse return;
                            self.selection.start_char = glyph_index;
                            self.selection.start_line = l_i;
                            self.selection.state = .point0;
                            cb.gui.grabMouse(mouseGrabbed, vt, win, cb.btn);
                        }
                    }
                }
            },
            else => {},
            .right => {
                const bi = g.Widget.BtnContextWindow.buttonId;
                const r_win = g.Widget.BtnContextWindow.create(
                    cb.gui,
                    cb.pos,
                    .{
                        .buttons = &.{.{ bi("copy"), "Copy ", .btn }},
                        .btn_cb = rightClickMenuBtn,
                        .btn_vt = &self.cbhandle,
                    },
                ) catch return;
                cb.gui.setTransientWindow(r_win, &self.vt);
            },
        }
    }

    fn rightClickMenuBtn(cb: *CbHandle, id: g.Uid, dat: g.MouseCbState, _: *iWindow) void {
        const self = cb.cast(@This());
        //self.vt.dirty();
        const bi = g.Widget.BtnContextWindow.buttonId;
        switch (id) {
            bi("copy") => {
                self.copySelection(dat.gui) catch return;
            },
            else => {},
        }
    }

    fn copySelection(self: *@This(), gui: *Gui) !void {
        if (self.selection.state != .point1) return;
        const s = self.selection;

        const lines = self.lines.items;

        var temp = std.ArrayList(u8){};
        defer temp.deinit(gui.alloc);
        if (s.start_line == s.end_line) {
            try temp.appendSlice(gui.alloc, lines[s.start_line][s.start_char..s.end_char]);
        } else {
            const fwd = s.start_line < s.end_line;
            const line = lines[if (fwd) s.start_line else s.end_line];
            try temp.appendSlice(gui.alloc, line[(if (fwd) s.start_char else s.end_char)..]);

            const st_i = @min(s.start_line, s.end_line);
            const end_i = @max(s.start_line, s.end_line);
            for (st_i + 1..end_i) |l_i| {
                try temp.appendSlice(gui.alloc, lines[l_i]);
            }
            const eline = lines[if (fwd) s.end_line else s.start_line];
            try temp.appendSlice(gui.alloc, eline[0..if (fwd) s.end_char else s.start_char]);
        }

        try temp.append(gui.alloc, 0);

        _ = graph.c.SDL_SetClipboardText(@ptrCast(temp.items.ptr));
    }

    pub fn mouseGrabbed(vt: *iArea, cb: g.MouseCbState, win: *iWindow) void {
        const self = vt.cast(@This());
        _ = win;
        if (self.opts.index_ptr) |ind| {
            if (ind.* >= self.lines.items.len) return;
            var lay = scrollLay(self.scroll_area, cb.gui);
            for (self.lines.items[ind.*..], ind.*..) |line, l_i| {
                const ar = lay.getArea() orelse return;
                if (ar.containsPoint(cb.pos)) {
                    const glyph_index = cb.gui.dstate.font.nearestGlyphX(
                        line,
                        cb.gui.dstate.nstyle.text_h,
                        cb.pos.sub(ar.pos()),
                        false,
                    ) orelse return;
                    self.selection.state = .point1;

                    if (self.selection.end_char != glyph_index or self.selection.end_line != l_i)
                        vt.dirty(); //Optimize
                    self.selection.end_char = glyph_index;
                    self.selection.end_line = l_i;
                }
            }
        }
    }

    pub fn addOwnedText(self: *@This(), owned: []const u8, gui: *Gui) !void {
        if (self.vt.children.items.len != 1) return;
        const vscr = self.vt.children.items[0].cast(VScroll);
        const extra_margin = gui.dstate.nstyle.text_h / 3;
        const tw = VScroll.getAreaW(vscr.vt.area.w - extra_margin, gui.dstate.scale);
        switch (self.opts.mode) {
            .split_on_space => self.buildLinesSpaceSplit(gui.dstate.font, tw, gui.dstate.nstyle.text_h, owned) catch return,
            .simple => self.buildLines(gui.dstate.font, tw, gui.dstate.nstyle.text_h, owned) catch return,
        }
        const new_count = self.lines.items.len;
        vscr.updateCount(new_count);
    }

    pub fn rebuildScroll(self: *@This(), gui: *Gui, win: *iWindow) void {
        if (self.vt.children.items.len != 1) return;
        const vscr = self.vt.children.items[0].cast(VScroll);
        vscr.rebuild(gui, win);
    }

    pub fn gotoBottom(self: *@This()) void {
        if (self.vt.children.items.len != 1) return;
        const vscr = self.vt.children.items[0].cast(VScroll);
        vscr.gotoBottom();
    }

    fn scrollLay(bound: Rect, gui: *Gui) g.VerticalLayout {
        return .{ .item_height = gui.dstate.nstyle.item_h, .bounds = bound };
    }

    fn nthArea(bound: Rect, gui: *Gui, index: usize) ?Rect {
        const h = gui.dstate.nstyle.item_h;

        const new_y = @as(f32, @floatFromInt(index)) * h;
        if (new_y + h > bound.h) return null;

        return Rec(bound.x, bound.y + new_y, bound.w, h);
    }

    pub fn buildScroll(cb: *CbHandle, layout: *iArea, index: usize) void {
        const gui = layout.win_ptr.gui_ptr;

        const self = cb.cast(@This());
        var ly = scrollLay(layout.area, gui);
        self.scroll_area = layout.area;
        if (index >= self.lines.items.len) return;
        //self.selection.state = .init;
        self.vt.dirty(); //Required as none of the wg.Text have a bg
        for (self.lines.items[index..], index..) |line, i| {
            _ = i;
            //const color: u32 = if (i % 2 == 0) 0xffff_ffff else 0xff_0000_ff;
            _ = Widget.Text.buildStatic(layout, ly.getArea(), line, .{ .bg_col = null });
        }
    }

    pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
        const self = vt.cast(@This());
        gui.alloc.free(self.cat_string);
        self.lines.deinit(gui.alloc);
        gui.alloc.destroy(self);
    }

    pub fn draw(vt: *iArea, gui: *Gui, d: *g.DrawState) void {
        const self = vt.cast(@This());
        d.ctx.rect(vt.area, self.opts.bg_col orelse d.nstyle.color.text_bg);

        //TODO make sure the index is santized big dummy
        if (true) {
            switch (self.selection.state) {
                else => {},
                .point1 => {
                    const fh = gui.dstate.nstyle.text_h;
                    if (self.opts.index_ptr) |ind| {
                        const font = gui.dstate.font;
                        const lines = self.lines.items;
                        const s = self.selection;
                        const single = s.start_line == s.end_line;

                        if (single and (s.start_line < ind.*)) return; //Off screen

                        const ar_i_start = if (ind.* > s.start_line) 0 else s.start_line - ind.*;
                        const ar_i_end = if (ind.* > s.end_line) ind.* else s.end_line - ind.*;

                        //TODO check if line is shown first
                        if (single) {
                            const ar = nthArea(self.scroll_area, gui, ar_i_start) orelse return;
                            const first = @min(s.start_char, s.end_char);
                            const last = @max(s.start_char, s.end_char);
                            const start = font.textBounds(lines[s.start_line][0..first], fh);
                            const end = font.textBounds(lines[s.end_line][0..last], fh);
                            d.ctx.rect(Rec(
                                start.x + ar.x,
                                ar.y,
                                end.x - start.x,
                                ar.h,
                            ), 0xffff);
                        } else { //Multi line
                            const ar0 = nthArea(self.scroll_area, gui, ar_i_start) orelse return;
                            const ar1 = nthArea(self.scroll_area, gui, ar_i_end) orelse return;

                            const is_beginning = ar1.y > ar0.y;

                            { //start line
                                if (is_beginning) { //Draw the whole line starting at start
                                    const end = font.textBounds(lines[s.start_line], fh).x;
                                    const start = font.textBounds(lines[s.start_line][0..s.start_char], fh).x;
                                    d.ctx.rect(Rec(ar0.x + start, ar0.y, end - start, ar0.h), 0xffff);
                                } else { //Draw the line from beginning to start
                                    const start = 0;
                                    const end = font.textBounds(lines[s.start_line][0..s.start_char], fh).x;
                                    d.ctx.rect(Rec(ar0.x + start, ar0.y, end - start, ar0.h), 0xffff);
                                }
                            }

                            { //end line

                                if (is_beginning) {
                                    const start = 0;
                                    const end = font.textBounds(lines[s.end_line][0..s.end_char], fh).x;
                                    d.ctx.rect(Rec(ar1.x + start, ar1.y, end - start, ar1.h), 0xffff);
                                } else {
                                    const end = font.textBounds(lines[s.end_line], fh).x;
                                    const start = font.textBounds(lines[s.end_line][0..s.end_char], fh).x;
                                    d.ctx.rect(Rec(ar1.x + start, ar1.y, end - start, ar1.h), 0xffff);
                                }
                            }

                            //Draw all inbetween lines
                            const st_i = @min(s.start_line, s.end_line);
                            const end_i = @max(s.start_line, s.end_line);
                            for (lines[st_i + 1 .. end_i], st_i + 1..) |line, l_i| {
                                if (ind.* > l_i) continue; //off screen
                                const ar = nthArea(self.scroll_area, gui, l_i - ind.*) orelse continue;
                                const tb = font.textBounds(line, fh);
                                d.ctx.rect(Rec(ar.x, ar.y, tb.x, ar.h), 0xffff);
                            }
                        }
                    }
                },
            }
        }
        //d.ctx.rect(vt.area, 0xff); //Black rect
    }

    // populate self.lines with cat_string
    fn buildLines(self: *@This(), font: *graph.FontInterface, area_w: f32, font_h: f32, string: []const u8) !void {
        const max_line_w = area_w;
        var xwalker = font.xWalker(string, font_h);
        var current_line_w: f32 = 0;
        var start_index: usize = 0;
        const gui = self.vt.win_ptr.gui_ptr;
        while (xwalker.next()) |n| {
            const w = n[0];
            current_line_w += w;
            if (current_line_w > max_line_w or n[1] == '\n') {
                const end = xwalker.index();
                try self.lines.append(gui.alloc, string[start_index..end]);
                start_index = end;
                current_line_w = 0;
            }
        }
        try self.lines.append(gui.alloc, string[start_index..]);
    }

    /// the passed in string must live for duration of self
    fn buildLinesSpaceSplit(self: *@This(), font: *graph.FontInterface, area_w: f32, font_h: f32, string: []const u8) !void {
        const max_line_w = area_w;
        var xwalker = font.xWalker(string, font_h);
        var current_line_w: f32 = 0;
        var start_index: usize = 0;
        var last_space: ?usize = null;
        var width_at_last_space: f32 = 0;
        const gui = self.vt.win_ptr.gui_ptr;
        while (xwalker.next()) |n| {
            const w = n[0];
            current_line_w += w;
            if (n[1] == ' ') {
                //TODO split on any unicode ws
                last_space = xwalker.index();
                width_at_last_space = current_line_w;
            }
            const past = current_line_w > max_line_w;
            if (past or n[1] == '\n') {
                const end = xwalker.index();
                if (past and last_space != null) {
                    const ls = last_space.?;
                    if (start_index > ls) return;
                    try self.lines.append(gui.alloc, string[start_index..ls]);
                    current_line_w = current_line_w - width_at_last_space;
                    start_index = ls;
                } else {
                    if (start_index > end) return;
                    try self.lines.append(gui.alloc, string[start_index..end]);
                    start_index = end;
                    current_line_w = 0;
                }
            }
        }
        try self.lines.append(gui.alloc, string[start_index..]);
    }

    // ^ ^
    fn catStrings(alloc: std.mem.Allocator, text: []const []const u8) ![]const u8 {
        var strlen: usize = 0;
        for (text) |str|
            strlen += str.len;
        const slice = try alloc.alloc(u8, strlen);
        strlen = 0;
        for (text) |str| {
            @memcpy(slice[strlen .. strlen + str.len], str);
            strlen += str.len;
        }
        return slice;
    }
};
