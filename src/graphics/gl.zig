const c = @import("c.zig").c;
pub const za = @import("zalgebra");
const std = @import("std");
const gl = @import("gl");
pub const glID = gl.uint;
const ptypes = @import("types.zig");
const Vec2f = ptypes.Vec2f;
const Vec2i = ptypes.Vec2i;
const Vec3f = ptypes.Vec3f;
const Color = ptypes.Color;
const CharColor = ptypes.CharColor;
const Rect = ptypes.Rect;
const V3 = za.Vec3;
const itc = ptypes.itc;

pub const Vertex = packed struct { x: f32, y: f32, z: f32, r: f32, g: f32, b: f32, a: f32 };

const log = std.log.scoped(.GL);
pub const PrimitiveMode = enum(u32) {
    points = gl.POINTS,
    line_strip = gl.LINE_STRIP,
    line_loop = gl.LINE_LOOP,
    lines = gl.LINES,
    line_strip_adjacency = gl.LINE_STRIP_ADJACENCY,
    lines_adjacency = gl.LINES_ADJACENCY,
    triangle_strip = gl.TRIANGLE_STRIP,
    triangle_fan = gl.TRIANGLE_FAN,
    triangles = gl.TRIANGLES,
    triangle_strip_adjacency = gl.TRIANGLE_STRIP_ADJACENCY,
    triangles_adjacency = gl.TRIANGLES_ADJACENCY,
    patches = gl.PATCHES,
};

pub fn checkError() void {
    var err = gl.GetError();
    while (err != gl.NO_ERROR) : (err = gl.GetError()) {
        const str = switch (err) {
            gl.INVALID_ENUM => "An unacceptable value is specified for an enumerated argument. The offending command is ignored and has no other side effect than to set the error flag.",
            gl.INVALID_VALUE => "A numeric argument is out of range. The offending command is ignored and has no other side effect than to set the error flag.",
            gl.INVALID_OPERATION => "The specified operation is not allowed in the current state. The offending command is ignored and has no other side effect than to set the error flag.",
            gl.INVALID_FRAMEBUFFER_OPERATION => "The framebuffer object is not complete. The offending command is ignored and has no other side effect than to set the error flag.",
            gl.OUT_OF_MEMORY => "There is not enough memory left to execute the command. The state of the GL is undefined, except for the state of the error flags, after this error is recorded.",
            gl.STACK_UNDERFLOW => "An attempt has been made to perform an operation that would cause an internal stack to underflow.",
            gl.STACK_OVERFLOW => "An attempt has been made to perform an operation that would cause an internal stack to overflow.",
            else => "Unknown gl error, Something is corrupt",
        };
        log.warn("glGetError: {s}", .{str});
    }
}

pub const DebugSource = enum(u32) {
    api = gl.DEBUG_SOURCE_API,
    window_system = gl.DEBUG_SOURCE_WINDOW_SYSTEM,
    shader_compiler = gl.DEBUG_SOURCE_SHADER_COMPILER,
    third_party = gl.DEBUG_SOURCE_THIRD_PARTY,
    application = gl.DEBUG_SOURCE_APPLICATION,
    other = gl.DEBUG_SOURCE_OTHER,
    dont_care = gl.DONT_CARE,
};

pub const DebugType = enum(u32) {
    Error = gl.DEBUG_TYPE_ERROR,
    deprecated_behavior = gl.DEBUG_TYPE_DEPRECATED_BEHAVIOR,
    undefined_behavior = gl.DEBUG_TYPE_UNDEFINED_BEHAVIOR,
    portablity = gl.DEBUG_TYPE_PORTABILITY,
    performance = gl.DEBUG_TYPE_PERFORMANCE,
    marker = gl.DEBUG_TYPE_MARKER,
    push_group = gl.DEBUG_TYPE_PUSH_GROUP,
    pop_group = gl.DEBUG_TYPE_POP_GROUP,
    other = gl.DEBUG_TYPE_OTHER,
    dont_care = gl.DONT_CARE,
};

pub const DebugSeverity = enum(u32) {
    low = gl.DEBUG_SEVERITY_LOW,
    medium = gl.DEBUG_SEVERITY_MEDIUM,
    high = gl.DEBUG_SEVERITY_HIGH,
    notification = gl.DEBUG_SEVERITY_NOTIFICATION,
    dont_care = gl.DONT_CARE,
};

