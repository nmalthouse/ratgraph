const std = @import("std");
const font = @import("font.zig");
const sdl = @import("SDL.zig");
const c = @import("c.zig").c;
const Glyph = font.Glyph;
const PROFILE = true;

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

    ftlib: c.FT_Library,
    face: c.FT_Face,

    SF: f32 = 0,

    file_slice: ?std.ArrayList(u8) = null,
    param: InitParams,

    pub fn deinit(self: *Self) void {
        self.glyphs.deinit();
        self.scratch_bmp.deinit();
        self.bitmap.deinit();
        self.font.texture.deinit();
        if (self.file_slice) |fs|
            fs.deinit();
    }

    pub fn init(alloc: std.mem.Allocator, dir: std.fs.Dir, filename: []const u8, pixel_size: f32, params: InitParams) !Self {
        const infile = try dir.openFile(filename, .{});
        defer infile.close();
        var slice_list = std.ArrayList(u8).init(alloc);
        try infile.reader().readAllArrayList(&slice_list, std.math.maxInt(usize));

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
        var finfo: c.stbtt_fontinfo = undefined;
        _ = c.stbtt_InitFont(&finfo, @as([*c]const u8, @ptrCast(buf)), c.stbtt_GetFontOffsetForIndex(&buf[0], 0));

        const SF = c.stbtt_ScaleForPixelHeight(&finfo, pixel_size);
        var result = OnlineFont{
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
            .finfo = finfo,
            .scratch_bmp = try font.Bitmap.initBlank(alloc, 10, 10, .g_8),
            .bitmap = undefined,
        };
        if (PROFILE) {
            result.timer = try std.time.Timer.start();
            result.time = 0;
        }

        {
            var x0: c_int = 0;
            var y0: c_int = 0;
            var x1: c_int = 0;
            var y1: c_int = 0;
            c.stbtt_GetFontBoundingBox(&finfo, &x0, &y0, &x1, &y1);

            result.cell_width = @intFromFloat(@abs(@ceil(@as(f32, @floatFromInt(x1)) * SF) - @ceil(@as(f32, @floatFromInt(x0)) * SF)));
            result.cell_height = @intFromFloat(@abs(@ceil(@as(f32, @floatFromInt(y1)) * SF) - @ceil(@as(f32, @floatFromInt(y0)) * SF)));
        }
        result.font.texture = font.Texture.initFromBuffer(null, result.cell_width * ww, result.cell_height * ww, .{
            .pixel_store_alignment = 1,
            .internal_format = c.GL_RED,
            .pixel_format = c.GL_RED,
            .min_filter = c.GL_LINEAR,
            .mag_filter = c.GL_LINEAR_MIPMAP_LINEAR,
        });
        result.bitmap = try font.Bitmap.initBlank(alloc, result.cell_width * ww, result.cell_height * ww, .g_8);

        {
            var ascent: c_int = 0;
            var descent: c_int = 0;
            var line_gap: c_int = 0;
            c.stbtt_GetFontVMetrics(&finfo, &ascent, &descent, &line_gap);

            result.font.ascent = @as(f32, @floatFromInt(ascent)) * SF;
            result.font.descent = @as(f32, @floatFromInt(descent)) * SF;
            result.font.height = result.font.ascent - result.font.descent;
            result.font.line_gap = result.font.height + @as(f32, @floatFromInt(line_gap)) * SF;
        }
        _ = result.font.getGlyph(std.unicode.replacement_character);

        return result;
    }

    pub fn syncBitmapToGL(self: *Self) void {
        if (!self.bitmap_dirty) return;
        if (PROFILE)
            self.timer.reset();
        self.bitmap_dirty = false;
        c.glPixelStorei(c.GL_UNPACK_ALIGNMENT, 1);
        c.glBindTexture(c.GL_TEXTURE_2D, self.font.texture.id);
        c.glTexImage2D(
            c.GL_TEXTURE_2D,
            0,
            c.GL_RED,
            @intCast(self.bitmap.w),
            @intCast(self.bitmap.h),
            0,
            c.GL_RED,
            c.GL_UNSIGNED_BYTE,
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
            if (c.stbtt_FindGlyphIndex(&self.finfo, codepoint) == 0) {}
            var x: c_int = 0;
            var y: c_int = 0;
            var xf: c_int = 0;
            var yf: c_int = 0;
            c.stbtt_GetCodepointBitmapBox(&self.finfo, cpo, SF, SF, &x, &y, &xf, &yf);
            const w: f32 = @floatFromInt(xf - x);
            const h: f32 = @floatFromInt(yf - y);
            const atlas_cx = @mod(self.cindex, self.cx);
            const atlas_cy = @divTrunc(self.cindex, self.cy);
            if (xf - x > 0 and yf - y > 0) {
                //var bmp = try Bitmap.initBlank(alloc, xf - x, yf - y, .g_8);
                c.stbtt_MakeCodepointBitmap(
                    &self.finfo,
                    &self.bitmap.data.items[@intCast(atlas_cy * self.cell_height * @as(i32, @intCast(self.bitmap.w)) + atlas_cx * self.cell_width)],
                    xf - x,
                    yf - y,
                    @intCast(self.bitmap.w),
                    //xf - x,
                    SF,
                    SF,
                    cpo,
                );
            }

            var adv_w: c_int = 0;
            var left_side_bearing: c_int = 0;
            c.stbtt_GetCodepointHMetrics(&self.finfo, cpo, &adv_w, &left_side_bearing);
            var glyph = Glyph{
                .tr = .{ .x = -1, .y = -1, .w = w, .h = h },
                .offset_x = @as(f32, @floatFromInt(left_side_bearing)) * SF,
                .offset_y = -@as(f32, @floatFromInt(y)),
                .advance_x = @as(f32, @floatFromInt(adv_w)) * SF,
                .width = w,
                .height = h,
            };
            self.bitmap_dirty = true;
            {
                glyph.tr.x = @floatFromInt(atlas_cx * self.cell_width);
                glyph.tr.y = @floatFromInt(atlas_cy * self.cell_height);
                self.cindex = @mod(self.cindex + 1, ww * ww);
                if (PROFILE) {
                    self.time += self.timer.read();
                }
            }
            self.glyphs.put(cpo, glyph) catch unreachable;
            return glyph;
            //bake the glyph
        };
    }
};
