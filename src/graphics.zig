const std = @import("std");
pub const c = @import("graphics/c.zig").c;
pub const za = @import("zalgebra");
pub const ArgGen = @import("arg_gen.zig");

pub const Tiled = @import("tiled.zig");

const Alloc = std.mem.Allocator;
const Dir = std.fs.Dir;

const lcast = std.math.lossyCast;
pub const Gui = @import("gui.zig");
pub const SparseSet = @import("graphics/sparse_set.zig").SparseSet;
pub const Collision = @import("col.zig");
pub const SpatialGrid = @import("spatial_grid.zig");
pub const Ecs = @import("registry.zig");
pub const Lua = @import("lua.zig");
pub const V3 = za.Vec3;
pub const AssetBake = @import("assetbake.zig");
pub const OnlineFont = @import("graphics/online_font.zig").OnlineFont;

pub const meshutil = @import("mesh.zig");
pub const ptypes = @import("graphics/types.zig");
pub const Rect = ptypes.Rect;
pub const Rec = Rect.NewAny;
pub const Vec2f = ptypes.Vec2f;
pub const Vec2i = ptypes.Vec2i;
pub const Vec3f = ptypes.Vec3f;
pub const Orientation = ptypes.Orientation;
pub const Camera2D = ptypes.Camera2D;
pub const Camera3D = ptypes.Camera3D;
pub const FontUtil = @import("graphics/font.zig");
pub const Font = FontUtil.Font;
pub const FontInterface = FontUtil.PublicFontInterface;
pub const Texture = FontUtil.Texture;
pub const Bitmap = FontUtil.Bitmap;
pub const RectPack = FontUtil.RectPack;
pub const Hsva = ptypes.Hsva;
pub const Colori = ptypes.Colori;
pub const itc = ptypes.itc;
pub const Shader = GL.Shader;
pub const gui_app = @import("gui_app.zig");
pub const Os9Gui = gui_app.Os9Gui;
pub const RGui = @import("gui/vtables.zig");

pub const GL = @import("graphics/gl.zig");
pub const glID = GL.glID;

pub const SDL = @import("graphics/SDL.zig");
pub const Bind = SDL.Bind;

test "basic graph usage" {
    const graph = @This(); // const graph = @import("graph");
    const alloc = std.testing.allocator;

    var win = try graph.SDL.Window.createWindow("My window", .{
        // Optional, see Window.createWindow definition for full list of options
        .window_size = .{ .x = 800, .y = 600 },
    });
    defer win.destroyWindow();

    var draw = graph.ImmediateDrawingContext.init(alloc);
    defer draw.deinit();

    var font = try graph.Font.init(alloc, std.fs.cwd(), "asset/fonts/roboto.ttf", 40, .{});
    defer font.deinit();
    const r = Rec(0, 0, 100, 100);
    const v1 = Vec2f.new(0, 0);
    const v2 = Vec2f.new(3, 3);
    const v3 = Vec2f.new(30, 30);

    var cam = graph.Camera3D{};

    while (!win.should_exit) {
        try draw.begin(0x2f2f2fff, win.screen_dimensions.toF());
        win.pumpEvents(.poll); //Important that this is called after draw.begin for input lag reasons

        //The following are all drawn in 2d using the default orthographic camera.
        //The bounds of the camera are the window dimensions
        draw.text(.{ .x = 50, .y = 300 }, "Hello", .{ .font = &font.font, .px_size = 20, .color = 0xffffffff });
        draw.rect(r, 0xff00ffff);
        draw.rectVertexColors(r, &.{ 0xff, 0xff, 0xff, 0xff });
        draw.nineSlice(r, r, font.font.texture, 1, Colori.White);
        draw.rectTex(r, r, font.font.texture);
        draw.line(v1, v2, 0xff);
        draw.triangle(v1, v2, v3, 0xfffffff0);

        try draw.flush(null, null); //Flush any draw commands

        draw.triangle(v1, v2, v3, 0xfffffff0);

        cam.updateDebugMove(.{
            .down = win.keyHigh(.LSHIFT),
            .up = win.keyHigh(.SPACE),
            .left = win.keyHigh(.A),
            .right = win.keyHigh(.D),
            .fwd = win.keyHigh(.W),
            .bwd = win.keyHigh(.S),
            .mouse_delta = win.mouse.delta,
            .scroll_delta = win.mouse.wheel_delta.y,
        });

        //Drawn in 3d using 'cam'
        draw.cube(za.Vec3.new(0, 0, 0), za.Vec3.new(1, 1, 1), 0xffffffff);

        try draw.end(cam);
        win.swap();

        //make the test exit, remove if copying
        win.should_exit = true;
    }
}

/// A structure that maps indices to a rectangle within a larger rectangle based on various parameters.
/// Useful for tilemaps that include padding
pub const SubTileset = struct {
    const Self = @This();

    description: []u8 = "",
    start: Vec2i, //xy of first tile
    tw: i32, //width of tile
    th: i32,
    pad: Vec2i, //xy spacing between tiles
    num: Vec2i, //number of cols, rows
    count: usize, //Total number of tiles, useful if last row is short

    pub fn getTexRec(self: Self, index: usize) Rect {
        const i: i32 = @intCast(index % self.count);
        return Rec(
            self.start.x + @mod(i, self.num.x) * (self.tw + self.pad.x),
            self.start.y + @divFloor(i, self.num.x) * (self.th + self.pad.y),
            self.tw,
            self.th,
        );
    }

    pub fn getBounds(self: Self) Rect {
        return Rec(
            self.start.x,
            self.start.y,
            self.num.x * (self.tw + self.pad.x),
            self.num.y * (self.th + self.pad.y),
        );
    }
};

///A Fixed width bitmap font structure
pub const FixedBitmapFont = struct {
    const Self = @This();

    texture: Texture,
    sts: SubTileset,

    translation_table: [128]u8 = [_]u8{127} ** 128,

    // each index of this decode_string corresponds to the index of the character in subTileSet
    pub fn init(texture: Texture, sts: SubTileset, decode_string: []const u8) Self {
        var ret = Self{
            .texture = texture,
            .sts = sts,
        };
        for (decode_string, 0..) |ch, i| {
            ret.translation_table[ch] = @as(u8, @intCast(i));
        }

        return ret;
    }
};