pub export fn messageCallback(
    src: gl.@"enum",
    Type: gl.@"enum",
    id: gl.uint,
    severity: gl.@"enum",
    length: gl.sizei,
    msg: [*c]const u8,
    user_params: ?*const anyopaque,
) callconv(.c) void {
    _ = user_params;
    const fmt = "{s}, {s}, {s}, {d}: {s}";
    const args = .{
        @tagName(@as(DebugSource, @enumFromInt(src))),
        @tagName(@as(DebugSeverity, @enumFromInt(severity))),
        @tagName(@as(DebugType, @enumFromInt(Type))),
        id,
        msg[0..@intCast(length)],
    };
    switch (@as(DebugSeverity, @enumFromInt(severity))) {
        .low => log.info(fmt, args),
        .medium => log.warn(fmt, args),
        .high => log.warn(fmt, args),
        .notification => log.debug(fmt, args),
        .dont_care => log.debug(fmt, args),
    }
}

pub fn passUniform(shader: c_uint, uniform_name: [*c]const u8, data: anytype) void {
    const uniform_location = gl.GetUniformLocation(shader, uniform_name);
    switch (@TypeOf(data)) {
        za.Mat4 => gl.UniformMatrix4fv(uniform_location, 1, gl.FALSE, @ptrCast(&data.data[0][0])),
        za.Vec3 => gl.Uniform3f(uniform_location, data.data[0], data.data[1], data.data[2]),
        f32 => gl.Uniform1f(uniform_location, data),
        bool => gl.Uniform1i(uniform_location, if (data) 1 else 0),
        Color => gl.Uniform4f(uniform_location, data[0], data[1], data[2], data[3]),
        ptypes.Vec2i => gl.Uniform2f(uniform_location, @floatFromInt(data.x), @floatFromInt(data.y)),
        else => @compileError("GL.passUniform type not implemented: " ++ @typeName(@TypeOf(data))),
    }
}

pub fn bufferData(buffer_type: glID, handle: glID, comptime item: type, slice: []item) void {
    gl.BindBuffer(buffer_type, handle);
    gl.BufferData(
        buffer_type,
        @as(c_long, @intCast(slice.len)) * @sizeOf(item),
        slice.ptr,
        gl.STATIC_DRAW,
    );
    gl.BindBuffer(gl.ARRAY_BUFFER, 0);
}

pub fn generateVertexAttributes(vao: c_uint, vbo: c_uint, comptime T: anytype) void {
    generateVertexAttributesEx(vao, vbo, T, 0);
}

pub fn generateVertexAttributesEx(vao: c_uint, vbo: c_uint, comptime T: anytype, field_offset: u32) void {
    const info = @typeInfo(T);
    switch (info) {
        .@"struct" => {
            const st = info.@"struct";
            if (st.layout != .@"packed") @compileError("generateVertexAttributes only supports packed structs");
            inline for (st.fields, 0..) |field, f_ii| {
                const f_i = @as(u32, @intCast(f_ii)) + field_offset;
                switch (field.type) {
                    f32 => floatVertexAttrib(vao, vbo, f_i, 1, T, field.name),
                    Vec2f => floatVertexAttrib(vao, vbo, f_i, 2, T, field.name),
                    Vec3f => floatVertexAttrib(vao, vbo, f_i, 3, T, field.name),
                    u16 => intVertexAttrib(vao, vbo, f_i, 1, T, field.name, gl.UNSIGNED_SHORT),
                    u32 => intVertexAttrib(vao, vbo, f_i, 1, T, field.name, gl.UNSIGNED_INT),
                    else => @compileError("generateVertexAttributes struct field type not supported: " ++ @typeName(field.field_type) ++ " " ++ field.name),
                }
            }
        },
        else => @compileError("generateVertexAttributes expects a struct"),
    }
}

pub fn bufferSubData(buffer_type: glID, handle: glID, offset: usize, len: usize, comptime item: type, slice: []item) void {
    gl.BindBuffer(buffer_type, handle);
    gl.BufferSubData(
        buffer_type,
        @as(c_long, @intCast(offset)) * @sizeOf(item),
        @as(c_long, @intCast(len)) * @sizeOf(item),
        &slice[offset],
    );

    gl.BindBuffer(gl.ARRAY_BUFFER, 0);
}

