const std = @import("std");
const font = @import("font.zig");
const sdl = @import("SDL.zig");
const c = @import("c.zig").c;
const gl = @import("gl");
const Glyph = font.Glyph;
const PROFILE = false;

pub const OnlineFont = struct {
    const Self = @This();

    pub const InitParams = struct {
        cell_count_w: i32 = 30,
    };

    timer: if (PROFILE) std.time.Timer else void = undefined,
    time: if (PROFILE) u64 else void = undefined,

    font: font.PublicFontInterface,
    glyphs: std.AutoHashMap(u21, Glyph),
    cell_width: i32,
    cell_height: i32,
    cx: i32 = 10,
    cy: i32 = 10,
    cindex: i32 = 0,
    scratch_bmp: font.Bitmap,
    bitmap: font.Bitmap,

    bitmap_dirty: bool = true,

    ftlib: c.FT_Library = undefined,
    face: c.FT_Face = undefined,

    SF: f32 = 0,

    alloc: std.mem.Allocator,
    file_slice: std.ArrayList(u8) = .{},
    param: InitParams,

    pub fn deinit(self: *Self) void {
        self.glyphs.deinit();
        self.scratch_bmp.deinit();
        self.bitmap.deinit();
        self.font.texture.deinit();
        self.file_slice.deinit(self.alloc);
    }

    pub fn init(alloc: std.mem.Allocator, dir: std.fs.Dir, filename: []const u8, pixel_size: f32, params: InitParams) !Self {
        const infile = try dir.openFile(filename, .{});
        defer infile.close();
        var slice_list: std.ArrayList(u8) = .{};
        var read_buf: [4096]u8 = undefined;
        var re = infile.reader(&read_buf);
        try re.interface.appendRemaining(alloc, &slice_list, .unlimited);

        var ret = try initFromBuffer(alloc, slice_list.items, pixel_size, params);
        ret.file_slice = slice_list;
        return ret;
    }

    pub fn dumpToPng(self: *Self, dir: std.fs.Dir, name: []const u8) !void {
        try self.bitmap.writeToPngFile(dir, name);
    }

    pub fn initFromBuffer(
        alloc: std.mem.Allocator,
        /// Buf must live as long as the returned object
        buf: []const u8,
        pixel_size: f32,
        params: InitParams,
    ) !Self {
        const ww = params.cell_count_w;

        const SF = 1.0;
        var result = OnlineFont{
            .alloc = alloc,
            .font = .{
                .getGlyphFn = &OnlineFont.getGlyph,
                .height = 0,
                .font_size = pixel_size,
                .texture = .{ .id = 0, .w = 0, .h = 0 },
                .ascent = 0,
                .descent = 0,
                .line_gap = 0,
            },
            .param = params,
            .glyphs = std.AutoHashMap(u21, Glyph).init(alloc),
            .cell_width = 0,
            .cell_height = 0,
            .SF = SF,
            .scratch_bmp = try font.Bitmap.initBlank(alloc, 10, 10, .g_8),
            .bitmap = undefined,
        };

        _ = c.FT_Init_FreeType(&result.ftlib);

        const open_args = c.FT_Open_Args{
            .flags = c.FT_OPEN_MEMORY,
            .memory_base = &buf[0],
            .memory_size = @intCast(buf.len),
            .pathname = null,
            .stream = null,
            .driver = null,
            .num_params = 0,
            .params = null,
        };
        _ = c.FT_Open_Face(result.ftlib, &open_args, 0, &result.face);

        var Req = c.FT_Size_RequestRec{
            .type = c.FT_SIZE_REQUEST_TYPE_NOMINAL,
            .width = 0,
            .height = @as(i32, @intFromFloat(pixel_size * 64)),
            .horiResolution = 0,
            .vertResolution = 0,
        };
        _ = c.FT_Request_Size(result.face, &Req);

        {
            const fr = result.face.*;
            result.font.ascent = @as(f32, @floatFromInt(fr.size.*.metrics.ascender)) / 64;
            result.font.descent = @as(f32, @floatFromInt(fr.size.*.metrics.descender)) / 64;
            const max_advance = @as(f32, @floatFromInt(fr.size.*.metrics.max_advance)) / 64;
            result.font.line_gap = @as(f32, @floatFromInt(fr.size.*.metrics.height)) / 64;
            result.font.height = result.font.ascent - result.font.descent;
            result.cell_width = @intFromFloat(max_advance);
            result.cell_height = @intFromFloat(result.font.height);
        }

        result.font.texture = font.Texture.initFromBuffer(null, result.cell_width * ww, result.cell_height * ww, .{
            .pixel_store_alignment = 1,
            .internal_format = gl.RED,
            .pixel_format = gl.RED,
            .min_filter = gl.LINEAR,
            .mag_filter = gl.LINEAR_MIPMAP_LINEAR,
        });
        result.bitmap = try font.Bitmap.initBlank(alloc, result.cell_width * ww, result.cell_height * ww, .g_8);

        _ = result.font.getGlyph(std.unicode.replacement_character);

        return result;
    }

    pub fn syncBitmapToGL(self: *Self) void {
        if (!self.bitmap_dirty) return;
        if (PROFILE)
            self.timer.reset();
        self.bitmap_dirty = false;
        gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1);
        gl.BindTexture(gl.TEXTURE_2D, self.font.texture.id);
        gl.TexImage2D(
            gl.TEXTURE_2D,
            0,
            gl.RED,
            @intCast(self.bitmap.w),
            @intCast(self.bitmap.h),
            0,
            gl.RED,
            gl.UNSIGNED_BYTE,
            &self.bitmap.data.items[0],
        );
        if (PROFILE) {
            self.time += self.timer.read();
            std.debug.print("rebuilt ofont in {d} us\n", .{self.time / std.time.ns_per_us});
            self.time = 0;
        }
    }

    pub fn getGlyph(font_i: *font.PublicFontInterface, codepoint: u21) font.Glyph {
        const self: *@This() = @fieldParentPtr("font", font_i);
        return self.glyphs.get(codepoint) orelse {
            if (PROFILE)
                self.timer.reset();
            const ww = self.param.cell_count_w;
            const cpo = codepoint;
            const SF = self.SF;
            _ = SF;
            const glyph_i = c.FT_Get_Char_Index(self.face, codepoint);

            _ = c.FT_Load_Glyph(self.face, glyph_i, c.FT_LOAD_DEFAULT);
            _ = c.FT_Render_Glyph(self.face.*.glyph, c.FT_RENDER_MODE_NORMAL);
            const metrics = &self.face.*.glyph.*.metrics;
            const bitmap = &(self.face.*.glyph.*.bitmap);
            var glyph = Glyph{
                .tr = .{ .x = -1, .y = -1, .w = @as(f32, @floatFromInt(bitmap.width)), .h = @as(f32, @floatFromInt(bitmap.rows)) },
                .offset_x = @as(f32, @floatFromInt(@divFloor(metrics.horiBearingX, 64))),
                .offset_y = @as(f32, @floatFromInt(@divFloor(metrics.horiBearingY, 64))),
                .advance_x = @as(f32, @floatFromInt(@divFloor(metrics.horiAdvance, 64))),
                .width = @as(f32, @floatFromInt(bitmap.width)),
                .height = @as(f32, @floatFromInt(bitmap.rows)),
            };
            if (bitmap.buffer == null) {
                self.glyphs.put(cpo, glyph) catch unreachable;
                return glyph;
            }

            const atlas_cx = @mod(self.cindex, self.cx);
            const atlas_cy = @divTrunc(self.cindex, self.cy);

            self.bitmap_dirty = true;
            {
                glyph.tr.x = @floatFromInt(atlas_cx * self.cell_width);
                glyph.tr.y = @floatFromInt(atlas_cy * self.cell_height);
                self.cindex = @mod(self.cindex + 1, ww * ww);
                if (PROFILE) {
                    self.time += self.timer.read();
                }
            }

            var bmp = font.Bitmap{
                .format = .g_8,
                .data = .{ .items = bitmap.buffer[0 .. bitmap.rows * bitmap.width], .capacity = undefined, .allocator = undefined },
                .w = bitmap.width,
                .h = bitmap.rows,
            };
            try self.bitmap.copySubR(@intFromFloat(glyph.tr.x), @intFromFloat(glyph.tr.y), &bmp, 0, 0, bitmap.width, bitmap.rows);

            self.glyphs.put(cpo, glyph) catch unreachable;
            return glyph;
            //bake the glyph
        };
    }
};