//TODO load a font and have a draw.textFmt convenience function with args:(pos, fmt, fmt_args, size);
pub const ImmediateDrawingContext = struct {
    const Self = @This();
    const log = std.log.scoped(.ImmediateDrawingContext);
    pub const TextParam = struct {
        background_rect: ?u32 = null,
        color: u32,
        px_size: f32,
        font: *FontInterface,

        do_newlines: bool = true,

        /// If not null, gets filled with the width of the rendered text in pixels.
        width_pointer: ?*f32 = null,
    };

    threadlocal var textFmtBuffer: [1024]u8 = undefined;

    pub const VtxFmt = struct {
        pub const Color_2D = packed struct { pos: Vec2f, z: u16, color: u32 };
        pub const Color_Texture_2D = packed struct { pos: Vec2f, uv: Vec2f, z: u16, color: u32 }; // 22 bytes
        pub const Color_3D = packed struct { pos: Vec3f, color: u32 };
        pub const Textured_3D = packed struct { pos: Vec3f, uv: Vec2f, color: u32 };
        pub const Textured_3D_NC = packed struct { pos: Vec3f, uv: Vec2f };

        //idea for a small vertex, xy are 14.2 or 13.3 fixed point. 2^13 allows for up to 8k with 8 subpixel positions
        //uv are also some fixed point maybe 13.3. These would not be normalized?
        pub const SmallTex = packed struct { x: u16, y: u16, u: u16, v: u16, z: u16 };
        //Total size: 10bytes

        pub fn textured3D(x: f32, y: f32, z: f32, u: f32, v: f32, color: u32) Textured_3D {
            return .{
                .pos = Vec3f.new(x, y, z),
                .uv = Vec2f.new(u, v),
                .color = color,
            };
        }

        pub fn color3D(x: f32, y: f32, z: f32, color: u32) Color_3D {
            return .{
                .pos = Vec3f.new(x, y, z),
                .color = color,
            };
        }
    };

    pub const Batches = union(enum) {
        color_tri: NewBatch(VtxFmt.Color_2D, .{ .index_buffer = true, .primitive_mode = .triangles }),
        color_tri_tex: NewBatch(VtxFmt.Color_Texture_2D, .{ .index_buffer = true, .primitive_mode = .triangles }),
        color_line: NewBatch(VtxFmt.Color_2D, .{ .index_buffer = false, .primitive_mode = .lines }),
        color_line3D: NewBatch(VtxFmt.Color_3D, .{ .index_buffer = true, .primitive_mode = .lines }),
        color_point3D: NewBatch(VtxFmt.Color_3D, .{ .index_buffer = false, .primitive_mode = .points }),
        color_cube: NewBatch(VtxFmt.Color_3D, .{ .index_buffer = true, .primitive_mode = .triangles }),
        billboard: NewBatch(VtxFmt.Textured_3D, .{ .index_buffer = true, .primitive_mode = .triangles }),
    };

    const MapT = std.AutoArrayHashMap(MapKey, Batches);
    const MapKey = struct {
        batch_kind: @typeInfo(Batches).@"union".tag_type.?,
        params: DrawParams,
    };
    const MapKeySortCtx = struct {
        items: []const MapKey,
        pub fn lessThan(ctx: MapKeySortCtx, l: usize, r: usize) bool {
            return ctx.items[l].params.draw_priority < ctx.items[r].params.draw_priority;
        }
    };

    /// These are globals rather than members so multiple instances of ImmediateDrawingContext can exist without creating duplicate resources.
    threadlocal var shaders_are_set = false;
    pub threadlocal var font_shader: c_uint = 0;
    pub threadlocal var colored_tri_shader: c_uint = 0;
    pub threadlocal var colored_line3d_shader: c_uint = 0;
    pub threadlocal var colored_point3d_shader: c_uint = 0;
    pub threadlocal var textured_tri_shader: c_uint = 0;
    pub threadlocal var textured_tri_3d_shader: c_uint = 0;
    pub threadlocal var textured_tri_3d_shader_new: c_uint = 0;
    pub threadlocal var billboard_shader: c_uint = 0;

    batches: MapT,

    zindex: u16 = 0,

    alloc: Alloc,

    //TODO actually check this and log or panic
    draw_fn_error: enum {
        no,
        yes,
    } = .no,

    /// This is always in sync with the actual window
    real_screen_dimensions: Vec2f = .{ .x = 0, .y = 0 },
    /// This can be changed for viewports
    screen_dimensions: Vec2f = .{ .x = 0, .y = 0 },
    preflush_cb: ?*const fn () void = null,

    pub fn init(alloc: Alloc) Self {
        const SD = "graphics/shader/";
        if (!shaders_are_set) {
            shaders_are_set = true;
            textured_tri_3d_shader = Shader.simpleShader(@embedFile(SD ++ "alpha_texturequad.vert"), @embedFile(SD ++ "texturequad.frag"));

            colored_tri_shader = Shader.simpleShader(@embedFile(SD ++ "newtri.vert"), @embedFile(SD ++ "colorquad.frag"));
            colored_line3d_shader = Shader.simpleShader(@embedFile(SD ++ "line3d.vert"), @embedFile(SD ++ "colorquad.frag"));
            colored_point3d_shader = Shader.simpleShader(@embedFile(SD ++ "line3d.vert"), @embedFile(SD ++ "point.fsh"));
            textured_tri_shader = Shader.simpleShader(@embedFile(SD ++ "tex_tri2d.vert"), @embedFile(SD ++ "tex_tri2d.frag"));
            textured_tri_3d_shader_new = Shader.simpleShader(@embedFile(SD ++ "tex_tri3d.vsh"), @embedFile(SD ++ "tex_tri3d.fsh"));
            billboard_shader = Shader.simpleShader(@embedFile(SD ++ "billboard_tex.vsh"), @embedFile(SD ++ "tex_tri3d.fsh"));

            font_shader = Shader.simpleShader(@embedFile(SD ++ "tex_tri2d.vert"), @embedFile(SD ++ "tex_tri2d_alpha.frag"));
        }
        return Self{
            .alloc = alloc,
            .batches = MapT.init(alloc),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.batches.values()) |*b| {
            inline for (@typeInfo(Batches).@"union".fields, 0..) |ufield, i| {
                if (i == @intFromEnum(b.*)) {
                    @field(b, ufield.name).deinit();
                }
            }
        }
        self.batches.deinit();
    }

    fn setErr(self: *Self, e: anyerror) void {
        std.debug.print("ImmediateDrawingContext: {any}\n", .{e});
        self.draw_fn_error = .yes;
    }

    fn drawErr(e: anyerror!void) void {
        e catch |err| {
            log.err("draw function: {any}", .{err});
        };
    }

    pub fn getBatch(self: *Self, key: MapKey) !*Batches {
        const res = try self.batches.getOrPut(key);
        if (!res.found_existing) {
            inline for (@typeInfo(Batches).@"union".fields, 0..) |ufield, i| {
                if (i == @intFromEnum(key.batch_kind)) {
                    res.value_ptr.* = @unionInit(Batches, ufield.name, ufield.type.init(self.alloc));
                    res.key_ptr.* = key;
                    break;
                }
            }
        }
        return res.value_ptr;
    }

    pub fn clearBuffers(self: *Self) !void {
        for (self.batches.values()) |*b| {
            inline for (@typeInfo(Batches).@"union".fields, 0..) |ufield, i| {
                if (i == @intFromEnum(b.*)) {
                    try @field(b, ufield.name).clear();
                }
            }
        }
    }

    pub fn beginNoClear(self: *Self, screen_dim: Vec2f) !void {
        self.screen_dimensions = screen_dim;
        try self.clearBuffers();
        //c.glClear(c.GL_DEPTH_BUFFER_BIT);
        self.zindex = 1;
    }

    pub fn begin(self: *Self, bg_color: u32, screen_dim: Vec2f) !void {
        self.screen_dimensions = screen_dim;
        try self.clearBuffers();

        self.zindex = 1;

        const color = ptypes.intToColorF(bg_color);
        c.glClearColor(color[0], color[1], color[2], color[3]);
        c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);
    }

    pub fn rectPt(self: *Self, rpt: Rect, color: u32) void {
        self.rect(rpt.mul(80 / 72.0), color);
    }

    pub fn rectV(self: *Self, pos: Vec2f, dim: Vec2f, color: u32) void {
        self.rect(Rect.newV(pos, dim), color);
    }

    pub fn rect(self: *Self, rpt: Rect, color: u32) void {
        drawErr(e: {
            const r = rpt;
            const b = &(self.getBatch(.{ .batch_kind = .color_tri, .params = .{ .shader = colored_tri_shader } }) catch |err| break :e err).color_tri;
            const z = self.zindex;
            self.zindex += 1;
            b.indicies.appendSlice(&genQuadIndices(@as(u32, @intCast(b.vertices.items.len)))) catch |err| break :e err;
            b.vertices.appendSlice(&.{
                .{ .z = z, .color = color, .pos = .{ .x = r.x + r.w, .y = r.y + r.h } },
                .{ .z = z, .color = color, .pos = .{ .x = r.x + r.w, .y = r.y } },
                .{ .z = z, .color = color, .pos = .{ .x = r.x, .y = r.y } },
                .{ .z = z, .color = color, .pos = .{ .x = r.x, .y = r.y + r.h } },
            }) catch |err| break :e err;
        });
    }

    /// The colors are wound ccw starting at top left corner
    pub fn rectVertexColors(self: *Self, r: Rect, vert_colors: []const u32) void {
        drawErr(e: {
            const b = &(self.getBatch(.{ .batch_kind = .color_tri, .params = .{
                .shader = colored_tri_shader,
            } }) catch |err| break :e err).color_tri;
            const z = self.zindex;
            self.zindex += 1;
            b.indicies.appendSlice(&genQuadIndices(@as(u32, @intCast(b.vertices.items.len)))) catch |err| break :e err;
            b.vertices.appendSlice(&.{
                .{ .z = z, .color = vert_colors[2], .pos = .{ .x = r.x + r.w, .y = r.y + r.h } },
                .{ .z = z, .color = vert_colors[3], .pos = .{ .x = r.x + r.w, .y = r.y } },
                .{ .z = z, .color = vert_colors[0], .pos = .{ .x = r.x, .y = r.y } },
                .{ .z = z, .color = vert_colors[1], .pos = .{ .x = r.x, .y = r.y + r.h } },
            }) catch |err| break :e err;
        });
    }

    pub fn nineSlice(self: *Self, r: Rect, tr: Rect, texture: Texture, scale: f32, tint: u32) void {
        const un = GL.normalizeTexRect(tr, texture.w, texture.h);
        const tbw = un.w / 3;
        const tbh = un.h / 3;
        const bw = tr.w / 3 * scale;
        const bh = tr.h / 3 * scale;
        const Uv = [_]Vec2f{
            //row 1
            .{ .y = un.y, .x = un.x + 0 },
            .{ .y = un.y, .x = un.x + tbw },
            .{ .y = un.y, .x = un.x + un.w - tbw },
            .{ .y = un.y, .x = un.x + un.w },
            //row 2
            .{ .y = un.y + tbh, .x = un.x + 0 },
            .{ .y = un.y + tbh, .x = un.x + tbw },
            .{ .y = un.y + tbh, .x = un.x + un.w - tbw },
            .{ .y = un.y + tbh, .x = un.x + un.w },
            //row 3
            .{ .y = un.y + un.h - tbh, .x = un.x + 0 },
            .{ .y = un.y + un.h - tbh, .x = un.x + tbw },
            .{ .y = un.y + un.h - tbh, .x = un.x + un.w - tbw },
            .{ .y = un.y + un.h - tbh, .x = un.x + un.w },
            //row 4
            .{ .y = un.y + un.h, .x = un.x + 0 },
            .{ .y = un.y + un.h, .x = un.x + tbw },
            .{ .y = un.y + un.h, .x = un.x + un.w - tbw },
            .{ .y = un.y + un.h, .x = un.x + un.w },
        };
        const b = &(self.getBatch(.{ .batch_kind = .color_tri_tex, .params = .{ .shader = textured_tri_shader, .texture = texture.id } }) catch return).color_tri_tex;
        const z = self.zindex;
        self.zindex += 1;
        //br, tr, tl, bl
        const i: u32 = @intCast(b.vertices.items.len);
        b.indicies.appendSlice(&.{
            //tl
            i + 0,  i + 4,  i + 1,  i + 4,  i + 5,  i + 1,
            //tm
            i + 1,  i + 5,  i + 2,  i + 5,  i + 6,  i + 2,
            //tr
            i + 2,  i + 6,  i + 3,  i + 6,  i + 7,  i + 3,
            //ml
            i + 4,  i + 8,  i + 5,  i + 8,  i + 9,  i + 5,
            //mm
            i + 5,  i + 9,  i + 6,  i + 9,  i + 10, i + 6,
            //mr
            i + 6,  i + 10, i + 7,  i + 10, i + 11, i + 7,
            //bl
            i + 8,  i + 12, i + 9,  i + 12, i + 13, i + 9,
            //bm
            i + 13, i + 10, i + 9,  i + 13, i + 14, i + 10,
            //br
            i + 10, i + 14, i + 11, i + 14, i + 15, i + 11,
        }) catch |e| {
            self.setErr(e);
            return;
        };

        b.vertices.appendSlice(&.{}) catch |e| {
            self.setErr(e);
            return;
        };

        b.vertices.appendSlice(&.{
            //Row 1
            .{ .z = z, .color = tint, .uv = Uv[0], .pos = .{ .y = r.y, .x = r.x } },
            .{ .z = z, .color = tint, .uv = Uv[1], .pos = .{ .y = r.y, .x = r.x + bw } },
            .{ .z = z, .color = tint, .uv = Uv[2], .pos = .{ .y = r.y, .x = r.x + r.w - bw } },
            .{ .z = z, .color = tint, .uv = Uv[3], .pos = .{ .y = r.y, .x = r.x + r.w } },
            //Row 2
            .{ .z = z, .color = tint, .uv = Uv[4], .pos = .{ .y = r.y + bh, .x = r.x } },
            .{ .z = z, .color = tint, .uv = Uv[5], .pos = .{ .y = r.y + bh, .x = r.x + bw } },
            .{ .z = z, .color = tint, .uv = Uv[6], .pos = .{ .y = r.y + bh, .x = r.x + r.w - bw } },
            .{ .z = z, .color = tint, .uv = Uv[7], .pos = .{ .y = r.y + bh, .x = r.x + r.w } },
            //Row 3
            .{ .z = z, .color = tint, .uv = Uv[8], .pos = .{ .y = r.y + r.h - bh, .x = r.x } },
            .{ .z = z, .color = tint, .uv = Uv[9], .pos = .{ .y = r.y + r.h - bh, .x = r.x + bw } },
            .{ .z = z, .color = tint, .uv = Uv[10], .pos = .{ .y = r.y + r.h - bh, .x = r.x + r.w - bw } },
            .{ .z = z, .color = tint, .uv = Uv[11], .pos = .{ .y = r.y + r.h - bh, .x = r.x + r.w } },
            ////Row 4
            .{ .z = z, .color = tint, .uv = Uv[12], .pos = .{ .y = r.y + r.h, .x = r.x } },
            .{ .z = z, .color = tint, .uv = Uv[13], .pos = .{ .y = r.y + r.h, .x = r.x + bw } },
            .{ .z = z, .color = tint, .uv = Uv[14], .pos = .{ .y = r.y + r.h, .x = r.x + r.w - bw } },
            .{ .z = z, .color = tint, .uv = Uv[15], .pos = .{ .y = r.y + r.h, .x = r.x + r.w } },
        }) catch |e| {
            self.setErr(e);
            return;
        };
    }

    pub fn rectTex(self: *Self, r: Rect, tr: Rect, texture: Texture) void {
        self.rectTexTint(r, tr, 0xffffffff, texture);
    }

    pub fn rectBorder(self: *Self, r: Rect, bw: f32, color: u32) void {
        self.rect(.{ .x = r.x, .y = r.y, .w = r.w, .h = bw }, color);
        self.rect(.{ .x = r.x + r.w - bw, .y = r.y, .w = bw, .h = r.h }, color);
        self.rect(.{ .x = r.x, .y = r.y + r.h - bw, .w = r.w, .h = bw }, color);
        self.rect(.{ .x = r.x, .y = r.y, .w = bw, .h = r.h }, color);
    }

    pub fn rectLine(self: *Self, r: Rect, bw: f32, color: u32) void {
        self.line(r.topL(), r.topR(), color, bw);
        self.line(r.topL().add(.{ .x = 0, .y = -bw / 2 }), r.botL().add(.{ .x = 0, .y = bw / 2 }), color, bw);
        self.line(r.botL(), r.botR(), color, bw);
        self.line(r.topR().add(.{ .x = 0, .y = -bw / 2 }), r.botR().add(.{ .x = 0, .y = bw / 2 }), color, bw);
    }

    pub fn rectTexTintShader(self: *Self, r: Rect, tr: Rect, col: u32, texture: Texture, shader: glID) void {
        const b = &(self.getBatch(.{ .batch_kind = .color_tri_tex, .params = .{ .shader = shader, .texture = texture.id } }) catch return).color_tri_tex;
        const z = self.zindex;
        self.zindex += 1;
        const un = GL.normalizeTexRect(tr, texture.w, texture.h);

        b.indicies.appendSlice(&genQuadIndices(@as(u32, @intCast(b.vertices.items.len)))) catch return;
        b.vertices.appendSlice(&.{
            .{ .pos = .{ .x = r.x + r.w, .y = r.y + r.h }, .z = z, .uv = .{ .x = un.x + un.w, .y = un.y + un.h }, .color = col }, //0
            .{ .pos = .{ .x = r.x + r.w, .y = r.y }, .z = z, .uv = .{ .x = un.x + un.w, .y = un.y }, .color = col }, //1
            .{ .pos = .{ .x = r.x, .y = r.y }, .z = z, .uv = .{ .x = un.x, .y = un.y }, .color = col }, //2
            .{ .pos = .{ .x = r.x, .y = r.y + r.h }, .z = z, .uv = .{ .x = un.x, .y = un.y + un.h }, .color = col }, //3
        }) catch return;
    }

    pub fn rectTexTint(self: *Self, r: Rect, tr: Rect, col: u32, texture: Texture) void {
        self.rectTexTintShader(r, tr, col, texture, textured_tri_shader);
    }

    pub fn rectTexTintUvOffset(self: *Self, r: Rect, tr: Rect, col: u32, texture: Texture, uv_offset: u8) void {
        //FIXME support flip flags again
        const b = &(self.getBatch(.{ .batch_kind = .color_tri_tex, .params = .{ .shader = textured_tri_shader, .texture = texture.id } }) catch return).color_tri_tex;
        const z = self.zindex;
        self.zindex += 1;
        const un = GL.normalizeTexRect(tr, texture.w, texture.h);
        const uvs = [4]Vec2f{
            .{ .x = un.x + un.w, .y = un.y + un.h },
            .{ .x = un.x + un.w, .y = un.y },
            .{ .x = un.x, .y = un.y },
            .{ .x = un.x, .y = un.y + un.h },
        };
        //Bits are HVD
        const uo = uv_offset;
        //const uo = 4 - ([_]u8{ 0, 1, 0, 3, 2, 2, 2, 3 })[uv_offset];
        const uvf = [4]u8{
            uo % 4,
            (uo + 1) % 4,
            (uo + 2) % 4,
            (uo + 3) % 4,
        };
        // Vert ^ horiz = flip vert
        //econst h: u8 = if ((uv_offset >> 2 & 0b1) ^ ((uv_offset >> 1) & 0b1) == 1) 1 else 0;
        const h = 0; //Disable flip flags

        b.indicies.appendSlice(&genQuadIndices(@as(u32, @intCast(b.vertices.items.len)))) catch return;
        b.vertices.appendSlice(&.{
            .{ .pos = .{ .x = r.x + r.w, .y = r.y + r.h }, .z = z, .uv = uvs[uvf[(0 + h) % 4]], .color = col }, //0
            .{ .pos = .{ .x = r.x + r.w, .y = r.y }, .z = z, .uv = uvs[uvf[(1 + 4 - h) % 4]], .color = col }, //1
            .{ .pos = .{ .x = r.x, .y = r.y }, .z = z, .uv = uvs[uvf[(2 + h) % 4]], .color = col }, //2
            .{ .pos = .{ .x = r.x, .y = r.y + r.h }, .z = z, .uv = uvs[uvf[(3 + 4 - h) % 4]], .color = col }, //3
        }) catch return;
    }

    pub fn text(self: *Self, pos: Vec2f, str: []const u8, param: TextParam) void {
        const font = param.font;
        const SF = (param.px_size / font.font_size);
        const fac = 1;
        const x = @trunc(pos.x);
        const y = @trunc(pos.y);

        const col = param.color;
        const b = &(self.getBatch(.{
            .batch_kind = .color_tri_tex,
            //Text should always be drawn last for best transparency
            .params = .{
                .shader = font_shader,
                .texture = font.texture.id,
                .draw_priority = 0xff,
                .write_depth = false,
            },
        }) catch return).color_tri_tex;

        b.vertices.ensureUnusedCapacity(str.len * 4) catch return;
        b.indicies.ensureUnusedCapacity(str.len * 6) catch return;

        const view = std.unicode.Utf8View.init(str) catch {
            std.debug.print("broke :{s}\n", .{str});
            return;
        };
        var it = view.iterator();

        var vx = x * fac;
        var vy = y * fac + ((font.ascent + font.descent) * SF);
        const z = self.zindex + 1;
        while (it.nextCodepoint()) |ch| {
            if (ch == '\n') {
                if (param.do_newlines) {
                    vy += font.line_gap * SF;
                    vx = x * fac;
                }
                continue;
            }

            const g = font.getGlyph(ch);

            const r = Rect{
                .x = vx + (g.offset_x) * SF,
                .y = vy - (g.offset_y) * SF,
                .w = (g.width) * SF,
                .h = (g.height) * SF,
            };

            //self.rect(r, 0xffffffff);

            b.indicies.appendSlice(&genQuadIndices(@as(u32, @intCast(b.vertices.items.len)))) catch return;
            const un = GL.normalizeTexRect(g.tr, font.texture.w, font.texture.h);
            b.vertices.appendSlice(&.{
                .{ .pos = .{ .x = r.x + r.w, .y = r.y + r.h }, .z = z, .uv = .{ .x = un.x + un.w, .y = un.y + un.h }, .color = col }, //0
                .{ .pos = .{ .x = r.x + r.w, .y = r.y }, .z = z, .uv = .{ .x = un.x + un.w, .y = un.y }, .color = col }, //1
                .{ .pos = .{ .x = r.x, .y = r.y }, .z = z, .uv = .{ .x = un.x, .y = un.y }, .color = col }, //2
                .{ .pos = .{ .x = r.x, .y = r.y + r.h }, .z = z, .uv = .{ .x = un.x, .y = un.y + un.h }, .color = col }, //3
            }) catch return;

            vx += (g.advance_x) * SF;
        }
        if (param.background_rect) |bg_col| {
            self.rect(Rec(pos.x, pos.y, vx - pos.x, vy - pos.y), bg_col);
        }
        if (param.width_pointer) |wp| {
            wp.* = vx - pos.x;
        }
        self.zindex += 1; //one for rz
    }

    pub fn textFmt(self: *Self, pos: Vec2f, comptime fmt: []const u8, args: anytype, param: TextParam) void {
        var fbs = std.io.FixedBufferStream([]u8){ .pos = 0, .buffer = &textFmtBuffer };
        fbs.writer().print(fmt, args) catch {
            log.warn("string exceeded textFmt buffer", .{});
            log.warn(fmt, args);
            return;
        };
        self.text(pos, fbs.getWritten(), param);
    }

    pub fn textClipped(self: *Self, area: Rect, comptime fmt: []const u8, args: anytype, param: TextParam, justify: enum { left, right, center }) void {
        var fbs = std.io.FixedBufferStream([]u8){ .pos = 0, .buffer = &textFmtBuffer };
        fbs.writer().print(fmt, args) catch {
            log.warn("string exceeded textFmt buffer", .{});
            log.warn(fmt, args);
            return;
        };

        const slice = fbs.getWritten();
        //const slice = fbs.getWritten();
        const bounds = param.font.textBounds(slice, param.px_size);
        const last_char_index = blk: {
            if (param.font.nearestGlyphX(slice, param.px_size, .{ .x = area.w - param.px_size, .y = 0 }, true)) |lci| {
                break :blk lci;
            }
            break :blk slice.len;
        };

        const x_ = switch (justify) {
            .left => area.x,
            .right => area.x + area.w - bounds.x,
            .center => area.x + area.w / 2 - bounds.x / 2,
        };
        const x = if (last_char_index < slice.len) area.x else x_;
        const sl = if (last_char_index < slice.len) slice[0..last_char_index] else slice;
        self.text(Vec2f.new(x, area.y), sl, param);
        //self.drawText(sl, Vec2f.new(x, area.y), size, color, font);
    }

    //pub fn textFmtOpts(self: *Self, area: Rect, comptime fmt: []const u8, args: anytype, font)

    pub fn point3D(self: *Self, point: za.Vec3, color: u32, width: f32) void {
        const b = &(self.getBatch(.{ .batch_kind = .color_point3D, .params = .{
            .shader = colored_point3d_shader,
            .camera = ._3d,
            .line_point_width = @intFromFloat(@min(255, @abs(width * 4))),
        } }) catch return).color_point3D;
        b.vertices.append(.{ .pos = .{ .x = point.x(), .y = point.y(), .z = point.z() }, .color = color }) catch return;
    }

    pub fn cubeFrame(self: *Self, pos: za.Vec3, ext: za.Vec3, color: u32) void {
        const b = &(self.getBatch(.{ .batch_kind = .color_line3D, .params = .{ .shader = colored_line3d_shader, .camera = ._3d } }) catch return).color_line3D;
        const v = &b.vertices;
        const i: u32 = @intCast(v.items.len);

        const z1 = pos.z();
        v.append(.{ .color = color, .pos = .{ .z = z1, .x = pos.x(), .y = pos.y() } }) catch return;
        v.append(.{ .color = color, .pos = .{ .z = z1, .x = pos.x() + ext.x(), .y = pos.y() } }) catch return;
        v.append(.{ .color = color, .pos = .{ .z = z1, .x = pos.x() + ext.x(), .y = pos.y() + ext.y() } }) catch return;
        v.append(.{ .color = color, .pos = .{ .z = z1, .x = pos.x(), .y = pos.y() + ext.y() } }) catch return;

        const z2 = pos.z() + ext.z();
        v.append(.{ .color = color, .pos = .{ .z = z2, .x = pos.x(), .y = pos.y() } }) catch return;
        v.append(.{ .color = color, .pos = .{ .z = z2, .x = pos.x() + ext.x(), .y = pos.y() } }) catch return;
        v.append(.{ .color = color, .pos = .{ .z = z2, .x = pos.x() + ext.x(), .y = pos.y() + ext.y() } }) catch return;
        v.append(.{ .color = color, .pos = .{ .z = z2, .x = pos.x(), .y = pos.y() + ext.y() } }) catch return;
        const in = &b.indicies;

        in.appendSlice(&.{
            i, i + 1, i + 1, i + 2, i + 2, i + 3, i + 3, i, //bottom layer
            i, i + 4, i + 1, i + 5, i + 2, i + 6, i + 3, i + 7, //Verticals
            i + 4, i + 5, i + 5, i + 6, i + 6, i + 7, i + 7, i + 4, //top layer
        }) catch return;
    }

    pub fn line3D(self: *Self, start_point: za.Vec3, end_point: za.Vec3, color: u32, width: f32) void {
        const b = &(self.getBatch(.{ .batch_kind = .color_line3D, .params = .{
            .shader = colored_line3d_shader,
            .camera = ._3d,
            .line_point_width = @intFromFloat(@min(255, @abs(width * 4))),
        } }) catch return).color_line3D;
        const i = b.vertices.items.len;
        b.vertices.append(.{ .pos = .{ .x = start_point.x(), .y = start_point.y(), .z = start_point.z() }, .color = color }) catch return;
        b.vertices.append(.{ .pos = .{ .x = end_point.x(), .y = end_point.y(), .z = end_point.z() }, .color = color }) catch return;
        b.indicies.append(@intCast(i)) catch return;
        b.indicies.append(@intCast(i + 1)) catch return;
    }

    //vec3 vertexPosition_worldspace =
    //billboardCenter_wordspace
    //+ CameraRight_worldspace * billboardVertices.x * BillboardSize.x
    //+ CameraUp_worldspace * billboardVertices.y * BillboardSize.y;

    pub fn billboard(self: *Self, pos: za.Vec3, size: Vec2f, tr: Rect, texture: Texture, cam: Camera3D) void {
        const b = &(self.getBatch(.{ .batch_kind = .billboard, .params = .{
            .shader = billboard_shader,
            .texture = texture.id,
            .camera = ._3d,
        } }) catch return).billboard;
        const o: u32 = @intCast(b.vertices.items.len);
        const up = cam.getUp();
        const right = cam.front.cross(up).norm();
        b.indicies.appendSlice(&genQuadIndices(o)) catch return;
        const un = GL.normalizeTexRect(tr, texture.w, texture.h);
        const co = 0xffffffff;

        const sz = size.x;
        const po = pos.scale(2).sub(cam.pos);
        const A = po.sub(right.add(up).scale(sz));
        const B = po.add(right.sub(up).scale(sz));
        const C = po.add(right.add(up).scale(sz));
        const D = po.sub(right.sub(up).scale(sz));

        b.vertices.appendSlice(&.{
            VtxFmt.textured3D(B.x(), B.y(), B.z(), un.x + un.w, un.y + un.h, co),
            VtxFmt.textured3D(C.x(), C.y(), C.z(), un.x + un.w, un.y, co),
            VtxFmt.textured3D(D.x(), D.y(), D.z(), un.x, un.y, co),
            VtxFmt.textured3D(A.x(), A.y(), A.z(), un.x, un.y + un.h, co),
        }) catch return;
    }

    pub fn triangle3D(self: *Self, vs: []const za.Vec3, color: u32) void {
        const b = &(self.getBatch(.{ .batch_kind = .color_cube, .params = .{
            .shader = colored_line3d_shader,
            .camera = ._3d,
        } }) catch return).color_cube;
        const of: u32 = @intCast(b.vertices.items.len);
        b.indicies.appendSlice(&.{ of, of + 1, of + 2 }) catch return;
        b.vertices.appendSlice(&.{
            VtxFmt.color3D(vs[2].x(), vs[2].y(), vs[2].z(), color),
            VtxFmt.color3D(vs[1].x(), vs[1].y(), vs[1].z(), color),
            VtxFmt.color3D(vs[0].x(), vs[0].y(), vs[0].z(), color),
        }) catch return;
    }

    /// Draw a convex polygon, 'vs' is ordered winding. direction is unimportant as both sides are drawn
    pub fn convexPoly(self: *Self, vs: []const za.Vec3, color: u32) void {
        const b = &(self.getBatch(.{ .batch_kind = .color_cube, .params = .{
            .shader = colored_line3d_shader,
            .camera = ._3d,
        } }) catch return).color_cube;
        const of: u32 = @intCast(b.vertices.items.len);
        b.vertices.ensureUnusedCapacity(vs.len) catch return;
        for (vs) |v|
            b.vertices.append(VtxFmt.color3D(v.x(), v.y(), v.z(), color)) catch return;

        for (1..vs.len - 1) |i| {
            const ii: u32 = @intCast(i);
            b.indicies.appendSlice(&.{
                (0 + of),
                (ii + 1 + of),
                (ii + of),
                (ii + of), //Back face too
                (ii + 1 + of),
                (0 + of),
            }) catch return;
        }
    }

    pub fn convexPolyIndexed(
        self: *Self,
        index: []const u32,
        vs: []const za.Vec3,
        color: u32,
        param: struct {
            offset: za.Vec3 = za.Vec3.zero(),
            rot: ?za.Mat3 = null, //Rotation is applied before offset
        },
    ) void {
        const b = &(self.getBatch(.{ .batch_kind = .color_cube, .params = .{
            .shader = colored_line3d_shader,
            .camera = ._3d,
        } }) catch return).color_cube;
        const of: u32 = @intCast(b.vertices.items.len);
        b.vertices.ensureUnusedCapacity(index.len) catch return;
        for (index) |i| {
            var v = vs[i];
            if (param.rot) |r|
                v = r.mulByVec3(v);
            v = v.add(param.offset);
            b.vertices.append(VtxFmt.color3D(v.x(), v.y(), v.z(), color)) catch return;
        }

        for (1..index.len - 1) |i| {
            const ii: u32 = @intCast(i);
            b.indicies.appendSlice(&.{
                (0 + of),
                (ii + 1 + of),
                (ii + of),
                (ii + of), //Back face too
                (ii + 1 + of),
                (0 + of),
            }) catch return;
        }
    }

    pub fn cube(self: *Self, pos: za.Vec3, ext: za.Vec3, color: u32) void {
        const px = pos.x();
        const py = pos.y();
        const pz = pos.z();
        const sx = ext.x();
        const sy = ext.y();
        const sz = ext.z();
        const b = &(self.getBatch(.{ .batch_kind = .color_cube, .params = .{
            .shader = colored_line3d_shader,
            .camera = ._3d,
        } }) catch return).color_cube;
        b.indicies.appendSlice(&GL.genCubeIndicies(@as(u32, @intCast(b.vertices.items.len)))) catch return;
        // zig fmt: off
        b.vertices.appendSlice(&.{
        // front
        VtxFmt.color3D(px + sx, py + sy, pz, color), //0
        VtxFmt.color3D(px + sx, py     , pz, color), //1
        VtxFmt.color3D(px     , py     , pz, color), //2
        VtxFmt.color3D(px     , py + sy, pz, color), //3

        // backcolor
        VtxFmt.color3D(px     , py + sy, pz + sz, color), //3
        VtxFmt.color3D(px     , py     , pz + sz, color), //2
        VtxFmt.color3D(px + sx, py     , pz + sz, color), //1
        VtxFmt.color3D(px + sx, py + sy, pz + sz, color), //0


        VtxFmt.color3D(px + sx, py, pz,      color),
        VtxFmt.color3D(px + sx, py, pz + sz, color),
        VtxFmt.color3D(px     , py, pz + sz, color),
        VtxFmt.color3D(px     , py, pz     , color),

        VtxFmt.color3D(px     , py + sy, pz     ,  color),
        VtxFmt.color3D(px     , py + sy, pz + sz,  color),
        VtxFmt.color3D(px + sx, py + sy, pz + sz,  color),
        VtxFmt.color3D(px + sx, py + sy, pz,       color),

        VtxFmt.color3D(px, py + sy, pz,       color),
        VtxFmt.color3D(px, py , pz,           color),
        VtxFmt.color3D(px, py , pz + sz,      color),
        VtxFmt.color3D(px, py + sy , pz + sz, color),

        VtxFmt.color3D(px + sx, py + sy , pz + sz, color),
        VtxFmt.color3D(px + sx, py , pz + sz,      color),
        VtxFmt.color3D(px + sx, py , pz,           color),
        VtxFmt.color3D(px + sx, py + sy, pz,       color),


    }) catch return;
    // zig fmt: on
    }

    // Winding order should be CCW
    pub fn triangle(self: *Self, v1: Vec2f, v2: Vec2f, v3: Vec2f, color: u32) void {
        const b = &(self.getBatch(.{ .batch_kind = .color_tri, .params = .{ .shader = colored_tri_shader } }) catch return).color_tri;
        const z = self.zindex;
        const i: u32 = @intCast(b.vertices.items.len);
        b.indicies.appendSlice(&.{ i, i + 1, i + 2 }) catch return;
        b.vertices.appendSlice(&.{
            .{ .pos = v1, .z = z, .color = color },
            .{ .pos = v2, .z = z, .color = color },
            .{ .pos = v3, .z = z, .color = color },
        }) catch return;
    }

    //TODO destroy this and use a font
    pub fn bitmapText(self: *Self, x: f32, y: f32, h: f32, str: []const u8, font: FixedBitmapFont, col: u32) void {
        const b = &(self.getBatch(.{
            .batch_kind = .color_tri_tex,
            //Text should always be drawn last for best transparency
            .params = .{ .shader = textured_tri_shader, .texture = font.texture.id, .draw_priority = 0xff },
        }) catch return).color_tri_tex;
        const z = self.zindex;
        self.zindex += 1;

        var i: u32 = 0;
        for (str) |char| {
            if (char == ' ' or char == '_') {
                i += 1;
                continue;
            }

            const ind = font.translation_table[std.ascii.toUpper(char)];
            const fi = @as(f32, @floatFromInt(i));
            const tr = font.sts.getTexRec(if (ind == 127) continue else ind);
            const un = GL.normalizeTexRect(tr, font.texture.w, font.texture.h);
            const r = Rec(x + fi * h, y, h, h);

            b.indicies.appendSlice(&genQuadIndices(@as(u32, @intCast(b.vertices.items.len)))) catch return;
            b.vertices.appendSlice(&.{
                .{ .pos = .{ .x = r.x + r.w, .y = r.y + r.h }, .z = z, .uv = .{ .x = un.x + un.w, .y = un.y + un.h }, .color = col }, //0
                .{ .pos = .{ .x = r.x + r.w, .y = r.y }, .z = z, .uv = .{ .x = un.x + un.w, .y = un.y }, .color = col }, //1
                .{ .pos = .{ .x = r.x, .y = r.y }, .z = z, .uv = .{ .x = un.x, .y = un.y }, .color = col }, //2
                .{ .pos = .{ .x = r.x, .y = r.y + r.h }, .z = z, .uv = .{ .x = un.x, .y = un.y + un.h }, .color = col }, //3
            }) catch return;

            i += 1;
        }
    }

    pub fn line(self: *Self, start_p: Vec2f, end_p: Vec2f, color: u32, width: f32) void {
        const b = &(self.getBatch(.{ .batch_kind = .color_line, .params = .{
            .shader = colored_tri_shader,
            .line_point_width = @intFromFloat(@min(255, @abs(width * 4))),
        } }) catch return).color_line;
        const z = self.zindex;
        self.zindex += 1;
        b.vertices.appendSlice(&.{
            .{ .pos = start_p, .z = z, .color = color },
            .{ .pos = end_p, .z = z, .color = color },
        }) catch return;
    }

    pub fn setViewport(self: *Self, vo: ?Rect) void {
        const sb = self.screen_dimensions;
        if (vo) |v| {
            c.glViewport(
                @as(i32, @intFromFloat(v.x)),
                @as(i32, @intFromFloat(sb.y - (v.y + v.h))),
                @as(i32, @intFromFloat(v.w)),
                @as(i32, @intFromFloat(v.h)),
            );
        } else {
            self.setViewport(Rec(0, 0, sb.x, sb.y));
        }
    }

    pub fn flushCustomMat(self: *Self, cam_2d: za.Mat4, cam_3d: za.Mat4) !void {
        if (self.preflush_cb) |cb|
            cb();
        GL.enable(.blend);
        c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);
        c.glBlendEquation(c.GL_FUNC_ADD);
        defer GL.disable(.blend);
        //const view_3d = if (camera_3d) |c3| c3.getMatrix(
        //    self.screen_dimensions.x / self.screen_dimensions.y,
        //    1,
        //    64 * 512,
        //    //0.1,
        //    //100000,
        //) else view;
        const model = za.Mat4.identity();

        const sortctx = MapKeySortCtx{ .items = self.batches.keys() }; // Sort the batches by params.draw_priority
        self.batches.sort(sortctx);
        var b_it = self.batches.iterator();
        while (b_it.next()) |b| {
            inline for (@typeInfo(Batches).@"union".fields, 0..) |ufield, i| {
                if (i == @intFromEnum(b.value_ptr.*)) {
                    @field(b.value_ptr.*, ufield.name).pushVertexData();
                    @field(b.value_ptr.*, ufield.name).draw(b.key_ptr.params, switch (b.key_ptr.params.camera) {
                        ._2d => cam_2d,
                        ._3d => cam_3d,
                    }, model);
                }
            }
        }
        try self.clearBuffers();
    }

    pub fn flush(self: *Self, custom_camera: ?Rect, camera_3d: ?ptypes.Camera3D) !void {
        const cb = if (custom_camera) |cc| cc else Rec(0, 0, self.screen_dimensions.x, self.screen_dimensions.y);
        const view = za.orthographic(cb.x, cb.x + cb.w, cb.y + cb.h, cb.y, -100000, 1);
        const view_3d = if (camera_3d) |c3| c3.getMatrix(
            self.screen_dimensions.x / self.screen_dimensions.y,
            1,
            64 * 512,
            //0.1,
            //100000,
        ) else view;
        try self.flushCustomMat(view, view_3d);
    }

    pub fn end(self: *Self, camera_3d: ?Camera3D) !void {
        try self.flush(null, camera_3d);
    }
};

