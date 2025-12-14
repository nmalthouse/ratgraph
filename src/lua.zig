const std = @import("std");
pub const lua = @cImport({
    @cInclude("lua.h");
    @cInclude("lauxlib.h");
    @cInclude("lualib.h");
});

//TODO have a allocator on hand if we exceed fba
const Self = @This();
pub const c = lua;
pub const Ls = ?*lua.lua_State;
threadlocal var zstring_buffer: [512]u8 = undefined;
threadlocal var fba_buffer: [2048]u8 = undefined;

state: Ls,
fba: std.heap.FixedBufferAllocator,

pub fn init() @This() {
    const l = lua.luaL_newstate();
    lua.luaL_openlibs(l);
    return .{
        .fba = std.heap.FixedBufferAllocator.init(&fba_buffer),
        .state = l,
    };
}

pub fn getAlloc(self: *Self) std.mem.Allocator {
    return self.fba.allocator();
}

pub fn clearAlloc(self: *Self) void {
    self.fba.reset();
}

pub fn loadBufferIntoFunction(self: *Self, buf: []const u8, fn_name: []const u8) void {
    //lua.lua_pushcfunction(self.state, handleError);
    _ = lua.luaL_loadbufferx(self.state, &buf[0], buf.len, "crass", null);
    lua.lua_setglobal(self.state, zstring(fn_name));
    //const err = lua.lua_pcallk(self.state, 0, 0, -2, 0, null);
    //checkErrorTb(self.state, err);
    //lua.lua_pop(self.state, 1); //pushCFunction
}

pub fn loadAndRunFile(self: *Self, filename: []const u8) void {
    lua.lua_pushcfunction(self.state, handleError);

    const lf = lua.luaL_loadfilex(self.state, zstring(filename), "bt");
    switch (lf) {
        else => {
            std.debug.print("Unknown lua error in loadAndRunFile()\n", .{});
            return;
        },
        c.LUA_OK => {},
        c.LUA_ERRSYNTAX => {
            std.debug.print("LUA_ERRSYNTAX\n", .{});
            return;
        },
        c.LUA_ERRMEM => {
            std.debug.print("LUA_ERRMEM\n", .{});
            return;
        },
        c.LUA_ERRFILE => {
            std.debug.print("LUA_ERRFILE\n", .{});
            return;
        },
    }
    const err = lua.lua_pcallk(self.state, 0, 0, -2, 0, null);
    checkErrorTb(self.state, err);
    lua.lua_pop(self.state, 1); //pushCFunction
}

pub fn callLuaFunctionEx(self: *Self, fn_name: []const u8, nargs: c_int, nres: c_int) !void {
    lua.lua_pushcfunction(self.state, handleError);
    _ = lua.lua_getglobal(self.state, zstring(fn_name));
    const err = lua.lua_pcallk(self.state, nargs, nres, -2, 0, null);
    checkErrorTb(self.state, err);
    lua.lua_pop(self.state, 1); //pushCFunction
    if (err != 0)
        return error.luaError;
}

pub fn callLuaFunction(self: *Self, fn_name: []const u8) !void {
    try self.callLuaFunctionEx(fn_name, 0, 0);
}

pub fn reg(self: *Self, name: [*c]const u8, fn_: ?*const fn (Ls) callconv(.c) c_int) void {
    lua.lua_register(self.state, name, fn_);
}

