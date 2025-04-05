const std = @import("std");
const c = @import("graphics/c.zig");
pub const GL = @import("graphics/gl.zig");
pub const graph = @import("graphics.zig");
pub const za = @import("zalgebra");

const log = std.log.scoped(.mesh_import);

/// A mesh is a piece of geometry that can be drawn with one api call.
pub const MeshVert = packed struct {
    x: f32,
    y: f32,
    z: f32,

    u: f32,
    v: f32,

    nx: f32,
    ny: f32,
    nz: f32,

    color: u32,

    tx: f32 = 0,
    ty: f32 = 0,
    tz: f32 = 0,
};

pub const Mesh = struct {
    const Self = @This();
    vertices: std.ArrayList(MeshVert),
    indicies: std.ArrayList(u32),

    diffuse_texture: c_uint = 0,

    vao: c_uint = undefined,
    vbo: c_uint = undefined,
    ebo: c_uint = undefined,

    pub fn init(alloc: std.mem.Allocator, diff_texture_id: c_uint) @This() {
        var ret = Self{
            .vertices = std.ArrayList(MeshVert).init(alloc),
            .indicies = std.ArrayList(u32).init(alloc),
            .diffuse_texture = diff_texture_id,
        };

        c.glGenVertexArrays(1, &ret.vao);
        c.glGenBuffers(1, &ret.vbo);
        c.glGenBuffers(1, &ret.ebo);

        GL.floatVertexAttrib(ret.vao, ret.vbo, 0, 3, MeshVert, "x"); //XYZ
        GL.floatVertexAttrib(ret.vao, ret.vbo, 1, 2, MeshVert, "u"); //RGBA
        GL.floatVertexAttrib(ret.vao, ret.vbo, 2, 3, MeshVert, "nx"); //RGBA
        GL.intVertexAttrib(ret.vao, ret.vbo, 3, 1, MeshVert, "color", c.GL_UNSIGNED_INT);
        GL.floatVertexAttrib(ret.vao, ret.vbo, 4, 3, MeshVert, "tx");

        c.glBindVertexArray(ret.vao);
        GL.bufferData(c.GL_ARRAY_BUFFER, ret.vbo, MeshVert, ret.vertices.items);
        GL.bufferData(c.GL_ELEMENT_ARRAY_BUFFER, ret.ebo, u32, ret.indicies.items);
        return ret;
    }

    pub fn drawSimple(b: *Self, view: za.Mat4, model: za.Mat4, shader: c_uint) void {
        c.glUseProgram(shader);
        GL.passUniform(shader, "view", view);
        GL.passUniform(shader, "model", model);
        if (b.diffuse_texture != 0) {
            const diffuse_loc = c.glGetUniformLocation(shader, "diffuse_texture");

            c.glUniform1i(diffuse_loc, 0);
            c.glBindTextureUnit(0, b.diffuse_texture);
        }

        c.glBindVertexArray(b.vao);
        c.glDrawElements(c.GL_TRIANGLES, @as(c_int, @intCast(b.indicies.items.len)), c.GL_UNSIGNED_INT, null);
    }

    pub fn setData(self: *Self) void {
        c.glBindVertexArray(self.vao);
        GL.bufferData(c.GL_ARRAY_BUFFER, self.vbo, MeshVert, self.vertices.items);
        GL.bufferData(c.GL_ELEMENT_ARRAY_BUFFER, self.ebo, u32, self.indicies.items);
    }

    pub fn deinit(self: *Self) void {
        self.vertices.deinit();
        self.indicies.deinit();
    }
};

