//! Provides keybinding management.
//! An application may have multiple contexts in which bindings should apply. These contexts can be enabled and disabled.
//! Bindings can also partially overlap within a context, for example both z and ctrl+z can be bound.
//! When ctrl+z is pressed the 'z' bind is not set as it has a lower default priority.
//!
//! When an application calls SDL.Window.pumpEvents, the active context set is determined and the highest priority key is set.
//! By default, priority is equal to the number of modifier keys, although users can choose any value before calling registerBind()
//!
//! struct BindRegistry manages binding contexts.
//!
//! Internal usage:
//! Create a Context using newContext(). This returns an handle to the context.
//!
//! Register some struct Binding using registerBind.
//!
//! A binding has some FocusMode {exclusive, multi}.
//! Multi key events are always passed if their context is active. Multi binds are useful for binds like WASD
//! Exclusive binds: Only one can ever be active. If a higher priority exclusive key has a .rising state it replaces
//! the currently active exclusive bind.
//! There is no guarantee the sequence .rising, .high, .falling are set for exclusive keys.
//! Exclusive binds are useful for traditional keybindings (ctrl+z -> undo)
//!
//! Bindings can also enable repeat. This passes the Os' key repeat by setting the buttons state to .rising whenever repeating.
//!
//! Update loop:
//!     Enable/disable desired contexts
//!
//!     Call updateSdl() (SDL.Window does this internally on pumpEvents())
//!
//!     Users can now poll for key state using isState(bind_id, ButtonState) bool or getState(bind_id) ButtonState
//!     Bindings in inactive contexts always return .low

pub const ButtonBind = union(enum) {
    keycode: keycodes.Keycode,
    scancode: keycodes.Scancode,
    mouse: keycodes.MouseButton,

    fn stateIndex(self: @This()) usize {
        return switch (self) {
            .scancode => |s| @intFromEnum(s),
            .keycode => |k| if (builtin.is_test) @intFromEnum(k) else c.SDL_GetScancodeFromKey(@intFromEnum(k), null),
            .mouse => |m| @as(usize, @intFromEnum(m)) + MouseStateIndexOffset,
        };
    }
};

pub const Binding = struct {
    button: ButtonBind,
    modifier: KeymodMask,
    mode: FocusMode,

    priority: u8,
    context: ContextId,
    repeat: bool = false,

    pub fn bind(btn: ButtonBind, mode: FocusMode, mod: []const Keymod, repeat: bool, ctx: ContextId) @This() {
        return .{
            .context = ctx,
            .repeat = repeat,
            .button = btn,
            .mode = mode,
            .priority = @intCast(mod.len),
            .modifier = Keymod.mask(mod),
        };
    }
};