pub fn intVertexAttrib(vao: glID, vbo: glID, index: u32, num_elem: u32, comptime item: type, comptime starting_field: []const u8, int_type: gl.@"enum") void {
    gl.BindVertexArray(vao);
    gl.BindBuffer(gl.ARRAY_BUFFER, vbo);
    defer gl.BindVertexArray(0);
    defer gl.BindBuffer(gl.ARRAY_BUFFER, 0);

    gl.VertexAttribIPointer(
        index,
        @as(c_int, @intCast(num_elem)),
        int_type,
        @sizeOf(item),
        @offsetOf(item, starting_field),
    );
    gl.EnableVertexAttribArray(index);
}

pub fn floatVertexAttrib(vao: glID, vbo: glID, index: u32, size: u32, comptime item: type, comptime starting_field: []const u8) void {
    gl.BindVertexArray(vao);
    gl.BindBuffer(gl.ARRAY_BUFFER, vbo);
    defer gl.BindVertexArray(0);
    defer gl.BindBuffer(gl.ARRAY_BUFFER, 0);

    gl.VertexAttribPointer(
        index,
        @as(c_int, @intCast(size)),
        gl.FLOAT,
        gl.FALSE,
        @sizeOf(item),
        @offsetOf(item, starting_field),
    );
    gl.EnableVertexAttribArray(index);
}

pub fn simpleDrawBatch(view: za.Mat4, model: za.Mat4, batch: anytype, has_ebo: bool) void {
    gl.UseProgram(batch.shader);
    gl.BindVertexArray(batch.vao);

    bufferData(gl.ARRAY_BUFFER, batch.vbo, Vertex, batch.vertices.items);
    if (has_ebo)
        bufferData(gl.ELEMENT_ARRAY_BUFFER, batch.ebo, u32, batch.indicies.items);

    gl.BindTexture(gl.TEXTURE_2D, 0);

    passUniform(batch.shader, "view", view);
    passUniform(batch.shader, "model", model);

    gl.DrawElements(gl.TRIANGLES, @as(c_int, @intCast(batch.indicies.items.len)), gl._UNSIGNED_INT, 0);
    //gl.BindVertexArray(0);

}

pub const Plane = enum { xy, yz, xz };
pub fn vertexTexturedDir(plane: Plane, x: f32, y: f32, z: f32, u: f32, v: f32, col: Color) VertexTextured {
    const p: struct { x: f32, y: f32, z: f32, u: f32, v: f32 } = switch (plane) {
        .xy => .{ .x = x, .y = y, .z = z, .u = u, .v = v },
        .yz => .{ .x = y, .y = z, .z = x, .u = u, .v = v },
        .xz => .{ .x = x, .y = z, .z = y, .u = u, .v = v },
    };
    return .{ .x = p.x, .y = p.y, .z = p.z, .u = p.u, .v = p.v, .r = col[0], .g = col[1], .b = col[2], .a = col[3] };
}

pub fn quadTex(pos: V3, w: f32, h: f32, plane: Plane, neg: bool, tr: Rect, tx_w: u32, tx_h: u32, color: CharColor) [4]VertexTextured {
    const un = normalizeTexRect(tr, tx_w, tx_h);
    const col = color.toFloat();
    const p: struct { x: f32, y: f32, z: f32 } = .{ .x = pos.data[0], .y = pos.data[1], .z = pos.data[2] };
    // zig fmt: off
    if (neg) {
        return .{
            vertexTexturedDir(plane, p.x,     p.y + h, p.z, un.x       , un.y + un.h, col),
            vertexTexturedDir(plane, p.x + w, p.y + h, p.z, un.x       , un.y       , col),
            vertexTexturedDir(plane, p.x + w, p.y,     p.z, un.x + un.w, un.y       , col),
            vertexTexturedDir(plane, p.x,     p.y,     p.z, un.x + un.w, un.y + un.h, col),
        };
    } else {
        return .{
            vertexTexturedDir(plane, p.x,     p.y,     p.z, un.x + un.w, un.y + un.h, col),
            vertexTexturedDir(plane, p.x + w, p.y,     p.z, un.x + un.w, un.y       , col),
            vertexTexturedDir(plane, p.x + w, p.y + h, p.z, un.x       , un.y       , col),
            vertexTexturedDir(plane, p.x,     p.y + h, p.z, un.x       , un.y + un.h, col),
        };
    }
    // zig fmt: on
}

