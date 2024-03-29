const std = @import("std");
const Cache = @import("gui_cache.zig");
//TODO
//Annotate all functions with what state they depend on. Make it easier to ensure proper state. For instance  gui.scissor depends on scroll_
//
//Idea: Parametric rects IDk. Somehow make a rect depend on another rects values. Probably stupid

const json = std.json;
const clamp = std.math.clamp;
pub const graph = @import("graphics.zig");
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
const SRect = struct {
    const Self = @This();
    //TODO rename to inset
    pub fn scale(self: Self, amount: i16) Self {
        return .{ .x = self.x + amount, .y = self.y + amount, .w = self.w - amount * 2, .h = self.h - amount * 2 };
    }

    pub fn new(x: i16, y: i16, w: i16, h: i16) Self {
        return .{ .x = x, .y = y, .w = w, .h = h };
    }

    pub fn toF32(self: Self) graph.Rect {
        return .{ .x = @as(f32, @floatFromInt(self.x)), .y = @as(f32, @floatFromInt(self.y)), .w = @as(f32, @floatFromInt(self.w)), .h = @as(f32, @floatFromInt(self.h)) };
    }

    pub fn pos(self: Self) Vec2i {
        return .{ .x = self.x, .y = self.y };
    }

    x: i16,
    y: i16,
    w: i16,
    h: i16,
};

const Hsva = graph.Hsva;
const Color = graph.CharColor;
const Colori = graph.Colori;
const itc = graph.itc;

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
        color: Color,
    },

    rect_textured: struct {
        r: Rect,
        color: Color,
        uv: Rect,
        texture: graph.Texture,
    },

    rect_outline: struct {
        r: Rect,
        color: Color,
    },

    rect_filled_multi_color: struct {
        r: Rect,
        colors: [4]Color,
    },

    line: struct {
        a: Vec2f,
        b: Vec2f,
        color: Color,
    },

    text: struct {
        font: *graph.Font,
        pos: Vec2i,
        size: f32,
        string: []const u8,
        color: Color,
    },

    scissor: struct {
        area: ?Rect = null,
    },

    set_camera: struct {
        cam_area: ?Rect = null,
        offset: Vec2f = .{ .x = 0, .y = 0 },
        win_area: ?Rect = null,
    },
};

//TODO bitset type that takes an enum and gives each field a mask bit. see github.com/emekoi/bitset-zig

pub const Justify = enum { right, left, center };
pub const Orientation = graph.Orientation;

pub const InputState = struct {
    pub const DefaultKeyboardState = graph.SDL.Window.KeyboardStateT.initEmpty();
    //TODO switch to using new graphics.zig MouseState
    //make clickwidget support rightClicks, double click etc
    //Figure out textinput
    mouse_pos: Vec2f = .{ .x = 0, .y = 0 },
    mouse_delta: Vec2f = .{ .x = 0, .y = 0 },
    mouse_left_held: bool = false,
    mouse_left_clicked: bool = false,
    mouse_wheel_delta: f32 = 0,
    mouse_wheel_down: bool = false,
    keyboard_state: *const graph.SDL.Window.KeyboardStateT = &DefaultKeyboardState,
    keys: []const graph.SDL.KeyState = &.{},
};

fn opaqueSelf(comptime self: type, ptr: *anyopaque) *self {
    return @as(*self, @ptrCast(@alignCast(ptr)));
}

//TODO This should be replaced with something less hacky.
//Many instances of begin (SubRectLayout) then begin(another layout) when laying out a window
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
    const floating_pixel_error = 0.3; //If we switch to ints this won't be a problem. but doing math will be annoying
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

        //const w = (bounds.w - self.paddingh) / @as(f32, @floatFromInt(self.count));
        //defer self.current_w += w + self.paddingh;
        defer self.current_w += w + self.paddingh;

        return .{ .x = bounds.x + self.current_w, .y = bounds.y, .w = w, .h = bounds.h };
    }

    pub fn pushCount(self: *HorizLayout, next_count: usize) void {
        self.count_override = next_count;
    }
};

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

