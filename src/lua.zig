const std = @import("std");
const lua = @cImport({
    @cInclude("lua.h");
    @cInclude("lauxlib.h");
    @cInclude("lualib.h");
});

const Self = @This();
pub const c = lua;
pub const Ls = ?*lua.lua_State;
threadlocal var zstring_buffer: [512]u8 = undefined;
threadlocal var fba_buffer: [2048]u8 = undefined;

state: Ls,
fba: std.heap.FixedBufferAllocator,

pub fn init() @This() {
    var l = lua.luaL_newstate();
    lua.luaL_openlibs(l);
    return .{
        .fba = std.heap.FixedBufferAllocator.init(&fba_buffer),
        .state = l,
    };
}

pub fn clearAlloc(self: *Self) void {
    self.fba.reset();
}

pub fn loadAndRunFile(self: *Self, filename: [*c]const u8) void {
    const lf = lua.luaL_loadfilex(self.state, filename, "bt");
    checkError(self.state, lua.lua_pcallk(self.state, 0, lua.LUA_MULTRET, 0, 0, null));
    _ = lf;
}

pub fn callLuaFunction(self: *Self, fn_name: [*c]const u8) !void {
    lua.lua_pushcfunction(self.state, handleError);
    _ = lua.lua_getglobal(self.state, fn_name);
    const err = lua.lua_pcallk(self.state, 0, 0, -2, 0, null);
    checkErrorTb(self.state, err);
    lua.lua_pop(self.state, 1); //pushCFunction
    if (err != 0)
        return error.luaError;
}

pub fn reg(self: *Self, name: [*c]const u8, fn_: ?*const fn (Ls) callconv(.C) c_int) void {
    lua.lua_register(self.state, name, fn_);
}

pub fn regN(self: *Self, fns: []const struct { [*c]const u8, ?*const fn (Ls) callconv(.C) c_int }) void {
    for (fns) |fnp| {
        lua.lua_register(self.state, fnp[0], fnp[1]);
    }
}

pub export fn handleError(L: Ls) c_int {
    var len: usize = 0;
    const str = lua.lua_tolstring(L, 1, &len);
    lua.luaL_traceback(L, L, str, 1);
    lua.lua_remove(L, -2);
    return 1;
}

pub fn checkErrorTb(L: Ls, err: c_int) void {
    if (err != lua.LUA_OK) {
        var len: usize = 0;
        const tb = lua.lua_tolstring(L, -1, &len);
        std.debug.print("TRACEBACK {s}\n", .{tb[0..len]});
        lua.lua_pop(L, 1);
    }
}

pub fn checkError(L: Ls, err: c_int) void {
    if (err != 0) {
        var len: usize = 0;
        const str = lua.lua_tolstring(L, 1, &len);
        std.debug.print("LUA ERROR: {s}\n", .{str[0..len]});
        lua.lua_pop(L, 1);
    }
}

pub fn printStack(L: Ls) void {
    std.debug.print("BEGIN STACK DUMP: \n", .{});
    const top = lua.lua_gettop(L);
    var i: i32 = 1;
    while (i <= top) : (i += 1) {
        const t = lua.lua_type(L, i);
        std.debug.print("{d} ", .{i});
        switch (t) {
            lua.LUA_TSTRING => std.debug.print("STRING: {s}\n", .{tostring(L, i)}),
            lua.LUA_TBOOLEAN => std.debug.print("BOOL: {any}\n", .{lua.lua_toboolean(L, i)}),
            lua.LUA_TNUMBER => std.debug.print("{d}\n", .{tonumber(L, i)}),
            else => std.debug.print("{s}\n", .{lua.lua_typename(L, t)}),
        }
    }
    std.debug.print("END STACK\n", .{});
}

pub fn tonumber(L: Ls, idx: c_int) lua.lua_Number {
    var is_num: c_int = 0;
    return lua.lua_tonumberx(L, idx, &is_num);
}

pub fn tostring(L: Ls, idx: c_int) []const u8 {
    var len: usize = 0;
    const str = lua.lua_tolstring(L, idx, &len);
    return str[0..len];
}

pub fn zstring(str: []const u8) [*c]const u8 {
    std.mem.copy(u8, &zstring_buffer, str);
    zstring_buffer[str.len] = 0;
    return &zstring_buffer[0];
}