const log = std.log.scoped(.keybinding);
pub const BindRegistry = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    binds: std.ArrayList(Binding),

    active_bind: BindId = .none,
    active_bind_state: ButtonState = .low,

    /// contains both scancode and mouse state, mouse state begins at MouseStateIndexOffset as keycodes.MouseButton
    button_state: std.ArrayList(ButtonState),
    mod: KeymodMask,

    /// maps button_index to list of bind ids
    /// only .exclusive binds are put in the lut as there is no need to compare the priority of .multi binds.
    button_bind_lut: std.ArrayList(std.ArrayList(BindId)),

    context_counter: usize = 0,
    contexts: std.StaticBitSet(MAX_CONTEXT),

    pub fn init(alloc: std.mem.Allocator) !Self {
        var self = Self{
            .contexts = .initEmpty(),
            .alloc = alloc,
            .binds = .{},
            .button_state = .{},
            .mod = 0,
            .button_bind_lut = .{},
        };
        try self.button_state.appendNTimes(self.alloc, .low, MouseStateIndexOffset + @intFromEnum(keycodes.MouseButton.max_mouse_btn));
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.binds.deinit(self.alloc);
        self.button_state.deinit(self.alloc);

        for (self.button_bind_lut.items) |*lut| {
            lut.deinit(self.alloc);
        }
        self.button_bind_lut.deinit(self.alloc);
    }

    /// Rules:
    /// Iterate sdl keys
    /// if any keys are rising AND they have bindings, determine which binding has highest priority and make it active
    /// otherise:
    /// if there is an active_bind update its state
    ///
    /// Priority rules:
    /// keys with more modifier keys have a higher priority
    pub fn updateSdl(self: *Self, mod: u32) void {
        self.mod = 0;
        if (mod & keycodes.KM_LCTRL > 0 or mod & keycodes.KM_RCTRL > 0) self.mod |= Keymod.mask(&.{.ctrl});
        if (mod & keycodes.KM_LALT > 0 or mod & keycodes.KM_RALT > 0) self.mod |= Keymod.mask(&.{.alt});
        if (mod & keycodes.KM_LSHIFT > 0 or mod & keycodes.KM_RSHIFT > 0) self.mod |= Keymod.mask(&.{.shift});

        var max_priority: u8 = 0;
        var max_binding: BindId = .none;
        for (self.button_state.items, 0..) |state, key_index| {
            if (state == .rising) {
                const binds = if (key_index < self.button_bind_lut.items.len) self.button_bind_lut.items[key_index].items else continue;

                for (binds) |bind_id| {
                    const bind = self.binds.items[@intFromEnum(bind_id)];
                    if (!self.isContextActive(bind.context)) continue;
                    if (Keymod.matches(self.mod, bind.modifier) and bind.priority >= max_priority) {
                        max_priority = bind.priority;
                        max_binding = bind_id;
                    }
                }
            }
        }

        if (max_binding != .none) {
            self.active_bind = max_binding;
            self.active_bind_state = .rising; //This will always be rising
        } else if (self.active_bind != .none) {
            const bind = self.binds.items[@intFromEnum(self.active_bind)];
            self.active_bind_state = self.getButtonState(bind.button);
            if (self.active_bind_state == .low or !self.isContextActive(bind.context))
                self.active_bind = .none;
        }
    }

    fn isContextActive(self: *const Self, ctx_id: ContextId) bool {
        if (ctx_id == .none) return false;
        return self.contexts.isSet(@intFromEnum(ctx_id));
    }

    pub fn enableContexts(self: *Self, mask: ContextMask) void {
        self.contexts.setUnion(mask.set);
    }

    pub fn enableContext(self: *Self, ctx_id: ContextId, enable: bool) void {
        if (ctx_id == .none) return;
        self.contexts.setValue(@intFromEnum(ctx_id), enable);
    }

    pub fn enableAll(self: *Self, enable: bool) void {
        if (enable) self.contexts = .initFull() else self.contexts = .initEmpty();
    }

    pub fn newContext(self: *Self, name: ?[]const u8) !ContextId {
        const id = self.context_counter;
        self.context_counter += 1;
        if (id >= MAX_CONTEXT) return error.tooManyContext;
        _ = name;
        //if (name) |n| log.info("adding context {s} {d}", .{ n, id });
        return @enumFromInt(id);
    }

    pub fn registerBind(self: *Self, bind: Binding, name: ?[]const u8) !BindId {
        const id: BindId = @enumFromInt(self.binds.items.len);
        try self.binds.append(self.alloc, bind);

        if (@intFromEnum(bind.context) >= self.context_counter) return error.invalidContext;

        _ = name;
        //if (name) |n| log.info("\tbind {s} {d}", .{ n, id });
        switch (bind.mode) {
            .exclusive => {
                const key_index = bind.button.stateIndex();

                if (key_index >= self.button_bind_lut.items.len)
                    try self.button_bind_lut.appendNTimes(self.alloc, .{}, key_index - self.button_bind_lut.items.len + 1);
                try self.button_bind_lut.items[key_index].append(self.alloc, id);
            },
            .multi => {}, //No need to put multi binds into lut

        }

        return id;
    }

    fn getBind(self: *const Self, bind_id: BindId) ?Binding {
        if (@intFromEnum(bind_id) >= self.binds.items.len) return null;
        return self.binds.items[@intFromEnum(bind_id)];
    }

    pub fn getState(self: *const Self, bind_id: BindId) ButtonState {
        const bind = self.getBind(bind_id) orelse return .low;
        switch (bind.mode) {
            .multi => {
                const btn = self.getButtonState(bind.button);
                if (!self.isContextActive(bind.context) or !Keymod.matches(self.mod, bind.modifier)) return .low;
                if (bind.repeat) {
                    return if (btn == .rising_repeat) .rising else btn;
                } else {
                    return if (btn == .rising_repeat) .high else btn;
                }
            },
            .exclusive => {
                const btn = self.active_bind_state;
                if (bind_id != self.active_bind) return .low;
                if (bind.repeat) {
                    return if (btn == .rising_repeat) .rising else btn;
                } else {
                    return if (btn == .rising_repeat) .high else btn;
                }
            },
        }
    }

    pub inline fn isState(self: *const Self, bind: BindId, state: ButtonState) bool {
        const s = self.getState(bind);
        return (s == state);
    }

    fn getButtonState(self: *const Self, btn: ButtonBind) ButtonState {
        const index = btn.stateIndex();
        if (index >= self.button_state.items.len) return .low;
        return self.button_state.items[index];
    }
};

/// These names are less ambiguous than "pressed" "released" "held"
pub const ButtonState = enum {
    rising,
    rising_repeat,
    high,
    falling,
    low,

    ///From frame to frame, correctly set state of a button given a binary input (up, down)
    pub fn set(self: *ButtonState, pressed: bool) void {
        if (pressed) {
            self.* = switch (self.*) {
                .rising, .high, .rising_repeat => .high,
                .low, .falling => .rising,
            };
        } else {
            self.* = switch (self.*) {
                .rising, .high, .rising_repeat => .falling,
                .low, .falling => .low,
            };
        }
    }
};