//TODO use a utf8 library to add utf8 support. check out the ziglyph library
pub const RetainedState = struct {
    //Implementation of https://rxi.github.io/textbox_behaviour.html
    pub const TextInput = struct {
        const Self = @This();
        const uni = std.unicode;
        const edit_keys_list = graph.Bind(&.{
            .{ "move_left", "Left" },
            .{ "move_right", "Right" },
            .{ "backspace", "Backspace" },
            .{ "delete", "Delete" },
        });

        const SingleLineMovement = enum {
            left,
            right,
            next_word_end,
            prev_word_end,
            start,
            end,
        };

        codepoints: std.ArrayList(u8),

        head: i32,
        tail: i32,

        fn select_to(self: *Self, movement: SingleLineMovement) void {
            const max = @as(i32, @intCast(self.codepoints.items.len));
            switch (movement) {
                .left => {
                    self.head = clamp(self.head - 1, 0, max);
                },
                .right => {
                    self.head = clamp(self.head + 1, 0, max);
                },
                .start => self.head = 0,
                .end => self.head = max,
                else => {},
            }
        }

        fn move_to(self: *Self, movement: SingleLineMovement) void {
            self.select_to(movement);
            self.tail = self.head;
        }

        fn delete_to(self: *Self, movement: SingleLineMovement) void {
            const max = @as(i32, @intCast(self.codepoints.items.len));
            switch (movement) {
                .left => {
                    if (max == 0 or self.head == 0) return;
                    self.head -= 1;
                    self.head = clamp(self.head, 0, max);
                    self.tail = self.head;
                    _ = self.codepoints.orderedRemove(@as(usize, @intCast(self.head)));
                },
                .right => {
                    if (max == 0 or self.head == max) return;
                    _ = self.codepoints.orderedRemove(@as(usize, @intCast(self.head)));
                    self.tail = self.head;
                },
                else => {},
            }
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

        pub fn setCaret(self: *Self, pos: usize) void {
            if (pos > self.codepoints.items.len) return;
            self.head = @as(i32, @intCast(pos));
            self.tail = @as(i32, @intCast(pos));
        }

        pub fn reset(self: *Self, new_str: []const u8) !void {
            try self.codepoints.resize(0);
            try self.codepoints.appendSlice(new_str);
            self.head = 0;
            self.tail = 0;
        }

        pub fn resetFmt(self: *Self, comptime fmt: []const u8, args: anytype) !void {
            try self.reset("");
            try self.codepoints.writer().print(fmt, args);
            self.head = @as(i32, @intCast(self.codepoints.items.len));
            self.tail = self.head;
        }

        pub fn handleEventsOpts(
            tb: *TextInput,
            text_input: []const u8,
            input_state: InputState,
            options: struct {
                /// If set, only the listed characters will be inserted. Others will be silently ignored
                restricted_charset: ?[]const u8 = null,
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

            for (text_input) |new_char| {
                if (options.restricted_charset) |cset| {
                    restricted_blk: {
                        for (cset) |achar| {
                            if (achar == new_char)
                                break :restricted_blk;
                        }
                        continue;
                    }
                }
                if (tb.head != tb.tail) {
                    //try tb.chars.replaceRange(tb.tail, tb.head - tb.tail, codepoint.?);
                    //tb.tail = tb.head;
                } else {
                    try tb.codepoints.insert(@intCast(tb.head), new_char);
                    tb.head += 1;
                    tb.tail = tb.head;
                }
            }

            for (input_state.keys) |key| {
                switch (StaticData.key_binds.get(key.scancode)) {
                    .move_left => tb.move_to(.left),
                    .move_right => tb.move_to(.right),
                    .delete => tb.delete_to(.right),
                    .backspace => tb.delete_to(.left),
                    else => {},
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

//TODO Some sort of drawMultiWidget(anywidget, list of args) would be cool
//in order to be usefull a lambda function to transform items in a slice to argument lists would have to be provided
//If a struct provides a guiDraw function this could be called
//so gui.drawMulti(my_slice) would iterate my_slice and call guiDraw on each

//TODO add some sort of anotations to Context functions to show level of feature support.
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

//A wrapper over std autoHash to allow hashing floats. All the floats being hashed are pixel coordinates. They are first scaled by 10 before being truncated and hashed
pub fn hashW(hasher: anytype, key: anytype, comptime strat: std.hash.Strategy) void {
    const Key = @TypeOf(key);
    switch (@typeInfo(Key)) {
        .Struct => |info| {
            inline for (info.fields) |field| {
                hashW(hasher, @field(key, field.name), strat);
            }
        },
        .Union => |info| {
            if (info.tag_type == null) @compileError("Cannot hash untagged union");
            inline for (info.fields, 0..) |field, i| {
                if (i == @intFromEnum(key)) {
                    hashW(hasher, @field(key, field.name), strat);
                    break;
                }
            }
        },
        .Pointer => |info| {
            switch (info.size) {
                .Slice => {
                    for (key) |element| {
                        hashW(hasher, element, strat);
                    }
                },
                else => {},
                //else => @compileError("not supported pointer type to hashW " ++ @typeName(Key)),
            }
        },
        .Array => {
            for (key) |element|
                hashW(hasher, element, strat);
        },
        .Opaque => {},
        .Optional => if (key) |k| hashW(hasher, k, strat),
        .Float => {
            std.hash.autoHashStrat(hasher, @as(i32, @intFromFloat(key * 10)), strat);
        },
        .Int, .Bool => std.hash.autoHashStrat(hasher, key, strat),
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

//TODO Is hashing the type name really a good idea
pub const OpaqueDataStore = struct {
    const Self = @This();
    const DataStoreMapT = std.StringHashMap(DataItem);

    pub const DataItem = struct {
        type_name_hash: u64,
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
        }
        for (self.keys.items) |key| {
            self.alloc.free(key);
        }

        self.keys.deinit();
        self.map.deinit();
    }

    pub fn store(self: *Self, comptime data_type: type, name: []const u8) !struct {
        data: *data_type,
        is_init: bool,
    } {
        var hasher = std.hash.Wyhash.init(0);
        std.hash.autoHashStrat(&hasher, @typeName(data_type), .Shallow);
        const hash = hasher.final();

        var is_init = false;
        if (!self.map.contains(name)) {
            is_init = true;
            const name_store = try self.alloc.alloc(u8, name.len);
            std.mem.copy(u8, name_store, name);
            try self.keys.append(name_store);
            const data_untyped = try self.alloc.alloc(u8, @sizeOf(data_type));
            //const data = @as(*data_type, @ptrCast(@alignCast(data_untyped)));
            //data.* = init_value;
            try self.map.put(name_store, .{ .type_name_hash = hash, .data = data_untyped });
        }
        const v = self.map.get(name) orelse unreachable;
        if (v.type_name_hash != hash) return error.wrongType;
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
//Textinput
//TODO Seperate context into two structs.
// A core struct for the low level gui stuff and a basic widgets struct other things can compose
// core  would include:
// Layout functions
// draw functions
// click widget etc
// text input state
// popup state
//
pub const Context = struct {
    pub var dealloc_count: u32 = 0;
    pub var alloc_count: u32 = 0;
    const Self = @This();
    const LayoutStackT = std.SinglyLinkedList(Layout);
    const RetainedHashMapT = std.StringHashMap(RetainedState);

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
                //TODO what happens when an enum with non default values is used
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

        was_init: bool = true, //Exist to draw debug indicator for fresh nodes
        is_init: bool = false,
        pub fn init(self: *@This(), alloc: std.mem.Allocator) void {
            if (self.is_init) unreachable;
            alloc_count += 1;
            self.is_init = true;
            self.widget_hashes = std.ArrayList(u64).init(alloc);
            self.widget_data = WidgetDataT.init(alloc);
            self.commands = std.ArrayList(DrawCommand).init(alloc);
        }

        pub fn deinit(self: *@This()) void {
            if (self.is_init) {
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

    const Popup = struct {
        area: Rect,
    };

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

        pub fn eql(a: WidgetId, b: WidgetId) bool {
            return (a.layout_hash == b.layout_hash and a.index == b.index);
        }
    };

    pub const TextInputState = struct {
        pub const States = enum {
            start,
            stop,
            cont,
            disabled,
        };

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

        pub fn advanceStateActive(self: *TextInputState) void {
            self.state = switch (self.state) {
                .start => .cont,
                .disabled => .start,
                .cont, .stop => .cont,
            };
        }
    };

    dirty_draw_depth: ?u32 = null,
    no_caching: bool = true,

    console: Console,
    font: *graph.Font,
    icon_font: *graph.Font,

    layout: Layout,

    stack_alloc: *std.heap.FixedBufferAllocator,
    alloc: std.mem.Allocator,
    layout_stack: LayoutStackT = .{},
    command_list: std.ArrayList(DrawCommand),

    command_list_popup: std.ArrayList(DrawCommand),

    tooltip_state: TooltipState,

    retained_alloc: std.mem.Allocator,
    namespace: []const u8 = "global",
    //TODO change naming system, state from last frame should be prefixed with last_frame or exist inside a last_frame_state struct
    old_namespace: []const u8 = "",

    scratch_buf_pos: usize = 0,
    scratch_buf: [2048]u8 = undefined,
    strings: [2048]u8 = undefined,
    str_index: usize = 0,

    layout_cache: LayoutCacheT,
    current_layout_cache_data: ?*LayoutCacheData = null,

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

    //TODO look into using sdl double click functionality
    click_timer: u64 = 0,
    //TODO this field is for clickWidget, label or move to something
    last_clicked: ?WidgetId = null,

    //TODO is there a reason these nulls are all seperate?
    popup: ?Popup = null,
    popup_scroll_bounds: ?Rect = null,
    popup_id: ?WidgetId = null,
    /// This is set true on beginPopup and set false on endPopup
    in_popup: bool = false,
    last_frame_had_popup: bool = false,

    /// Represents the screen space area of the current scroll area, when a nested scroll section is created,
    /// it is always clipped to exist inside the parent scroll_bounds
    scroll_bounds: ?Rect = null,
    scroll_claimed_mouse: bool = false,

    pub fn scratchPrint(self: *Self, comptime fmt: []const u8, args: anytype) []const u8 {
        var fbs = std.io.FixedBufferStream([]u8){ .buffer = self.scratch_buf[self.scratch_buf_pos..], .pos = 0 };
        fbs.writer().print(fmt, args) catch unreachable;
        self.scratch_buf_pos += fbs.pos;
        return fbs.getWritten();
    }

    pub fn storeString(self: *Self, str: []const u8) []const u8 {
        if (str.len + self.str_index >= self.strings.len) {
            const slice = self.alloc.alloc(u8, str.len) catch unreachable;
            std.mem.copy(u8, slice, str);
            return slice;
        }

        const sl = self.strings[self.str_index .. self.str_index + str.len];
        std.mem.copy(u8, sl, str);
        defer self.str_index += str.len;

        return sl;
    }

    pub fn isKeyDown(self: *Self, scancode: graph.keycodes.Scancode) bool {
        return self.input_state.keyboard_state.isSet(@intFromEnum(scancode));
    }

    pub fn isCursorInRect(self: *Self, r: Rect) bool {
        return r.containsPoint(self.input_state.mouse_pos);
    }

    pub fn qualifyName(self: *const Self, name: []const u8) ![]const u8 {
        const qn = try self.alloc.alloc(u8, name.len + self.namespace.len + 1);
        std.mem.copy(u8, qn, self.namespace);
        qn[self.namespace.len] = ':';
        std.mem.copy(u8, qn[self.namespace.len + 1 ..], name);
        return qn;
    }

    pub fn getArea(self: *Self) ?Rect {
        const new_area = self.layout.getArea();
        self.tooltip_state.pending_area = new_area;
        if (self.scroll_bounds) |sb| {
            if (!sb.overlap(new_area orelse return new_area))
                return null;
        }
        return new_area;
    }

    pub fn tooltip(self: *Self, message: []const u8, size: f32) void {
        const ts = &self.tooltip_state;
        const pa = ts.pending_area orelse return;
        if (self.isCursorInRect(pa)) {
            if (ts.mouse_in_area) |ma| {
                if (ma.eql(pa)) {
                    ts.hover_time += 1;
                    if (ts.hover_time > 20 and !ts.hide_active) {
                        if (self.input_state.mouse_left_clicked) {
                            ts.hide_active = true;
                        }
                        const bounds = self.font.textBounds(message, size);
                        const mp = self.input_state.mouse_pos;
                        ts.command_list.append(.{ .rect_filled = .{ .r = Rect.newV(mp, bounds), .color = Color.Gray } }) catch unreachable;
                        ts.command_list.append(.{
                            .text = .{ .string = message, .pos = mp.toI(i16, Vec2i), .size = size, .color = Color.White, .font = self.font },
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
            return .{ .layout_hash = ld.hash, .index = ld.widget_index };
        }
        unreachable;
    }

    pub fn isActivePopup(self: *Self, id: WidgetId) bool {
        if (self.popup_id) |pop_id| {
            return pop_id.eql(id);
        }
        return false;
    }

    pub fn isActiveTextinput(self: *Self, id: WidgetId) bool {
        if (self.text_input_state.active_id) |t_id| {
            return t_id.eql(id);
        }
        return false;
    }

    pub fn getWidgetState(self: *Self, dependent_data: anytype) WidgetState {
        const result: WidgetState = blk: {
            const hash = dhash(dependent_data);
            if (self.current_layout_cache_data) |ld| {
                if (ld.dirty) break :blk .dirty;
                if (ld.is_init != true) unreachable;
                defer ld.widget_hash_index += 1;
                if (ld.widget_hash_index >= ld.widget_hashes.items.len) { //append to list and return .init
                    ld.widget_hashes.append(hash) catch unreachable;
                    break :blk .init;
                } else { //Compare and either overwrite or return
                    if (hash == ld.widget_hashes.items[ld.widget_hash_index])
                        break :blk .no_change;
                    ld.widget_hashes.items[ld.widget_hash_index] = hash;
                    //TODO notify child layouts
                    break :blk .input_changed;
                }
            }
            unreachable;
        };
        if (self.no_caching)
            return .init;
        return result;
    }

    pub fn init(alloc: std.mem.Allocator, stack_alloc: *std.heap.FixedBufferAllocator, bounds: Rect, font: *graph.Font, icon_font: *graph.Font) !Self {
        //TODO change stack_alloc from a FixedBufferAllocator to a ArenaAllocator
        const sa = stack_alloc.allocator();
        return Self{
            .console = Console.init(alloc),
            .layout = .{ .bounds = bounds },
            .layout_stack = .{},
            .layout_cache = try LayoutCacheT.init(alloc),
            .stack_alloc = stack_alloc,
            .alloc = stack_alloc.allocator(),
            .font = font,
            .icon_font = icon_font,
            //.retained_data = RetainedHashMapT.init(alloc),
            .retained_alloc = alloc,
            .tooltip_state = .{ .command_list = std.ArrayList(DrawCommand).init(sa) },
            .command_list = std.ArrayList(DrawCommand).init(sa),
            .command_list_popup = std.ArrayList(DrawCommand).init(sa),
            .textbox_state = RetainedState.TextInput.init(alloc),
        };
    }

    pub fn reset(self: *Self, input_state: InputState) !void {
        self.dirty_draw_depth = null;
        self.str_index = 0;
        self.scratch_buf_pos = 0;
        self.scroll_claimed_mouse = false;

        try self.layout_cache.begin();
        if (self.scroll_bounds != null) return error.unmatchedBeginScroll;
        if (std.mem.indexOfScalar(u8, self.namespace, ':') != null)
            return error.unmatchedPushNamespace;
        if (self.layout_stack.len() > 0)
            return error.unmatchedBeginLayout;
        self.command_list.deinit();
        self.command_list_popup.deinit();
        self.text_input_state.advanceStateReset();
        self.stack_alloc.reset();
        self.command_list = std.ArrayList(DrawCommand).init(self.alloc);
        self.command_list_popup = std.ArrayList(DrawCommand).init(self.alloc);
        self.tooltip_state.command_list = std.ArrayList(DrawCommand).init(self.alloc);
        if (self.tooltip_state.mouse_in_area) |ma| {
            if (!self.isCursorInRect(ma)) {
                self.tooltip_state.hover_time = 0;
                self.tooltip_state.hide_active = false;
            }
        }
        self.input_state = input_state;

        self.layout.reset();
        self.click_timer += 1;

        if (self.popup) |p| {
            if (self.input_state.mouse_left_clicked and !p.area.containsPoint(self.input_state.mouse_pos)) {
                self.popup = null;
                self.popup_id = null;
            }
        }
        if (self.mouse_released) {
            self.mouse_grab_id = null;
            self.mouse_released = false;
        }
        if (!self.input_state.mouse_left_held and self.mouse_grab_id != null) {
            self.mouse_released = true;
        }

        if (!self.last_frame_had_popup) {
            self.popup = null;
            self.popup_id = null;
        }
        self.last_frame_had_popup = false;
    }

    pub fn deinit(self: *Self) void {
        self.layout_cache.deinit();
        self.console.deinit();
        self.textbox_state.deinit();
    }

    pub fn setNamespace(self: *Self, new_namespace: []const u8) void {
        if (!std.mem.eql(u8, new_namespace, self.old_namespace)) {
            self.layout_cache.clear() catch unreachable;
            self.old_namespace = self.namespace;
            self.namespace = new_namespace;
        }
    }

    pub fn pushNamespace(self: *Self, child_name: []const u8) !void {
        const name = try self.qualifyName(child_name);
        self.namespace = name;
    }

    pub fn popNamespace(self: *Self) void {
        self.namespace = self.namespace[0..std.mem.lastIndexOfScalar(u8, self.namespace, ':').?];
    }

    pub fn clickWidget(self: *Self, rec: Rect) ClickState {
        return self.clickWidgetEx(rec, .{}).click;
    }

    pub fn clickWidgetEx(self: *Self, rec: Rect, opts: struct {
        teleport_area: ?Rect = null,
    }) struct { click: ClickState, id: WidgetId } {
        const id = self.getId();

        if (self.popup) |p| {
            //TODO this will fail sometimes because we can't garantee popup has been called before this click widget
            //Can set layout to have popup flag or something
            if (!self.in_popup and p.area.containsPoint(self.input_state.mouse_pos)) return .{ .click = .none, .id = id };
        }

        const containsCursor = rec.containsPoint(self.input_state.mouse_pos);
        const clicked = self.input_state.mouse_left_clicked;

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
            if (self.scroll_bounds) |sb| {
                if (!sb.containsPoint(self.input_state.mouse_pos))
                    return .{ .click = .none, .id = id };
            }
            if (opts.teleport_area) |parent_area| {
                if (clicked and !containsCursor and parent_area.containsPoint(self.input_state.mouse_pos)) {
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

    pub fn draggable(self: *Self, area: Rect, mdelta_scale: Vec2f, x_val: anytype, y_val: anytype, opts: struct {
        x_min: ?f32 = null,
        x_max: ?f32 = null,
        y_min: ?f32 = null,
        y_max: ?f32 = null,
    }) ClickState {
        const Helper = struct {
            const Type = std.builtin.Type;

            fn getVal(comptime info: Type, val: anytype) f32 {
                return switch (info) {
                    .Int => @floatFromInt(val.*),
                    .Float => @as(f32, @floatCast(val.*)),
                    .Void => 0,
                    else => @compileError("invalid type"),
                };
            }

            fn addDelta(comptime info: Type, val: *f32, delta: f32, trunc_state: *f32) void {
                if (info == .Int or info == .Float)
                    val.* += delta + trunc_state.*;
                if (info == .Int)
                    trunc_state.* = val.* - @trunc(val.*);
            }

            fn setVal(comptime info: Type, valptr: anytype, val: f32, min: ?f32, max: ?f32) void {
                const math = std.math;
                switch (info) {
                    .Float => {
                        valptr.* = math.clamp(val, if (min) |m| m else math.floatMin(f32), if (max) |mx| mx else math.floatMin(f32));
                    },
                    .Int => {
                        const cval = math.clamp(val, if (min) |m| m else math.minInt(@Type(info)), if (max) |mx| mx else math.maxInt(@Type(info)));
                        valptr.* = @as(@typeInfo(@TypeOf(valptr)).Pointer.child, @intFromFloat(@trunc(cval)));
                    },
                    .Void => {},
                    else => @compileError("invalid type"),
                }
            }
        };
        const xptrinfo = @typeInfo(@TypeOf(x_val));
        const xinfo = @typeInfo(xptrinfo.Pointer.child);
        const yptrinfo = @typeInfo(@TypeOf(y_val));
        const yinfo = @typeInfo(yptrinfo.Pointer.child);

        var val: Vec2f = .{ .x = Helper.getVal(xinfo, x_val), .y = Helper.getVal(yinfo, y_val) };
        const click = self.clickWidget(area);

        if (click == .click) {
            self.draggable_state = .{ .x = 0, .y = 0 };
        }
        if (click == .click or click == .held) {
            Helper.addDelta(xinfo, &val.x, mdelta_scale.x * self.input_state.mouse_delta.x, &self.draggable_state.x);
            Helper.addDelta(yinfo, &val.y, mdelta_scale.y * self.input_state.mouse_delta.y, &self.draggable_state.y);
        }
        Helper.setVal(xinfo, x_val, val.x, opts.x_min, opts.x_max);
        Helper.setVal(yinfo, y_val, val.y, opts.y_min, opts.y_max);
        return click;
    }

    //TODO ensure our new layout does not clip the previous layout, special case for scroll areas and popups as they can clip
    pub fn beginLayout(self: *Self, comptime Layout_T: type, layout_data: Layout_T, opts: struct { bg: Color = itc(0x222222ff), scissor: ?Rect = null }) !*Layout_T {
        const new_layout = try self.alloc.create(Layout_T);
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

        const node = try self.alloc.create(LayoutStackT.Node);
        node.next = null;
        node.data = old_layout;
        self.layout_stack.prepend(node);
        self.layout.setNew(Layout_T, new_layout);

        { //Layout cache
            const dirty = if (self.current_layout_cache_data) |ld| ld.dirty else false;
            try self.layout_cache.push(.{ .hash = self.layout.hash(), .rec = self.layout.bounds, .scissor = opts.scissor });
            self.current_layout_cache_data = self.layout_cache.getCacheDataPtr();
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
        return new_layout;
    }

    pub fn endLayout(self: *Self) void {
        {
            const ld = self.current_layout_cache_data.?;
            const last_frame_hash = ld.last_frame_cmd_hash;
            ld.hashCommands();
            ld.draw_cmds = (ld.last_frame_cmd_hash != last_frame_hash);
            const dde = if (ld.draw_cmds and self.layout_cache.depth > 0) self.layout_cache.depth - 1 else null;
            if (self.dirty_draw_depth) |dd| {
                if (dd > dde orelse 0)
                    self.dirty_draw_depth = dd;
            } else {
                self.dirty_draw_depth = dde;
            }
        }

        self.layout_cache.pop() catch unreachable;
        self.current_layout_cache_data = self.layout_cache.getCacheDataPtr();
        //const ld = self.current_layout_cache_data.?;
        //if()
        if (self.current_layout_cache_data) |ld| {
            if (!ld.is_init) unreachable;
            if (self.dirty_draw_depth) |draw_depth| {
                if (self.layout_cache.depth == draw_depth) {
                    ld.draw_backup = true;
                    if (draw_depth > 0)
                        self.dirty_draw_depth.? -= 1;
                }
            }
        }
        if (self.layout_stack.popFirst()) |layout| {
            self.layout = layout.data;
            self.alloc.destroy(layout);
        } else {
            unreachable;
        }
    }

    pub fn beginPopup(self: *Self, area: Rect) !void {
        _ = try self.beginLayout(SubRectLayout, .{ .rect = area }, .{});
        self.last_frame_had_popup = true;
        self.in_popup = true;
        self.popup = .{ .area = area };
    }

    pub fn endPopup(self: *Self) void {
        self.in_popup = false;
        if (self.popup_id == null)
            self.popup = null;
        self.endLayout();
    }

    pub fn skipArea(self: *Self) void {
        _ = self.getArea();
    }

    pub fn draw(self: *Self, command: DrawCommand) void {
        if (self.in_popup) {
            self.command_list_popup.append(command) catch unreachable;
        } else {
            if (self.current_layout_cache_data) |lcd| {
                lcd.commands.append(command) catch unreachable;
            }
            //self.command_list.append(command) catch unreachable;
        }
    }

    pub fn drawSetCamera(self: *Self, cam: DrawCommand) void {
        self.draw(cam);
        //self.command_list.append(cam) catch unreachable;
    }

    pub fn scissor(self: *Self, r: ?Rect) void {
        _ = self;
        _ = r;
        //self.draw(.{ .scissor = .{ .area = r } });
    }

    pub fn drawText(self: *Self, string: []const u8, pos: Vec2f, size: f32, color: Color) void {
        self.draw(.{ .text = .{ .string = self.storeString(string), .pos = pos.toI(i16, Vec2i), .size = size, .color = color, .font = self.font } });
    }

    pub fn drawIcon(self: *Self, icon: u21, pos: Vec2f, size: f32, color: Color) void {
        var out: [4]u8 = undefined;
        const count = std.unicode.utf8Encode(icon, &out) catch unreachable;
        self.draw(.{ .text = .{ .string = self.storeString(out[0..count]), .pos = pos.toI(i16, Vec2i), .size = size, .color = color, .font = self.icon_font } });
    }

    pub fn drawLine(self: *Self, a: Vec2f, b: Vec2f, color: Color) void {
        self.draw(.{ .line = .{ .a = a, .b = b, .color = color } });
    }

    pub fn drawRectFilled(self: *Self, r: Rect, color: Color) void {
        self.draw(.{ .rect_filled = .{ .r = r, .color = color } });
    }

    pub fn drawRectOutline(self: *Self, r: Rect, color: Color) void {
        self.draw(.{ .rect_outline = .{ .r = r, .color = color } });
    }

    pub fn drawRectTextured(self: *Self, r: Rect, color: Color, uv: Rect, t: graph.Texture) void {
        self.draw(.{ .rect_textured = .{ .r = r, .color = color, .uv = uv, .texture = t } });
    }

    //Colors are wound ccw, starting at top left
    pub fn drawRectMultiColor(self: *Self, r: Rect, colors: [4]Color) void {
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
        color: Color,
        opts: struct { justify: Justify = .left },
    ) void {
        const slice = self.scratchPrint(fmt, args);
        //const slice = fbs.getWritten();
        const bounds = self.font.textBounds(slice, size);
        const last_char_index = blk: {
            if (self.font.nearestGlyphX(slice, size, .{ .x = area.w, .y = 0 })) |lci| {
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
        self.drawText(sl, Vec2f.new(x, area.y), size, color);
    }

    pub fn colorInline(self: *Self, color: *Hsva) !void {
        const rec = self.getArea() orelse return;
        const id = self.getId();

        const click = self.clickWidget(rec);
        const wstate = self.getWidgetState(.{ .c = click, .r = rec, .cc = color.* });

        if (self.isActivePopup(id)) {
            const lrq = self.layout.last_requested_bounds orelse graph.Rec(0, 0, 0, 0);
            const pr = graph.Rec(lrq.x, lrq.y, 700, 700);
            try self.beginPopup(pr);
            //_ = try self.beginLayout(SubRectLayout, .{ .rect = pr });
            //defer self.endLayout();
            defer self.endPopup();
            self.colorPicker(color);
        } else {
            if (click == .click) {
                self.popup_id = id;
                self.last_frame_had_popup = true;
            }
        }
        if (wstate != .no_change)
            self.drawRectFilled(rec, graph.hsvaToColor(color.*));
    }

    //TODO what happens when the enum has lots of values and can't fit on the screen. Add scrolling function.
    //Should typing and autocompleting a value be a function

    pub fn drawConsole(self: *Self, console: Console, line_height: f32) void {
        const area = self.getArea() orelse return;
        const count: usize = @intFromFloat(area.h / line_height);
        var start: usize = 0;
        if (count < console.lines.items.len) {
            start = console.lines.items.len - count;
        }
        var y: f32 = 0;
        self.drawRectFilled(area, Color.Black);
        for (console.lines.items[start..]) |line| {
            self.drawText(line, .{ .x = area.x, .y = area.y + y }, line_height, Color.White);
            y += line_height;
        }
    }

    pub fn beginScroll(self: *Self, offset: *Vec2f, opts: struct {
        horiz_scroll: bool = false,
        vertical_scroll: bool = false,
        bar_w: f32 = 60,
        scroll_area_w: f32,
        scroll_area_h: f32,
    }) !?ScrollData {
        var area = self.getArea() orelse return null;

        if (opts.horiz_scroll)
            area.h -= opts.bar_w;
        if (opts.vertical_scroll)
            area.w -= opts.bar_w;

        var clipped_area = area;
        //Scroll exists inside a scroll. Push bounds and offset into parent layout
        if (self.scroll_bounds) |parent_b| {
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

        self.scroll_bounds = clipped_area;
        self.scissor(clipped_area);
        _ = try self.beginLayout(
            SubRectLayout,
            .{ .rect = graph.Rec(area.x - offset.x, area.y - offset.y, opts.scroll_area_w, opts.scroll_area_h) },
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

        self.scroll_bounds = self.layout.parent_scroll_bounds;
        self.scissor(self.scroll_bounds);
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

    pub fn sliderGeneric(self: *Self, number_ptr: anytype, min: anytype, max: anytype, params: struct {
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
        if (pinfo != .Pointer or pinfo.Pointer.is_const) @compileError(invalid_type_error);
        const number_type = pinfo.Pointer.child;
        const number_t: GenericWidget.NumType = switch (@typeInfo(number_type)) {
            .Float => .float,
            .Int => |int| switch (int.signedness) {
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

        if (lmax - lmin == 0)
            return null;

        const mdel = orient.vec2fComponent(self.input_state.mouse_delta);
        const mpos = orient.vec2fComponent(self.input_state.mouse_pos);
        const scale = (rec.w - params.handle_w - (params.handle_offset_x * 2)) / (lmax - lmin);

        var val: f32 = switch (number_t) {
            .float => @as(f32, @floatCast(number_ptr.*)),
            .int, .uint => @as(f32, @floatFromInt(number_ptr.*)),
        };

        var handle: Rect = switch (orient) {
            .horizontal => Rect.new(params.handle_offset_x + arec.x + (val - min) * scale, params.handle_offset_y + arec.y, params.handle_w, params.handle_h),
            .vertical => Rect.new(params.handle_offset_y + arec.x, params.handle_offset_x + arec.y + (val - min) * scale, params.handle_h, params.handle_w),
        };

        const clicked = self.clickWidget(handle);

        if (clicked == .click) {
            self.focused_slider_state = 0;
        }

        // Only moving the slider until after our initial .click state prevents the slider from teleporting when used with a touch screen or other input method that teleports the cursor like a drawing tablet.
        if (clicked == .held) {
            val += self.focused_slider_state;
            val += mdel / scale;
            val = std.math.clamp(val, lmin, lmax);

            //Prevent the slider's and the cursor's position from becoming misaligned when the cursor goes past the slider boundries.
            if (mpos - params.handle_offset_x > rec.x + rec.w)
                val = max;
            if (mpos + params.handle_offset_x < rec.x)
                val = min;

            if (number_t == .int or number_t == .uint)
                self.focused_slider_state = (val - @trunc(val));
            (if (is_horiz) handle.x else handle.y) = params.handle_offset_x + rec.x + (val - lmin) * scale;
        }

        if (self.mouse_grab_id == null and !self.scroll_claimed_mouse and arec.containsPoint(self.input_state.mouse_pos)) {
            self.scroll_claimed_mouse = true;
            switch (number_t) {
                .float => {},
                .int, .uint => {
                    val += self.input_state.mouse_wheel_delta;
                    val = std.math.clamp(val, lmin, lmax);
                },
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

    pub fn textboxGeneric(self: *Self, contents: *std.ArrayList(u8), params: struct {
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
        };

        if (self.isActiveTextinput(id)) {
            const tb = &self.textbox_state;
            self.text_input_state.advanceStateActive();
            try tb.handleEventsOpts(
                self.text_input_state.buffer,
                self.input_state,
                .{ .restricted_charset = params.restrict_chars_to },
            );
            const sl = tb.getSlice();
            const caret_x = self.font.textBounds(sl[0..@as(usize, @intCast(tb.head))], trect.h).x;
            ret.caret = caret_x;

            if (!std.mem.eql(u8, sl, contents.items)) {
                try contents.resize(sl.len);
                std.mem.copy(u8, contents.items, sl);
            }
        }
        if (click == .click) {
            if (!self.isActiveTextinput(id)) {
                self.text_input_state.active_id = id;
                try self.textbox_state.resetFmt("{s}", .{contents.items});
            }
            const cin = self.font.nearestGlyphX(self.textbox_state.getSlice(), trect.h, self.input_state.mouse_pos.sub(trect.pos()));
            if (cin) |cc| {
                self.textbox_state.setCaret(cc - 1);
            }
        }
        ret.slice = contents.items;
        return ret;
    }

    pub fn textboxNumberGeneric(self: *Self, number_ptr: anytype, params: struct {
        text_inset: f32,
    }) !?GenericWidget.Textbox {
        const NumType = enum { uint, int, float };

        const comptime_err_prefix = @typeName(@This()) ++ ".textboxNumberGeneric: ";
        const invalid_type_error = comptime_err_prefix ++ "Argument \'number_ptr\' expects a mutable pointer to an int or float. Recieved: " ++ @typeName(@TypeOf(number_ptr));
        const area = self.getArea() orelse return null;
        const tarea = area.inset(params.text_inset);

        const pinfo = @typeInfo(@TypeOf(number_ptr));
        if (pinfo != .Pointer or pinfo.Pointer.is_const) @compileError(invalid_type_error);
        const number_type = pinfo.Pointer.child;
        const number_t: NumType = switch (@typeInfo(number_type)) {
            .Float => .float,
            .Int => |int| switch (int.signedness) {
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
            const charset = switch (number_t) {
                .int => "-0123456789",
                .uint => "0123456789",
                .float => "ainf.-0123456789",
            };
            self.text_input_state.advanceStateActive();
            try self.textbox_state.handleEventsOpts(
                self.text_input_state.buffer,
                self.input_state,
                .{ .restricted_charset = charset },
            );
            const sl = self.textbox_state.getSlice();
            const caret_x = self.font.textBounds(sl[0..@as(usize, @intCast(self.textbox_state.head))], tarea.h).x;
            ret.caret = caret_x;
            if (sl.len == 0) {
                number_ptr.* = 0;
            } else {
                number_ptr.* = switch (number_t) {
                    .float => std.fmt.parseFloat(number_type, sl) catch blk: {
                        ret.is_invalid = true;
                        break :blk number_ptr.*;
                    },
                    .uint, .int => std.fmt.parseInt(number_type, sl, 10) catch blk: {
                        ret.is_invalid = true;
                        break :blk number_ptr.*;
                    },
                };
            }
            ret.slice = self.storeString(sl);
        } else {
            ret.slice = self.scratchPrint("{d}", .{number_ptr.*});
            //var fbs = std.io.FixedBufferStream([]u8){ .pos = 0, .buffer = &self.scratch_buf };
            //try fbs.writer().print("{d}", .{number_ptr.*});
            //ret.slice = fbs.getWritten();
        }
        if (click == .click) {
            if (!self.isActiveTextinput(id)) {
                self.text_input_state.active_id = id;
                try self.textbox_state.resetFmt("{d}", .{number_ptr.*});
            }

            const cin = self.font.nearestGlyphX(self.textbox_state.getSlice(), tarea.h, self.input_state.mouse_pos.sub(tarea.pos()));
            if (cin) |cc| {
                self.textbox_state.setCaret(cc - 1);
            }
        }

        return ret;
    }

    //TODO there are a few states for this function when drawing
    //popped / not popped
    // A 'U' indicates user facing
    // beginPopup
    // U "draw stuff"
    // beginscrollVLayout <- This causes draw.scissor to be called, if we inset the scroll area but want to draw a border it has to happend before this call
    // U for each enum value draw a widget
    // U set a value if clicked
    // end the v layout
    // end all regardless
    // U draw the non popped
    //
    pub fn enumDropdownGeneric(self: *Self, comptime enumT: type, enum_val: *enumT, params: struct {
        max_items: usize,
        scroll_bar_w: f32,
        inset_scroll: f32 = 0,
    }) !?GenericWidget.EnumDropdown {
        const rec = self.getArea() orelse return null;
        const id = self.getId();
        const h = rec.h;
        const nfields = @typeInfo(enumT).Enum.fields.len;

        _ = enum_val;
        const click = self.clickWidget(rec);
        const popup_h = h * @as(f32, if (nfields > params.max_items) @floatFromInt(params.max_items) else @floatFromInt(nfields));

        if (self.isActivePopup(id)) {
            //var done = false;
            const lrq = self.layout.last_requested_bounds orelse graph.Rec(0, 0, 0, 0);
            const popup_rec = graph.Rec(lrq.x, lrq.y, lrq.w, popup_h);
            try self.beginPopup(popup_rec);
            const inset = popup_rec.inset(params.inset_scroll);
            _ = try self.beginLayout(SubRectLayout, .{ .rect = inset }, .{});
            if (try self.beginVLayoutScroll(&self.enum_drop_down_scroll, .{ .item_height = h }, params.scroll_bar_w)) |scroll| {
                return .{
                    .area = popup_rec,
                    .popup_active = true,
                    .slider_area = scroll.data.vertical_slider_area.?,
                    .slider_range = .{ .x = 0, .y = h * nfields - inset.h },
                    .slider_ptr = &self.enum_drop_down_scroll.y,
                };
            }
            self.endLayout();
            self.endPopup();
        } else {
            if (click == .click) {
                self.enum_drop_down_scroll = .{ .x = 0, .y = 0 };
                self.popup_id = id;
                self.last_frame_had_popup = true;
            }
        }
        return .{ .area = rec, .popup_active = false };
    }

    //TODO make generic
    pub fn colorPicker(self: *Self, color: *Hsva) void {
        const hue_slider_w = 70;
        //const sv_size = 500;
        const rec = self.getArea() orelse return;
        const sv_area = Rect.new(rec.x, rec.y, rec.w - hue_slider_w, rec.h);
        const h_area = Rect.new(rec.x + rec.w - hue_slider_w, rec.y, hue_slider_w, rec.h);
        const wstate = self.getWidgetState(.{ .t = WidgetTypes.color_picker, .r = rec.toIntRect(i16, SRect) });

        var hsva = color.*;
        const hs = 15;
        var sv_handle = Rect.new(sv_area.x + hsva.s * sv_area.w - hs / 2, sv_area.y + (1.0 - hsva.v) * sv_area.h - hs / 2, hs, hs);

        const hue_handle_height = 15;
        var hue_handle = Rect.new(h_area.x, h_area.y + h_area.h * hsva.h / 360.0 - hue_handle_height / 2, h_area.w, hue_handle_height);

        const clicked = self.clickWidgetEx(sv_handle, .{ .teleport_area = sv_area }).click;
        const mpos = self.input_state.mouse_pos;
        switch (clicked) {
            .click, .held => {
                const mdel = self.input_state.mouse_delta;

                hsva.s += mdel.x / sv_area.w;
                hsva.v += -mdel.y / sv_area.h;

                hsva.s = std.math.clamp(hsva.s, 0, 1);
                hsva.v = std.math.clamp(hsva.v, 0, 1);

                if (mpos.x > sv_area.x + sv_area.w)
                    hsva.s = 1.0;
                if (mpos.x < sv_area.x)
                    hsva.s = 0.0;

                if (mpos.y > sv_area.y + sv_area.h)
                    hsva.v = 0.0;
                if (mpos.y < sv_area.y)
                    hsva.v = 1.0;
            },
            .click_teleport => {
                hsva.s = (mpos.x - sv_area.x) / sv_area.w;
                hsva.v = (1.0 - (mpos.y - sv_area.y) / sv_area.h);
                hsva.s = std.math.clamp(hsva.s, 0, 1);
                hsva.v = std.math.clamp(hsva.v, 0, 1);
            },

            else => {},
        }

        sv_handle = Rect.new(sv_area.x + hsva.s * sv_area.w - hs / 2, sv_area.y + (1.0 - hsva.v) * sv_area.h - hs / 2, hs, hs);

        const hue_clicked = self.clickWidgetEx(hue_handle, .{ .teleport_area = h_area }).click;
        switch (hue_clicked) {
            .click, .held => {
                const mdel = self.input_state.mouse_delta;
                hsva.h += 360 * mdel.y / h_area.h;
                hsva.h = std.math.clamp(hsva.h, 0, 360);

                if (self.input_state.mouse_pos.y > h_area.y + h_area.h)
                    hsva.h = 360.0;
                if (self.input_state.mouse_pos.y < h_area.y)
                    hsva.h = 0.0;
            },
            .click_teleport => {
                hsva.h = (mpos.y - h_area.y) / h_area.h * 360.0;
            },
            else => {},
        }
        hue_handle = Rect.new(h_area.x, h_area.y + h_area.h * hsva.h / 360.0 - hue_handle_height / 2, h_area.w, hue_handle_height);

        color.* = hsva;

        if (graph.rectContainsPoint(rec, self.input_state.mouse_pos) or wstate != .no_change or clicked != .none or hue_clicked != .none) {
            const Col = graph.CharColorNew;
            self.drawRectFilled(rec, Color.Gray);
            //Ported from Nuklear
            {
                const hue_colors: [7]Color = .{ Col(255, 0, 0, 255), Col(255, 255, 0, 255), Col(0, 255, 0, 255), Col(0, 255, 255, 255), Col(0, 0, 255, 255), Col(255, 0, 255, 255), Col(255, 0, 0, 255) };
                const hr = h_area;
                var i: u32 = 0;
                while (i < 6) : (i += 1) {
                    const fi = @as(f32, @floatFromInt(i));
                    self.drawRectMultiColor(Rect.new(hr.x, hr.y + fi * hr.h / 6.0, hr.w, hr.h / 6.0), .{
                        hue_colors[i], // 1
                        hue_colors[i + 1], //3
                        hue_colors[i + 1], //4
                        hue_colors[i], //2
                    });
                }
            }
            const temp = graph.hsvaToColor(.{ .h = hsva.h, .s = 1, .v = 1, .a = 1 });
            const black_trans = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };
            self.drawRectMultiColor(sv_area, .{ Color.White, Color.White, temp, temp });
            self.drawRectMultiColor(sv_area, .{ black_trans, Color.Black, Color.Black, black_trans });

            self.drawRectFilled(sv_handle, Color.Black);
            self.drawRectFilled(hue_handle, Color.Black);
        }
    }

    fn editProperty(self: *Self, comptime propertyT: type, property: *propertyT) !void {
        const child_info = @typeInfo(propertyT);
        switch (child_info) {
            .Struct => {
                const o = property;
                switch (propertyT) {
                    graph.Hsva => try self.colorInline(property),
                    graph.Rect => try self.printLabel("Rect({d:.2} {d:.2} {d:.2} {d:.2})", .{ o.x, o.y, o.w, o.h }),
                    else => {
                        //self.drawText("Struct", .{ .x = rec.x + rec.w / 2, .y = rec.y + fi * item_height }, item_height, Color.Black);
                        const rec = self.getArea() orelse return;
                        const wstate = self.getWidgetState(.{ .p = rec });
                        const id = self.getId();
                        const click = self.clickWidget(rec);
                        if (self.isActivePopup(id)) {
                            const lrq = self.layout.last_requested_bounds orelse return;
                            const pr = graph.Rec(lrq.x, lrq.y, 900, 700);
                            try self.beginPopup(pr);
                            defer self.endPopup();

                            //if (try self.beginLayout(try ld.getWidgetData(0), .{ .item_height = 3000 }, .{})) |scroll| {
                            //    defer self.endScroll(scroll);
                            //    try self.propertyTable(propertyT, property);
                            //}
                        } else {
                            if (click == .click) {
                                self.popup_id = id;
                                self.last_frame_had_popup = true;
                            }
                        }

                        if (wstate != .no_change)
                            self.drawText("{Struct}", rec.pos(), rec.h, Color.Black);
                    },
                }
            },
            .Bool => {
                self.checkbox("cunt", property);
                //try self.printLabel("{any}", .{property.*});
            },
            .Enum => {
                try self.enumDropDown(propertyT, property);
            },
            .Int, .Float => {
                try self.textboxNumber(property);
            },
            .Pointer => |p| {
                switch (p.size) {
                    .Slice => {
                        switch (p.child) {
                            u8 => {
                                try self.printLabel("{s}", .{property.*});
                            },
                            else => {},
                        }
                    },
                    else => {
                        self.skipArea();
                    },
                }
            },
            else => {
                self.skipArea();
            },
        }
    }

    pub fn propertyTableHeight(self: *Self, comptime propertyT: type) f32 {
        _ = self;
        const item_height = 40;
        const info = @typeInfo(propertyT);
        return @as(f32, @floatFromInt(info.Struct.fields.len)) * item_height;
    }

    //TODO
    //What functions do we need to provide for property.
    //Number spinner.
    //boolean checkbox
    //Tuple drop down. (Vec3 is displayed as (x, y, z) can be dropped down to modify each component)
    pub fn propertyTable(self: *Self, comptime propertyT: type, property: *propertyT) !void {
        const info = @typeInfo(propertyT);
        //TODO check property is a struct

        const num = info.Struct.fields.len;
        const item_height = 40;
        const rec = self.getArea() orelse return;
        _ = try self.beginLayout(SubRectLayout, .{ .rect = rec }, .{});
        defer self.endLayout();

        _ = try self.beginLayout(TableLayout, .{ .item_height = item_height, .columns = 2 }, .{});
        defer self.endLayout();

        const wstate = self.getWidgetState(.{ .t = WidgetTypes.propertyTable, .r = rec.toIntRect(i16, SRect), .n = num });
        if (wstate != .no_change) {
            self.drawRectFilled(rec, Color.White);
        }

        inline for (info.Struct.fields) |field| {
            const ar = self.getArea() orelse return;
            if (wstate != .no_change) {
                self.drawText(field.name, ar.pos(), item_height, Color.Black);
            }
            const child_info = @typeInfo(field.type);
            switch (child_info) {
                .Optional => {
                    const op = @field(property, field.name);
                    if (op != null) {
                        try self.editProperty(@TypeOf(op.?), &(@field(property, field.name).?));
                    } else {
                        try self.printLabel("null", .{});
                    }
                },
                else => {
                    try self.editProperty(field.type, &@field(property, field.name));
                },
            }
        }

        if (wstate != .no_change) {
            self.drawLine(.{ .x = rec.x + rec.w / 2, .y = rec.y }, .{ .x = rec.x + rec.w / 2, .y = rec.y + item_height * @as(f32, @floatFromInt(num)) }, Color.Black);
            var i: u32 = 0;
            while (i <= num) : (i += 1) {
                self.drawLine(
                    .{ .x = rec.x, .y = rec.y + item_height * @as(f32, @floatFromInt(i)) },
                    .{ .x = rec.x + rec.w, .y = rec.y + item_height * @as(f32, @floatFromInt(i)) },
                    Color.Black,
                );
            }
        }
    }
};

pub const GuiDrawContext = struct {
    const Self = @This();

    main_rtexture: graph.RenderTexture,
    popup_rtexture: graph.RenderTexture,

    camera_offset: Vec2f = .{ .x = 0, .y = 0 },
    camera_bounds: ?Rect = null,
    win_bounds: Rect = graph.Rec(0, 0, 0, 0),

    pub fn init() !Self {
        return .{ .main_rtexture = try graph.RenderTexture.init(10, 10), .popup_rtexture = try graph.RenderTexture.init(10, 10) };
    }

    pub fn deinit(self: *Self) void {
        self.main_rtexture.deinit();
        self.popup_rtexture.deinit();
    }

    pub fn drawGui(self: *Self, draw: *graph.ImmediateDrawingContext, font: *graph.Font, parea: Rect, gui: *Context, win_w: i32, win_h: i32) !void {
        try self.main_rtexture.setSize(@as(i32, @intFromFloat(parea.w)), @as(i32, @intFromFloat(parea.h)));
        const ignore_cache = true;
        self.main_rtexture.bind(ignore_cache);
        self.camera_bounds = parea;
        {
            var scissor: bool = false;
            var scissor_depth: u32 = 0;
            var node = gui.layout_cache.first;
            while (node) |n| : (node = n.next) {
                if (n.data.scissor) |sz| {
                    scissor = true;
                    scissor_depth = n.depth;
                    try self.drawCommand(.{ .scissor = .{ .area = sz } }, draw, font);
                }
                if (n.data.scissor == null) {
                    if (scissor and n.depth <= scissor_depth) {
                        scissor = false;
                        try self.drawCommand(.{ .scissor = .{ .area = null } }, draw, font);
                    }
                }
                for (n.data.commands.items) |command| {
                    try self.drawCommand(command, draw, font);
                }
                n.data.draw_backup = false;
            }
        }
        try draw.flush(parea);
        draw.screen_dimensions = .{ .x = @as(f32, @floatFromInt(win_w)), .y = @as(f32, @floatFromInt(win_h)) };
        graph.c.glBindFramebuffer(graph.c.GL_FRAMEBUFFER, 0);
        graph.c.glViewport(0, 0, win_w, win_h);

        const tr = self.main_rtexture.texture.rect();
        draw.rectTex(graph.Rec(parea.x, parea.y, parea.w, parea.h), graph.Rec(0, 0, tr.w, -tr.h), self.main_rtexture.texture);

        if (true)
            return;
        //ctx.screen_bounds = graph.IRect.new(0, 0, @intFromFloat(parea.w), @intFromFloat(parea.h));
        draw.screen_dimensions = .{ .x = parea.w, .y = parea.h };
        {
            const c = graph.c;
            c.glEnable(c.GL_STENCIL_TEST);
            c.glColorMask(c.GL_FALSE, c.GL_FALSE, c.GL_FALSE, c.GL_FALSE);
            c.glDepthMask(c.GL_FALSE);
            c.glClearStencil(0xff);
            c.glStencilFunc(c.GL_NEVER, 1, 0xFF);
            c.glStencilOp(c.GL_REPLACE, c.GL_KEEP, c.GL_KEEP); // draw 1s on test fail (always)

            c.glStencilMask(0xFF);
            c.glClear(c.GL_STENCIL_BUFFER_BIT); // needs mask=0xFF

            var node = gui.layout_cache.first;
            var redraw_depth: ?u32 = null;
            while (node) |n| : (node = n.next) {
                if (redraw_depth) |dep| {
                    if (n.depth > dep) {
                        n.data.draw_cmds = true;
                        continue;
                    } else {
                        redraw_depth = null;
                    }
                }
                if (n.data.draw_cmds) {
                    draw.rect(if (n.data.scissor) |s| s else n.data.rec, Colori.Black);
                    redraw_depth = n.depth;
                }
            }
            try draw.flush(null);
            c.glColorMask(c.GL_TRUE, c.GL_TRUE, c.GL_TRUE, c.GL_TRUE);
            c.glDepthMask(c.GL_TRUE);
            c.glStencilMask(0x00);
            c.glStencilFunc(c.GL_EQUAL, 1, 0xFF);
        }
        draw.rect(parea, Colori.Blue);
        {
            var scissor: bool = false;
            var scissor_depth: u32 = 0;
            var node = gui.layout_cache.first;
            while (node) |n| : (node = n.next) {
                if (n.data.draw_cmds or ignore_cache or n.data.draw_backup) {
                    if (n.data.scissor) |sz| {
                        scissor = true;
                        scissor_depth = n.depth;
                        try self.drawCommand(.{ .scissor = .{ .area = sz } }, draw, font);
                    }
                    for (n.data.commands.items) |command| {
                        try self.drawCommand(command, draw, font);
                    }
                }
                if (n.data.scissor == null) {
                    if (scissor and n.depth <= scissor_depth) {
                        scissor = false;
                        try self.drawCommand(.{ .scissor = .{ .area = null } }, draw, font);
                    }
                }
                n.data.draw_backup = false;
            }
        }
        graph.c.glDisable(graph.c.GL_STENCIL_TEST);

        //if (gui.popup) |p| {
        //    //try self.popup_rtexture.setSize(@as(i32, @intFromFloat(p.area.w)), @as(i32, @intFromFloat(p.area.w)));
        //    //self.popup_rtexture.bind(true);

        //    _ = p;
        //    //ctx.screen_bounds = graph.Rec(p.area.x, p.area.y + p.area.h, p.area.x + p.area.w, p.area.y).toIntRect(i32, graph.IRect);
        //    for (gui.command_list_popup.items) |command| {
        //        try self.drawCommand(command, ctx, font);
        //    }
        //    try ctx.flush(.{ .x = 0, .y = 0 }, null);
        //}

        //for (gui.tooltip_state.command_list.items) |tt| {
        //    try self.drawCommand(tt, ctx, font);
        //    try ctx.flush(.{ .x = 0, .y = 0 }, null);
        //}

        //try ctx.drawRectTex(parea, parea, Color.White, self.main_rtexture.texture);

        //try ctx.drawRectTex(parea, graph.Rec(0, 0, self.main_rtexture.texture.w, self.main_rtexture.texture.h), Color.White, self.main_rtexture.texture);
        //if (gui.popup) |p| {
        //    try ctx.drawRectTex(p.area, graph.Rec(0, 0, self.popup_rtexture.w, self.popup_rtexture.h), Color.White, self.popup_rtexture.texture);
        //}
    }

    pub fn drawCommand(self: *Self, command: DrawCommand, draw: *graph.ImmediateDrawingContext, font: *graph.Font) !void {
        const cc = graph.ptypes.charColorToInt;
        _ = font;
        switch (command) {
            .rect_filled => |rf| {
                draw.rect(rf.r, cc(rf.color));
            },
            .text => |t| {
                const p = t.pos.toF();

                draw.textPx(p, t.string, t.font, t.size * 0.7, cc(t.color));
            },
            .line => |l| {
                draw.line(l.a, l.b, cc(l.color));
            },
            .rect_textured => |t| {
                draw.rectTexTint(t.r, t.uv, cc(t.color), t.texture);
            },
            .rect_outline => |rl| {
                const r = rl.r;
                draw.line(r.topL(), r.topR(), cc(rl.color));
                draw.line(r.topR(), r.botR(), cc(rl.color));
                draw.line(r.botR(), r.botL(), cc(rl.color));
                draw.line(r.botL(), r.topL(), cc(rl.color));
            },
            .set_camera => |sc| {
                try draw.flush(sc.cam_area);
                //try ctx.flush(sc.offset, sc.cam_area);
                draw.setViewport(sc.win_area);
            },
            .scissor => |s| {
                const c = graph.c;
                try draw.flush(self.camera_bounds);
                //try ctx.flush(self.camera_offset, self.camera_bounds);
                if (s.area) |ar| {
                    c.glEnable(c.GL_SCISSOR_TEST);
                    c.glScissor(
                        @as(i32, @intFromFloat(ar.x - self.camera_bounds.?.x)),
                        //@as(i32, @intFromFloat(draw.screen_dimensions.y - (ar.y + ar.h))),
                        @as(i32, @intFromFloat(self.camera_bounds.?.h - (ar.y + ar.h) + self.camera_bounds.?.y)),
                        //@floatToInt(i32, ar.y + ar.h) - ctx.screen_bounds.h,
                        @as(i32, @intFromFloat(ar.w)),
                        @as(i32, @intFromFloat(ar.h)),
                    );
                    //ctx.drawRect(graph.Rec(0, 0, 10000, 10000), Color.Blue);
                } else {
                    c.glDisable(c.GL_SCISSOR_TEST);
                }
            },
            .rect_filled_multi_color => |rf| {
                draw.rect(rf.r, 0xffffffff);
                //TODO  reimplement
                //ctx.drawRectCol(rf.r, rf.colors);
            },
            .rect_9slice => |s| {
                draw.nineSlice(s.r, s.uv, s.texture, s.scale);
                //try ctx.draw9Slice(s.r, s.uv, s.texture, s.scale);
            },
            .rect_9border => |s| {
                _ = s;
                //draw.rectTex(s.r, s.uv, s.texture);
                //try ctx.draw9Border(s.r, s.uv, s.texture, s.scale, s.cutout_start, s.cutout_end);
            },
        }
    }
};