pub fn cube(px: f32, py: f32, pz: f32, sx: f32, sy: f32, sz: f32, tr: Rect, tx_w: u32, tx_h: u32, colorsopt: ?[]const CharColor) [24]VertexTextured {
    const colors = if (colorsopt) |cc| cc else &[6]CharColor{
        itc(0x888888ff), //Front
        itc(0x888888ff), //Back
        itc(0x666666ff), //Bottom
        itc(0xffffffff), //Top
        itc(0xaaaaaaff),
        itc(0xaaaaaaff),
    };
    const un = normalizeTexRect(tr, @as(i32, @intCast(tx_w)), @as(i32, @intCast(tx_h)));
    // zig fmt: off
    return [_]VertexTextured{
        // front
        vertexTextured(px + sx, py + sy, pz, un.x + un.w, un.y + un.h, colors[0].toFloat()), //0
        vertexTextured(px + sx, py     , pz, un.x + un.w, un.y       , colors[0].toFloat()), //1
        vertexTextured(px     , py     , pz, un.x       , un.y       , colors[0].toFloat()), //2
        vertexTextured(px     , py + sy, pz, un.x       , un.y + un.h, colors[0].toFloat()), //3

        // back
        vertexTextured(px     , py + sy, pz + sz, un.x       , un.y + un.h, colors[1].toFloat()), //3
        vertexTextured(px     , py     , pz + sz, un.x       , un.y       , colors[1].toFloat()), //2
        vertexTextured(px + sx, py     , pz + sz, un.x + un.w, un.y       , colors[1].toFloat()), //1
        vertexTextured(px + sx, py + sy, pz + sz, un.x + un.w, un.y + un.h, colors[1].toFloat()), //0


        vertexTextured(px + sx, py, pz,      un.x+un.w,un.y + un.h, colors[2].toFloat()),
        vertexTextured(px + sx, py, pz + sz, un.x+un.w,un.y, colors[2].toFloat()),
        vertexTextured(px     , py, pz + sz, un.x,un.y, colors[2].toFloat()),
        vertexTextured(px     , py, pz     , un.x,un.y + un.h, colors[2].toFloat()),

        vertexTextured(px     , py + sy, pz     , un.x,un.y + un.h, colors[3].toFloat()),
        vertexTextured(px     , py + sy, pz + sz, un.x,un.y, colors[3].toFloat()),
        vertexTextured(px + sx, py + sy, pz + sz, un.x + un.w,un.y, colors[3].toFloat()),
        vertexTextured(px + sx, py + sy, pz, un.x + un.w,   un.y + un.h , colors[3].toFloat()),

        vertexTextured(px, py + sy, pz, un.x + un.w,un.y + un.h,colors[4].toFloat()),
        vertexTextured(px, py , pz, un.x + un.w,un.y,colors[4].toFloat()),
        vertexTextured(px, py , pz + sz, un.x,un.y,colors[4].toFloat()),
        vertexTextured(px, py + sy , pz + sz, un.x,un.y + un.h,colors[4].toFloat()),

        vertexTextured(px + sx, py + sy , pz + sz, un.x,un.y + un.h,colors[5].toFloat()),
        vertexTextured(px + sx, py , pz + sz, un.x,un.y,colors[5].toFloat()),
        vertexTextured(px + sx, py , pz, un.x + un.w,un.y,colors[5].toFloat()),
        vertexTextured(px + sx, py + sy, pz, un.x + un.w,un.y + un.h,colors[5].toFloat()),


    };
    // zig fmt: on

}

