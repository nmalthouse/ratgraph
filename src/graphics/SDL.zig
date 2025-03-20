const std = @import("std");
const ptypes = @import("types.zig");
const Vec2f = ptypes.Vec2f;
const Vec2i = ptypes.Vec2i;
const c = @import("c.zig");
pub const glID = c.GLuint;
pub const keycodes = @import("keycodes.zig");
const GL = @import("gl.zig");

fn reduceU32Mask(items: []const u32) u32 {
    var result: u32 = 0;
    for (items) |item| {
        result |= item;
    }
    return result;
}

const log = std.log.scoped(.SDL);
/// These names are less ambiguous than "pressed" "released" "held"
pub const ButtonState = enum {
    rising,
    high,
    falling,
    low,

    ///From frame to frame, correctly set state of a button given a binary input (up, down)
    pub fn set(self: *ButtonState, pressed: bool) void {
        if (pressed) {
            self.* = switch (self.*) {
                .rising, .high => .high,
                .low, .falling => .rising,
            };
        } else {
            self.* = switch (self.*) {
                .rising, .high => .falling,
                .low, .falling => .low,
            };
        }
    }
};

threadlocal var scratch_buffer: [256]u8 = undefined;

pub fn getScancodeFromName(name: []const u8) usize {
    if (name.len > scratch_buffer.len - 1)
        return 0;
    @memcpy(scratch_buffer[0..name.len], name);
    scratch_buffer[name.len] = 0;

    return c.SDL_GetScancodeFromName(&scratch_buffer[0]);
}

pub const MouseState = struct {
    left: ButtonState = .low,
    right: ButtonState = .low,
    middle: ButtonState = .low,
    x1: ButtonState = .low,
    x2: ButtonState = .low,

    pos: Vec2f = .{ .x = 0, .y = 0 },
    delta: Vec2f = .{ .x = 0, .y = 0 },

    wheel_delta: Vec2f = .{ .x = 0, .y = 0 },

    pub fn setButtonsSDL(self: *MouseState, sdl_button_mask: u32) void {
        const b = sdl_button_mask;
        self.left.set(b & c.SDL_BUTTON_LMASK != 0);
        self.right.set(b & c.SDL_BUTTON_RMASK != 0);
        self.middle.set(b & c.SDL_BUTTON_MMASK != 0);
        self.x1.set(b & c.SDL_BUTTON_X1MASK != 0);
        self.x2.set(b & c.SDL_BUTTON_X2MASK != 0);
    }
};

pub const KeyState = struct {
    state: ButtonState,
    scancode: keycodes.Scancode,
};

pub fn getKeyFromScancode(scancode: keycodes.Scancode) keycodes.Keycode {
    return @enumFromInt(c.SDL_GetKeyFromScancode(@intFromEnum(scancode)));
}

pub fn getScancodeFromKey(key: keycodes.Keycode) keycodes.Scancode {
    return @enumFromInt(c.SDL_GetScancodeFromKey(@intFromEnum(key), null));
}