/// This structure modifies ImmediateDrawingContext.zindex
pub const MultiLineText = struct {
    pos_i: Vec2f,
    pos: Vec2f,
    ctx: *ImmediateDrawingContext,
    font: *FontInterface,

    max_width: f32,

    starting_z: u16,

    pub fn start(dctx: *ImmediateDrawingContext, start_pos: Vec2f, font: *FontInterface) @This() {
        defer dctx.zindex += 1; //Reserve a z for background rect
        return .{
            .starting_z = dctx.zindex,
            .max_width = 0,
            .font = font,
            .ctx = dctx,
            .pos = start_pos,
            .pos_i = start_pos,
        };
    }

    pub fn text(self: *@This(), str: []const u8, px_size: f32, col: u32) void {
        var w: f32 = 0;
        self.ctx.text(self.pos, str, .{ .width_pointer = &w, .color = col, .font = self.font, .px_size = px_size });
        self.max_width = @max(w, self.max_width);
        self.pos.y += px_size;
    }

    pub fn textFmt(self: *@This(), comptime fmt: []const u8, args: anytype, px_size: f32, color: u32) void {
        var w: f32 = 0;
        self.ctx.textFmt(self.pos, fmt, args, .{
            .width_pointer = &w,
            .color = color,
            .px_size = px_size,
            .font = self.font,
        });
        self.max_width = @max(w, self.max_width);
        self.pos.y += px_size;
    }

    pub fn drawBgRect(self: *@This(), color: u32, min_width: f32) void {
        const old_z = self.ctx.zindex;
        defer self.ctx.zindex = old_z;
        self.ctx.zindex = self.starting_z;
        self.ctx.rect(Rec(self.pos_i.x, self.pos_i.y, @max(min_width, self.max_width), self.pos.y - self.pos_i.y), color);
    }
};

