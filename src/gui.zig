const std = @import("std");
const Cache = @import("gui_cache.zig");
const graph = @import("graphics.zig");
const gl = graph.GL;
//TODO write a backend using wasi
//TODO write a backend using glfw
//TODO gui should not depend on SDL. keys can be passed in an generic array. User must initialize keybindings with key ids

const json = std.json;
const clamp = std.math.clamp;
const Font = graph.FontUtil.PublicFontInterface;
const Vec2f = graph.Vec2f;
const Vec2i = struct {
    const Self = @This();

    pub fn toF(self: Self) Vec2f {
        return .{ .x = @as(f32, @floatFromInt(self.x)), .y = @as(f32, @floatFromInt(self.y)) };
    }

    x: i16,
    y: i16,
};

const Rect = graph.Rect;
const Hsva = graph.Hsva;
const Color = u32;
const Colori = graph.Colori;
const utf8 = @import("utf8.zig");

//TODO reduce memory footprint of these structs?
//Colors could be aliased.
//A Rect could probably be represented by 4 shorts
pub const DrawCommand = union(enum) {
    rect_9border: struct {
        r: Rect,
        uv: Rect,
        scale: f32,
        texture: graph.Texture,
        cutout_start: f32,
        cutout_end: f32,
    },
    rect_9slice: struct {
        r: Rect,
        uv: Rect,
        scale: f32,
        texture: graph.Texture,
    },

    rect_filled: struct {
        r: Rect,
        color: u32,
    },

    rect_textured: struct {
        r: Rect,
        color: u32,
        uv: Rect,
        texture: graph.Texture,
    },

    rect_outline: struct {
        r: Rect,
        color: u32,
    },

    rect_filled_multi_color: struct {
        r: Rect,
        colors: [4]u32,
    },

    line: struct {
        a: Vec2f,
        b: Vec2f,
        color: u32,
    },

    text: struct {
        font: *Font,
        pos: Vec2i,
        size: f32,
        string: []const u8,
        color: u32,
    },

    scissor: struct {
        area: ?Rect = null,
    },

    set_camera: ?struct {
        cam_area: Rect,
        screen_area: Rect,
    },
};

pub const Justify = enum { right, left, center };
pub const Orientation = graph.Orientation;

//TODO InputState should have no SDL dependancy.
pub const InputState = struct {
    pub const DefaultKeyboardState = graph.SDL.Window.KeyboardStateT.initEmpty();
    mouse: graph.SDL.MouseState = .{},
    keys: []const graph.SDL.KeyState = &.{}, // Populated with keys just pressed, keydown events
    key_state: []const graph.SDL.ButtonState = &.{},
    //key_state: *const graph.SDL.Window.KeyStateT = &graph.SDL.Window.EmptyKeyState, //All the keys state
    mod_state: graph.SDL.keycodes.KeymodMask = 0,
};

fn opaqueSelf(comptime self: type, ptr: *anyopaque) *self {
    return @as(*self, @ptrCast(@alignCast(ptr)));
}

pub const SubRectLayout = struct {
    rect: Rect,
    index: u32 = 0,
    hidden: bool = false,

    fn hash(self: *anyopaque, bounds: Rect) u64 {
        return dhash(.{ .r = bounds, .d = opaqueSelf(SubRectLayout, self).* });
    }

    pub fn getArea(bounds: Rect, anyself: *anyopaque) ?Rect {
        const self = opaqueSelf(@This(), anyself);
        _ = bounds;
        if (self.index > 0) return null;
        self.index += 1;
        return self.rect;
    }
};