pub fn genCubeIndicies(index: u32) [36]u32 {
    return [_]u32{
        index + 0,
        index + 1,
        index + 3,
        index + 1,
        index + 2,
        index + 3,

        index + 4,
        index + 5,
        index + 7,
        index + 5,
        index + 6,
        index + 7,

        index + 8,
        index + 9,
        index + 11,
        index + 9,
        index + 10,
        index + 11,

        index + 12,
        index + 13,
        index + 15,
        index + 13,
        index + 14,
        index + 15,

        index + 16,
        index + 17,
        index + 19,
        index + 17,
        index + 18,
        index + 19,

        index + 20,
        index + 21,
        index + 23,
        index + 21,
        index + 22,
        index + 23,
    };
}
pub fn createQuadTextured(r: Rect, z: f32, tr: Rect, tx_w: i32, tx_h: i32, color: Color) [4]VertexTextured {
    const un = normalizeTexRect(tr, tx_w, tx_h);
    // zig fmt: off
    return [_]VertexTextured {
        vertexTextured(r.x + r.w, r.y + r.h, z, un.x + un.w, un.y + un.h, color), //0
        vertexTextured(r.x + r.w, r.y      , z, un.x + un.w, un.y       , color), //1
        vertexTextured(r.x      , r.y      , z, un.x       , un.y       , color), //2
        vertexTextured(r.x      , r.y + r.h, z, un.x       , un.y + un.h, color), //3
    };
    // zig fmt: on
}
pub fn createQuadColor(r: Rect, z: f32, color: [4]CharColor) [4]Vertex {
    return [_]Vertex{
        vertex(r.x + r.w, r.y + r.h, z, color[2].toFloat()), //low right
        vertex(r.x + r.w, r.y, z, color[3].toFloat()), //up right
        vertex(r.x, r.y, z, color[0].toFloat()), //up left
        vertex(r.x, r.y + r.h, z, color[1].toFloat()), //low left
    };
}

pub fn createQuad(r: Rect, z: f32, color: Color) [4]Vertex {
    return [_]Vertex{
        vertex(r.x + r.w, r.y + r.h, z, color),
        vertex(r.x + r.w, r.y, z, color),
        vertex(r.x, r.y, z, color),
        vertex(r.x, r.y + r.h, z, color),
    };
}

pub fn normalizeTexRect(tr: Rect, tx_w: i32, tx_h: i32) Rect {
    const tw = @as(f32, @floatFromInt(tx_w));
    const th = @as(f32, @floatFromInt(tx_h));
    return .{
        .x = tr.x / tw,
        .y = tr.y / th,
        .w = tr.w / tw,
        .h = tr.h / th,
    };
}
pub const VertexTextured = packed struct { x: f32, y: f32, z: f32, u: f32, v: f32, r: f32, g: f32, b: f32, a: f32 };

pub fn vertex(x: f32, y: f32, z: f32, col: Color) Vertex {
    return .{ .x = x, .y = y, .z = z, .r = col[0], .g = col[1], .b = col[2], .a = col[3] };
}

pub fn vertexTextured(x: f32, y: f32, z: f32, u: f32, v: f32, col: Color) VertexTextured {
    return .{ .x = x, .y = y, .z = z, .u = u, .v = v, .r = col[0], .g = col[1], .b = col[2], .a = col[3] };
}