pub const BatchOptions = struct {
    index_buffer: bool,
    primitive_mode: GL.PrimitiveMode,
};
pub const DrawParams = struct {
    texture: ?c_uint = null,
    camera: enum { _3d, _2d } = ._2d,
    ///The higher the number, the later the batch gets drawn.
    draw_priority: u8 = 0,
    shader: c_uint,
    write_depth: bool = true,
    //Fixed point 6.2 pixels for easy hashing
    line_point_width: u8 = 1 << 2,
};
pub const PassedUniform = struct {
    name: [*c]const u8,
    payload: union(enum) { float: f32 },
};
pub fn NewBatch(comptime vertex_type: type, comptime batch_options: BatchOptions) type {
    const IndexType = u32;
    return struct {
        pub const Self = @This();
        pub const VtxType = vertex_type;

        vbo: c_uint,
        vao: c_uint,
        ebo: if (batch_options.index_buffer) c_uint else void,
        vertices: std.ArrayList(vertex_type),
        indicies: if (batch_options.index_buffer) std.ArrayList(IndexType) else void,
        primitive_mode: GL.PrimitiveMode = batch_options.primitive_mode,

        pub fn init(alloc: Alloc) @This() {
            var ret = @This(){
                .vertices = std.ArrayList(vertex_type).init(alloc),
                .indicies = if (batch_options.index_buffer) std.ArrayList(IndexType).init(alloc) else {},
                .ebo = if (batch_options.index_buffer) 0 else {},
                .vao = 0,
                .vbo = 0,
            };

            c.glGenVertexArrays(1, &ret.vao);
            c.glGenBuffers(1, &ret.vbo);
            if (batch_options.index_buffer) c.glGenBuffers(1, &ret.ebo);

            GL.generateVertexAttributes(ret.vao, ret.vbo, vertex_type);

            return ret;
        }

        pub fn deinit(self: *Self) void {
            self.vertices.deinit();
            if (batch_options.index_buffer)
                self.indicies.deinit();
        }

        pub fn dirty(self: *Self) bool {
            return self.vertices.items.len != 0;
        }

        pub fn pushVertexData(self: *Self) void {
            c.glBindVertexArray(self.vao);
            GL.bufferData(c.GL_ARRAY_BUFFER, self.vbo, vertex_type, self.vertices.items);
            if (batch_options.index_buffer)
                GL.bufferData(c.GL_ELEMENT_ARRAY_BUFFER, self.ebo, u32, self.indicies.items);
        }

        pub fn clear(self: *Self) !void {
            try self.vertices.resize(0);
            if (batch_options.index_buffer)
                try self.indicies.resize(0);
        }

        pub fn draw(self: *Self, params: DrawParams, view: za.Mat4, model: za.Mat4) void {
            self.drawUniform(params, view, model, &.{});
        }

        pub fn drawUniform(self: *Self, params: DrawParams, view: za.Mat4, model: za.Mat4, uniform_list: []const PassedUniform) void {
            if (self.vertices.items.len == 0)
                return;
            if (!params.write_depth)
                c.glDepthMask(c.GL_FALSE);
            defer c.glDepthMask(c.GL_TRUE);
            c.glUseProgram(params.shader);
            c.glBindVertexArray(self.vao);
            if (params.texture) |texture| {
                c.glBindTextureUnit(0, texture);
            }
            GL.passUniform(params.shader, "view", view);
            GL.passUniform(params.shader, "model", model);
            for (uniform_list) |uni| {
                switch (uni.payload) {
                    .float => |f| GL.passUniform(params.shader, uni.name, f),
                }
            }
            c.glLineWidth(@as(f32, @floatFromInt(params.line_point_width)) / 4);
            c.glPointSize(@as(f32, @floatFromInt(params.line_point_width)) / 4);

            const prim: u32 = @intFromEnum(self.primitive_mode);
            if (batch_options.index_buffer) {
                c.glDrawElements(prim, @as(c_int, @intCast(self.indicies.items.len)), c.GL_UNSIGNED_INT, null);
            } else {
                c.glDrawArrays(prim, 0, @as(c_int, @intCast(self.vertices.items.len)));
            }
        }
    };
}