pub const FocusMode = enum {
    exclusive, //Only one exclusive binding can be active
    multi, //Many multi binding's can be active, they do not block exclusive
};

pub const BindId = enum(u32) {
    none = std.math.maxInt(u32),
    _,
};

pub const MAX_CONTEXT = 64;

pub const ContextMask = struct {
    pub const empty: ContextMask = .{ .set = .initEmpty() };
    set: std.StaticBitSet(MAX_CONTEXT),

    pub fn setValue(self: *@This(), id: ContextId, value: bool) void {
        if (id == .none) return;
        self.set.setValue(@intFromEnum(id), value);
    }
};

pub const ContextId = enum(u32) {
    none = std.math.maxInt(u32),
    _,
};

pub const MouseStateIndexOffset: usize = @intFromEnum(keycodes.Scancode.ODES);

pub const KeymodMask = u8;
pub const Keymod = enum(KeymodMask) {
    ctrl = 0b1,
    shift = 0b10,
    alt = 0b100,

    pub fn mask(to_mask: []const Keymod) KeymodMask {
        var ret: KeymodMask = 0;
        for (to_mask) |t|
            ret |= @intFromEnum(t);
        return ret;
    }

    pub fn matches(A: KeymodMask, B: KeymodMask) bool {
        //A = mod state
        //B = binding we are testing
        //AB | out
        //00 | 1
        //01 | 0 -> maxterm (A + B')
        //10 | 1
        //11 | 1
        //
        //If all bits are 1, this mod matches.
        //Example: ctrl and shift are held. Bind mod requires shift. Matches. Other way around does not.
        return A | ~B == std.math.maxInt(KeymodMask);
    }
};

//In tests, remember that keycodes cannot be used bacause sdl is not compiled!
test {
    const eq = std.testing.expectEqual;
    var bctx = try BindRegistry.init(std.testing.allocator);
    defer bctx.deinit();

    const ctx0 = try bctx.newContext();

    const my_bind = try bctx.registerBind(.bind(.{ .scancode = .E }, .exclusive, ctx0));
    const ex_1 = try bctx.registerBind(.bind(.{ .scancode = .F }, .exclusive, ctx0));
    const multi_0 = try bctx.registerBind(.bind(.{ .scancode = .W }, .multi, ctx0));
    const multi_1 = try bctx.registerBind(.bind(.{ .scancode = .A }, .multi, ctx0));

    try std.testing.expectEqual(ButtonState.low, bctx.getState(my_bind));
    bctx.button_state.items[@intFromEnum(keycodes.Scancode.E)] = .rising;

    bctx.enableContext(ctx0, true);
    try bctx.updateSdl();
    try std.testing.expectEqual(ButtonState.rising, bctx.getState(my_bind));

    { //Test multi

        bctx.button_state.items[@intFromEnum(keycodes.Scancode.W)] = .high;
        bctx.button_state.items[@intFromEnum(keycodes.Scancode.A)] = .rising;
        try bctx.updateSdl();
        try eq(ButtonState.rising, bctx.getState(my_bind));
        try eq(ButtonState.high, bctx.getState(multi_0));
        try eq(ButtonState.rising, bctx.getState(multi_1));
    }

    { // test multi and exclusive
        bctx.button_state.items[@intFromEnum(keycodes.Scancode.E)] = .high;
        try bctx.updateSdl();
        try eq(ButtonState.high, bctx.getState(my_bind));
        try eq(ButtonState.high, bctx.getState(multi_0));
        try eq(ButtonState.rising, bctx.getState(multi_1));
    }

    { //exclusive rising takes priority
        bctx.button_state.items[@intFromEnum(keycodes.Scancode.F)] = .rising;
        try bctx.updateSdl();
        try eq(ButtonState.low, bctx.getState(my_bind));
        try eq(ButtonState.rising, bctx.getState(ex_1));
        try eq(ButtonState.high, bctx.getState(multi_0));
        try eq(ButtonState.rising, bctx.getState(multi_1));
    }

    { //ctx disable
        bctx.enableContext(ctx0, false);
        try bctx.updateSdl();
        try eq(ButtonState.low, bctx.getState(my_bind));
        try eq(ButtonState.low, bctx.getState(ex_1));
        try eq(ButtonState.low, bctx.getState(multi_0));
        try eq(ButtonState.low, bctx.getState(multi_1));
    }
}

const std = @import("std");
const builtin = @import("builtin");
const c = @import("c.zig").c;
const sdl = @import("SDL.zig");
const keycodes = @import("keycodes.zig");