pub const Window = struct {
    const Self = @This();
    pub const KeyboardStateT = std.bit_set.IntegerBitSet(c.SDL_SCANCODE_COUNT);
    pub const KeysT = std.BoundedArray(KeyState, 16);
    pub const KeyStateT = [c.SDL_SCANCODE_COUNT]ButtonState;
    pub const EmptyKeyState: KeyStateT = [_]ButtonState{.low} ** c.SDL_SCANCODE_COUNT;

    pub const ChildWindow = struct {
        win: *c.SDL_Window,

        pub fn deinit(self: *@This()) void {
            c.SDL_DestroyWindow(self.win);
        }
    };

    win: *c.SDL_Window,
    ctx: c.SDL_GLContext,

    screen_dimensions: Vec2i = .{ .x = 0, .y = 0 },
    frame_time: std.time.Timer,
    target_frame_len_ns: ?u64 = null,

    should_exit: bool = false,

    mouse: MouseState = undefined,
    mod: keycodes.KeymodMask = 0,

    //key_state: [c.SDL_SCANCODE_COUNT]ButtonState = [_]ButtonState{.low} ** c.SDL_NUM_SCANCODES,
    key_state: KeyStateT = [_]ButtonState{.low} ** c.SDL_SCANCODE_COUNT,
    keys: KeysT = KeysT.init(0) catch unreachable,
    keyboard_state: KeyboardStateT = KeyboardStateT.initEmpty(),
    last_frame_keyboard_state: KeyboardStateT = KeyboardStateT.initEmpty(),

    text_input_buffer: [32]u8 = undefined,
    text_input: []const u8,

    pub fn sdlLogErr() void {
        log.err("{s}", .{c.SDL_GetError()});
    }

    fn setAttr(attr: c.SDL_GLAttr, val: c_int) !void {
        if (!c.SDL_GL_SetAttribute(attr, val)) {
            sdlLogErr();
            return error.SDLSetAttr;
        }
    }

    pub fn grabMouse(self: *const Self, should: bool) void {
        _ = c.SDL_SetWindowRelativeMouseMode(self.win, if (should) true else false);
        //c.SDL_SetWindowMouseGrab(self.win, if (should) 1 else 0);
        if (should) {
            _ = c.SDL_ShowCursor();
        } else {
            _ = c.SDL_HideCursor();
        }
    }

    //pub fn screenshotGL(self: *const Self,alloc: Alloc,  )void{

    //}

    pub fn createWindow(title: [*c]const u8, options: struct {
        window_size: Vec2i = .{ .x = 1280, .y = 960 },
        double_buffer: bool = true,
        gl_profile: enum { core, compat, es } = .core,
        stencil_buffer_depth: ?i32 = 8,
        gl_major_version: i32 = 4,
        gl_minor_version: i32 = 6,
        ///If set, attempt to make all frames last this long in ns. This option should only be set when frame_sync = .immediate
        target_frame_len_ns: ?u64 = null,
        frame_sync: enum(i32) {
            vsync = 1,
            ///FreeSync, G-Sync
            adaptive_vsync = -1,
            immediate = 0,
        } = .vsync,
        extra_gl_attributes: []const struct { attr: c.SDL_GLAttr, val: i32 } = &.{},
        gl_flags: []const u32 = &.{c.SDL_GL_CONTEXT_DEBUG_FLAG},
        window_flags: []const u32 = &.{},
    }) !Self {
        log.info("Attempting to create window: {s}", .{title});
        if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
            sdlLogErr();
            return error.SDLInit;
        }
        errdefer c.SDL_Quit();

        try setAttr(c.SDL_GL_CONTEXT_PROFILE_MASK, switch (options.gl_profile) {
            .core => c.SDL_GL_CONTEXT_PROFILE_CORE,
            .compat => c.SDL_GL_CONTEXT_PROFILE_COMPATIBILITY,
            .es => c.SDL_GL_CONTEXT_PROFILE_ES,
        });
        try setAttr(c.SDL_GL_DOUBLEBUFFER, if (options.double_buffer) 1 else 0);
        try setAttr(c.SDL_GL_CONTEXT_MAJOR_VERSION, options.gl_major_version);
        try setAttr(c.SDL_GL_CONTEXT_MINOR_VERSION, options.gl_minor_version);
        try setAttr(c.SDL_GL_CONTEXT_FLAGS, @as(i32, @intCast(reduceU32Mask(options.gl_flags))));
        if (options.stencil_buffer_depth) |sdepth|
            try setAttr(c.SDL_GL_STENCIL_SIZE, sdepth);
        for (options.extra_gl_attributes) |attr| {
            try setAttr(attr.attr, attr.val);
        }

        const win = c.SDL_CreateWindow(
            title,
            //c.SDL_WINDOWPOS_UNDEFINED,
            //c.SDL_WINDOWPOS_UNDEFINED,
            options.window_size.x,
            options.window_size.y,
            @as(u32, c.SDL_WINDOW_OPENGL | c.SDL_WINDOW_RESIZABLE) |
                @as(u32, @intCast(reduceU32Mask(options.window_flags))),
        ) orelse {
            sdlLogErr();
            return error.SDLInit;
        };
        errdefer c.SDL_DestroyWindow(win);

        const context = c.SDL_GL_CreateContext(win) orelse {
            sdlLogErr();
            return error.SDLCreatingContext;
        };
        errdefer _ = c.SDL_GL_DestroyContext(context);

        log.info("gl renderer: {s}", .{c.glGetString(c.GL_RENDERER)});
        log.info("gl vendor: {s}", .{c.glGetString(c.GL_VENDOR)});
        log.info("gl version: {s}", .{c.glGetString(c.GL_VERSION)});
        log.info("gl shader version: {s}", .{c.glGetString(c.GL_SHADING_LANGUAGE_VERSION)});

        if (!c.SDL_GL_SetSwapInterval(@intFromEnum(options.frame_sync))) {
            sdlLogErr();
            if (options.frame_sync == .adaptive_vsync) {
                log.warn("Failed to set adaptive sync, attempting to set vsync", .{});
                if (!c.SDL_GL_SetSwapInterval(1)) {
                    sdlLogErr();
                    return error.SetSwapInterval;
                }
            } else {
                return error.SetSwapInterval;
            }
        }
        {
            var set_swap: c_int = 0;
            _ = c.SDL_GL_GetSwapInterval(&set_swap);
            log.info("set swap interval, desired: {s}, actual: {s}", .{
                @tagName(options.frame_sync),
                @tagName(@as(@TypeOf(options.frame_sync), @enumFromInt(set_swap))),
            });
        }
        //TODO where should these be set instead?
        //c.glEnable(c.GL_MULTISAMPLE);
        c.glEnable(c.GL_DEPTH_TEST);
        //c.glEnable(c.GL_STENCIL_TEST);
        c.glEnable(c.GL_DEBUG_OUTPUT);
        c.glEnable(c.GL_DEBUG_OUTPUT_SYNCHRONOUS);
        c.glDebugMessageControl(c.GL_DONT_CARE, c.GL_DONT_CARE, c.GL_DEBUG_SEVERITY_NOTIFICATION, 0, null, c.GL_FALSE);
        c.glDebugMessageCallback(GL.messageCallback, null);

        var ret = Self{
            .win = win,
            .ctx = context,
            .text_input = "",
            .frame_time = try std.time.Timer.start(),
            .target_frame_len_ns = options.target_frame_len_ns,
        };
        ret.pumpEvents();
        return ret;
    }

    pub fn createChildWindow(self: *Self, title: [*c]const u8, w: i32, h: i32) !ChildWindow {
        _ = self;
        const win = c.SDL_CreateWindow(
            title,
            c.SDL_WINDOWPOS_UNDEFINED,
            c.SDL_WINDOWPOS_UNDEFINED,
            w,
            h,
            @as(u32, c.SDL_WINDOW_OPENGL | c.SDL_WINDOW_RESIZABLE),
        ) orelse {
            sdlLogErr();
            return error.SDLWindowInit;
        };
        errdefer c.SDL_DestroyWindow(win);
        return .{ .win = win };
    }

    pub fn destroyWindow(self: Self) void {
        _ = c.SDL_GL_DestroyContext(self.ctx);
        c.SDL_DestroyWindow(self.win);
        c.SDL_Quit();
    }

    pub fn logGlExtensions() void {
        var num_ext: i64 = 0;
        c.glGetInteger64v(c.GL_NUM_EXTENSIONS, &num_ext);
        for (0..@intCast(num_ext)) |i| {
            log.info("ext: {s}", .{c.glGetStringi(c.GL_EXTENSIONS, @intCast(i))});
        }
    }

    pub fn getScancodeFromName(self: *Self, name: [*c]const u8) usize {
        _ = self;
        return c.SDL_GetScancodeFromName(name);
    }

    pub fn swap(self: *Self) void {
        _ = c.SDL_GL_SwapWindow(self.win);
        if (self.target_frame_len_ns) |tft| {
            const frame_took = self.frame_time.read();
            if (frame_took < tft)
                std.time.sleep(tft - frame_took);
        }
    }

    pub fn getDpi(_: *Self) f32 {
        @compileError("broken don't use");
        //var dpi: f32 = 0;

        //var hdpi: f32 = 0;
        //var vdpi: f32 = 0;
        //_ = c.SDL_GetDisplayDPI(c.SDL_GetWindowDisplayIndex(self.win), &dpi, &hdpi, &vdpi);
        //return dpi;
    }

    pub fn setClipboard(alloc: std.mem.Allocator, text: []const u8) !void {
        const sl = try alloc.dupeZ(u8, text);
        if (!c.SDL_SetClipboardText(sl)) {
            sdlLogErr();
        }
        alloc.free(sl);
    }

    /// Caller owns slice
    pub fn getClipboard(alloc: std.mem.Allocator) ![]const u8 {
        const clip = c.SDL_GetClipboardText();
        defer c.SDL_free(clip);
        return try alloc.dupe(u8, std.mem.span(clip));
    }

    pub fn enableNativeIme(self: *const Self, enable: bool) bool {
        _ = self;
        //_ = c.SDL_SetHint("SDL_HINT_IME_INTERNAL_EDITING", "1");
        return (c.SDL_SetHint("SDL_HINT_IME_SHOW_UI", if (enable) "1" else "0") == 1);
    }

    pub fn getKeyboardState(self: *Self, len: *usize) []const u8 {
        _ = self;
        var l: i32 = 0;
        const ret = c.SDL_GetKeyboardState(&l);
        len.* = @intCast(l);
        return ret[0..@intCast(l)];
    }

    pub fn pumpEvents(self: *Self) void {
        self.frame_time.reset();

        c.SDL_PumpEvents();
        {
            var fx: f32 = undefined;
            var fy: f32 = undefined;
            self.mouse.setButtonsSDL(c.SDL_GetMouseState(&fx, &fy));
            self.mouse.pos = .{ .x = fx, .y = fy };

            _ = c.SDL_GetRelativeMouseState(&fx, &fy);

            self.mouse.delta = .{ .x = fx, .y = fy };

            self.mouse.wheel_delta = .{ .x = 0, .y = 0 };
        }
        for (&self.key_state) |*k| {
            k.* = .low;
        }
        self.mod = c.SDL_GetModState();

        self.keys.resize(0) catch unreachable;
        self.last_frame_keyboard_state = self.keyboard_state;
        self.keyboard_state.mask = 0;
        {
            var l: i32 = 0;
            const ret = c.SDL_GetKeyboardState(&l)[0..@intCast(l)];
            //ret[0..@intCast(usize, l)];
            for (ret, 0..) |key, i| {
                if (key) {
                    self.keyboard_state.set(i);
                    self.key_state[i] = .high;
                }
            }
        }
        self.text_input = "";
        //TODO mechanism for using sdl_waitevent instead.
        //block on sdl_waitevent, then sdl_peekevent, check against interval and then return from this function
        //would allow for a gui app to only render frames when needed

        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event)) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => self.should_exit = true,
                c.SDL_EVENT_KEY_DOWN => {
                    if (event.key.key == c.SDLK_ESCAPE)
                        self.should_exit = true;

                    const scancode = c.SDL_GetScancodeFromKey(event.key.key, null);
                    if (!self.last_frame_keyboard_state.isSet(scancode))
                        self.key_state[scancode] = .rising;
                    self.keys.append(.{
                        .state = .rising,
                        .scancode = @enumFromInt(scancode),
                    }) catch unreachable;
                },
                c.SDL_EVENT_KEY_UP => {
                    const scancode = c.SDL_GetScancodeFromKey(event.key.key, null);
                    self.key_state[scancode] = .falling;
                },
                c.SDL_EVENT_TEXT_EDITING_CANDIDATES => {
                    std.debug.print("CANDIDATES\n", .{});
                },
                c.SDL_EVENT_TEXT_EDITING => {
                    const ed = event.edit;
                    const slice = std.mem.sliceTo(ed.text, 0);
                    std.debug.print("TEXT EDIT{s}\n", .{slice});
                },
                c.SDL_EVENT_TEXT_INPUT => {
                    const slice = std.mem.sliceTo(event.text.text, 0);
                    @memcpy(self.text_input_buffer[0..slice.len], slice);
                    self.text_input = self.text_input_buffer[0..slice.len];
                    std.debug.print("TEXT INPUT{s}\n", .{self.text_input});
                },
                c.SDL_EVENT_KEYMAP_CHANGED => {
                    log.warn("keymap changed", .{});
                },
                c.SDL_EVENT_MOUSE_WHEEL => {
                    self.mouse.wheel_delta = Vec2f.new(event.wheel.x, event.wheel.y);
                },
                c.SDL_EVENT_MOUSE_MOTION => {},
                c.SDL_EVENT_MOUSE_BUTTON_DOWN => {},
                c.SDL_EVENT_MOUSE_BUTTON_UP => {},

                c.SDL_EVENT_WINDOW_CLOSE_REQUESTED => self.should_exit = true,
                c.SDL_EVENT_WINDOW_RESIZED, c.SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED => {
                    var x: c_int = undefined;
                    var y: c_int = undefined;
                    _ = c.SDL_GetWindowSize(self.win, &x, &y);
                    self.screen_dimensions.x = x;
                    self.screen_dimensions.y = y;
                    c.glViewport(0, 0, self.screen_dimensions.x, self.screen_dimensions.y);
                },
                else => continue,
            }
        }
    }

    pub fn centerWindow(self: *Self) void {
        c.SDL_SetWindowPosition(self.win, c.SDL_WINDOWPOS_CENTERED, c.SDL_WINDOWPOS_CENTERED);
    }

    pub fn setWindowSize(self: *Self, w: i32, h: i32) void {
        c.SDL_SetWindowSize(self.win, w, h);
    }

    pub fn glScissor(self: *Self, x: i32, y: i32, w: i32, h: i32) void {
        _ = self;
        c.glScissor(x, h - y, w, h);
    }

    pub fn bindScreenFramebuffer(self: *Self) void {
        c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);
        c.glViewport(0, 0, self.screen_dimensions.x, self.screen_dimensions.y);
    }

    pub fn startTextInput(self: *const Self, ime_rect: ?ptypes.Rect) void {
        const rec = if (ime_rect) |r| c.SDL_Rect{
            .x = @intFromFloat(r.x),
            .y = @intFromFloat(r.x),
            .w = @intFromFloat(r.w),
            .h = @intFromFloat(r.h),
        } else c.SDL_Rect{ .x = 0, .y = 0, .w = 100, .h = 100 };
        _ = rec;
        //if (!c.SDL_SetTextInputArea(self.win, &rec, 0)) sdlLogErr();
        if (!c.SDL_StartTextInput(self.win)) sdlLogErr();
    }

    pub fn stopTextInput(self: *const Self) void {
        if (!c.SDL_StopTextInput(self.win)) sdlLogErr();
    }

    pub fn keyRising(self: *const Self, scancode: keycodes.Scancode) bool {
        return self.key_state[@intFromEnum(scancode)] == .rising;
    }

    pub fn keyFalling(self: *const Self, scancode: keycodes.Scancode) bool {
        return self.key_state[@intFromEnum(scancode)] == .falling;
    }

    pub fn keyHigh(self: *const Self, scancode: keycodes.Scancode) bool {
        return self.keyboard_state.isSet(@intFromEnum(scancode));
    }

    pub fn rect(self: *const Self) ptypes.Rect {
        return ptypes.Rect.NewAny(0, 0, self.screen_dimensions.x, self.screen_dimensions.y);
    }
};