pub fn genQuadIndices(index: u32) [6]u32 {
    return [_]u32{
        index + 0,
        index + 1,
        index + 3,
        index + 1,
        index + 2,
        index + 3,
    };
}

pub const Padding = struct {
    const Self = @This();
    top: f32 = 0,
    bottom: f32 = 0,
    left: f32 = 0,
    right: f32 = 0,

    pub fn new(t: f32, b: f32, l: f32, r: f32) Self {
        return .{ .top = t, .bottom = b, .left = l, .right = r };
    }

    pub fn scale(self: Self, f: f32) Self {
        return .{ .top = self.top * f, .bottom = self.bottom * f, .left = self.left * f, .right = self.right * f };
    }

    pub fn vertical(self: Self) f32 {
        return self.top + self.bottom;
    }

    pub fn horizontal(self: Self) f32 {
        return self.left + self.right;
    }
};

pub const RenderTexture = struct {
    const Self = @This();
    fb: c_uint,
    depth_rb: c_uint,
    stencil_rb: c_uint,
    texture: Texture,
    w: i32,
    h: i32,

    pub fn init(wa: anytype, ha: anytype) !Self {
        const w = lcast(i32, wa);
        const h = lcast(i32, ha);
        var ret = Self{
            .w = w,
            .h = h,
            .fb = 0,
            .depth_rb = 0,
            .stencil_rb = 0,
            .texture = Texture.initFromBuffer(null, w, h, .{
                .min_filter = c.GL_LINEAR,
                .mag_filter = c.GL_NEAREST,
                .generate_mipmaps = false,
            }),
            //.texture = Texture.
        };
        c.glGenFramebuffers(1, &ret.fb);
        c.glBindFramebuffer(c.GL_FRAMEBUFFER, ret.fb);

        //c.glGenRenderbuffers(1, &ret.depth_rb);
        //c.glBindRenderbuffer(c.GL_RENDERBUFFER, ret.depth_rb);
        //c.glRenderbufferStorage(c.GL_RENDERBUFFER, c.GL_DEPTH_COMPONENT, w, h);
        //c.glFramebufferRenderbuffer(c.GL_FRAMEBUFFER, c.GL_DEPTH_ATTACHMENT, c.GL_RENDERBUFFER, ret.depth_rb);

        c.glGenRenderbuffers(1, &ret.stencil_rb);
        c.glBindRenderbuffer(c.GL_RENDERBUFFER, ret.stencil_rb);
        c.glRenderbufferStorage(c.GL_RENDERBUFFER, c.GL_DEPTH_STENCIL, w, h);
        c.glFramebufferRenderbuffer(c.GL_FRAMEBUFFER, c.GL_DEPTH_STENCIL_ATTACHMENT, c.GL_RENDERBUFFER, ret.stencil_rb);

        c.glFramebufferTexture(c.GL_FRAMEBUFFER, c.GL_COLOR_ATTACHMENT0, ret.texture.id, 0);
        const draw_buffers = [_]c.GLenum{c.GL_COLOR_ATTACHMENT0};
        c.glDrawBuffers(draw_buffers.len, &draw_buffers[0]);

        if (c.glCheckFramebufferStatus(c.GL_FRAMEBUFFER) != c.GL_FRAMEBUFFER_COMPLETE) return error.framebufferCreateFailed;

        c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);
        c.glBindRenderbuffer(c.GL_RENDERBUFFER, 0);

        return ret;
    }

    pub fn setSize(self: *Self, w: anytype, h: anytype) !bool {
        const wi = lcast(i32, w);
        const hi = lcast(i32, h);
        if (wi != self.w or hi != self.h) {
            self.deinit();
            self.* = try RenderTexture.init(w, h);
            return true;
        }
        return false;
    }

    pub fn rect(self: *Self) Rect {
        const r = self.texture.rect();
        return Rec(r.x, r.y + r.h, r.w, -r.h);
    }

    pub fn deinit(self: *Self) void {
        c.glDeleteFramebuffers(1, &self.fb);
        c.glDeleteRenderbuffers(1, &self.depth_rb);
        c.glDeleteRenderbuffers(1, &self.stencil_rb);
        c.glDeleteTextures(1, &self.texture.id);
    }

    pub fn bind(self: *Self, clear: bool) void {
        c.glBindFramebuffer(c.GL_FRAMEBUFFER, self.fb);
        c.glViewport(0, 0, self.w, self.h);
        if (clear) {
            c.glClearColor(1, 1, 1, 1);
            c.glClear(c.GL_COLOR_BUFFER_BIT);
        }
        c.glClear(c.GL_DEPTH_BUFFER_BIT);
    }
};