/// A model is made up of multiple meshes
pub const Model = struct {
    const Self = @This();
    textures: std.ArrayList(graph.Texture),
    meshes: std.ArrayList(Mesh),

    min: za.Vec3 = za.Vec3.zero(),
    max: za.Vec3 = za.Vec3.zero(),

    pub fn init(alloc: std.mem.Allocator) Model {
        return .{
            .textures = std.ArrayList(graph.Texture).init(alloc),
            .meshes = std.ArrayList(Mesh).init(alloc),
        };
    }

    pub fn deinit(self: *Self) void {
        self.textures.deinit();
        for (self.meshes.items) |*mesh| {
            mesh.deinit();
        }
        self.meshes.deinit();
    }
};

// Loading objs looks like this.
// an obj is a list of meshes
// load the obj as normal into one big arraylist of verticies and indicies.
// whenever encountering usemtl,
pub fn loadObj(alloc: std.mem.Allocator, dir: std.fs.Dir, filename: []const u8, scale: f32) !Model {
    var uvs = std.ArrayList(graph.Vec2f).init(alloc);
    defer uvs.deinit();
    var verts = std.ArrayList(graph.Vec3f).init(alloc);
    defer verts.deinit();
    var norms = std.ArrayList(graph.Vec3f).init(alloc);
    defer norms.deinit();
    var model = Model.init(alloc);

    var minx: f32 = std.math.floatMax(f32);
    var miny: f32 = std.math.floatMax(f32);
    var minz: f32 = std.math.floatMax(f32);

    var maxx: f32 = std.math.floatMin(f32);
    var maxy: f32 = std.math.floatMin(f32);
    var maxz: f32 = std.math.floatMin(f32);

    var mtls = std.ArrayList(Mtl).init(alloc);
    defer {
        for (mtls.items) |m| {
            alloc.free(m.name);
            if (m.diffuse_path) |d|
                alloc.free(d);
        }
        mtls.deinit();
    }
    var mesh_map = std.StringHashMap(Mesh).init(alloc);
    defer mesh_map.deinit();
    var current_mesh: ?*Mesh = null;

    const obj = try dir.openFile(filename, .{});
    const sl = try obj.reader().readAllAlloc(alloc, std.math.maxInt(usize));
    defer alloc.free(sl);
    var line_it = std.mem.splitAny(u8, sl, "\n\r");
    while (line_it.next()) |line| {
        var tok = std.mem.tokenizeAny(u8, line, " \t");
        const com = tok.next() orelse continue;
        const eql = std.mem.eql;
        if (eql(u8, com, "v")) { //Vertex
            errdefer std.debug.print("{s}\n", .{line});
            const x = try std.fmt.parseFloat(f32, tok.next().?);
            const y = try std.fmt.parseFloat(f32, tok.next().?);
            const z = try std.fmt.parseFloat(f32, tok.next().?);
            minx = @min(minx, x);
            miny = @min(miny, y);
            minz = @min(minz, z);
            maxx = @max(maxx, x);
            maxy = @max(maxy, y);
            maxz = @max(maxz, z);
            try verts.append(.{ .x = x, .y = y, .z = z });
        } else if (eql(u8, com, "vt")) { //vertex uv
            const u = try std.fmt.parseFloat(f32, tok.next().?);
            const v = try std.fmt.parseFloat(f32, tok.next().?);
            try uvs.append(.{ .x = u, .y = v });
        } else if (eql(u8, com, "vn")) { //Vertex normal
            const x = try std.fmt.parseFloat(f32, tok.next().?);
            const y = try std.fmt.parseFloat(f32, tok.next().?);
            const z = try std.fmt.parseFloat(f32, tok.next().?);
            try norms.append(.{ .x = x, .y = y, .z = z });
        } else if (eql(u8, com, "f")) { //Face
            //Mesh
            if (current_mesh) |m| {
                var count: usize = 0;
                const vi: u32 = @intCast(m.vertices.items.len);
                while (tok.next()) |v| {
                    count += 1;
                    var sp = std.mem.splitScalar(u8, v, '/');
                    const ind = try std.fmt.parseInt(usize, sp.next().?, 10);
                    const uv = blk: {
                        if (sp.next()) |uv| {
                            if (uv.len > 0) {
                                const uind = try std.fmt.parseInt(usize, uv, 10);
                                break :blk uvs.items[uind - 1];
                            }
                        }
                        break :blk graph.Vec2f.new(0, 0);
                    };
                    const ver = verts.items[@intCast(ind - 1)];
                    const norm = blk: {
                        if (sp.next()) |n| {
                            if (n.len > 0) {
                                const nind = try std.fmt.parseInt(usize, n, 10);
                                break :blk norms.items[nind - 1];
                            }
                        }
                        break :blk graph.Vec3f{ .x = 0, .y = 1, .z = 0 };
                    };
                    try m.vertices.append(.{
                        .x = scale * ver.x,
                        .y = scale * ver.y,
                        .z = scale * ver.z,
                        .u = uv.x,
                        .v = 1 - uv.y,
                        .nx = norm.x,
                        .ny = norm.y,
                        .nz = norm.z,
                        .color = 0xffffffff,
                    });
                    //try cubes.indicies.append(@intCast(cubes.vertices.items.len - 1));
                }
                switch (count) {
                    0...2 => unreachable,
                    3 => {
                        try m.indicies.appendSlice(&.{
                            vi, vi + 1, vi + 2,
                        });
                        const v1 = &m.vertices.items[vi];
                        const v2 = &m.vertices.items[vi + 1];
                        const v3 = &m.vertices.items[vi + 2];
                        const e1 = za.Vec3.new(v2.x, v2.y, v2.z).sub(za.Vec3.new(v1.x, v1.y, v1.z));
                        const e2 = za.Vec3.new(v3.x, v3.y, v3.z).sub(za.Vec3.new(v1.x, v1.y, v1.z));
                        const du1 = v2.u - v1.u;
                        const dv1 = v2.v - v1.v;
                        const du2 = v3.u - v1.u;
                        const dv2 = v3.v - v1.v;
                        const f = 1.0 / (du1 * dv2 - du2 * dv1);
                        const tangent = za.Vec3.new(
                            (dv2 * e1.x()) - (dv1 * e2.x()),
                            (dv2 * e1.y()) - (dv1 * e2.y()),
                            (dv2 * e1.z()) - (dv1 * e2.z()),
                        ).scale(f);

                        //const bitangent = V3f.new(
                        //    (-du2 * e1.x()) - (du1 * e2.x()),
                        //    (-du2 * e1.y()) - (du1 * e2.y()),
                        //    (-du2 * e1.z()) - (du1 * e2.z()),
                        //    ).scale(f);
                        v1.tx += tangent.x();
                        v2.tx += tangent.x();
                        v3.tx += tangent.x();
                        v1.ty += tangent.y();
                        v2.ty += tangent.y();
                        v3.ty += tangent.y();
                        v1.tz += tangent.z();
                        v2.tz += tangent.z();
                        v3.tz += tangent.z();
                    },
                    4 => {
                        try m.indicies.appendSlice(&.{
                            vi,
                            vi + 1,
                            vi + 2,
                            vi + 3,
                            vi,
                            vi + 2,
                        });
                    },
                    else => {
                        std.debug.print("weird {d}\n", .{count});
                    },
                }
            }
        } else if (eql(u8, com, "usemtl")) {
            const mtl = tok.next().?;
            if (mesh_map.getPtr(mtl)) |meshptr| {
                current_mesh = meshptr;
            }
        } else if (eql(u8, com, "s")) { //smooth shading

        } else if (eql(u8, com, "mtllib")) {
            const mtl_filename = tok.next().?;

            var file_prefix = std.ArrayList(u8).init(alloc);
            var mtl_filename_full = std.ArrayList(u8).init(alloc);
            defer mtl_filename_full.deinit();
            defer file_prefix.deinit();
            if (std.mem.lastIndexOfScalar(u8, filename, '/')) |ind| {
                try file_prefix.appendSlice(filename[0..ind]);
                try file_prefix.append('/');
            }
            try mtl_filename_full.appendSlice(file_prefix.items);
            try mtl_filename_full.appendSlice(mtl_filename);

            const old_mtl_len = mtls.items.len;
            loadMtl(alloc, dir, mtl_filename_full.items, &mtls) catch |err| switch (err) {
                error.FileNotFound => {
                    log.warn("obj mtl file not found: {s} {s}", .{ filename, mtl_filename });
                    continue;
                },
                else => return err,
            };
            const file_prefix_len = file_prefix.items.len;
            for (mtls.items[old_mtl_len..]) |mt| {
                const dpath = mt.diffuse_path orelse {
                    try mesh_map.put(mt.name, Mesh.init(alloc, 0));
                    continue;
                };

                try file_prefix.appendSlice(dpath);
                //try file_prefix.appendSlice(".png");
                defer file_prefix.shrinkRetainingCapacity(file_prefix_len);
                const tex = graph.Texture.initFromImgFile(alloc, dir, file_prefix.items, .{}) catch |err| switch (err) {
                    error.FileNotFound => {
                        log.warn("png file not found: {s} {s}", .{ filename, file_prefix.items });
                        continue;
                    },
                    else => return err,
                };
                try model.textures.append(tex);
                try mesh_map.put(mt.name, Mesh.init(alloc, tex.id));
            }
        } else {}
    }
    var vit = mesh_map.iterator();
    while (vit.next()) |mesh| {
        for (mesh.value_ptr.vertices.items) |*vert| {
            const norm = za.Vec3.new(vert.tx, vert.ty, vert.tz).norm();
            vert.tx = norm.x();
            vert.ty = norm.y();
            vert.tz = norm.z();
        }
        mesh.value_ptr.setData();
        try model.meshes.append(mesh.value_ptr.*);
    }
    model.min = za.Vec3.new(minx, miny, minz).scale(scale);
    model.max = za.Vec3.new(maxx, maxy, maxz).scale(scale);

    std.debug.print("Loaded obj {s}, with {d} verticies\n", .{ filename, verts.items.len });

    return model;
}