pub const BindType = struct {
    pub const Binding = struct {
        keycodes.Scancode,
        keycodes.KeymodMask,
    };
    name: [:0]const u8,
    bind: Binding,
};

pub const BindList = []const BindType;
//TODO remove this crap

///Takes a list of bindings{"name", "key_name"} and generates an enum
///can be used with BindingMap and a switch() to map key input events to actions
pub fn GenerateBindingEnum(comptime map: BindList) type {
    const TypeInfo = std.builtin.Type;
    var fields: [map.len]TypeInfo.EnumField = undefined;

    inline for (map, 0..) |bind, b_i| {
        fields[b_i] = .{ .name = bind.name, .value = b_i };
    }
    return @Type(TypeInfo{ .Enum = .{
        .fields = fields[0..],
        .tag_type = std.math.IntFittingRange(0, map.len),
        .decls = &.{},
        .is_exhaustive = true,
    } });
}

pub fn Bind(comptime bind_list: BindList) type {
    return struct {
        const Self = @This();
        pub const bindlist = bind_list;
        const BindEnum = GenerateBindingEnum(bind_list);

        mappings: [bind_list.len]BindType.Binding = [_]BindType.Binding{.{ .UNKNOWN, 0 }} ** bind_list.len,

        pub fn init() @This() {
            var ret: @This() = .{};

            for (bind_list, 0..) |bind, i| {
                ret.mappings[i] = bind.bind;
            }

            return ret;
        }

        pub fn getWithMod(self: *const @This(), scancode: keycodes.Scancode, mod: keycodes.KeymodMask) ?BindEnum {
            for (self.mappings, 0..) |m, i| {
                if (m[0] == scancode and m[1] == mod)
                    return @enumFromInt(i);
            }
            return null;
        }

        pub fn get(self: *const @This(), scancode: keycodes.Scancode) ?BindEnum {
            return self.scancode_table[@intFromEnum(scancode)].binding;
        }
    };
}