const AvgBuf = struct {
    const Self = @This();
    const len = 100;

    pos: u32 = 0,
    buf: [len]f32 = .{0} ** len,

    fn insert(self: *Self, val: f32) void {
        self.buf[self.pos] = val;
        self.pos = (self.pos + 1) % @as(u32, @intCast(self.buf.len));
    }

    fn avg(self: *Self) f32 {
        var res: f32 = 0;
        for (self.buf) |it| {
            res += it;
        }
        return res / @as(f32, @floatFromInt(self.buf.len));
    }
};

fn lerp(start: f32, end: f32, ratio: f32) f32 {
    return start + (end - start) * ratio;
}

fn lerpVec(start: Vec2f, end: Vec2f, ratio: f32) Vec2f {
    return (.{ .x = lerp(start.x, end.x, ratio), .y = lerp(start.y, end.y, ratio) });
}

pub const CubeVert = packed struct {
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
    ti: u16,
};

pub fn cubeVert(x: f32, y: f32, z: f32, u: f32, v: f32, nx: f32, ny: f32, nz: f32, color: u32, tx: f32, ty: f32, tz: f32, ti: u16) CubeVert {
    return .{
        .x = x,
        .y = y,
        .z = z,

        .u = u,
        .v = v,

        .nx = nx,
        .ny = ny,
        .nz = nz,

        .color = color,
        .tx = tx,
        .ty = ty,
        .tz = tz,
        .ti = ti,
    };
}