pub const Shader = struct {
    pub const Type = enum(gl.@"enum") {
        comp = gl.COMPUTE_SHADER,
        vert = gl.VERTEX_SHADER,
        tesc = gl.TESS_CONTROL_SHADER,
        tese = gl.TESS_EVALUATION_SHADER,
        geom = gl.GEOMETRY_SHADER,
        frag = gl.FRAGMENT_SHADER,
    };

    pub const Stage = struct {
        src: [*]const u8,
        t: Type,
    };

    fn checkShaderErr(shader: glID, comporlink: c_uint) void {
        var success: c_int = undefined;
        var infoLog: [512]u8 = undefined;
        gl.GetShaderiv(shader, comporlink, @ptrCast(&success));
        if (success == 0) {
            var len: c_int = 0;
            gl.GetShaderInfoLog(shader, 512, &len, &infoLog);
            std.debug.panic("ERROR::SHADER::\n{s}\n", .{infoLog[0..@as(usize, @intCast(len))]});
        }
    }

    fn checkLinkErr(shader: glID) void {
        var params: c_int = undefined;
        var infoLog: [512]u8 = undefined;
        gl.GetProgramiv(shader, gl.LINK_STATUS, @ptrCast(&params));
        if (params == gl.FALSE) {
            var len: c_int = 0;
            gl.GetProgramInfoLog(shader, 512, &len, &infoLog);
            std.debug.panic("ERROR::SHADER_PROGRAM::\n{s}\n", .{infoLog[0..@as(usize, @intCast(len))]});
        }
    }

    fn compShader(src: [*]const [*]const u8, s_type: c_uint) glID {
        const vert = gl.CreateShader(s_type);
        gl.ShaderSource(vert, 1, src, null);
        gl.CompileShader(vert);
        checkShaderErr(vert, gl.COMPILE_STATUS);
        return vert;
    }

    pub fn loadFromFilesystem(alloc: std.mem.Allocator, dir: std.fs.Dir, stages: []const struct { path: []const u8, t: Type }) !glID {
        var array_lists = try alloc.alloc([]const u8, stages.len);
        var sources = try alloc.alloc(Stage, stages.len);
        defer alloc.free(sources);
        defer {
            for (array_lists) |ar| {
                alloc.free(ar);
            }
            alloc.free(array_lists);
        }
        var buf: [1024]u8 = undefined;
        for (stages, 0..) |stage, i| {
            var file = try dir.openFile(stage.path, .{});
            defer file.close();

            var aw = std.Io.Writer.Allocating.init(alloc);
            defer aw.deinit();

            const wr = &aw.writer;

            var rea = file.reader(&buf);
            _ = try rea.interface.streamRemaining(wr);
            _ = try wr.splatByteAll(0, 1);

            array_lists[i] = try aw.toOwnedSlice();
            sources[i] = .{ .src = @ptrCast(array_lists[i]), .t = stage.t };
        }

        return advancedShader(sources);
    }

    pub fn simpleShader(vert_src: [*]const u8, frag_src: [*]const u8) glID {
        const vert = compShader(@ptrCast(&vert_src), gl.VERTEX_SHADER);
        defer gl.DeleteShader(vert);

        const frag = compShader(@ptrCast(&frag_src), gl.FRAGMENT_SHADER);
        defer gl.DeleteShader(frag);

        const shader = gl.CreateProgram();
        gl.AttachShader(shader, vert);
        gl.AttachShader(shader, frag);
        gl.LinkProgram(shader);
        checkLinkErr(shader);

        return shader;
    }

    pub fn advancedShader(stages: []const Stage) glID {
        const shader = gl.CreateProgram();
        var stage_del: [@typeInfo(Type).@"enum".fields.len]c_uint = undefined;
        var i: usize = 0;
        for (stages) |stage| {
            const st = compShader(@ptrCast(&stage.src), @as(c_uint, @intCast(@intFromEnum(stage.t))));
            stage_del[i] = st;
            i += 1;
            gl.AttachShader(shader, st);
        }

        gl.LinkProgram(shader);
        checkLinkErr(shader);
        for (0..i) |ii| {
            gl.DeleteShader(stage_del[ii]);
        }
        return shader;
    }

    fn defaultQuadShader() glID {
        return simpleShader(@embedFile("shader/colorquad.vert"), @embedFile("shader/colorquad.frag"));
    }

    fn defaultQuadTexShader() glID {
        return simpleShader(@embedFile("shader/alpha_texturequad.vert"), @embedFile("shader/texturequad.frag"));
    }

    fn defaultFontShader() glID {
        return simpleShader(@embedFile("shader/alpha_texturequad.vert"), @embedFile("shader/alpha_texturequad.frag"));
    }
};

pub const Capability = enum(gl.@"enum") {
    blend = gl.BLEND,
    depth_test = gl.DEPTH_TEST,
    scissor_test = gl.SCISSOR_TEST,
    stencil_test = gl.STENCIL_TEST,
    debug_output = gl.DEBUG_OUTPUT,
    debug_output_synchronous = gl.DEBUG_OUTPUT_SYNCHRONOUS,
    _,
};

const state_tracking = false;

pub fn logState(comptime fmt: []const u8, args: anytype) void {
    if (comptime state_tracking) {
        log.info(fmt, args);
    }
}

pub fn enable(cap: Capability) void {
    logState("enable {s}", .{@tagName(cap)});
    gl.Enable(@intFromEnum(cap));
}

pub fn disable(cap: Capability) void {
    logState("disable {s}", .{@tagName(cap)});
    gl.Disable(@intFromEnum(cap));
}

pub fn genVertexArray() c_uint {
    var ret: c_uint = 0;
    gl.GenVertexArrays(1, @ptrCast(&ret));
    return ret;
}

pub fn genBuffer() c_uint {
    var ret: c_uint = 0;
    gl.GenBuffers(1, @ptrCast(&ret));
    return ret;
}