pub fn regN(self: *Self, fns: []const struct { [*c]const u8, ?*const fn (Ls) callconv(.c) c_int }) void {
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

pub fn putError(self: *Self, msg: []const u8) noreturn {
    _ = lua.luaL_error(self.state, zstring(msg)); //Longjmp
    unreachable;
}

pub fn putErrorFmt(self: *Self, comptime fmt: []const u8, args: anytype) noreturn {
    var buff: [256]u8 = undefined;
    var fbs = std.io.FixedBufferStream([]u8){ .buffer = &buff, .pos = 0 };
    fbs.writer().print(fmt, args) catch unreachable;
    self.putError(fbs.getWritten());
    unreachable;
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
    @memcpy(zstring_buffer[0..str.len], str);
    zstring_buffer[str.len] = 0;
    return &zstring_buffer[0];
}

//TODO are we allowed to return these strings without duping them?
//don't think so because we pop
pub fn getArg(self: *Self, L: Ls, comptime s: type, idx: c_int) s {
    const in = @typeInfo(s);
    return switch (in) {
        .float => @floatCast(lua.luaL_checknumber(L, idx)),
        .int => std.math.lossyCast(s, lua.luaL_checkinteger(L, idx)),
        .@"enum" => blk: {
            var len: usize = 0;
            const str = lua.luaL_checklstring(L, idx, &len);
            const enum_ = std.meta.stringToEnum(s, str[0..len]);
            if (enum_) |e|
                break :blk e;
            self.putErrorFmt("Invalid enum value: {s}", .{str});
            return undefined;
        },
        .bool => lua.lua_toboolean(L, idx) == 1,
        .@"union" => |u| {
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
        .pointer => |p| {
            if (p.size == .slice) {
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
        .@"struct" => {
            var ret: s = undefined;
            inline for (in.@"struct".fields) |f| {
                const lt = lua.lua_getfield(L, idx, zstring(f.name));
                @field(ret, f.name) = switch (lt) {
                    lua.LUA_TNIL => if (f.default_value_ptr) |d| @as(*const f.type, @ptrCast(@alignCast(d))).* else blk: {
                        std.debug.print("THIS IS BROKEN\n", .{});
                        break :blk undefined;
                    },
                    else => self.getArg(L, f.type, -1),
                };
                lua.lua_pop(L, 1);
            }
            return ret;
        },
        .optional => |o| {
            const t = lua.lua_type(L, idx);
            if (t == lua.LUA_TNIL) {
                return null;
            }
            return self.getArg(L, o.child, idx);
        },
        else => @compileError("getV type not supported " ++ @typeName(s)),
    };
}

pub fn getGlobal(self: *Self, L: Ls, name: []const u8, comptime s: type) s {
    _ = lua.lua_getglobal(L, zstring(name));
    defer lua.lua_pop(L, 1);
    return self.getArg(self.state, s, 1);
    // switch (@typeInfo(s)) {
    //     .Struct => {
    //         return self.getArg(self.state, s, 1);
    //     },
    //     else => @compileError("not supported"),
    // }
}

pub fn setGlobal(self: *Self, name: [*c]const u8, item: anytype) void {
    pushV(self.state, item);
    lua.lua_setglobal(self.state, name);
}

pub fn pushHashMap(L: Ls, hm: anytype) void {
    lua.lua_newtable(L);
    var it = hm.iterator();
    while (it.next()) |item| {
        //std.debug.print("PUSHING {s} {s}\n", .{ item.key_ptr.*, item.value_ptr.* });
        _ = lua.lua_pushstring(L, zstring(item.key_ptr.*));
        pushV(L, @as([]const u8, item.value_ptr.*));
        lua.lua_settable(L, -3);
    }
}

pub fn pushV(L: Ls, s: anytype) void {
    const sT = @TypeOf(s);
    const info = @typeInfo(sT);
    switch (info) {
        .@"struct" => |st| {
            lua.lua_newtable(L);
            inline for (st.fields) |f| {
                _ = lua.lua_pushstring(L, zstring(f.name));
                pushV(L, @field(s, f.name));
                lua.lua_settable(L, -3);
            }
            if (comptime std.meta.hasFn(sT, "setLuaTable")) {
                @field(sT, "setLuaTable")(L);
            }
        },
        .@"enum" => {
            const str = @tagName(s);
            _ = lua.lua_pushlstring(L, zstring(str), str.len);
        },
        .optional => {
            if (s == null) {
                lua.lua_pushnil(L);
            } else {
                pushV(L, s.?);
            }
        },
        .@"union" => |u| {
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
        .float => lua.lua_pushnumber(L, s),
        .bool => lua.lua_pushboolean(L, if (s) 1 else 0),
        .int => lua.lua_pushinteger(L, std.math.lossyCast(i64, s)),
        .array => {
            lua.lua_newtable(L);
            for (s, 1..) |item, i| {
                lua.lua_pushinteger(L, @intCast(i));
                pushV(L, item);
                lua.lua_settable(L, -3);
            }
        },
        .pointer => |p| {
            if (p.size == .slice) {
                if (p.child == u8) {
                    _ = lua.lua_pushlstring(L, @ptrCast(s), s.len);
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

/// Warning, if the api_struct contains strings, they must have type specified as []const u8 otherwise lua corrupts memory for some reason
pub fn registerAllStruct(self: *Self, comptime api_struct: type) void {
    const info = @typeInfo(api_struct);
    inline for (info.@"struct".decls) |decl| {
        const tinfo = @typeInfo(@TypeOf(@field(api_struct, decl.name)));
        const lua_name = decl.name;
        switch (tinfo) {
            .Fn => self.reg(lua_name, @field(api_struct, decl.name)),
            //else => |crass| @compileError("Cannot export to lua: " ++ @tagName(crass)),
            //@typeName(@TypeOf(@field(api_struct, decl.name)))),
            else => self.setGlobal(lua_name, @field(api_struct, decl.name)),
        }
    }
}