pub const Cubes = struct {
    const Self = @This();
    vertices: std.ArrayList(CubeVert),
    indicies: std.ArrayList(u32),

    shader: glID,
    texture: Texture,
    vao: c_uint = undefined,
    vbo: c_uint = undefined,
    ebo: c_uint = undefined,

    pub fn setData(self: *Self) void {
        c.glBindVertexArray(self.vao);
        GL.bufferData(c.GL_ARRAY_BUFFER, self.vbo, CubeVert, self.vertices.items);
        GL.bufferData(c.GL_ELEMENT_ARRAY_BUFFER, self.ebo, u32, self.indicies.items);
    }

    pub fn drawSimple(b: *Self, view: za.Mat4, model: za.Mat4, shader: glID) void {
        c.glUseProgram(shader);
        GL.passUniform(b.shader, "view", view);
        GL.passUniform(b.shader, "model", model);

        c.glBindVertexArray(b.vao);
        c.glDrawElements(c.GL_TRIANGLES, @as(c_int, @intCast(b.indicies.items.len)), c.GL_UNSIGNED_INT, null);
    }

    pub fn draw(b: *Self, view: za.Mat4, model: za.Mat4) void {
        c.glUseProgram(b.shader);
        const diffuse_loc = c.glGetUniformLocation(b.shader, "diffuse_texture");

        c.glUniform1i(diffuse_loc, 0);
        c.glActiveTexture(c.GL_TEXTURE0 + 0);
        c.glBindTexture(c.GL_TEXTURE_2D, b.texture.id);

        GL.passUniform(b.shader, "view", view);
        GL.passUniform(b.shader, "model", model);

        c.glBindVertexArray(b.vao);
        c.glDrawElements(c.GL_TRIANGLES, @as(c_int, @intCast(b.indicies.items.len)), c.GL_UNSIGNED_INT, null);
        c.glActiveTexture(c.GL_TEXTURE0);
    }

    pub fn init(alloc: Alloc, texture: Texture, shader: glID) @This() {
        var ret = Self{
            .vertices = std.ArrayList(CubeVert).init(alloc),
            .indicies = std.ArrayList(u32).init(alloc),
            .texture = texture,
            .shader = shader,
        };

        c.glGenVertexArrays(1, &ret.vao);
        c.glGenBuffers(1, &ret.vbo);
        c.glGenBuffers(1, &ret.ebo);

        GL.floatVertexAttrib(ret.vao, ret.vbo, 0, 3, CubeVert, "x"); //XYZ
        GL.floatVertexAttrib(ret.vao, ret.vbo, 1, 2, CubeVert, "u"); //RGBA
        GL.floatVertexAttrib(ret.vao, ret.vbo, 2, 3, CubeVert, "nx"); //RGBA
        GL.intVertexAttrib(ret.vao, ret.vbo, 3, 1, CubeVert, "color", c.GL_UNSIGNED_INT);
        GL.floatVertexAttrib(ret.vao, ret.vbo, 4, 3, CubeVert, "tx");
        GL.intVertexAttrib(ret.vao, ret.vbo, 5, 1, CubeVert, "ti", c.GL_UNSIGNED_SHORT);

        c.glBindVertexArray(ret.vao);
        GL.bufferData(c.GL_ARRAY_BUFFER, ret.vbo, CubeVert, ret.vertices.items);
        GL.bufferData(c.GL_ELEMENT_ARRAY_BUFFER, ret.ebo, u32, ret.indicies.items);
        return ret;
    }

    //pub fn shaded_cube(self: *Self, pos: Vec3f, extents: Vec3f, tr: Rect) !void {
    //    const p = pos;
    //    const e = extents;
    //    const white = charColorToFloat(itc(0xffffffff));
    //    const u = normalizeTexRect(tr, @as(i32, @intCast(self.texture.w)), @as(i32, @intCast(self.texture.h)));
    //    try self.vertices.appendSlice(&.{
    //        vertexTextured(p.x, p.y, p.z, u.x, u.y, white),
    //        vertexTextured(p.x, p.y, p.z + e.z, u.x, u.y, white),
    //    });
    //}
    pub fn cubeVec(self: *Self, pos: anytype, scale: anytype, tr: Rect) !void {
        try self.cube(
            lcast(f32, pos.x),
            lcast(f32, pos.y),
            lcast(f32, pos.z),
            lcast(f32, scale.x),
            lcast(f32, scale.y),
            lcast(f32, scale.z),
            tr,
            null,
        );
    }

    pub fn cube(self: *Self, px: f32, py: f32, pz: f32, sx: f32, sy: f32, sz: f32, tr: Rect, ti: u16) !void {
        try self.cubeExtra(px, py, pz, sx, sy, sz, tr, ti, [_]u32{0xffffffff} ** 6);
    }

    pub fn cubeExtra(self: *Self, px: f32, py: f32, pz: f32, sx: f32, sy: f32, sz: f32, tr: Rect, ti: u16, colors: ?[6]u32) !void {
        const tx_w = self.texture.w;
        const tx_h = self.texture.h;
        const cc = colors orelse [_]u32{0xffffffff} ** 6;
        const un = GL.normalizeTexRect(tr, @as(i32, @intCast(tx_w)), @as(i32, @intCast(tx_h)));
        try self.indicies.appendSlice(&GL.genCubeIndicies(@as(u32, @intCast(self.vertices.items.len))));
        const nx = sx / tr.w * 512;
        const ny = sy / tr.h * 512;
        const nz = sz / tr.w * 512;

        const uxx = (un.x + un.w) * nx;
        const uyy = (un.y + un.h) * ny;
        const uzz = (un.x + un.w) * nz;
        // zig fmt: off
    try self.vertices.appendSlice(&.{
        // front
        cubeVert(px + sx, py + sy, pz, uxx, uyy, 0,0,-1, cc[0], 1,0,0,ti), //0
        cubeVert(px + sx, py     , pz, uxx, un.y       , 0,0,-1, cc[0], 1,0,0,ti), //1
        cubeVert(px     , py     , pz, un.x       , un.y       , 0,0,-1, cc[0], 1,0,0,ti), //2
        cubeVert(px     , py + sy, pz, un.x       , uyy, 0,0,-1, cc[0], 1,0,0,ti), //3

        // back
        cubeVert(px     , py + sy, pz + sz, un.x       , (un.y + un.h) * ny, 0,0,1, cc[1], 1,0,0,ti), //3
        cubeVert(px     , py     , pz + sz, un.x       , un.y       , 0,0,1, cc[1], 1,0,0,ti), //2
        cubeVert(px + sx, py     , pz + sz, (un.x + un.w) * nx, un.y       , 0,0,1, cc[1], 1,0,0,ti), //1
        cubeVert(px + sx, py + sy, pz + sz, (un.x + un.w) * nx, (un.y + un.h) * ny, 0,0,1, cc[1], 1,0,0,ti), //0


        cubeVert(px + sx, py, pz,      uxx,un.x, 0,-1,0,      cc[2], 1,0,0,ti),
        cubeVert(px + sx, py, pz + sz, uxx,uzz,        0,-1,0,      cc[2], 1,0,0,ti),
        cubeVert(px     , py, pz + sz, un.x,uzz,             0,-1,0,      cc[2], 1,0,0,ti),
        cubeVert(px     , py, pz     , un.x,un.y + un.h,      0,-1,0,      cc[2], 1,0,0,ti),

        cubeVert(px     , py + sy, pz     , un.x,un.y ,        0,1,0,   cc[3], 1,0,0,ti),
        cubeVert(px     , py + sy, pz + sz, un.x,(un.y + un.w) * nz,               0,1,0,   cc[3], 1,0,0,ti),
        cubeVert(px + sx, py + sy, pz + sz, (un.x + un.w) * nx,(un.y + un.w) * nz,        0,1,0,   cc[3], 1,0,0,ti),
        cubeVert(px + sx, py + sy, pz, (un.x + un.w) * nx,   un.y  ,  0,1,0,   cc[3], 1,0,0,ti),

        cubeVert(px, py + sy, pz, un.x + un.w,un.y + un.h,   -1,0,0,   cc[4], 0,1,0,ti),
        cubeVert(px, py , pz, un.x + un.w,un.y,              -1,0,0,   cc[4], 0,1,0,ti),
        cubeVert(px, py , pz + sz, un.x,un.y,                -1,0,0,   cc[4], 0,1,0,ti),
        cubeVert(px, py + sy , pz + sz, un.x,un.y + un.h,    -1,0,0,   cc[4], 0,1,0,ti),

        cubeVert(px + sx, py + sy , pz + sz , un.x       ,  un.y + un.h,     1,0,0, cc[5], 0,-1,0,ti),
        cubeVert(px + sx, py      , pz + sz , un.x       ,  un.y,            1,0,0, cc[5], 0,-1,0,ti),
        cubeVert(px + sx, py      , pz      , un.x + un.w,  un.y,            1,0,0, cc[5], 0,-1,0,ti),
        cubeVert(px + sx, py + sy , pz      , un.x + un.w,  un.y + un.h,     1,0,0, cc[5], 0,-1,0,ti),


    });
    // zig fmt: on

    }

    pub fn clear(self: *Self) void {
        self.vertices.clearRetainingCapacity();
        self.indicies.clearRetainingCapacity();
    }

    pub fn deinit(self: *Self) void {
        self.vertices.deinit();
        self.indicies.deinit();
    }
};