pub const Mtl = struct {
    name: []const u8,
    diffuse_path: ?[]const u8 = null,
};

pub fn loadMtl(alloc: std.mem.Allocator, dir: std.fs.Dir, filename: []const u8, mtl_list: *std.ArrayList(Mtl)) !void {
    const h = std.hash.Wyhash.hash;
    const mtl_file = try dir.openFile(filename, .{});
    const slmtl = try mtl_file.reader().readAllAlloc(alloc, std.math.maxInt(usize));
    defer alloc.free(slmtl);
    var mtl_it = std.mem.splitAny(u8, slmtl, "\n\r");
    var mtl: ?Mtl = null;
    while (mtl_it.next()) |mtlline| {
        var tok = std.mem.tokenizeAny(u8, mtlline, " \t");
        const com = tok.next() orelse continue;
        switch (h(0, com)) {
            h(0, "newmtl") => {
                if (mtl) |m|
                    try mtl_list.append(m);

                const name = tok.next().?;
                mtl = .{ .name = try alloc.dupe(u8, name) };
            },
            h(0, "map_Ka") => {},
            h(0, "map_Kd") => {
                const tex_path = tok.next().?;
                mtl.?.diffuse_path = try alloc.dupe(u8, tex_path);
            },
            h(0, "map_Ks") => {},
            h(0, "map_Ns") => {},
            h(0, "map_d") => {},
            h(0, "map_bump"), h(0, "bump") => {},
            h(0, "Ka") => { //ambient
            },
            h(0, "Ks") => { //Specular
            },
            h(0, "Kd") => { //Diffuse
            },
            h(0, "Ns") => { //specular exponent
            },
            else => {},
        }
    }
    if (mtl) |m|
        try mtl_list.append(m);
}
