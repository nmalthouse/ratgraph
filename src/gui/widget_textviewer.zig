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
    };
    vt: iArea,
    cbhandle: CbHandle = .{},

    cat_string: []const u8, //Alloced by gui
    lines: std.ArrayList([]const u8), //slices into cat_string
    opts: Opts,

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
        parent.addChild(&self.vt, .{ .area = area, .deinit_fn = deinit, .draw_fn = draw, .onclick = onclick });

        const inset = area.inset(INSET_AMOUNT * gui.dstate.scale);

        //First, walk through string with xWalker and stick in a buffer of lines
        const extra_margin = gui.dstate.nstyle.text_h / 3;
        const tw = VScroll.getAreaW(inset.w - extra_margin, gui.dstate.scale);
        switch (opts.mode) {
            .split_on_space => self.buildLinesSpaceSplit(gui.dstate.font, tw, gui.dstate.nstyle.text_h, self.cat_string) catch return .failed,
            .simple => self.buildLines(gui.dstate.font, tw, gui.dstate.nstyle.text_h, self.cat_string) catch return .failed,
        }
        return VScroll.build(&self.vt, inset, .{
            .build_vt = &self.cbhandle,
            .build_cb = &buildScroll,
            .win = win,
            .item_h = gui.dstate.nstyle.item_h,
            .count = self.lines.items.len,
            .index_ptr = null,
            .force_scroll = opts.force_scroll,
            .bg_col = gui.dstate.nstyle.color.text_bg,
        });
    }

    //Every selection can be drawn with 0-3 rectangles
    pub fn onclick(vt: *iArea, cb: g.MouseCbState, win: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));

        _ = self;
        _ = cb;
        _ = win;
    }

    pub fn addOwnedText(self: *@This(), owned: []const u8, gui: *Gui) !void {
        if (self.vt.children.items.len != 1) return;
        const vscr: *VScroll = @alignCast(@fieldParentPtr("vt", self.vt.children.items[0]));
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
        const vscr: *VScroll = @alignCast(@fieldParentPtr("vt", self.vt.children.items[0]));
        vscr.rebuild(gui, win);
    }

    pub fn gotoBottom(self: *@This()) void {
        if (self.vt.children.items.len != 1) return;
        const vscr: *VScroll = @alignCast(@fieldParentPtr("vt", self.vt.children.items[0]));
        vscr.gotoBottom();
    }

    pub fn buildScroll(cb: *CbHandle, layout: *iArea, index: usize) void {
        const gui = layout.win_ptr.gui_ptr;

        const self: *@This() = @alignCast(@fieldParentPtr("cbhandle", cb));
        var ly = g.VerticalLayout{ .item_height = gui.dstate.nstyle.item_h, .bounds = layout.area };
        if (index >= self.lines.items.len) return;
        for (self.lines.items[index..], index..) |line, i| {
            _ = i;
            //const color: u32 = if (i % 2 == 0) 0xffff_ffff else 0xff_0000_ff;
            _ = Widget.Text.buildStatic(layout, ly.getArea(), line, .{ .bg_col = self.opts.bg_col });
        }
    }

    pub fn deinit(vt: *iArea, gui: *Gui, _: *iWindow) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        gui.alloc.free(self.cat_string);
        self.lines.deinit(gui.alloc);
        gui.alloc.destroy(self);
    }

    pub fn draw(vt: *iArea, _: *Gui, d: *g.DrawState) void {
        const self: *@This() = @alignCast(@fieldParentPtr("vt", vt));
        d.ctx.rect(vt.area, self.opts.bg_col orelse d.nstyle.color.text_bg);
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