pub fn getArg(self: *Self, L: Ls, comptime s: type, idx: c_int) s {
    const in = @typeInfo(s);
    return switch (in) {
        .Float => @floatCast(lua.luaL_checknumber(L, idx)),
        .Int => std.math.lossyCast(s, lua.luaL_checkinteger(L, idx)),
        .Enum => blk: {
            var len: usize = 0;
            const str = lua.luaL_checklstring(L, idx, &len);
            const h = std.hash.Wyhash.hash;
            inline for (in.Enum.fields) |f| {
                if (h(0, f.name) == h(0, str[0..len])) {
                    break :blk @enumFromInt(f.value);
                }
            }
        },
        .Bool => lua.lua_toboolean(L, idx) == 1,
        .Union => |u| {
            const eql = std.mem.eql;
            lua.luaL_checktype(L, idx, c.LUA_TTABLE);
            lua.lua_pushnil(L);
            _ = lua.lua_next(L, -2);
            var slen: usize = 0;
            const zname = lua.lua_tolstring(L, -2, &slen);
            const name = zname[0..slen];
            defer lua.lua_pop(L, 2);

            inline for (u.fields) |f| {
                if (eql(u8, f.name, name)) {
                    return @unionInit(s, f.name, self.getArg(L, f.type, -1));
                }
            }
            _ = lua.luaL_error(L, "invalid union value");
            return undefined;
        },
        .Pointer => |p| {
            if (p.size == .Slice) {
                if (p.child == u8) {
                    var len: usize = 0;
                    const str = lua.luaL_checklstring(L, idx, &len);
                    return str[0..len];
                } else {
                    lua.luaL_checktype(L, idx, c.LUA_TTABLE);
                    lua.lua_len(L, idx); //len on stack
                    var is_num: c_int = 0;
                    const len: usize = @intCast(lua.lua_tointegerx(L, -1, &is_num));
                    lua.lua_pop(L, 1);
                    const alloc = self.fba.allocator();
                    const slice = alloc.alloc(p.child, len) catch unreachable;

                    for (1..len + 1) |i| {
                        const lt = lua.lua_geti(L, -1, @intCast(i));
                        _ = lt;
                        slice[i - 1] = self.getArg(L, p.child, -1);
                        lua.lua_pop(L, 1);
                    }
                    return slice;
                }
            } else {
                @compileError("Can't get slice from lua " ++ p);
            }
        },
        .Struct => {
            var ret: s = undefined;
            inline for (in.Struct.fields) |f| {
                const lt = lua.lua_getfield(L, idx, zstring(f.name));
                @field(ret, f.name) = switch (lt) {
                    lua.LUA_TNIL => if (f.default_value) |d| @as(*const f.type, @ptrCast(@alignCast(d))).* else undefined,
                    else => self.getArg(L, f.type, -1),
                };
                lua.lua_pop(L, 1);
            }
            return ret;
        },
        else => @compileError("getV type not supported " ++ @typeName(s)),
    };
}

pub fn getGlobal(self: *Self, L: Ls, name: []const u8, comptime s: type) s {
    _ = lua.lua_getglobal(L, zstring(name));
    switch (@typeInfo(s)) {
        .Struct => {
            return self.getArg(self.state, s, 1);
        },
        else => @compileError("not supported"),
    }
}

pub fn setGlobal(self: *Self, name: [*c]const u8, item: anytype) void {
    pushV(self.state, item);
    lua.lua_setglobal(self.state, name);
}

pub fn pushV(L: Ls, s: anytype) void {
    const info = @typeInfo(@TypeOf(s));
    switch (info) {
        .Struct => |st| {
            lua.lua_newtable(L);
            inline for (st.fields) |f| {
                _ = lua.lua_pushstring(L, zstring(f.name));
                pushV(L, @field(s, f.name));
                lua.lua_settable(L, -3);
            }
        },
        .Enum => {
            const str = @tagName(s);
            _ = lua.lua_pushlstring(L, zstring(str), str.len);
        },
        .Optional => {
            if (s == null) {
                lua.lua_pushnil(L);
            } else {
                pushV(L, s.?);
            }
        },
        .Union => |u| {
            lua.lua_newtable(L);
            inline for (u.fields, 0..) |f, i| {
                if (i == @intFromEnum(s)) {
                    const name = f.name;
                    _ = lua.lua_pushlstring(L, zstring(name), name.len);
                    pushV(L, @field(s, name));
                    lua.lua_settable(L, -3);
                    return;
                }
            }
            lua.lua_pushnil(L);
        },
        .Float => lua.lua_pushnumber(L, s),
        .Bool => lua.lua_pushboolean(L, if (s) 1 else 0),
        .Int => lua.lua_pushinteger(L, std.math.lossyCast(i64, s)),
        .Array => {
            lua.lua_newtable(L);
            for (s, 1..) |item, i| {
                lua.lua_pushinteger(L, @intCast(i));
                pushV(L, item);
                lua.lua_settable(L, -3);
            }
        },
        .Pointer => |p| {
            if (p.size == .Slice) {
                if (p.child == u8) {
                    _ = lua.lua_pushlstring(L, zstring(s), s.len);
                } else {
                    lua.lua_newtable(L);
                    for (s, 1..) |item, i| {
                        lua.lua_pushinteger(L, @intCast(i));
                        pushV(L, item);
                        lua.lua_settable(L, -3);
                    }
                    return;
                }
            } else {
                //@compileError("Can't send slice to lua " ++ p);
            }
        },
        else => @compileError("pusnhV don't work with: " ++ s),
    }
}