//TODO layouts should be vtables instead
pub const TableLayout = struct {
    const Self = @This();
    hidden: bool = false,

    //Config
    columns: u32,
    item_height: f32,

    //State
    current_y: f32 = 0,
    column_index: u32 = 0,

    pub fn hash(self: *anyopaque, bounds: Rect) u64 {
        return dhash(.{ .r = bounds, .d = opaqueSelf(@This(), self).* });
    }

    pub fn getArea(bounds: Rect, anyself: *anyopaque) ?Rect {
        const self = opaqueSelf(@This(), anyself);
        if (self.current_y > bounds.h) return null;

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

pub const VerticalLayout = struct {
    const Self = @This();
    padding: graph.Padding = .{ .top = 0, .bottom = 0, .left = 0, .right = 0 },
    item_height: f32,
    current_h: f32 = 0,
    hidden: bool = false,
    next_height: ?f32 = null,
    give_remaining: bool = false,

    pub fn hash(self: *anyopaque, bounds: Rect) u64 {
        return dhash(.{ .r = bounds, .d = opaqueSelf(@This(), self).* });
    }

    fn getArea(bounds: Rect, anyself: *anyopaque) ?Rect {
        const self = opaqueSelf(@This(), anyself);
        const h = if (self.next_height) |nh| nh else self.item_height;
        self.next_height = null;

        if (self.current_h + self.padding.top > bounds.h or self.hidden) //We don't add h yet because the last element can be partially displayed. (if clipped)
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

    //TODO this doesn't really "push" a height. misleading as one might push push push then expecting subsequent widgets to pop pop pop
    pub fn pushHeight(self: *Self, h: f32) void {
        self.next_height = h;
    }

    /// The next requested area will be the rest of the available space
    pub fn pushRemaining(self: *Self) void {
        self.give_remaining = true;
    }
};

pub const HorizLayout = struct {
    paddingh: f32 = 20,
    index: usize = 0,
    count: usize,
    current_w: f32 = 0,
    hidden: bool = false,
    count_override: ?usize = null,

    pub fn hash(self: *anyopaque, bounds: Rect) u64 {
        return dhash(.{ .r = bounds, .d = opaqueSelf(@This(), self).* });
    }

    pub fn getArea(bounds: Rect, anyself: *anyopaque) ?Rect {
        const self = opaqueSelf(@This(), anyself);
        defer self.index += if (self.count_override) |co| co else 1;
        const fc: f32 = @floatFromInt(self.count);
        const w = ((bounds.w - self.paddingh * (fc - 1)) / fc) * @as(f32, @floatFromInt(if (self.count_override) |co| co else 1));
        self.count_override = null;

        defer self.current_w += w + self.paddingh;

        return .{ .x = bounds.x + self.current_w, .y = bounds.y, .w = w, .h = bounds.h };
    }

    pub fn pushCount(self: *HorizLayout, next_count: usize) void {
        self.count_override = next_count;
    }
};

//TODO Rather than having beginLayout be a ducktyped generic that fills out the Layout vtable,
// declare a LayoutInterface struct that each layout implements
pub const Layout = struct {
    const Self = @This();
    const HashFnSig = *const fn (*anyopaque, Rect) u64;
    const GetAreaFnSig = *const fn (bounds: Rect, self: *anyopaque) ?Rect;

    bounds: Rect,

    hash_layout: ?HashFnSig = null,
    layout_data: ?*anyopaque = null,
    get_area: ?GetAreaFnSig = null,

    parent_scroll_bounds: ?Rect = null,

    last_requested_bounds: ?Rect = null,

    pub fn setNew(self: *Self, comptime Layout_T: type, layout_data: *anyopaque) void {
        self.layout_data = layout_data;
        self.hash_layout = &@field(Layout_T, "hash");
        self.get_area = &@field(Layout_T, "getArea");
    }

    pub fn isSet(self: *Self) bool {
        return (self.get_area != null and self.hash_layout != null and self.layout_data != null);
    }

    pub fn getArea(self: *Self) ?Rect {
        self.last_requested_bounds = self.get_area.?(self.bounds, self.layout_data.?);
        return self.last_requested_bounds;
    }

    pub fn hash(self: *Self) u64 {
        return self.hash_layout.?(self.layout_data.?, self.bounds);
    }

    pub fn reset(self: *Self) void {
        self.layout_data = null;
        self.get_area = null;
        self.hash_layout = null;
    }
};

pub const RetainedState = struct {
    //Implementation of https://rxi.github.io/textbox_behaviour.html
    pub const TextInput = struct {
        const Utf8It = utf8.BiDirectionalUtf8Iterator;
        const Self = @This();
        const uni = std.unicode;
        const M = graph.SDL.keycodes.Keymod;
        const None = M.mask(&.{.NONE});
        //TODO make this configurable
        const edit_keys_list = graph.Bind(&.{
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

        codepoints: std.ArrayList(u8),

        head: usize,
        tail: usize,

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

        pub fn init(alloc: std.mem.Allocator) Self {
            return Self{ .codepoints = std.ArrayList(u8).init(alloc), .head = 0, .tail = 0 };
        }

        pub fn deinit(self: *Self) void {
            self.codepoints.deinit();
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

        pub fn handleEventsOpts(
            tb: *TextInput,
            text_input: []const u8,
            input_state: InputState,
            options: struct {
                /// If set, only the listed characters will be inserted. Others will be silently ignored
                restricted_charset: ?[]const u8 = null,
                max_len: ?usize = null,
            },
        ) !void {
            const StaticData = struct {
                var are_binds_init: bool = false;
                var key_binds: edit_keys_list = undefined;
            };
            if (!StaticData.are_binds_init) {
                StaticData.are_binds_init = true;
                StaticData.key_binds = edit_keys_list.init();
            }

            const view = try std.unicode.Utf8View.init(text_input);
            var it = view.iterator();

            while (it.nextCodepointSlice()) |new_cp| {
                var new_len: usize = tb.codepoints.items.len;
                if (options.restricted_charset) |cset| {
                    restricted_blk: {
                        for (cset) |achar| {
                            const cp = try std.unicode.utf8Decode(new_cp);
                            if (achar == cp)
                                break :restricted_blk;
                        }
                        continue;
                    }
                }
                if (tb.head != tb.tail) {
                    try tb.deleteSelection();
                    new_len = tb.codepoints.items.len;
                }
                if (options.max_len) |ml| {
                    if (new_len >= ml)
                        break;
                }
                try tb.codepoints.insertSlice(@intCast(tb.head), new_cp);
                tb.head += new_cp.len;
                tb.tail = tb.head;
            }

            const mod = input_state.mod_state & ~M.mask(&.{ .SCROLL, .NUM, .CAPS });
            for (input_state.keys) |key| {
                switch (StaticData.key_binds.getWithMod(@enumFromInt(key.key_id), mod) orelse continue) {
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
                        try tb.deleteSelection();
                        const clip = try getClipboard(tb.codepoints.allocator);
                        defer tb.codepoints.allocator.free(clip);
                        // creating a utf8view ensures the paste contains valid unicode and allows us to find the length
                        if (std.unicode.Utf8View.init(clip)) |clip_view| {
                            var clip_it = clip_view.iterator();
                            var len: usize = 0;
                            while (clip_it.nextCodepointSlice()) |_|
                                len += 1;
                            if (options.max_len) |ml| { //If the paste will exceed bounds don't paste anything
                                if (tb.codepoints.items.len + len > ml)
                                    continue;
                            }
                            try tb.codepoints.insertSlice(@intCast(tb.head), clip);
                            tb.head += @intCast(clip.len);
                            tb.tail = tb.head;
                        } else |err| switch (err) {
                            error.InvalidUtf8 => Context.log.err("Paste was not valid unicode!", .{}),
                        }
                    },
                }
            }
        }

        pub fn handleEvents(tb: *TextInput, text_input: []const u8, input_state: InputState) !void {
            try tb.handleEventsOpts(text_input, input_state, .{});
        }
    };

    pub const ElementData = union(enum) {
        text_box: TextInput,
        float: f32,

        pub fn deinit(self: *ElementData) void {
            switch (self.*) {
                .text_box => self.text_box.deinit(),
                .float => {},
            }
        }
    };

    data: ElementData,
};

pub const ClickState = enum(u8) {
    none,
    hover,
    hover_no_focus,
    click,
    click_teleport,
    held,
    click_release,
    double,
};

//What Widgets do varius ui's have
//Nuklear:
//  Textbox
//  Button
//  Checkbox
//  Radio
//  Selectable?
//  Slider
//  ProgressBar
//  ColorPicker
//  TextEdit
//  Chart
//  PopUp
//  ComboBox
//  Context
//  Tooltip
//  Menu

pub var hash_time: u64 = 0;
pub var hash_timer: std.time.Timer = undefined;

pub inline fn dhash(state: anytype) u64 {
    hash_timer.reset();
    defer hash_time += hash_timer.read();
    var hasher = std.hash.Wyhash.init(0);
    hashW(&hasher, state, .Deep);
    return hasher.final();
}

//A wrapper over std autoHash to allow hashing floats. All the floats being hashed are pixel coordinates. They are scaled by 10 then truncated and hashed
pub fn hashW(hasher: anytype, key: anytype, comptime strat: std.hash.Strategy) void {
    const Key = @TypeOf(key);
    switch (@typeInfo(Key)) {
        .@"struct" => |info| {
            inline for (info.fields) |field| {
                hashW(hasher, @field(key, field.name), strat);
            }
        },
        .@"union" => |info| {
            if (info.tag_type == null) @compileError("Cannot hash untagged union");
            inline for (info.fields, 0..) |field, i| {
                if (i == @intFromEnum(key)) {
                    hashW(hasher, @field(key, field.name), strat);
                    break;
                }
            }
        },
        .pointer => |info| {
            switch (info.size) {
                .slice => {
                    for (key) |element| {
                        hashW(hasher, element, strat);
                    }
                },
                else => {},
            }
        },
        .array => {
            for (key) |element|
                hashW(hasher, element, strat);
        },
        .@"opaque" => {},
        .optional => if (key) |k| hashW(hasher, k, strat),
        .float => {
            const f = if (std.math.isFinite(key)) key else 0 * 10;
            const ff: i32 = if (@abs(f) >= std.math.maxInt(i32)) std.math.maxInt(i32) else @intFromFloat(f);
            std.hash.autoHashStrat(hasher, ff, strat);
        },
        .int, .bool => std.hash.autoHashStrat(hasher, key, strat),
        else => @compileError("can't hash " ++ @typeName(Key)),
    }
}

pub const ButtonStyle = struct {
    bg: Hsva,
    top: Hsva,
    bot: Hsva,
};
pub var bstyle: ButtonStyle = .{
    .bg = graph.colorToHsva(Color.Gray),
    .top = graph.colorToHsva(Color.White),
    .bot = graph.colorToHsva(Color.Black),
};

pub const OpaqueDataStore = struct {
    const Self = @This();
    const DataStoreMapT = std.StringHashMap(DataItem);

    pub const DataItem = struct {
        type_name: []const u8,
        data: []u8,
    };

    keys: std.ArrayList([]const u8),
    map: DataStoreMapT,
    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) Self {
        return Self{ .keys = std.ArrayList([]const u8).init(alloc), .map = DataStoreMapT.init(alloc), .alloc = alloc };
    }

    pub fn deinit(self: *Self) void {
        var vit = self.map.valueIterator();
        var item = vit.next();
        while (item) |v| : (item = vit.next()) {
            self.alloc.free(v.data);
            self.alloc.free(v.type_name);
        }
        for (self.keys.items) |key| {
            self.alloc.free(key);
        }

        self.keys.deinit();
        self.map.deinit();
    }

    pub fn storeI(self: *Self, comptime data_type: type, init_value: data_type, name: []const u8) !*data_type {
        const s = try self.store(data_type, name);
        if (s.is_init)
            s.data.* = init_value;
        return s.data;
    }

    pub fn store(self: *Self, comptime data_type: type, name: []const u8) !struct {
        data: *data_type,
        is_init: bool,
    } {
        var is_init = false;
        if (!self.map.contains(name)) {
            is_init = true;
            const name_store = try self.alloc.dupe(u8, name);
            try self.keys.append(name_store);
            const data_untyped = try self.alloc.alloc(u8, @sizeOf(data_type));
            try self.map.put(name_store, .{ .type_name = try self.alloc.dupe(u8, @typeName(data_type)), .data = data_untyped });
        }
        const v = self.map.get(name) orelse unreachable;
        //if (v.type_name_hash != hash) return error.wrongType;
        if (!std.mem.eql(u8, v.type_name, @typeName(data_type))) return error.wrongType;
        return .{ .data = @as(*data_type, @ptrCast(@alignCast(v.data))), .is_init = is_init };
    }
};

//test "Opaque data store basic usage" {
//    const alloc = std.testing.allocator;
//    const expect = std.testing.expect;
//    var ds = OpaqueDataStore.init(alloc);
//    defer ds.deinit();
//
//    const val = try ds.store(i32, "my_var", 0);
//    try expect(val.* == 0);
//    const val2 = try ds.store(i32, "my_var", 0);
//    val2.* += 4;
//    try expect(val.* == 4);
//}

pub const Console = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    lines: std.ArrayList([]const u8),

    pub fn init(alloc: std.mem.Allocator) Self {
        return Self{ .alloc = alloc, .lines = std.ArrayList([]const u8).init(alloc) };
    }
    pub fn deinit(self: *Self) void {
        for (self.lines.items) |line| {
            self.alloc.free(line);
        }
        self.lines.deinit();
    }

    pub fn print(self: *Self, comptime fmt: []const u8, args: anytype) !void {
        var line = std.ArrayList(u8).init(self.alloc);
        try line.writer().print(fmt, args);
        try self.lines.append(try line.toOwnedSlice());
    }
};

pub const Context = struct {
    pub const log = std.log.scoped(.GuiContext);
    pub var dealloc_count: u32 = 0;
    pub var alloc_count: u32 = 0;
    const Self = @This();
    const LayoutStackT = std.SinglyLinkedList(Layout);
    const WindowStackT = std.SinglyLinkedList(usize); //Indicies into window array

    //Used for hashing
    const WidgetTypes = enum {
        button,
        color_picker,
        slider,
        propertyTable,
        checkbox,
        textbox,
        text_label,
        print_label,
    };

    pub const WidgetState = enum {
        init,
        input_changed,
        style_changed,
        no_change,
        dirty,
    };

    pub const GenericWidget = struct {
        const NumType = enum { uint, int, float };

        pub const Button = struct {
            area: Rect = graph.Rec(0, 0, 0, 0),
            state: ClickState = .none,
        };

        pub const Checkbox = struct {
            area: Rect,
            changed: bool,
        };

        pub const Textbox = struct {
            area: Rect,
            text_area: Rect,
            caret: ?f32,
            slice: []const u8,
            is_invalid: bool = false,
            selection_pos_min: f32 = 0,
            selection_pos_max: f32 = 0,
        };

        pub const Slider = struct {
            area: Rect,
            handle: Rect,
            click: ClickState,
        };

        pub const EnumDropdown = struct {
            area: Rect,
            popup_active: bool,
            slider_area: Rect = graph.Rec(0, 0, 0, 0),
            slider_range: Vec2f = .{ .x = 0, .y = 0 },
            slider_ptr: ?*f32 = null,

            done: bool = false,
            index: usize = 0,

            pub fn next(self: *EnumDropdown, comptime enumT: type) ?enumT {
                const info = @typeInfo(enumT).Enum.fields;
                if (self.index < info.len) {
                    defer self.index += 1;
                    inline for (info, 0..) |f, i| {
                        if (i == self.index)
                            return @enumFromInt(f.value);
                    }
                }
                return null;
            }

            pub fn set(self: *EnumDropdown, gui: *Context, enum_val: anytype, toset: anytype) void {
                if (!self.done) {
                    enum_val.* = toset;
                    gui.popup_id = null;
                    self.done = true;
                }
            }

            pub fn endFieldList(self: EnumDropdown, gui: *Context) !void {
                gui.endVLayoutScroll();
                _ = try gui.beginLayout(SubRectLayout, .{ .rect = self.slider_area }, .{});
            }

            pub fn end(self: EnumDropdown, gui: *Context) void {
                if (self.popup_active) {
                    gui.endLayout();
                    gui.endLayout();
                    gui.endPopup();
                }
            }
        };
    };

    const LayoutCacheData = struct {
        const WidgetDataChildT = f32;
        const WidgetDataT = std.AutoHashMap(u64, WidgetDataChildT);
        commands: std.ArrayList(DrawCommand) = undefined,
        last_frame_cmd_hash: u64 = 0,
        scissor: ?Rect = null,
        draw_cmds: bool = true,
        draw_backup: bool = false,

        hash: u64,

        rec: Rect,

        widget_index: u32 = 0,
        dirty: bool = true,

        widget_hashes: std.ArrayList(u64) = undefined,
        widget_hash_index: u32 = 0,

        widget_data: WidgetDataT = undefined,
        ds: OpaqueDataStore = undefined,

        was_init: bool = true, //Exist to draw debug indicator for fresh nodes
        is_init: bool = false,
        pub fn init(self: *@This(), alloc: std.mem.Allocator) void {
            if (self.is_init) unreachable;
            alloc_count += 1;
            self.is_init = true;
            self.widget_hashes = std.ArrayList(u64).init(alloc);
            self.widget_data = WidgetDataT.init(alloc);
            self.commands = std.ArrayList(DrawCommand).init(alloc);
            self.ds = OpaqueDataStore.init(alloc);
        }

        pub fn deinit(self: *@This()) void {
            if (self.is_init) {
                self.ds.deinit();
                self.widget_data.deinit();
                self.commands.deinit();
                dealloc_count += 1;
                self.widget_hashes.deinit();
            } else {
                unreachable;
            }
        }

        pub fn hashCommands(self: *@This()) void {
            self.last_frame_cmd_hash = dhash(self.commands.items);
        }

        pub fn getWidgetData(self: *@This(), init_value: WidgetDataChildT) !*WidgetDataChildT {
            const res = try self.widget_data.getOrPut(self.widget_hashes.items[self.widget_hash_index]);
            if (!res.found_existing) {
                res.value_ptr.* = init_value;
            }
            return res.value_ptr;
        }

        fn eql(a: @This(), b: @This()) bool {
            return a.hash == b.hash;
        }
    };
    const LayoutCacheT = Cache.StackCache(LayoutCacheData, LayoutCacheData.eql, .{ .log_debug = false });

    pub const ScrollData = struct {
        vertical_slider_area: ?Rect,
        horiz_slider_area: ?Rect,
        offset: *Vec2f,
        bar_w: f32, //????
    };

    pub const TooltipState = struct {
        command_list: std.ArrayList(DrawCommand),
        draw_area: ?Rect = null,

        pending_area: ?Rect = null,
        mouse_in_area: ?Rect = null,

        hover_time: u64 = 0,

        hide_active: bool = false,
    };

    pub const VLayoutScrollData = struct {
        data: ScrollData,
        area: Rect = graph.Rec(0, 0, 0, 0),
        layout: *VerticalLayout,
    };

    pub const WidgetId = struct {
        layout_hash: u64,
        index: u32,
        window_index: usize,

        pub fn eql(a: WidgetId, b: WidgetId) bool {
            return (a.layout_hash == b.layout_hash and a.index == b.index and a.window_index == b.window_index);
        }
    };

    pub const TextInputState = struct {
        pub const States = enum {
            start,
            stop,
            cont,
            disabled,
        };

        rect: Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
        state: States = .disabled,
        buffer: []const u8 = "",
        active_id: ?WidgetId = null,

        pub fn advanceStateReset(self: *TextInputState) void {
            self.state = switch (self.state) {
                .disabled => .disabled,
                .stop => .disabled,
                .cont => .stop,
                .start => .stop,
            };
        }

        pub fn advanceStateActive(self: *TextInputState, text_rect: Rect) void {
            self.rect = text_rect;
            self.state = switch (self.state) {
                .start => .cont,
                .disabled => .start,
                .cont, .stop => .cont,
            };
        }
    };

    pub const Window = struct {
        /// Memory stored in arena and reset every frame
        layout_stack: LayoutStackT = .{},
        /// Memory is retained and must be freed
        layout_cache: LayoutCacheT,

        area: Rect,
        /// Represents the screen space area of the current scroll area, when a nested scroll section is created,
        /// it is always clipped to exist inside the parent scroll_bounds
        scroll_bounds: ?Rect = null,

        depth: u32 = 0,

        pub fn init(alloc: std.mem.Allocator, area: Rect) !Window {
            return .{
                .layout_cache = try LayoutCacheT.init(alloc),
                .area = area,
            };
        }

        pub fn deinit(self: *@This()) void {
            self.layout_cache.deinit();
        }
    };

    window_index: ?usize = null,
    this_frame_num_windows: usize = 0,
    windows: std.ArrayList(Window),

    window_stack_node_index: usize = 0,
    window_stack_nodes: [32]WindowStackT.Node = undefined,

    window_stack: WindowStackT = .{},

    // Whatever window the mouse occupies has exclusive access to the pointer
    window_index_grabbed_mouse: ?usize = null,

    dirty_draw_depth: ?u32 = null,
    no_caching: bool = true,

    layout: Layout,
    current_layout_cache_data: ?*LayoutCacheData = null,

    frame_alloc: std.mem.Allocator,
    arena_alloc: *std.heap.ArenaAllocator,
    retained_alloc: std.mem.Allocator,

    tooltip_state: TooltipState,

    scratch_buf_pos: usize = 0,
    scratch_buf: []u8,
    tooltip_buf: []u8,

    input_state: InputState = .{},

    /// Stores the difference between slider_val and @trunc(slider_val) to prevent losing non integer changes in &val every frame.
    focused_slider_state: f32 = 0,
    draggable_state: Vec2f = .{ .x = 0, .y = 0 },

    text_input_state: TextInputState = .{},
    textbox_state: RetainedState.TextInput,

    enum_drop_down_scroll: Vec2f = .{ .x = 0, .y = 0 },

    /// The hash of the layout that has grabbed the mouse. Gets reset when mouse != held
    mouse_grab_id: ?WidgetId = null,
    mouse_released: bool = false,

    //TODO this field is for clickWidget, label or move to something
    click_timer: u64 = 0,
    held_timer: u64 = 0,
    last_clicked: ?WidgetId = null,

    // This field
    scroll_claimed_mouse: bool = false,

    focus_index: ?usize = 1,
    focus_counter: usize = 0,
    set_focused: bool = false,
    focused_area: ?graph.Rect = null,
    push_tooltip: bool = false,
    tooltip_text: []const u8 = "",
    last_frame_had_tooltip: bool = false,

    clamp_window: graph.Rect = .{},

    pub fn scratchPrint(self: *Self, comptime fmt: []const u8, args: anytype) []const u8 {
        var fbs = std.io.FixedBufferStream([]u8){ .buffer = self.scratch_buf[self.scratch_buf_pos..], .pos = 0 };
        fbs.writer().print(fmt, args) catch {
            return " !outofspace! ";
        };
        self.scratch_buf_pos += fbs.pos;
        return fbs.getWritten();
    }

    pub fn storeString(self: *Self, str: []const u8) []const u8 {
        const slice = self.frame_alloc.dupe(u8, str) catch {
            std.debug.panic("arena alloc failed", .{});
        };
        return slice;
    }

    pub fn isKeyDown(self: *Self, scancode: graph.SDL.keycodes.Scancode) bool {
        const s = self.ks(scancode);
        return s == .high or s == .rising;
    }

    fn ks(self: *Self, scancode: graph.SDL.keycodes.Scancode) graph.SDL.ButtonState {
        const sc: u32 = @intFromEnum(scancode);
        if (sc >= self.input_state.key_state.len)
            return .low;
        return self.input_state.key_state[sc];
    }

    pub fn isBindState(self: *Self, bind: graph.SDL.NewBind, state: graph.SDL.ButtonState) bool {
        if (self.text_input_state.state != .disabled) return state == .low;
        if (bind.mod == 0 or bind.mod ^ self.input_state.mod_state == 0) {
            const sc: u32 = switch (bind.key) {
                .scancode => |s| @intFromEnum(s),
                .keycode => |k| @intFromEnum(graph.SDL.getScancodeFromKey(k)),
            };
            if (sc >= self.input_state.key_state.len)
                return false;
            return self.input_state.key_state[sc] == state;
        }
        return state == .low;
    }

    pub fn keyState(self: *Self, scancode: graph.SDL.keycodes.Scancode) graph.SDL.ButtonState {
        if (self.text_input_state.state != .disabled) return .low;

        return self.ks(scancode);
    }

    pub fn isCursorInRect(self: *Self, r: Rect) bool {
        return r.containsPoint(self.input_state.mouse.pos);
    }

    pub fn getLayoutBounds(self: *Self) ?Rect {
        if (self.layout.isSet()) {
            return self.layout.bounds;
        }
        return null;
    }

    pub fn getArea(self: *Self) ?Rect {
        const w = self.getWindow();
        const new_area = self.layout.getArea();
        self.tooltip_state.pending_area = new_area;
        if (w.scroll_bounds) |sb| {
            if (!sb.overlap(new_area orelse return null))
                return null;
        }
        if (self.set_focused) {
            self.focused_area = new_area;
            self.set_focused = false;
        }
        self.push_tooltip = false;
        if (new_area) |a|
            self.push_tooltip = self.isCursorInRect(a); //TODO check if this window has mouse grab
        return new_area;
    }

    pub fn setTooltip(
        self: *Self,
        comptime fmt: []const u8,
        args: anytype,
    ) void {
        if (self.push_tooltip) {
            var fbs = std.io.FixedBufferStream([]u8){ .buffer = self.tooltip_buf, .pos = 0 };
            fbs.writer().print(fmt, args) catch {
                return;
            };
            self.tooltip_text = fbs.getWritten();

            self.last_frame_had_tooltip = true;
        }
    }

    pub fn tooltip(self: *Self, message: []const u8, size: f32, font: *Font) void {
        const ts = &self.tooltip_state;
        const pa = ts.pending_area orelse return;
        if (self.isCursorInRect(pa)) {
            if (ts.mouse_in_area) |ma| {
                if (ma.eql(pa)) {
                    ts.hover_time += 1;
                    if (ts.hover_time > 20 and !ts.hide_active) {
                        if (self.input_state.mouse.left == .rising) {
                            ts.hide_active = true;
                        }
                        const bounds = font.textBounds(message, size);
                        const mp = self.input_state.mouse.pos;
                        ts.command_list.append(.{ .rect_filled = .{ .r = Rect.newV(mp, bounds), .color = Colori.Gray } }) catch unreachable;
                        ts.command_list.append(.{
                            .text = .{ .string = message, .pos = mp.toI(i16, Vec2i), .size = size, .color = Colori.White, .font = font },
                        }) catch unreachable;
                    }
                } else {
                    ts.hover_time = 0;
                }
            }
            ts.mouse_in_area = ts.pending_area;
        }
        //is the mouse in this area?
        //has the mouse been in this area for atleast n frames
    }

    pub fn getId(self: *Self) WidgetId {
        if (self.current_layout_cache_data) |ld| {
            ld.widget_index += 1;
            return .{ .layout_hash = ld.hash, .index = ld.widget_index, .window_index = self.window_index.? };
        }
        std.debug.panic("getId called without a layout set!", .{});
    }

    pub fn isActiveTextinput(self: *Self, id: WidgetId) bool {
        if (self.text_input_state.active_id) |t_id| {
            return t_id.eql(id);
        }
        return false;
    }

    //prop table
    //pop_index ?usize
    pub fn storeLayoutData(self: *Self, comptime T: type, init_value: T, name: []const u8) !*T {
        if (self.current_layout_cache_data) |lcd| {
            return try lcd.ds.storeI(T, init_value, name);
        }
        unreachable;
    }

    pub fn init(alloc: std.mem.Allocator) !Self {
        const aa = try alloc.create(std.heap.ArenaAllocator);
        aa.* = std.heap.ArenaAllocator.init(alloc);
        return Self{
            .arena_alloc = aa,
            .scratch_buf = try alloc.alloc(u8, 4096 * 4),
            .tooltip_buf = try alloc.alloc(u8, 1024),
            .layout = .{ .bounds = graph.Rec(0, 0, 0, 0) },
            .windows = std.ArrayList(Window).init(alloc),
            .frame_alloc = aa.allocator(),
            .retained_alloc = alloc,
            .tooltip_state = .{ .command_list = std.ArrayList(DrawCommand).init(aa.allocator()) },
            .textbox_state = RetainedState.TextInput.init(alloc),
        };
    }

    pub fn reset(self: *Self, input_state: InputState, clamp_window: graph.Rect) !void {
        if (self.window_index != null) return error.unmatchedBeginWindow;

        self.clamp_window = clamp_window;
        self.focus_counter = 0;
        self.focused_area = null;
        if (!self.last_frame_had_tooltip) {
            self.tooltip_text = "";
        }
        self.last_frame_had_tooltip = false;

        //Iterate last frames windows and determine the deepest window current mouse_pos occupies
        var deepest_index: ?usize = null;
        var max_depth: usize = 0;
        for (self.windows.items[0..self.this_frame_num_windows], 0..) |w, i| {
            if (w.area.containsPoint(input_state.mouse.pos)) {
                if (w.depth > max_depth) {
                    max_depth = w.depth;
                    deepest_index = i;
                }
            }
        }
        self.window_index_grabbed_mouse = deepest_index;

        self.this_frame_num_windows = 0;
        self.window_stack_node_index = 0;

        self.dirty_draw_depth = null;
        self.scratch_buf_pos = 0;
        self.scroll_claimed_mouse = false;

        //if (self.scroll_bounds != null) return error.unmatchedBeginScroll;
        self.text_input_state.advanceStateReset();
        _ = self.arena_alloc.reset(.retain_capacity);
        self.tooltip_state.command_list = std.ArrayList(DrawCommand).init(self.frame_alloc);
        if (self.tooltip_state.mouse_in_area) |ma| {
            if (!self.isCursorInRect(ma)) {
                self.tooltip_state.hover_time = 0;
                self.tooltip_state.hide_active = false;
            }
        }
        self.input_state = input_state;

        self.layout.reset();
        self.click_timer += 1;
        self.held_timer = if (self.input_state.mouse.left == .high) self.held_timer + 1 else 0;

        if (self.mouse_released) {
            self.mouse_grab_id = null;
            self.mouse_released = false;
        }
        if (!(self.input_state.mouse.left == .high) and self.mouse_grab_id != null) {
            self.mouse_released = true;
        }
    }

    pub fn deinit(self: *Self) void {
        for (self.windows.items) |*w| {
            w.deinit();
        }
        self.windows.deinit();
        self.retained_alloc.free(self.scratch_buf);
        self.retained_alloc.free(self.tooltip_buf);
        self.textbox_state.deinit();
        self.arena_alloc.deinit();
        self.retained_alloc.destroy(self.arena_alloc);
    }

    pub fn clickWidget(self: *Self, rec: Rect) ClickState {
        return self.clickWidgetEx(rec, .{}).click;
    }

    pub fn getMouseWheelDelta(self: *Self) ?f32 {
        const w = self.getWindow();
        const sb = if (w.scroll_bounds) |s| s else w.area;
        if (self.mouse_grab_id == null and !self.scroll_claimed_mouse and sb.containsPoint(self.input_state.mouse.pos) and self.window_index_grabbed_mouse orelse 1000 == self.window_index.?) {
            self.scroll_claimed_mouse = true;
            return self.input_state.mouse.wheel_delta.y;
        }
        return null;
    }

    /// clickWidget is used to access pointer state.
    pub fn clickWidgetEx(self: *Self, rec: Rect, opts: struct {
        teleport_area: ?Rect = null,
        override_depth_test: bool = false,
    }) struct { click: ClickState, id: WidgetId } {
        const id = self.getId();

        const containsCursor = rec.containsPoint(self.input_state.mouse.pos);
        const clicked = self.input_state.mouse.left == .rising;
        const w = self.getWindow();

        if (self.mouse_grab_id) |grab_id| {
            if (grab_id.eql(id)) {
                if (self.mouse_released) {
                    self.click_timer = 0;
                    self.last_clicked = id;
                    self.mouse_grab_id = null;
                    return .{ .click = .click_release, .id = id };
                }
                return .{ .click = .held, .id = id };
            }
        } else {
            if (self.window_index_grabbed_mouse != self.window_index.? and !opts.override_depth_test)
                return .{ .click = .none, .id = id };
            if (w.scroll_bounds) |sb| {
                if (!sb.containsPoint(self.input_state.mouse.pos))
                    return .{ .click = .none, .id = id };
            }
            if (opts.teleport_area) |parent_area| {
                if (clicked and !containsCursor and parent_area.containsPoint(self.input_state.mouse.pos)) {
                    self.mouse_grab_id = id;
                    return .{ .click = .click_teleport, .id = id };
                }
            }
            const ret: ClickState = if (containsCursor) (if (clicked) .click else .hover) else .none;
            if (ret == .click) {
                if (!self.isActiveTextinput(id)) {
                    self.text_input_state.active_id = null;
                    self.text_input_state.state = .stop;
                }

                self.mouse_grab_id = id;
                const double_click_time = 10;
                if (self.click_timer < double_click_time) {
                    if (self.last_clicked) |lc| {
                        if (lc.eql(id))
                            return .{ .click = .double, .id = id };
                    }
                }
            }
            return .{ .click = ret, .id = id };
        }

        return .{ .click = if (containsCursor) .hover_no_focus else .none, .id = id };
    }

    pub fn isFocused(self: *Self) bool {
        self.focus_counter += 1;
        if (self.focus_index) |fi| {
            const f = (fi == self.focus_counter);
            self.set_focused = f;
            return f;
        }
        return false;
    }

    pub fn draggable(self: *Self, area: Rect, mdelta_scale: Vec2f, x_val: anytype, y_val: anytype, opts: struct {
        x_min: ?f32 = null,
        x_max: ?f32 = null,
        y_min: ?f32 = null,
        y_max: ?f32 = null,
        override_depth_test: bool = false,
    }) ClickState {
        const Helper = struct {
            const Type = std.builtin.Type;

            fn getVal(comptime info: Type, val: anytype) f32 {
                return switch (info) {
                    .int => @floatFromInt(val.*),
                    .float => @as(f32, @floatCast(val.*)),
                    .void => 0,
                    else => @compileError("invalid type"),
                };
            }

            fn addDelta(comptime info: Type, val: *f32, delta: f32, trunc_state: *f32) void {
                if (info == .int or info == .float)
                    val.* += delta + trunc_state.*;
                if (info == .int)
                    trunc_state.* = val.* - @trunc(val.*);
            }

            fn setVal(comptime info: Type, valptr: anytype, val: f32, min: ?f32, max: ?f32) void {
                const math = std.math;
                switch (info) {
                    .float => {
                        valptr.* = math.clamp(val, if (min) |m| m else math.floatMin(f32), if (max) |mx| mx else math.floatMax(f32));
                    },
                    .int => {
                        const cval = math.clamp(val, if (min) |m| m else math.minInt(@Type(info)), if (max) |mx| mx else math.maxInt(@Type(info)));
                        valptr.* = @as(@typeInfo(@TypeOf(valptr)).pointer.child, @intFromFloat(@trunc(cval)));
                    },
                    .void => {},
                    else => @compileError("invalid type"),
                }
            }
        };
        const xptrinfo = @typeInfo(@TypeOf(x_val));
        const xinfo = @typeInfo(xptrinfo.pointer.child);
        const yptrinfo = @typeInfo(@TypeOf(y_val));
        const yinfo = @typeInfo(yptrinfo.pointer.child);

        var val: Vec2f = .{ .x = Helper.getVal(xinfo, x_val), .y = Helper.getVal(yinfo, y_val) };
        const click = self.clickWidgetEx(area, .{ .override_depth_test = opts.override_depth_test }).click;

        if (click == .click) {
            self.draggable_state = .{ .x = 0, .y = 0 };
        }
        if (click == .click or click == .held) {
            Helper.addDelta(xinfo, &val.x, mdelta_scale.x * self.input_state.mouse.delta.x, &self.draggable_state.x);
            Helper.addDelta(yinfo, &val.y, mdelta_scale.y * self.input_state.mouse.delta.y, &self.draggable_state.y);
        }
        Helper.setVal(xinfo, x_val, val.x, opts.x_min, opts.x_max);
        Helper.setVal(yinfo, y_val, val.y, opts.y_min, opts.y_max);
        return click;
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

    pub fn beginWindow(self: *Self, area: Rect) !void {
        var old_depth: u32 = 0;
        if (self.window_index) |old_index| { //Push old window so we can restore after
            self.window_stack_nodes[self.window_stack_node_index] = .{ .data = old_index };
            self.window_stack.prepend(&self.window_stack_nodes[self.window_stack_node_index]);
            old_depth = self.windows.items[old_index].depth;
            //self.windows.items[old_index]
            const node = try self.frame_alloc.create(LayoutStackT.Node);
            node.next = null;
            node.data = self.layout;
            self.layoutStackPush(node);
            self.window_stack_node_index += 1;
            if (self.window_stack_node_index >= self.window_stack_nodes.len)
                return error.tooManyWindows;
        }
        self.this_frame_num_windows += 1;
        self.window_index = self.this_frame_num_windows - 1;
        //self.window_index = if (self.window_index) |ind| ind + 1 else 0;
        if (self.window_index.? >= self.windows.items.len) {
            try self.windows.append(try Window.init(self.retained_alloc, area));
        }
        const w = self.getWindow();
        w.area = area;
        w.depth = old_depth + 1;
        try w.layout_cache.begin();
        if (w.layout_stack.len() > 0)
            return error.unmatchedBeginLayout;

        self.layout.reset();
        self.layout.bounds = area;
        self.current_layout_cache_data = null;
        _ = try self.beginLayout(SubRectLayout, .{ .rect = area }, .{});
    }

    pub fn endWindow(self: *Self) void {
        //Set self.layout back to the prev windows first layout
        self.endLayout(); //The window's SubRect layout
        if (self.window_stack.popFirst()) |prev_window| {
            self.window_index = prev_window.data;
        } else {
            self.window_index = null;
        }
        if (self.window_index) |ind| {
            const old_w = &self.windows.items[ind];
            const layout = self.layoutStackPop();
            self.layout = layout.data;
            self.current_layout_cache_data = old_w.layout_cache.getCacheDataPtr();
        }
    }

    pub fn getWindow(self: *Self) *Window {
        return &self.windows.items[self.window_index orelse std.debug.panic("attempt to getWindow when no window set!", .{})];
    }

    fn layoutStackPush(self: *Self, node: *LayoutStackT.Node) void {
        const w = self.getWindow();
        w.layout_stack.prepend(node);
    }

    fn layoutStackPop(self: *Self) *LayoutStackT.Node {
        const w = self.getWindow();
        return w.layout_stack.popFirst() orelse std.debug.panic("invalid layout stack!", .{});
    }

    fn layoutCachePush(self: *Self, new_ld: LayoutCacheData) !void {
        const w = self.getWindow();
        { //Layout cache
            const dirty = if (self.current_layout_cache_data) |ld| ld.dirty else false;
            try w.layout_cache.push(new_ld);
            self.current_layout_cache_data = w.layout_cache.getCacheDataPtr();
            const ld = self.current_layout_cache_data.?;
            ld.widget_index = 0;
            ld.widget_hash_index = 0;

            if (dirty or !ld.is_init or self.no_caching) {
                //_ = opts;
                //self.drawRectFilled(self.layout.bounds, opts.bg);
            }

            if (!ld.is_init) {
                ld.init(self.retained_alloc);
            } else {
                ld.was_init = false;
            }
            //ld.hashCommands();
            try ld.commands.resize(0);

            ld.dirty = dirty;
        }
    }

    fn layoutCachePop(self: *Self) void {
        const w = self.getWindow();
        w.layout_cache.pop() catch std.debug.panic("invalid layout cache!", .{});
        self.current_layout_cache_data = w.layout_cache.getCacheDataPtr();
    }

    pub fn beginLayout(self: *Self, comptime Layout_T: type, layout_data: Layout_T, opts: struct { bg: u32 = 0x222222ff, scissor: ?Rect = null }) !*Layout_T {
        const new_layout = try self.frame_alloc.create(Layout_T);
        new_layout.* = layout_data;

        const old_layout = self.layout;
        if (self.layout.isSet()) {
            if (Layout_T == SubRectLayout) {
                self.layout.bounds = layout_data.rect;
            } else {
                const child_area = self.getArea();
                self.layout.bounds = child_area orelse Rect.new(0, 0, 0, 0);
                if (child_area == null)
                    new_layout.hidden = true;
            }
        }

        const node = try self.frame_alloc.create(LayoutStackT.Node);
        node.next = null;
        node.data = old_layout;
        self.layoutStackPush(node);
        //self.layout_stack.prepend(node);
        self.layout.setNew(Layout_T, new_layout);

        { //Layout cache
            try self.layoutCachePush(.{ .hash = self.layout.hash(), .rec = self.layout.bounds, .scissor = opts.scissor });
        }
        return new_layout;
    }

    pub fn endLayout(self: *Self) void {
        {
            const ld = self.current_layout_cache_data.?;
            const last_frame_hash = ld.last_frame_cmd_hash;
            ld.hashCommands();
            ld.draw_cmds = (ld.last_frame_cmd_hash != last_frame_hash);
        }

        self.layoutCachePop();
        const layout = self.layoutStackPop();
        self.layout = layout.data;
    }

    pub fn skipArea(self: *Self) void {
        _ = self.getArea();
    }

    pub fn draw(self: *Self, command: DrawCommand) void {
        if (self.current_layout_cache_data) |lcd| {
            lcd.commands.append(command) catch std.debug.panic("failed to append to draw commands", .{});
        }
    }

    pub fn drawSetCamera(self: *Self, cam: DrawCommand) void {
        self.draw(cam);
    }

    pub fn drawText(self: *Self, string: []const u8, pos: Vec2f, size: f32, color: u32, font: *Font) void {
        self.draw(.{ .text = .{ .string = self.storeString(string), .pos = pos.toI(i16, Vec2i), .size = size, .color = color, .font = font } });
    }

    pub fn drawIcon(self: *Self, icon: u21, pos: Vec2f, size: f32, color: u32, font: *Font) void {
        var out: [4]u8 = undefined;
        const count = std.unicode.utf8Encode(icon, &out) catch unreachable;
        self.draw(.{ .text = .{ .string = self.storeString(out[0..count]), .pos = pos.toI(i16, Vec2i), .size = size, .color = color, .font = font } });
    }

    pub fn drawLine(self: *Self, a: Vec2f, b: Vec2f, color: u32) void {
        self.draw(.{ .line = .{ .a = a, .b = b, .color = color } });
    }

    pub fn drawRectFilled(self: *Self, r: Rect, color: u32) void {
        self.draw(.{ .rect_filled = .{ .r = r, .color = color } });
    }

    pub fn drawRectOutline(self: *Self, r: Rect, color: u32) void {
        self.draw(.{ .rect_outline = .{ .r = r, .color = color } });
    }

    pub fn drawRectTextured(self: *Self, r: Rect, color: u32, uv: Rect, t: graph.Texture) void {
        self.draw(.{ .rect_textured = .{ .r = r, .color = color, .uv = uv, .texture = t } });
    }

    //Colors are wound ccw, starting at top left
    pub fn drawRectMultiColor(self: *Self, r: Rect, colors: [4]u32) void {
        self.draw(.{ .rect_filled_multi_color = .{ .r = r, .colors = colors } });
    }

    pub fn draw9Border(self: *Self, r: Rect, tr: Rect, texture: graph.Texture, scale: f32, cutout_start: f32, cutout_end: f32) void {
        self.draw(.{ .rect_9border = .{
            .r = r,
            .uv = tr,
            .texture = texture,
            .scale = scale,
            .cutout_start = cutout_start,
            .cutout_end = cutout_end,
        } });
    }

    pub fn draw9Slice(self: *Self, r: Rect, tr: Rect, texture: graph.Texture, scale: f32) void {
        self.draw(.{ .rect_9slice = .{
            .r = r,
            .uv = tr,
            .texture = texture,
            .scale = scale,
        } });
    }

    pub fn drawTextFmt(
        self: *Self,
        comptime fmt: []const u8,
        args: anytype,
        area: Rect,
        size: f32,
        color: u32,
        opts: struct { justify: Justify = .left },
        font: *Font,
    ) void {
        const slice = self.scratchPrint(fmt, args);
        //const slice = fbs.getWritten();
        const bounds = font.textBounds(slice, size);
        const last_char_index = blk: {
            if (font.nearestGlyphX(slice, size, .{ .x = area.w, .y = 0 }, true)) |lci| {
                if (lci > 0)
                    break :blk lci - 1;
                break :blk lci;
            }
            break :blk slice.len;
        };

        const x_ = switch (opts.justify) {
            .left => area.x,
            .right => area.x + area.w - bounds.x,
            .center => area.x + area.w / 2 - bounds.x / 2,
        };
        const x = if (last_char_index < slice.len) area.x else x_;
        const sl = if (last_char_index < slice.len) slice[0..last_char_index] else slice;
        self.drawText(sl, Vec2f.new(x, area.y), size, color, font);
    }

    pub fn beginScroll(self: *Self, offset: *Vec2f, opts: struct {
        horiz_scroll: bool = false,
        vertical_scroll: bool = false,
        bar_w: f32 = 60,
        scroll_area_w: f32,
        scroll_area_h: f32,
    }) !?ScrollData {
        var area = self.getArea() orelse return null;

        const w = self.getWindow();
        if (opts.horiz_scroll)
            area.h -= opts.bar_w;
        if (opts.vertical_scroll)
            area.w -= opts.bar_w;

        var clipped_area = area;
        //Scroll exists inside a scroll. Push bounds and offset into parent layout
        if (w.scroll_bounds) |parent_b| {
            self.layout.parent_scroll_bounds = parent_b;

            if (area.x < parent_b.x) { //Passed the left, clip left
                clipped_area.x = parent_b.x;
                if (clipped_area.x + clipped_area.w > parent_b.x + parent_b.w)
                    clipped_area.w = (parent_b.x + parent_b.w) - clipped_area.x;
            } else if (area.x + area.w > parent_b.x + parent_b.w) { //Passed the right, clip right
                clipped_area.w = (parent_b.x + parent_b.w) - clipped_area.x;
            }

            if (area.y < parent_b.y) {
                clipped_area.y = parent_b.y;
            } else if (area.y + area.h > parent_b.y + parent_b.h) {
                clipped_area.h = (parent_b.y + parent_b.h) - clipped_area.y;
            }
        }

        w.scroll_bounds = clipped_area;
        _ = try self.beginLayout(
            SubRectLayout,
            .{ .rect = graph.Rec(area.x - offset.x, area.y - offset.y, if (!opts.horiz_scroll) area.w else opts.scroll_area_w, opts.scroll_area_h) },
            .{ .scissor = clipped_area },
        );

        return ScrollData{
            .horiz_slider_area = if (opts.horiz_scroll) graph.Rec(area.x, area.y + area.h, area.w, opts.bar_w) else null,
            .vertical_slider_area = if (opts.vertical_scroll) graph.Rec(area.x + area.w, area.y, opts.bar_w, area.h) else null,
            .bar_w = opts.bar_w,
            .offset = offset,
        };
    }

    pub fn endScroll(self: *Self) void {
        self.endLayout(); //SubRectLayout
        const w = self.getWindow();

        w.scroll_bounds = self.layout.parent_scroll_bounds;
    }

    pub fn beginVLayoutScroll(self: *Self, scr: *Vec2f, layout: VerticalLayout, scroll_bar_w: f32) !?VLayoutScrollData {
        const bar_w = scroll_bar_w;
        if (try self.beginScroll(scr, .{
            .scroll_area_w = self.layout.bounds.w - bar_w,
            .scroll_area_h = 10000, //TODO have way of making size grow
            .vertical_scroll = true,
            .horiz_scroll = false,
            .bar_w = bar_w,
        })) |scroll| {
            return .{ .layout = try self.beginLayout(VerticalLayout, layout, .{}), .data = scroll };
        }
        return null;
    }

    pub fn endVLayoutScroll(self: *Self) void {
        self.endLayout();
        self.endScroll();
    }

    //Given the number val between min,max, normalize using exp base b
    fn sliderScaleFn(base: f32, min: f32, max: f32, val: f32) f32 {
        if (base == 1) {
            return (val - min) / (max - min);
        }

        return (std.math.pow(f32, base, (val - min) / max) - 1) / (base - 1);
    }

    fn sliderScaleFnInv(base: f32, min: f32, max: f32, norm: f32) f32 {
        if (base == 1) {
            return (max - min) * norm + min;
        }
        return @log(norm * (base - 1) + 1) / @log(base) * max + min;
    }

    pub fn sliderGeneric(self: *Self, number_ptr: anytype, min: anytype, max: anytype, params: struct {
        base: f32 = 1,
        handle_offset_x: f32 = 0,
        handle_offset_y: f32 = 0,
        handle_w: f32,
        handle_h: f32,
        orientation: Orientation = .horizontal,
    }) ?GenericWidget.Slider {
        const orient = params.orientation;
        const is_horiz = (params.orientation == .horizontal);
        const lmin = std.math.lossyCast(f32, min);
        const lmax = std.math.lossyCast(f32, max);
        const invalid_type_error = @typeName(@This()) ++ ".sliderGeneric: " ++ "Argument \'number_ptr\' expects a mutable pointer to an int or float. Recieved: " ++ @typeName(@TypeOf(number_ptr));
        const pinfo = @typeInfo(@TypeOf(number_ptr));
        if (pinfo != .pointer or pinfo.pointer.is_const) @compileError(invalid_type_error);
        const number_type = pinfo.pointer.child;
        const number_t: GenericWidget.NumType = switch (@typeInfo(number_type)) {
            .float => .float,
            .int => |int| switch (int.signedness) {
                .signed => .int,
                .unsigned => .uint,
            },
            else => @compileError(invalid_type_error),
        };

        //arec is the actual area the slider exists in, regardless of orientation
        //rec is the area the slider would occupy if it was horizontal
        //it is important to remember that the position and dimensions of rec are not located in screen space.
        const arec = self.getArea() orelse return null;
        const rec = if (is_horiz) arec else arec.swapAxis();
        const handle_h = rec.h;

        if (lmax - lmin == 0)
            return null;

        const mdel = orient.vec2fComponent(self.input_state.mouse.delta);
        const mpos = orient.vec2fComponent(self.input_state.mouse.pos);
        const scale = (rec.w - params.handle_w - (params.handle_offset_x * 2)) / (lmax - lmin);

        const sc = (rec.w - params.handle_w - (params.handle_offset_x * 2));
        //normalize val
        //mul by sc to convert to ss

        var val: f32 = switch (number_t) {
            .float => @as(f32, @floatCast(number_ptr.*)),
            .int, .uint => @as(f32, @floatFromInt(number_ptr.*)),
        };

        var handle: Rect = switch (orient) {
            //.horizontal => Rect.new(params.handle_offset_x + arec.x + (val - min) * scale, params.handle_offset_y + arec.y, params.handle_w, handle_h),
            //.vertical => Rect.new(params.handle_offset_y + arec.x, params.handle_offset_x + arec.y + (val - min) * scale, handle_h, params.handle_w),
            .horizontal => Rect.new(params.handle_offset_x + arec.x + sliderScaleFn(params.base, lmin, lmax, val) * sc, params.handle_offset_y + arec.y, params.handle_w, handle_h),
            .vertical => Rect.new(params.handle_offset_y + arec.x, params.handle_offset_x + arec.y + sliderScaleFn(params.base, lmin, lmax, val) * sc, handle_h, params.handle_w),
        };

        const clicked = self.clickWidget(handle);

        if (clicked == .click) {
            self.focused_slider_state = 0;
        }

        // Only moving the slider until after our initial .click state prevents the slider from teleporting when used with a touch screen or other input method that teleports the cursor like a drawing tablet.
        if (clicked == .held) {
            const new = std.math.clamp(sliderScaleFn(params.base, lmin, lmax, val + self.focused_slider_state) + mdel / sc, 0, 1);
            val = sliderScaleFnInv(params.base, lmin, lmax, new);

            //val += self.focused_slider_state;
            //val += mdel / scale;
            //val = std.math.clamp(val, lmin, lmax);

            //Prevent the slider's and the cursor's position from becoming misaligned when the cursor goes past the slider boundries.
            if (mpos - params.handle_offset_x > rec.x + rec.w)
                val = lmax;
            if (mpos + params.handle_offset_x < rec.x)
                val = lmin;

            if (number_t == .int or number_t == .uint)
                self.focused_slider_state = (val - @trunc(val));
            //(if (is_horiz) handle.x else handle.y) = params.handle_offset_x + rec.x + (val - lmin) * scale;
            (if (is_horiz) handle.x else handle.y) = params.handle_offset_x + rec.x + new * sc;
        }

        if (arec.containsPoint(self.input_state.mouse.pos)) {
            //BROKEN WITH LOG
            if (self.getMouseWheelDelta()) |del| {
                switch (number_t) {
                    .float => {},
                    .int, .uint => {
                        val += del;
                        val = std.math.clamp(val, lmin, lmax);
                    },
                }
            }
        }

        switch (number_t) {
            .float => {
                number_ptr.* = val;
            },
            .uint, .int => {
                number_ptr.* = @as(number_type, @intFromFloat(@trunc(val)));
                (if (is_horiz) handle.x else handle.y) = params.handle_offset_x + rec.x + (@trunc(val) - min) * scale;
            },
        }

        return .{
            .area = arec,
            .handle = handle,
            .click = clicked,
        };
    }

    pub fn buttonGeneric(self: *Self) GenericWidget.Button {
        const area = self.getArea() orelse return .{};
        const click = self.clickWidget(area);
        return .{ .area = area, .state = click };
    }

    pub fn checkboxGeneric(self: *Self, checked: *bool) ?GenericWidget.Checkbox {
        const area = self.getArea() orelse return null;
        var changed = false;
        const click = self.clickWidget(area);
        if (click == .click or click == .double) {
            checked.* = !checked.*;
            changed = true;
        }

        return .{ .area = area, .changed = changed };
    }

    //This should take a generic structure that has on optional, resize function or something.
    //The function can then support static or dynamic buffers
    pub fn textboxGeneric(self: *Self, contents: *std.ArrayList(u8), font: *Font, params: struct {
        text_h: f32,
        text_inset: f32,
        restrict_chars_to: ?[]const u8 = null,
    }) !?GenericWidget.Textbox {
        const area = self.getArea() orelse return null;
        const cw = self.clickWidgetEx(area, .{});
        const click = cw.click;
        const id = cw.id;
        const trect = area.inset(params.text_inset);
        var ret = GenericWidget.Textbox{
            .area = area,
            .text_area = trect,
            .caret = null,
            .slice = contents.items,
            .selection_pos_min = 0,
            .selection_pos_max = 0,
        };

        if (self.isActiveTextinput(id)) {
            if (self.keyState(.TAB) == .rising) {}
            const tb = &self.textbox_state;
            self.text_input_state.advanceStateActive(trect);
            try tb.handleEventsOpts(
                self.text_input_state.buffer,
                self.input_state,
                .{ .restricted_charset = params.restrict_chars_to },
            );
            const sl = tb.getSlice();
            const caret_x = font.textBounds(sl[0..@as(usize, @intCast(tb.head))], params.text_h).x;
            ret.caret = caret_x;
            if (tb.head != tb.tail) {
                const tail_x = font.textBounds(sl[0..@intCast(tb.tail)], params.text_h).x;
                ret.selection_pos_max = @max(caret_x, tail_x);
                ret.selection_pos_min = @min(caret_x, tail_x);
            }

            if (!std.mem.eql(u8, sl, contents.items)) {
                try contents.resize(sl.len);
                @memcpy(contents.items, sl);
            }
        }
        if (click == .click) {
            if (!self.isActiveTextinput(id)) {
                self.text_input_state.active_id = id;
                try self.textbox_state.resetFmt("{s}", .{contents.items});
            }
            const cin = font.nearestGlyphX(self.textbox_state.getSlice(), params.text_h, self.input_state.mouse.pos.sub(trect.pos()), true);
            if (cin) |cc| {
                self.textbox_state.setHead(cc, 0, true);
            }
        } else if (click == .held and self.held_timer > 4) {
            const cin = font.nearestGlyphX(self.textbox_state.getSlice(), params.text_h, self.input_state.mouse.pos.sub(trect.pos()), true);
            if (cin) |cc|
                self.textbox_state.setHead(cc, 0, false);
        }
        ret.slice = contents.items;
        return ret;
    }

    pub fn textboxGeneric2(self: *Self, contents: anytype, font: *Font, params: struct {
        text_h: f32,
        text_inset: f32,
        restrict_chars_to: ?[]const u8 = null,
        make_active: bool = false,
        make_inactive: bool = false,
    }) !?GenericWidget.Textbox {
        const area = self.getArea() orelse return null;
        const cw = self.clickWidgetEx(area, .{});
        const click = cw.click;
        const id = cw.id;
        const trect = area.inset(params.text_inset);
        const slice = contents.getSlice();
        var ret = GenericWidget.Textbox{
            .area = area,
            .text_area = trect,
            .caret = null,
            .slice = slice,
            .selection_pos_min = 0,
            .selection_pos_max = 0,
        };
        if (params.make_active) {
            if (!self.isActiveTextinput(id)) {
                self.text_input_state.active_id = id;
                try self.textbox_state.resetFmt("{s}", .{contents.getSlice()});
            }
        }

        if (self.isActiveTextinput(id)) {
            const tb = &self.textbox_state;
            self.text_input_state.advanceStateActive(trect);
            try tb.handleEventsOpts(
                self.text_input_state.buffer,
                self.input_state,
                .{ .restricted_charset = params.restrict_chars_to, .max_len = contents.getMaxLen() },
            );
            const sl = tb.getSlice();
            const caret_x = font.textBounds(sl[0..@as(usize, @intCast(tb.head))], params.text_h).x;
            ret.caret = caret_x;
            if (tb.head != tb.tail) {
                const tail_x = font.textBounds(sl[0..@intCast(tb.tail)], params.text_h).x;
                ret.selection_pos_max = @max(caret_x, tail_x);
                ret.selection_pos_min = @min(caret_x, tail_x);
            }

            if (!std.mem.eql(u8, sl, slice)) {
                const l = try contents.setSlice(sl);
                if (l > 0) {}
            }
            if (params.make_inactive)
                self.text_input_state.active_id = null;
        }
        if (click == .click) {
            if (!self.isActiveTextinput(id)) {
                self.text_input_state.active_id = id;
                try self.textbox_state.resetFmt("{s}", .{contents.getSlice()});
            }
            const cin = font.nearestGlyphX(self.textbox_state.getSlice(), params.text_h, self.input_state.mouse.pos.sub(trect.pos()), true);
            if (cin) |cc| {
                self.textbox_state.setHead(cc, 0, true);
            }
        } else if (click == .held and self.held_timer > 4) {
            const cin = font.nearestGlyphX(self.textbox_state.getSlice(), params.text_h, self.input_state.mouse.pos.sub(trect.pos()), true);
            if (cin) |cc|
                self.textbox_state.setHead(cc, 0, false);
        }
        ret.slice = contents.getSlice();
        return ret;
    }

    // TODO Should we defer updates of number_ptr until enter is pressed or the textbox unfocused?
    pub fn textboxNumberGeneric(self: *Self, number_ptr: anytype, font: *Font, params: struct {
        text_inset: f32,
    }) !?GenericWidget.Textbox {
        const NumType = enum { uint, int, float };

        const comptime_err_prefix = @typeName(@This()) ++ ".textboxNumberGeneric: ";
        const invalid_type_error = comptime_err_prefix ++ "Argument \'number_ptr\' expects a mutable pointer to an int or float. Recieved: " ++ @typeName(@TypeOf(number_ptr));
        const area = self.getArea() orelse return null;
        const tarea = area.inset(params.text_inset);

        const pinfo = @typeInfo(@TypeOf(number_ptr));
        if (pinfo != .pointer or pinfo.pointer.is_const) @compileError(invalid_type_error);
        const number_type = pinfo.pointer.child;
        const number_t: NumType = switch (@typeInfo(number_type)) {
            .float => .float,
            .int => |int| switch (int.signedness) {
                .signed => .int,
                .unsigned => .uint,
            },
            else => @compileError(invalid_type_error),
        };

        const cw = self.clickWidgetEx(area, .{});
        const id = cw.id;
        const click = cw.click;
        var ret = GenericWidget.Textbox{
            .area = area,
            .text_area = tarea,
            .caret = null,
            .slice = "",
        };

        if (self.isActiveTextinput(id)) {
            const tb = &self.textbox_state;
            const charset = switch (number_t) {
                .int => "-0123456789xabcdefABCDEF",
                .uint => "0123456789xabcdefABCDEF",
                .float => "ainf.-0123456789",
            };
            self.text_input_state.advanceStateActive(tarea);
            try self.textbox_state.handleEventsOpts(
                self.text_input_state.buffer,
                self.input_state,
                .{ .restricted_charset = charset },
            );
            const sl = self.textbox_state.getSlice();
            const caret_x = font.textBounds(sl[0..@as(usize, @intCast(self.textbox_state.head))], tarea.h).x;
            if (tb.head != tb.tail) {
                const tail_x = font.textBounds(sl[0..@intCast(tb.tail)], tarea.h).x;
                ret.selection_pos_max = @max(caret_x, tail_x);
                ret.selection_pos_min = @min(caret_x, tail_x);
            }
            ret.caret = caret_x;
            if (sl.len == 0) {
                number_ptr.* = 0;
            } else {
                number_ptr.* = switch (number_t) {
                    .float => std.fmt.parseFloat(number_type, sl) catch blk: {
                        ret.is_invalid = true;
                        break :blk number_ptr.*;
                    },
                    .uint, .int => std.fmt.parseInt(number_type, sl, 0) catch blk: {
                        ret.is_invalid = true;
                        break :blk number_ptr.*;
                    },
                };
            }
            ret.slice = self.storeString(sl);
        } else {
            ret.slice = self.scratchPrint("{d:.2}", .{number_ptr.*});
        }
        if (click == .click) {
            if (!self.isActiveTextinput(id)) {
                self.text_input_state.active_id = id;
                try self.textbox_state.resetFmt("{d:.2}", .{number_ptr.*});
            }

            const cin = font.nearestGlyphX(self.textbox_state.getSlice(), tarea.h, self.input_state.mouse.pos.sub(tarea.pos()), true);
            if (cin) |cc| {
                self.textbox_state.setHead(cc, 0, true);
            }
        }

        return ret;
    }
};

pub const GuiDrawContext = struct {
    const Self = @This();

    window_fbs: std.ArrayList(graph.RenderTexture),

    old_cam_bounds: ?Rect = null,
    camera_bounds: ?Rect = null,
    win_bounds: Rect = graph.Rec(0, 0, 0, 0),
    tint: u32 = 0xffff_ffff,

    pub fn init(alloc: std.mem.Allocator) !Self {
        return .{
            .window_fbs = std.ArrayList(graph.RenderTexture).init(alloc),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.window_fbs.items) |*fb|
            fb.deinit();
        self.window_fbs.deinit();
    }

    pub fn drawFbs(self: *Self, draw: *graph.ImmediateDrawingContext, gui: *Context) !void {
        graph.c.glBindFramebuffer(graph.c.GL_FRAMEBUFFER, 0);
        graph.c.glViewport(0, 0, @intFromFloat(draw.screen_dimensions.x), @intFromFloat(draw.screen_dimensions.y));
        const old_zindex = draw.zindex;
        for (self.window_fbs.items[0..gui.this_frame_num_windows], 0..) |fb, i| {
            draw.zindex = old_zindex + @as(u16, @intCast(gui.windows.items[i].depth));
            const tr = fb.texture.rect();
            draw.rect(gui.windows.items[i].area, 0xff);
            draw.rectTex(
                gui.windows.items[i].area,
                graph.Rec(0, 0, tr.w, -tr.h),
                fb.texture,
            );
        }
        //HACK, should be drawn in relavent window fbo,
        if (gui.focused_area) |fa| {
            draw.rectBorder(fa, 1, 0xff0000ff);
        }

        try draw.flush(null, null);
    }

    pub fn drawGui(self: *Self, draw: *graph.ImmediateDrawingContext, gui: *Context) !void {
        try draw.flush(null, null);
        gl.enable(.depth_test);
        gl.enable(.blend);
        graph.c.glBlendFunc(graph.c.GL_SRC_ALPHA, graph.c.GL_ONE_MINUS_SRC_ALPHA);
        graph.c.glBlendEquation(graph.c.GL_FUNC_ADD);
        defer gl.disable(.blend);
        const scr_dim = draw.screen_dimensions;
        const ignore_cache = true;
        for (gui.windows.items[0..gui.this_frame_num_windows], 0..) |w, i| {
            if (i >= self.window_fbs.items.len) {
                try self.window_fbs.append(try graph.RenderTexture.init(w.area.w, w.area.h));
            } else {
                _ = try self.window_fbs.items[i].setSize(w.area.w, w.area.h);
            }
            self.camera_bounds = w.area;
            self.window_fbs.items[i].bind(ignore_cache);
            {
                var scissor: bool = false;
                var scissor_depth: u32 = 0;
                var node = w.layout_cache.first;
                while (node) |n| : (node = n.next) {
                    if (n.data.scissor) |sz| {
                        scissor = true;
                        scissor_depth = n.depth;
                        try self.drawCommand(.{ .scissor = .{ .area = sz } }, draw);
                    }
                    if (n.data.scissor == null) {
                        if (scissor and n.depth <= scissor_depth) {
                            scissor = false;
                            try self.drawCommand(.{ .scissor = .{ .area = null } }, draw);
                        }
                    }
                    for (n.data.commands.items) |command| {
                        try self.drawCommand(command, draw);
                    }
                    n.data.draw_backup = false;
                }
                if (scissor) //Clear a remaning scissor
                    try self.drawCommand(.{ .scissor = .{ .area = null } }, draw);
            }
            try draw.flush(w.area, null);
            //draw.screen_dimensions = .{ .x = @as(f32, @floatFromInt(win_w)), .y = @as(f32, @floatFromInt(win_h)) };
            //graph.c.glBindFramebuffer(graph.c.GL_FRAMEBUFFER, 0);
            //graph.c.glViewport(0, 0, win_w, win_h);
            //const tr = self.window_fbs.items[i].texture.rect();
            //draw.rectTex(
            //    w.area,
            //    graph.Rec(0, 0, tr.w, -tr.h),
            //    self.window_fbs.items[i].texture,
            //);
        }
        draw.screen_dimensions = scr_dim;
        //graph.c.glViewport(0, 0, @intFromFloat(scr_dim.x), @intFromFloat(scr_dim.y));

        try self.drawFbs(draw, gui);

        //const old_zindex = draw.zindex;
        //for (self.window_fbs.items[0..gui.this_frame_num_windows], 0..) |fb, i| {
        //    draw.zindex = old_zindex + @as(u16, @intCast(gui.windows.items[i].depth));
        //    const tr = fb.texture.rect();
        //    draw.rect(gui.windows.items[i].area, 0xff);
        //    draw.rectTex(
        //        gui.windows.items[i].area,
        //        graph.Rec(0, 0, tr.w, -tr.h),
        //        fb.texture,
        //    );
        //}
        ////HACK, should be drawn in relavent window fbo,
        //if (gui.focused_area) |fa| {
        //    draw.rectBorder(fa, 1, 0xff0000ff);
        //}

        //try draw.flush(null, null);
        if (true)
            return;
        //ctx.screen_bounds = graph.IRect.new(0, 0, @intFromFloat(parea.w), @intFromFloat(parea.h));
        //draw.screen_dimensions = .{ .x = parea.w, .y = parea.h };
        //{
        //    const c = graph.c;
        //    gl.enable(.stencil_test);
        //    c.glColorMask(c.GL_FALSE, c.GL_FALSE, c.GL_FALSE, c.GL_FALSE);
        //    c.glDepthMask(c.GL_FALSE);
        //    c.glClearStencil(0xff);
        //    c.glStencilFunc(c.GL_NEVER, 1, 0xFF);
        //    c.glStencilOp(c.GL_REPLACE, c.GL_KEEP, c.GL_KEEP); // draw 1s on test fail (always)

        //    c.glStencilMask(0xFF);
        //    c.glClear(c.GL_STENCIL_BUFFER_BIT); // needs mask=0xFF

        //    var node = gui.layout_cache.first;
        //    var redraw_depth: ?u32 = null;
        //    while (node) |n| : (node = n.next) {
        //        if (redraw_depth) |dep| {
        //            if (n.depth > dep) {
        //                n.data.draw_cmds = true;
        //                continue;
        //            } else {
        //                redraw_depth = null;
        //            }
        //        }
        //        if (n.data.draw_cmds) {
        //            draw.rect(if (n.data.scissor) |s| s else n.data.rec, Colori.Black);
        //            redraw_depth = n.depth;
        //        }
        //    }
        //    try draw.flush(null);
        //    c.glColorMask(c.GL_TRUE, c.GL_TRUE, c.GL_TRUE, c.GL_TRUE);
        //    c.glDepthMask(c.GL_TRUE);
        //    c.glStencilMask(0x00);
        //    c.glStencilFunc(c.GL_EQUAL, 1, 0xFF);
        //}
        //draw.rect(parea, Colori.Blue);
        //{
        //    var scissor: bool = false;
        //    var scissor_depth: u32 = 0;
        //    var node = gui.layout_cache.first;
        //    while (node) |n| : (node = n.next) {
        //        if (n.data.draw_cmds or ignore_cache or n.data.draw_backup) {
        //            if (n.data.scissor) |sz| {
        //                scissor = true;
        //                scissor_depth = n.depth;
        //                try self.drawCommand(.{ .scissor = .{ .area = sz } }, draw, font);
        //            }
        //            for (n.data.commands.items) |command| {
        //                try self.drawCommand(command, draw, font);
        //            }
        //        }
        //        if (n.data.scissor == null) {
        //            if (scissor and n.depth <= scissor_depth) {
        //                scissor = false;
        //                try self.drawCommand(.{ .scissor = .{ .area = null } }, draw, font);
        //            }
        //        }
        //        n.data.draw_backup = false;
        //    }
        //}
        //gl.disable(.stencil_test);

        //try ctx.drawRectTex(parea, parea, Color.White, self.main_rtexture.texture);

        //try ctx.drawRectTex(parea, graph.Rec(0, 0, self.main_rtexture.texture.w, self.main_rtexture.texture.h), Color.White, self.main_rtexture.texture);
    }

    pub fn drawCommand(self: *Self, command: DrawCommand, draw: *graph.ImmediateDrawingContext) !void {
        switch (command) {
            .rect_filled => |rf| {
                draw.rect(rf.r, (rf.color));
            },
            .text => |t| {
                const p = t.pos.toF();

                draw.text(p, t.string, .{ .color = t.color, .px_size = t.size, .font = t.font });
            },
            .line => |l| {
                draw.line(l.a, l.b, (l.color), 2);
            },
            .rect_textured => |t| {
                draw.rectTexTint(t.r, t.uv, (t.color), t.texture);
            },
            .rect_outline => |rl| {
                const r = rl.r;
                draw.line(r.topL(), r.topR(), (rl.color), 1);
                draw.line(r.topR(), r.botR(), (rl.color), 1);
                draw.line(r.botR(), r.botL(), (rl.color), 1);
                draw.line(r.botL(), r.topL(), (rl.color), 1);
            },
            .set_camera => |sc| {
                try draw.flush(self.camera_bounds, null); //Flush old camera
                if (sc) |ca| {
                    if (self.old_cam_bounds == null)
                        self.old_cam_bounds = self.camera_bounds;
                    draw.setViewport(ca.screen_area.subVec(self.old_cam_bounds.?.pos()));
                    const ar = ca.screen_area;
                    graph.c.glViewport(
                        @as(i32, @intFromFloat(ar.x - self.camera_bounds.?.x)),
                        @as(i32, @intFromFloat(self.camera_bounds.?.h - (ar.y + ar.h) + self.camera_bounds.?.y)),
                        @as(i32, @intFromFloat(ar.w)),
                        @as(i32, @intFromFloat(ar.h)),
                    );
                    self.camera_bounds = ca.cam_area;
                } else {
                    self.camera_bounds = self.old_cam_bounds;
                    graph.c.glViewport(
                        0,
                        0,
                        @intFromFloat(self.camera_bounds.?.w),
                        @intFromFloat(self.camera_bounds.?.h),
                    );
                    self.old_cam_bounds = null;
                }
            },
            .scissor => |s| {
                const c = graph.c;
                try draw.flush(self.camera_bounds, null);
                if (s.area) |ar| {
                    gl.enable(.scissor_test);
                    c.glScissor(
                        @as(i32, @intFromFloat(ar.x - self.camera_bounds.?.x)),
                        @as(i32, @intFromFloat(self.camera_bounds.?.h - (ar.y + ar.h) + self.camera_bounds.?.y)),
                        @as(i32, @intFromFloat(ar.w)),
                        @as(i32, @intFromFloat(ar.h)),
                    );
                } else {
                    gl.disable(.scissor_test);
                }
            },
            .rect_filled_multi_color => |rf| {
                //ctx.drawRectCol(rf.r, rf.colors);
                var cols: [4]u32 = undefined;
                for (rf.colors, 0..) |col, i| {
                    cols[i] = col;
                }
                draw.rectVertexColors(rf.r, &cols);
            },
            .rect_9slice => |s| {
                draw.nineSlice(s.r, s.uv, s.texture, s.scale, self.tint);
            },
            .rect_9border => |s| {
                _ = s;
                //draw.rectTex(s.r, s.uv, s.texture);
                //try ctx.draw9Border(s.r, s.uv, s.texture, s.scale, s.cutout_start, s.cutout_end);
            },
        }
    }
};
