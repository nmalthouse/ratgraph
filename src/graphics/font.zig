const std = @import("std");
const c = @import("c.zig").c;
const Alloc = std.mem.Allocator;
const Dir = std.fs.Dir;
const SparseSet = @import("sparse_set.zig").SparseSet;
const ptypes = @import("types.zig");
const GL = @import("gl.zig");
const Rect = ptypes.Rect;
const Vec2f = ptypes.Vec2f;
const Vec2i = ptypes.Vec2i;
const lcast = std.math.lossyCast;
const intToColor = ptypes.intToColor;
const glID = GL.glID;
const Rec = Rect.NewAny;

/// Any font type must implement the following methods or fields
pub const PublicFontInterface = struct {
    const Self = @This();
    pub const TextXWalker = struct {
        it: std.unicode.Utf8Iterator,
        font: *PublicFontInterface,
        scale: f32,

        pub fn next(tw: *@This()) ?struct { f32, u21 } {
            if (tw.it.nextCodepoint()) |ch| {
                const glyph = tw.font.getGlyph(ch);
                return .{ (glyph.advance_x) * tw.scale, ch };
            }
            return null;
        }

        pub fn index(tw: *const @This()) usize {
            return tw.it.i;
        }
    };

    //The units for all of these is pixels
    font_size: f32,
    height: f32,
    ascent: f32, //Farthest the font ascends above baseline
    descent: f32, //Farthest the font descends below baseline
    line_gap: f32, //Distance between one rows descent and next rows ascent
    //to get next baseline: ascent - descent + line_gap

    texture: Texture,
    getGlyphFn: *const fn (*Self, u21) Glyph,

    pub fn getGlyph(self: *Self, codepoint: u21) Glyph {
        return self.getGlyphFn(self, codepoint);
    }

    pub fn xWalker(self: *Self, string: []const u8, size_px: anytype) TextXWalker {
        const scale = lcast(f32, size_px) / self.font_size;
        return TextXWalker{
            .scale = scale,
            .font = self,
            .it = std.unicode.Utf8Iterator{ .bytes = string, .i = 0 },
        };
    }

    pub fn textBounds(self: *Self, string: []const u8, size_px: anytype) Vec2f {
        const scale = lcast(f32, size_px) / self.font_size;

        var x_bound: f32 = 0;
        var bounds = Vec2f{ .x = 0, .y = self.line_gap * scale };

        var it = std.unicode.Utf8Iterator{ .bytes = string, .i = 0 };
        var char = it.nextCodepoint();
        while (char != null) : (char = it.nextCodepoint()) {
            switch (char.?) {
                '\n' => {
                    bounds.y += self.line_gap * scale;
                    if (x_bound > bounds.x)
                        bounds.x = x_bound;
                    x_bound = 0;
                },
                else => {},
            }

            const glyph = self.getGlyph(char.?);

            x_bound += (glyph.advance_x) * scale;
        }

        if (x_bound > bounds.x)
            bounds.x = x_bound;

        return bounds;
    }

    pub fn nearestGlyphX(self: *Self, string: []const u8, size_px: f32, rel_coord: Vec2f, reject_extreme: bool) ?usize {
        //const scale = (size_px / self.dpi * 72) / self.font_size;
        const scale = size_px / self.font_size;
        //const scale = size_px / @as(f32, @floatFromInt(self.height));
        if (string.len == 0) return null;

        var x_bound: f32 = 0;
        var bounds = Vec2f{ .x = 0, .y = 0 };

        var it = std.unicode.Utf8Iterator{ .bytes = string, .i = 0 };
        var char = it.nextCodepoint();
        while (char != null) : (char = it.nextCodepoint()) {
            const glyph = self.getGlyph(char.?);
            const xw = glyph.advance_x * scale;
            const yw = self.line_gap * scale;

            switch (char.?) {
                '\n' => {
                    bounds.y += yw;
                    if (x_bound > bounds.x)
                        bounds.x = x_bound;
                    x_bound = 0;
                },
                else => {
                    const x = rel_coord.x;
                    //const y = rel_coord.y;
                    //if (x < x_bound + xw and x > x_bound and y < bounds.y + yw and y > bounds.y) {
                    if (x < x_bound + xw and x > x_bound) {
                        return it.i;
                    }
                },
            }

            x_bound += xw;
        }
        if (reject_extreme)
            return null;

        if (rel_coord.x > x_bound)
            return string.len;

        return 0;
    }
};

pub const OptionalFileWriter = struct {
    writer: ?std.fs.File.Writer = null,

    pub fn print(self: *OptionalFileWriter, comptime fmt: []const u8, args: anytype) !void {
        if (self.writer) |wr| {
            try wr.print(fmt, args);
        }
    }
};
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

//TODO document all the glyph fields
pub const Glyph = struct {
    offset_x: f32 = 0,
    offset_y: f32 = 0,
    advance_x: f32 = 0,
    tr: Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
    width: f32 = 0,
    height: f32 = 0,
};

pub const Font = struct {
    ///Used to specify what codepoints are to be loaded
    pub const CharMapEntry = union(enum) {
        unicode: u21, //A single codepoint
        list: []const u21,
        range: [2]u21, //A range of codepoints (inclusive)

        pub fn flattenList(entries: []const CharMapEntry, out: *std.ArrayList(u21)) !void {
            for (entries) |codepoint| {
                switch (codepoint) {
                    .list => |list| {
                        for (list) |cp| {
                            try out.append(cp);
                        }
                    },
                    .range => |range| {
                        var i = range[0];
                        while (i <= range[1]) : (i += 1) {
                            try out.append(i);
                        }
                    },
                    .unicode => |cp| {
                        try out.append(cp);
                    },
                }
            }
        }
    };
    pub const InitOptions = struct {
        codepoints_to_load: []const CharMapEntry = &(CharMaps.Default),
        padding_px: u32 = 2,
        pack_factor: f32 = 1.3,
        debug_dir: ?Dir = null,
    };

    pub const InitBitmapOptions = struct {
        sts: SubTileset,
        codepoints_to_load: []const CharMapEntry, //The codepoints this list expands to maps to indices in the SubtileSet
    };

    ///Define common character sets
    pub const CharMaps = struct {
        pub const AsciiUpperAlpha = [_]CharMapEntry{.{ .range = .{ 65, 90 } }};
        pub const AsciiLowerAlpha = [_]CharMapEntry{.{ .range = .{ 97, 122 } }};
        pub const AsciiNumeric = [_]CharMapEntry{.{ .range = .{ 48, 57 } }};
        pub const AsciiPunctiation = [_]CharMapEntry{ .{ .range = .{ 32, 47 } }, .{ .range = .{ 58, 64 } }, .{ .range = .{ 91, 96 } }, .{ .range = .{ 123, 126 } } };

        pub const AsciiExtended = [_]CharMapEntry{.{ .range = .{ 128, 254 } }};

        pub const EssentialUnicode = [_]CharMapEntry{ .{ .unicode = std.unicode.replacement_character }, .{ .unicode = 0x2026 } };

        pub const AsciiBasic = AsciiUpperAlpha ++ AsciiLowerAlpha ++ AsciiNumeric ++ AsciiPunctiation;
        pub const Default = AsciiBasic ++ EssentialUnicode;

        pub const Apple = [_]CharMapEntry{
            .{ .unicode = 0xF8FF },
            .{ .unicode = 0x1001B8 },
        };
    };

    font: PublicFontInterface,

    /// calls to glyphs.get is super slow so we store the most common characters in a lut, lower_ascii
    lower_ascii: []?Glyph,
    glyphs: std.AutoHashMap(u21, Glyph),
    max_advance: f32, //Unused, it seems

    const Self = @This();
    // This breaks it all!
    pub const padding: i32 = 0;

    fn freetypeLogErr(stream: anytype, error_code: c_int) !void {
        if (error_code == 0)
            return;

        var found = false;
        inline for (c.ft_errors) |err| {
            if (err.err_code == error_code) {
                found = true;
                if (err.err_msg) |msg| {
                    stream.print("Freetype: Error {s}\n", .{msg}) catch return;
                }

                break;
            }
        }

        if (!found)
            stream.print("Freetype: Error code not found in table: {d}\n", .{error_code}) catch return;

        return error.freetype;
    }

    pub fn initFixed(alloc: Alloc, bmp: Bitmap, options: InitBitmapOptions) !Font {
        const codepoints_i: []u21 = blk: {
            var glyph_indices = std.ArrayList(u21).init(alloc);
            try CharMapEntry.flattenList(options.codepoints_to_load, &glyph_indices);
            try glyph_indices.append(std.unicode.replacement_character);
            break :blk try glyph_indices.toOwnedSlice();
        };
        defer alloc.free(codepoints_i);
        //const dense_slice = try alloc.alloc(Glyph, codepoints_i.len);
        var result = Font{
            .font = .{
                .getGlyphFn = &Font.getGlyph,
                .height = @floatFromInt(options.sts.th),
                .font_size = @floatFromInt(options.sts.th),
                .texture = .{ .id = 0, .w = 0, .h = 0 },
                .ascent = 0,
                .descent = 0,
                .line_gap = @floatFromInt(options.sts.th),
            },
            .max_advance = @floatFromInt(options.sts.tw),
            .glyphs = std.AutoHashMap(u21, Glyph).init(alloc),
        };
        for (codepoints_i, 0..) |item, i| {
            try result.glyphs.put(
                item,
                Glyph{
                    .width = @floatFromInt(options.sts.tw),
                    .height = @floatFromInt(options.sts.th),
                    .advance_x = @floatFromInt(options.sts.tw),
                    .tr = options.sts.getTexRec(i),
                },
            );
        }
        result.font.texture = Texture.initFromBitmap(bmp, .{ .mag_filter = c.GL_NEAREST });
        return result;
    }

    pub fn initStb(alloc: std.mem.Allocator, dir: std.fs.Dir, filename: []const u8, pixel_size: f32, options: InitOptions) !Font {
        const infile = try dir.openFile(filename, .{});
        defer infile.close();
        const slice = try infile.reader().readAllAlloc(alloc, std.math.maxInt(usize));
        defer alloc.free(slice);
        return initFromBuffer(alloc, slice, pixel_size, options);
    }

    pub fn initFromBuffer(alloc: Alloc, buf: []const u8, pixel_size: f32, options: InitOptions) !Font {
        const pad = options.padding_px;
        const codepoints_i: []u21 = blk: {
            var glyph_indices = std.ArrayList(u21).init(alloc);
            try glyph_indices.append(std.unicode.replacement_character);
            try CharMapEntry.flattenList(options.codepoints_to_load, &glyph_indices);
            break :blk try glyph_indices.toOwnedSlice();
        };
        var finfo: c.stbtt_fontinfo = undefined;
        _ = c.stbtt_InitFont(&finfo, @as([*c]const u8, @ptrCast(buf)), c.stbtt_GetFontOffsetForIndex(&buf[0], 0));

        //var timer = try std.time.Timer.start();
        //For each codepoint to load
        //  render to a bitmap
        //  store the metrics in glyph
        //  do the pack
        //  return
        //const dense_slice = try alloc.alloc(Glyph, codepoints_i.len);
        defer alloc.free(codepoints_i);
        var result = Font{
            .font = .{
                .getGlyphFn = &Font.getGlyph,
                .height = 0,
                //.glyph_set = try (SparseSet(Glyph, u21).fromOwnedDenseSlice(alloc, dense_slice, codepoints_i)),
                .font_size = pixel_size,
                .texture = .{ .id = 0, .w = 0, .h = 0 },
                .ascent = 0,
                .descent = 0,
                .line_gap = 0,
            },
            .max_advance = 0,
            .lower_ascii = try alloc.alloc(?Glyph, 128),
            .glyphs = std.AutoHashMap(u21, Glyph).init(alloc),
        };
        for (0..result.lower_ascii.len) |i|
            result.lower_ascii[i] = null;
        errdefer result.glyphs.deinit();
        errdefer alloc.free(result.lower_ascii);
        const SF = c.stbtt_ScaleForPixelHeight(&finfo, pixel_size);

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

        var pack_ctx = RectPack.init(alloc);
        defer pack_ctx.deinit();

        var cop_lut = std.ArrayList(u21).init(alloc);
        defer cop_lut.deinit();
        var bitmaps = std.ArrayList(Bitmap).init(alloc);
        defer {
            for (bitmaps.items) |*bitmap|
                bitmap.deinit();
            bitmaps.deinit();
        }

        for (codepoints_i) |code_i| {
            if (c.stbtt_FindGlyphIndex(&finfo, code_i) == 0) {}
            var x: c_int = 0;
            var y: c_int = 0;
            var xf: c_int = 0;
            var yf: c_int = 0;
            c.stbtt_GetCodepointBitmapBox(&finfo, code_i, SF, SF, &x, &y, &xf, &yf);
            const w: f32 = @floatFromInt(xf - x);
            const h: f32 = @floatFromInt(yf - y);
            if (xf - x > 0 and yf - y > 0) {
                var bmp = try Bitmap.initBlank(alloc, xf - x, yf - y, .g_8);
                c.stbtt_MakeCodepointBitmap(&finfo, &bmp.data.items[0], xf - x, yf - y, xf - x, SF, SF, code_i);
                try bitmaps.append(bmp);
                try cop_lut.append(code_i);
                try pack_ctx.appendRect(bitmaps.items.len - 1, bmp.w + pad, bmp.h + pad);
            }

            var adv_w: c_int = 0;
            var left_side_bearing: c_int = 0;
            c.stbtt_GetCodepointHMetrics(&finfo, code_i, &adv_w, &left_side_bearing);
            const glyph = Glyph{
                .tr = .{ .x = -1, .y = -1, .w = w, .h = h },
                .offset_x = @as(f32, @floatFromInt(left_side_bearing)) * SF,
                .offset_y = -@as(f32, @floatFromInt(y)),
                .advance_x = @as(f32, @floatFromInt(adv_w)) * SF,
                .width = w,
                .height = h,
            };
            try result.putGlyph(code_i, glyph);
        }
        const out_size = try pack_ctx.packOptimalSize();
        var out_bmp = try Bitmap.initBlank(alloc, out_size.x, out_size.y, .g_8);
        defer out_bmp.deinit();
        for (pack_ctx.rects.items) |r| {
            const bmx = @as(u32, @intCast(r.x)) + pad;
            const bmy = @as(u32, @intCast(r.y)) + pad;
            const gbmp = &bitmaps.items[@intCast(r.id)];
            try Bitmap.copySubR(&out_bmp, bmx, bmy, gbmp, 0, 0, gbmp.w, gbmp.h);

            const g = result.getGlyphPointer(@intCast(cop_lut.items[@intCast(r.id)]));
            //const g = (result.glyphs.getPtr(@intCast(cop_lut.items[@intCast(r.id)]))).?;
            g.tr.x = @floatFromInt(bmx);
            g.tr.y = @floatFromInt(bmy);
        }
        //std.debug.print("took x ms {d}\n", .{@as(f32, @floatFromInt(timer.read() / pack_ctx.rects.items.len)) / std.time.ns_per_ms});

        //try out_bmp.writeToPngFile(std.fs.cwd(), "crass.png");
        result.font.texture = Texture.initFromBitmap(out_bmp, .{
            .pixel_store_alignment = 1,
            .internal_format = c.GL_RED,
            .pixel_format = c.GL_RED,
            .min_filter = c.GL_NEAREST,
            .mag_filter = c.GL_NEAREST,
            //c.GL_LINEAR_MIPMAP_LINEAR,
        });
        return result;
    }

    pub fn init(alloc: Alloc, dir: Dir, filename: []const u8, point_size: f32, options: InitOptions) !Self {
        const codepoints_i: []u21 = blk: {
            var glyph_indices = std.ArrayList(u21).init(alloc);
            try CharMapEntry.flattenList(options.codepoints_to_load, &glyph_indices);
            try glyph_indices.append(std.unicode.replacement_character);
            break :blk try glyph_indices.toOwnedSlice();
        };

        var log = OptionalFileWriter{};
        if (options.debug_dir) |ddir| {
            ddir.makeDir("bitmaps") catch |err| switch (err) {
                error.PathAlreadyExists => {},
                else => return err,
            };
            const font_log = try ddir.createFile("fontgen.log", .{ .truncate = true });
            log.writer = font_log.writer();
            //defer font_log.close();
            try log.print("zig: Init font with arguments:\nfilename: \"{s}\"\npoint_size: {d}\n", .{
                filename,
                point_size,
            });
        }
        //const dense_slice = try alloc.alloc(Glyph, codepoints_i.len);
        defer alloc.free(codepoints_i);
        var result = Font{
            .font = .{
                .getGlyphFn = &Font.getGlyph,
                .height = 0,
                //.glyph_set = try (SparseSet(Glyph, u21).fromOwnedDenseSlice(alloc, dense_slice, codepoints_i)),
                .font_size = point_size,
                .texture = .{ .id = 0, .w = 0, .h = 0 },
                .ascent = 0,
                .descent = 0,
                .line_gap = 0,
            },
            .max_advance = 0,
            .glyphs = std.AutoHashMap(u21, Glyph).init(alloc),
            .lower_ascii = try alloc.alloc(?Glyph, 128),
        };
        for (0..result.lower_ascii.len) |i|
            result.lower_ascii[i] = null;
        errdefer alloc.free(result.lower_ascii);
        errdefer result.glyphs.deinit();

        //TODO switch to using a grid rather than rect packing

        const stderr = std.io.getStdErr().writer();

        var ftlib: c.FT_Library = undefined;
        try freetypeLogErr(stderr, c.FT_Init_FreeType(&ftlib));

        var face: c.FT_Face = undefined;

        const infile = try dir.openFile(filename, .{});
        defer infile.close();
        const file_slice = try infile.reader().readAllAlloc(alloc, std.math.maxInt(usize));
        defer alloc.free(file_slice);

        {
            const open_args = c.FT_Open_Args{
                .flags = c.FT_OPEN_MEMORY,
                .memory_base = &file_slice[0],
                .memory_size = @intCast(file_slice.len),
                .pathname = null,
                .stream = null,
                .driver = null,
                .num_params = 0,
                .params = null,
            };

            const err_code = c.FT_Open_Face(ftlib, &open_args, 0, &face);

            //var path = std.ArrayList(u8).fromOwnedSlice(alloc, try dir.realpathAlloc(alloc, filename));
            //defer path.deinit();
            //try path.append(0);

            //FT_New_Face loads font file from filepathname
            //the face pointer should be destroyed with FT_Done_Face()
            {
                //const err_code = c.FT_New_Face(ftlib, @as([*:0]const u8, @ptrCast(path.items)), 0, &face);
                switch (err_code) {
                    c.FT_Err_Cannot_Open_Resource => return error.fucked,
                    else => try freetypeLogErr(stderr, err_code),
                }
            }

            try log.print("Freetype face: num_faces:  {d}\n", .{face.*.num_faces});
            try log.print("Freetype face: num_glyphs:  {d}\n", .{face.*.num_glyphs});
            try log.print("Freetype face: family_name:  {s}\n", .{face.*.family_name});
            try log.print("Freetype face: style_name:  {s}\n", .{face.*.style_name});
            try log.print("Freetype face: units_per_EM:  {d}\n", .{face.*.units_per_EM});
            try log.print("Freetype face: ascender :  {d}fu\n", .{face.*.ascender});
            try log.print("Freetype face: descender :  {d}fu\n", .{face.*.descender});
            try log.print("Freetype face: height :  {d}fu\n", .{face.*.height});
            try log.print("Freetype face: calculated height :  {d}fu\n", .{face.*.ascender - face.*.descender});
            try log.print("Freetype face: max_advance_width:  {d}fu\n", .{face.*.max_advance_width});
            try log.print("Freetype face: underline_position:  {d}fu\n", .{face.*.underline_position});
            try log.print("Freetype face: underline_thickness:  {d}fu\n", .{face.*.underline_thickness});

            //const xw = face.*.max_advance_width

            if (false) {
                const mask_item = struct { mask: c_long, str: []const u8 };

                const mask_list = [_]mask_item{
                    .{ .mask = c.FT_FACE_FLAG_SCALABLE, .str = "FT_FACE_FLAG_SCALABLE          " },
                    .{ .mask = c.FT_FACE_FLAG_FIXED_SIZES, .str = "FT_FACE_FLAG_FIXED_SIZES       " },
                    .{ .mask = c.FT_FACE_FLAG_FIXED_WIDTH, .str = "FT_FACE_FLAG_FIXED_WIDTH       " },
                    .{ .mask = c.FT_FACE_FLAG_SFNT, .str = "FT_FACE_FLAG_SFNT              " },
                    .{ .mask = c.FT_FACE_FLAG_HORIZONTAL, .str = "FT_FACE_FLAG_HORIZONTAL        " },
                    .{ .mask = c.FT_FACE_FLAG_VERTICAL, .str = "FT_FACE_FLAG_VERTICAL          " },
                    .{ .mask = c.FT_FACE_FLAG_KERNING, .str = "FT_FACE_FLAG_KERNING           " },
                    .{ .mask = c.FT_FACE_FLAG_FAST_GLYPHS, .str = "FT_FACE_FLAG_FAST_GLYPHS       " },
                    .{ .mask = c.FT_FACE_FLAG_MULTIPLE_MASTERS, .str = "FT_FACE_FLAG_MULTIPLE_MASTERS  " },
                    .{ .mask = c.FT_FACE_FLAG_GLYPH_NAMES, .str = "FT_FACE_FLAG_GLYPH_NAMES       " },
                    .{ .mask = c.FT_FACE_FLAG_EXTERNAL_STREAM, .str = "FT_FACE_FLAG_EXTERNAL_STREAM   " },
                    .{ .mask = c.FT_FACE_FLAG_HINTER, .str = "FT_FACE_FLAG_HINTER            " },
                    .{ .mask = c.FT_FACE_FLAG_CID_KEYED, .str = "FT_FACE_FLAG_CID_KEYED         " },
                    .{ .mask = c.FT_FACE_FLAG_TRICKY, .str = "FT_FACE_FLAG_TRICKY            " },
                    .{ .mask = c.FT_FACE_FLAG_COLOR, .str = "FT_FACE_FLAG_COLOR             " },
                    .{ .mask = c.FT_FACE_FLAG_VARIATION, .str = "FT_FACE_FLAG_VARIATION         " },
                    .{ .mask = c.FT_FACE_FLAG_SVG, .str = "FT_FACE_FLAG_SVG               " },
                    .{ .mask = c.FT_FACE_FLAG_SBIX, .str = "FT_FACE_FLAG_SBIX              " },
                    .{ .mask = c.FT_FACE_FLAG_SBIX_OVERLAY, .str = "FT_FACE_FLAG_SBIX_OVERLAY      " },
                };
                const flags = face.*.face_flags;
                try log.print("Freetype face_flags mask: {b}\n", .{flags});
                for (mask_list) |mask| {
                    if ((mask.mask & flags) != 0) {
                        try log.print("Freetype: {s}\n", .{mask.str});
                    }
                }
            }
        }
        //try freetypeLogErr(stderr, c.FT_Library_SetLcdFilter(ftlib, c.FT_LCD_FILTER_DEFAULT));

        try freetypeLogErr(
            stderr,
            c.FT_Set_Pixel_Sizes(face, 0, @intFromFloat(point_size)),
            //c.FT_Set_Char_Size(
            //    face,
            //    0,
            //    @as(c_int, @intFromFloat(point_size * 72 / dpi)) * 64, //expects a size in 1/64 of points, font_size is in points
            //    @intFromFloat(dpi),
            //    @intFromFloat(dpi),
            //),
        );
        var Req = c.FT_Size_RequestRec{
            .type = c.FT_SIZE_REQUEST_TYPE_NOMINAL,
            .width = 0,
            .height = @as(i32, @intFromFloat(point_size * 64)),
            .horiResolution = 0,
            .vertResolution = 0,
        };
        _ = c.FT_Request_Size(face, &Req);

        { //Logs all the glyphs in this font file
            var agindex: c.FT_UInt = 0;
            var charcode = c.FT_Get_First_Char(face, &agindex);
            var col: usize = 0;
            while (agindex != 0) {
                col += 1;
                if (col > 15) {
                    col = 0;
                    try log.print("\n", .{});
                }
                try log.print("[{x} {u}] ", .{ charcode, @as(u21, @intCast(charcode)) });

                charcode = c.FT_Get_Next_Char(face, charcode, &agindex);
            }
            try log.print("\n", .{});
        }

        const fr = face.*;

        result.font.ascent = @as(f32, @floatFromInt(fr.size.*.metrics.ascender)) / 64;
        result.font.descent = @as(f32, @floatFromInt(fr.size.*.metrics.descender)) / 64;
        result.max_advance = @as(f32, @floatFromInt(fr.size.*.metrics.max_advance)) / 64;
        result.font.line_gap = @as(f32, @floatFromInt(fr.size.*.metrics.height)) / 64;
        result.font.height = result.font.ascent - result.font.descent;
        //result.line_gap = result.ascent;

        try log.print("Freetype face: ascender:  {d}px\n", .{result.font.ascent});
        try log.print("Freetype face: descender:  {d}px\n", .{result.font.descent});
        try log.print("Freetype face: line_gap:  {d}px\n", .{result.font.line_gap});
        try log.print("Freetype face: x_ppem: {d}px\n", .{@as(f32, @floatFromInt(fr.size.*.metrics.x_ppem))});
        try log.print("Freetype face: y_ppem: {d}px\n", .{@as(f32, @floatFromInt(fr.size.*.metrics.y_ppem))});

        var pack_ctx = RectPack.init(alloc);
        defer pack_ctx.deinit();

        var bitmaps = std.ArrayList(Bitmap).init(alloc);
        defer {
            for (bitmaps.items) |*bitmap|
                bitmap.deinit();
            bitmaps.deinit();
        }

        var timer = try std.time.Timer.start();
        for (codepoints_i) |code_i| {
            const glyph_i = c.FT_Get_Char_Index(face, code_i);
            if (glyph_i == 0) {
                //std.debug.print("Undefined char index: {d} {x}\n", .{ codepoint.i, codepoint.i });
                continue;
            }

            try freetypeLogErr(stderr, c.FT_Load_Glyph(face, glyph_i, c.FT_LOAD_DEFAULT));
            try freetypeLogErr(stderr, c.FT_Render_Glyph(face.*.glyph, c.FT_RENDER_MODE_NORMAL));
            //freetypeLogErr(stderr, c.FT_Render_Glyph(face.*.glyph, c.FT_RENDER_MODE_LCD));

            const bitmap = &(face.*.glyph.*.bitmap);

            if (bitmap.width != 0 and bitmap.rows != 0) {
                if (options.debug_dir != null) {
                    var buf: [255]u8 = undefined;
                    var fbs = std.io.FixedBufferStream([]u8){ .buffer = &buf, .pos = 0 };
                    try fbs.writer().print("debug/bitmaps/{d}.bmp", .{glyph_i});
                    try fbs.writer().writeByte(0);
                    _ = c.stbi_write_bmp(
                        @as([*c]const u8, @ptrCast(fbs.getWritten())),
                        @as(c_int, @intCast(bitmap.width)),
                        @as(c_int, @intCast(bitmap.rows)),
                        1,
                        @as([*c]u8, @ptrCast(bitmap.buffer[0 .. bitmap.rows * bitmap.width])),
                    );
                }
                try bitmaps.append(try Bitmap.initFromBuffer(alloc, bitmap.buffer[0 .. bitmap.width * bitmap.rows], bitmap.width, bitmap.rows, .g_8));

                try pack_ctx.appendRect(code_i, bitmap.width + padding + padding, bitmap.rows + padding + padding);
            }
            const metrics = &face.*.glyph.*.metrics;
            {
                const g: u21 = @intCast(code_i);
                try log.print("Freetype glyph: {u} 0x{x}\n", .{ g, g });
                try log.print("\twidth:  {d} (1/64 px), {d} px\n", .{ metrics.width, @divFloor(metrics.width, 64) });
                try log.print("\theight: {d} (1/64 px), {d} px\n", .{ metrics.height, @divFloor(metrics.height, 64) });
                try log.print("\tbearingX: {d} (1/64 px), {d} px\n", .{ metrics.horiBearingX, @divFloor(metrics.horiBearingX, 64) });
                try log.print("\tbearingY: {d} (1/64 px), {d} px\n", .{ metrics.horiBearingY, @divFloor(metrics.horiBearingY, 64) });
                try log.print("\tadvance: {d} (1/64 px), {d} px\n", .{ metrics.horiAdvance, @divFloor(metrics.horiAdvance, 64) });
                //try log.print("\twidth: {d}\n", .{metrics.width});
            }

            //const fpad = @as(f32, @floatFromInt(padding));
            const fpad = 0;
            const glyph = Glyph{
                .tr = .{ .x = -1, .y = -1, .w = @as(f32, @floatFromInt(bitmap.width)) + fpad, .h = @as(f32, @floatFromInt(bitmap.rows)) + fpad },
                .offset_x = @as(f32, @floatFromInt(@divFloor(metrics.horiBearingX, 64))),
                .offset_y = @as(f32, @floatFromInt(@divFloor(metrics.horiBearingY, 64))),
                .advance_x = @as(f32, @floatFromInt(@divFloor(metrics.horiAdvance, 64))),
                .width = @as(f32, @floatFromInt(bitmap.width)),
                .height = @as(f32, @floatFromInt(bitmap.rows)),
                //.width = @as(f32, @floatFromInt(@divFloor(metrics.width, 64))),
                //.height = @as(f32, @floatFromInt(@divFloor(metrics.height, 64))),
            };
            try result.putGlyph(code_i, glyph);
        }

        const elapsed = timer.read();
        try log.print("Rendered {d} glyphs in {d} ms, {d} ms avg\n", .{ result.glyphs.count(), @as(f32, @floatFromInt(elapsed)) / std.time.ns_per_ms, @as(f32, @floatFromInt(elapsed)) / std.time.ns_per_ms / @as(f32, @floatFromInt(result.glyphs.count())) });
        //Each glyph takes up result.max_advance x result.line_gap + padding
        const w_c: i32 = @intFromFloat(@ceil(@sqrt(@as(f32, @floatFromInt(pack_ctx.rects.items.len)))));
        const g_width: i32 = @intFromFloat(result.max_advance);
        const g_height: i32 = @intFromFloat(result.font.height);
        result.font.texture.w = w_c * (padding + @as(i32, @intFromFloat(result.max_advance)));
        result.font.texture.h = w_c * (padding + g_height);
        var texture_bitmap = try Bitmap.initBlank(alloc, result.font.texture.w, result.font.texture.h, .g_8);
        defer texture_bitmap.deinit();

        //var xi:u32 = 0;
        //var yi:u32 = 0;
        const w_ci: i32 = @intCast(w_c);
        for (pack_ctx.rects.items, 0..) |rect, i| {
            const ii: i32 = @intCast(i);
            const gbmp = &bitmaps.items[i];
            const cx: u32 = @intCast(@mod(ii, w_ci) * (g_width + padding));
            const cy: u32 = @intCast(@divFloor(ii, w_ci) * (g_height + padding));
            const g = result.getGlyphPointer(@as(u21, @intCast(rect.id)));
            g.tr.x = @floatFromInt(cx);
            g.tr.y = @floatFromInt(cy);
            try Bitmap.copySubR(&texture_bitmap, cx, cy, gbmp, 0, 0, gbmp.w, gbmp.h);
        }
        if (options.debug_dir) |ddir| {
            var out = std.ArrayList(u8).init(alloc);
            defer out.deinit();
            try out.writer().print("freetype_{s}.png", .{filename});
            std.mem.replaceScalar(u8, out.items, '/', '.');
            std.debug.print("{s}\n", .{out.items});
            try texture_bitmap.writeToPngFile(ddir, out.items);
        }

        result.font.texture = Texture.initFromBitmap(texture_bitmap, .{
            .pixel_store_alignment = 1,
            .internal_format = c.GL_RED,
            .pixel_format = c.GL_RED,
            .min_filter = c.GL_LINEAR,
            .mag_filter = c.GL_NEAREST,
        });

        return result;
    }

    pub fn getGlyph(font_i: *PublicFontInterface, codepoint: u21) Glyph {
        const self: *@This() = @fieldParentPtr("font", font_i);
        if (codepoint < 128)
            return self.lower_ascii[codepoint] orelse self.glyphs.get(std.unicode.replacement_character) orelse .{};
        return self.glyphs.get(codepoint) orelse self.glyphs.get(std.unicode.replacement_character) orelse .{};
    }

    pub fn putGlyph(self: *Self, code_i: u21, glyph: Glyph) !void {
        if (code_i < 128) {
            self.lower_ascii[code_i] = glyph;
        } else {
            try self.glyphs.put(code_i, glyph);
        }
    }

    fn getGlyphPointer(self: *Self, code_i: u21) *Glyph {
        if (code_i < 128) {
            return &(self.lower_ascii[code_i].?);
        }
        return self.glyphs.getPtr(code_i).?;
    }

    pub fn deinit(self: *Self) void {
        self.glyphs.allocator.free(self.lower_ascii);
        self.glyphs.deinit();
    }
};

///Rectangle packing
///Usage:
///init()
///appendRect()s
///pack();
///rects.items now contains the arranged rectangles.
///deinit()
pub const RectPack = struct {
    const Self = @This();
    pub const RectType = c.stbrp_rect;
    const RectDimType = c_int;
    const NodeType = c.stbrp_node;
    const ExtraNodeCount = 200;
    const InitRectPos = 50;

    rects: std.ArrayList(RectType),
    nodes: std.ArrayList(NodeType),

    running_size: usize = 0,

    pub fn init(alloc: Alloc) Self {
        return Self{
            .rects = std.ArrayList(RectType).init(alloc),
            .nodes = std.ArrayList(NodeType).init(alloc),
        };
    }

    pub fn deinit(self: Self) void {
        self.rects.deinit();
        self.nodes.deinit();
    }

    pub fn appendRect(self: *Self, id: anytype, w: anytype, h: anytype) !void {
        try self.rects.append(.{
            .was_packed = 0,
            .id = @intCast(id),
            .x = InitRectPos,
            .y = InitRectPos,
            .w = std.math.lossyCast(RectDimType, w),
            .h = std.math.lossyCast(c_int, h),
        });
        self.running_size += std.math.lossyCast(usize, w * h);
    }

    pub fn packOptimalSize(self: *Self) !Vec2i {
        var safety_factor: f32 = 1.1;
        const safety_factor_inc = 0.3;
        const max_fails = 3;
        for (0..max_fails) |_| {
            const fsize: f32 = @floatFromInt(self.running_size);
            const w: u32 = @intFromFloat(@ceil(@sqrt(fsize)) * safety_factor);
            self.pack(w, w) catch |err| {
                switch (err) {
                    error.rectPackFailed => {
                        std.debug.print("Rect pack failed, trying again\n", .{});
                        safety_factor += safety_factor_inc;
                        continue;
                    },
                    else => return err,
                }
            };
            return Vec2i{ .x = @intCast(w), .y = @intCast(w) };
        }
        return error.rectPackFailed;
    }

    pub fn pack(self: *Self, parent_area_w: u32, parent_area_h: u32) !void {
        if (self.rects.items.len == 0)
            return;

        try self.nodes.resize(parent_area_w + ExtraNodeCount);
        var rect_ctx: c.stbrp_context = undefined;

        c.stbrp_init_target(
            &rect_ctx,
            @intCast(parent_area_w),
            @intCast(parent_area_h),
            @ptrCast(self.nodes.items[0..self.nodes.items.len]),
            @intCast(self.nodes.items.len),
        );

        const pack_err = c.stbrp_pack_rects(
            &rect_ctx,
            @ptrCast(self.rects.items[0 .. self.rects.items.len - 1]),
            @intCast(self.rects.items.len),
        );
        if (pack_err != 1)
            return error.rectPackFailed;
    }
};

//TODO The loading functions tend to break when format is not rgb or rgba.
//Stbi img load likes to segfault.
pub const Bitmap = struct {
    const Self = @This();
    pub const ImageFormat = enum(usize) {
        rgba_8 = c.SPNG_FMT_RGBA8,
        rgb_8 = c.SPNG_FMT_RGB8,
        g_8 = c.SPNG_FMT_G8, //grayscale, 8 bit
        ga_8 = c.SPNG_FMT_GA8,

        pub fn fromChannelCount(count: u8) ?ImageFormat {
            return switch (count) {
                4 => .rgba_8,
                3 => .rgb_8,
                1 => .g_8,
                2 => .ga_8,
                else => null,
            };
        }

        pub fn toGLFormat(self: ImageFormat) c.GLenum {
            return switch (self) {
                .rgba_8 => c.GL_RGBA,
                .g_8 => c.GL_RED,
                .rgb_8 => c.GL_RGB,
                .ga_8 => c.GL_RG,
            };
        }

        pub fn toChannelCount(self: ImageFormat) u8 {
            return switch (self) {
                .rgba_8 => 4,
                .g_8 => 1,
                .rgb_8 => 3,
                .ga_8 => 2,
            };
        }

        pub fn toGLType(self: ImageFormat) c.GLenum {
            return switch (self) {
                else => c.GL_UNSIGNED_BYTE,
            };
        }
    };

    format: ImageFormat = .rgba_8,
    data: std.ArrayList(u8),
    w: u32,
    h: u32,

    pub fn rect(self: Self) Rect {
        return Rec(0, 0, self.w, self.h);
    }

    pub fn initBlank(alloc: Alloc, width: anytype, height: anytype, format: ImageFormat) !Self {
        const h = lcast(u32, height);
        const w = lcast(u32, width);
        var ret = Self{ .format = format, .data = std.ArrayList(u8).init(alloc), .w = lcast(u32, width), .h = lcast(u32, height) };
        try ret.data.appendNTimes(0, w * h * ImageFormat.toChannelCount(format));
        return ret;
    }

    pub fn initFromBuffer(alloc: Alloc, buffer: []const u8, width: anytype, height: anytype, format: ImageFormat) !Bitmap {
        const copy = try alloc.dupe(u8, buffer);
        return Bitmap{ .data = std.ArrayList(u8).fromOwnedSlice(alloc, copy), .w = lcast(u32, width), .h = lcast(u32, height), .format = format };
    }

    pub fn initFromPngBuffer(alloc: Alloc, buffer: []const u8) !Bitmap {
        const pngctx = c.spng_ctx_new(0);
        defer c.spng_ctx_free(pngctx);
        _ = c.spng_set_png_buffer(pngctx, &buffer[0], buffer.len);

        var ihdr: c.spng_ihdr = undefined;
        _ = c.spng_get_ihdr(pngctx, &ihdr);
        //ihdr.bit_depth;
        //ihdr.color_type;
        const fmt: ImageFormat = switch (ihdr.color_type) {
            c.SPNG_COLOR_TYPE_GRAYSCALE => .rgba_8,
            c.SPNG_COLOR_TYPE_GRAYSCALE_ALPHA => .rgba_8,
            c.SPNG_COLOR_TYPE_TRUECOLOR => .rgba_8,
            c.SPNG_COLOR_TYPE_TRUECOLOR_ALPHA => .rgba_8,
            c.SPNG_COLOR_TYPE_INDEXED => .rgba_8,
            else => return error.unsupportedColorFormat,
        };

        var out_size: usize = 0;
        _ = c.spng_decoded_image_size(pngctx, @intCast(@intFromEnum(fmt)), &out_size);

        const decoded_data = try alloc.alloc(u8, out_size);

        _ = c.spng_decode_image(pngctx, &decoded_data[0], out_size, @intCast(@intFromEnum(fmt)), 0);

        return Bitmap{ .format = fmt, .w = ihdr.width, .h = ihdr.height, .data = std.ArrayList(u8).fromOwnedSlice(alloc, decoded_data) };
    }

    pub fn initFromQoiBuffer(alloc: std.mem.Allocator, qoi_buf: []const u8) !Bitmap {
        var qd: c.qoi_desc = undefined;

        const decoded = c.qoi_decode(&qoi_buf[0], @intCast(qoi_buf.len), &qd, 0) orelse return error.qoiFailed;
        defer c.QOI_FREE(decoded);

        const qoi_s: [*c]const u8 = @ptrCast(decoded);

        const qlen: usize = qd.width * qd.height * qd.channels;

        const slice: []const u8 = qoi_s[0..qlen];
        return initFromBuffer(alloc, slice, qd.width, qd.height, switch (qd.channels) {
            3 => .rgb_8,
            4 => .rgba_8,
            else => return error.qoiInvalidChannelCount,
        });
    }

    pub fn initFromPngFile(alloc: Alloc, dir: Dir, sub_path: []const u8) !Bitmap {
        const file_slice = try dir.readFileAlloc(alloc, sub_path, std.math.maxInt(usize));
        defer alloc.free(file_slice);

        return try initFromPngBuffer(alloc, file_slice);
    }

    pub fn initFromImageFile(alloc: Alloc, dir: Dir, sub_path: []const u8) !Bitmap {
        const file_slice = try dir.readFileAlloc(alloc, sub_path, std.math.maxInt(usize));
        defer alloc.free(file_slice);

        return try initFromImageBuffer(alloc, file_slice);
    }

    pub fn initFromImageBuffer(alloc: Alloc, buffer: []const u8) !Bitmap {
        var x: c_int = 0;
        var y: c_int = 0;
        var num_channel: c_int = 0;
        const img_buf = c.stbi_load_from_memory(&buffer[0], @intCast(buffer.len), &x, &y, &num_channel, 4);
        if (img_buf == null)
            return error.stbImageFailed;
        const len = @as(usize, @intCast(num_channel * x * y));
        const decoded = try alloc.alloc(u8, len);
        defer alloc.free(decoded);
        @memcpy(decoded, img_buf[0..len]);

        return try initFromBuffer(
            alloc,
            decoded,
            x,
            y,
            ImageFormat.fromChannelCount(@intCast(num_channel)) orelse return error.unsupportedFormat,
        );
    }

    pub fn deinit(self: Self) void {
        self.data.deinit();
    }

    pub fn resize(self: *Self, new_width: anytype, new_height: anytype) !void {
        const h = lcast(u32, new_height);
        const w = lcast(u32, new_width);

        self.w = w;
        self.h = h;
        const num_comp: u32 = switch (self.format) {
            .rgba_8 => 4,
            .g_8 => 1,
            .rgb_8 => 3,
            .ga_8 => 2,
        };
        try self.data.resize(num_comp * w * h);
    }

    pub fn replaceColor(self: *Self, color: u32, replacement: u32) void {
        if (self.format != .rgba_8) unreachable;
        const search = intToColor(color);
        const rep = intToColor(replacement);
        for (0..(self.data.items.len / 4)) |i| {
            const d = self.data.items[i * 4 .. i * 4 + 4];
            if (d[0] == search.r and d[1] == search.g and d[2] == search.b) {
                d[0] = rep.r;
                d[1] = rep.g;
                d[2] = rep.b;
                d[3] = rep.a;
            }
        }
    }

    pub fn writeToBmpFile(self: *Self, alloc: Alloc, dir: Dir, file_name: []const u8) !void {
        if (self.format != .rgba_8) return error.unsupportedFormat;
        var path = std.ArrayList(u8).fromOwnedSlice(alloc, try dir.realpathAlloc(alloc, file_name));
        defer path.deinit();
        try path.append(0);

        _ = c.stbi_write_bmp(@as([*c]const u8, @ptrCast(path.items)), @as(c_int, @intCast(self.w)), @as(c_int, @intCast(self.h)), 4, @as([*c]u8, @ptrCast(self.data.items[0..self.data.items.len])));
    }

    pub fn writeToPngFile(self: *Self, dir: Dir, sub_path: []const u8) !void {
        var out_file = try dir.createFile(sub_path, .{});
        defer out_file.close();
        const pngctx = c.spng_ctx_new(c.SPNG_CTX_ENCODER);
        defer c.spng_ctx_free(pngctx);

        _ = c.spng_set_option(pngctx, c.SPNG_ENCODE_TO_BUFFER, 1);

        var ihdr = c.spng_ihdr{
            .width = self.w,
            .height = self.h,
            .bit_depth = 8,
            .color_type = switch (self.format) {
                .rgb_8 => c.SPNG_COLOR_TYPE_TRUECOLOR,
                .rgba_8 => c.SPNG_COLOR_TYPE_TRUECOLOR_ALPHA,
                .g_8 => c.SPNG_COLOR_TYPE_GRAYSCALE,
                .ga_8 => c.SPNG_COLOR_TYPE_GRAYSCALE_ALPHA,
            },
            .compression_method = 0,
            .filter_method = 0,
            .interlace_method = 0,
        };
        var err: c_int = 0;
        err = c.spng_set_ihdr(pngctx, &ihdr);
        if (err != 0)
            std.debug.print("PNG error {s}\n", .{c.spng_strerror(err)});

        err = c.spng_encode_image(pngctx, &self.data.items[0], self.data.items.len, c.SPNG_FMT_PNG, c.SPNG_ENCODE_FINALIZE);
        if (err != 0)
            std.debug.print("PNG error {s}\n", .{c.spng_strerror(err)});
        var png_size: usize = 0;
        const data = c.spng_get_png_buffer(pngctx, &png_size, &err);
        if (err != 0)
            std.debug.print("PNG error {s}\n", .{c.spng_strerror(err)});
        if (data) |d| {
            const sl = @as([*]u8, @ptrCast(d));
            _ = try out_file.writer().write(sl[0..png_size]);
            var c_alloc = std.heap.raw_c_allocator;
            c_alloc.free(sl[0..png_size]);
        } else {
            return error.failedToEncodePng;
        }
    }

    pub fn copySubR(dest: *Self, des_x: u32, des_y: u32, source: *Self, src_x: u32, src_y: u32, src_w: u32, src_h: u32) !void {
        const num_component = ImageFormat.toChannelCount(dest.format);
        var sy = src_y;
        while (sy < src_y + src_h) : (sy += 1) {
            var sx = src_x;
            while (sx < src_x + src_w) : (sx += 1) {
                const source_i = ((sy * source.w) + sx) * num_component;

                const rel_y = sy - src_y;
                const rel_x = sx - src_x;

                const dest_i = (((des_y + rel_y) * dest.w) + rel_x + des_x) * num_component;

                var i: usize = 0;
                while (i < num_component) : (i += 1) {
                    dest.data.items[dest_i + i] = source.data.items[source_i + i];
                }
            }
        }
    }
};

pub const Texture = struct {
    id: glID,
    w: i32,
    h: i32,

    pub fn rect(t: Texture) Rect {
        return Rec(0, 0, t.w, t.h);
    }

    pub fn aspectRatio(t: Texture) f32 {
        return @as(f32, @floatFromInt(t.w)) / @as(f32, @floatFromInt(t.h));
    }

    pub const Options = struct {
        internal_format: c.GLint = c.GL_RGBA,
        pixel_format: c.GLenum = c.GL_RGBA,
        pixel_type: c.GLenum = c.GL_UNSIGNED_BYTE,
        pixel_store_alignment: c.GLint = 4,
        target: c.GLenum = c.GL_TEXTURE_2D,

        wrap_u: c.GLint = c.GL_REPEAT,
        wrap_v: c.GLint = c.GL_REPEAT,

        generate_mipmaps: bool = true,
        min_filter: c.GLint = c.GL_LINEAR_MIPMAP_LINEAR,
        mag_filter: c.GLint = c.GL_LINEAR,
        border_color: [4]f32 = .{ 0, 0, 0, 1.0 },
        is_compressed: bool = false,
    };

    //Todo write tests does this actually work
    pub fn initFromImgFile(alloc: Alloc, dir: Dir, sub_path: []const u8, o: Options) !Texture {
        var file = try dir.openFile(sub_path, .{});
        defer file.close();
        var header: [8]u8 = undefined;
        const len = try file.read(&header);
        const sl = header[0..len];
        const eql = std.mem.eql;
        if (eql(u8, &.{ 0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a }, sl)) {
            var bmp = try Bitmap.initFromPngFile(alloc, dir, sub_path);
            defer bmp.deinit();
            return initFromBitmap(bmp, o);
        } else {
            var bmp = try Bitmap.initFromImageFile(alloc, dir, sub_path);
            defer bmp.deinit();
            return initFromBitmap(bmp, o);
        }
        return error.unrecognizedImageFileFormat;
    }

    pub fn initFromBuffer(buffer: ?[]const u8, w: i32, h: i32, o: Options) Texture {
        var tex_id: glID = 0;
        c.glPixelStorei(c.GL_UNPACK_ALIGNMENT, o.pixel_store_alignment);
        c.glGenTextures(1, &tex_id);
        c.glBindTexture(o.target, tex_id);
        if (o.is_compressed) {
            c.glCompressedTexImage2D(
                o.target,
                0,
                o.pixel_format,
                w,
                h,
                0,
                @intCast(if (buffer) |bmp| bmp.len else 0),
                if (buffer) |bmp| &bmp[0] else null,
            );
        } else {
            c.glTexImage2D(
                o.target,
                0, //Level of detail number
                o.internal_format,
                w,
                h,
                0, //khronos.org: this value must be 0
                o.pixel_format,
                o.pixel_type,
                if (buffer) |bmp| &bmp[0] else null,
            );
        }
        if (o.generate_mipmaps)
            c.glGenerateMipmap(o.target);

        c.glTexParameteri(o.target, c.GL_TEXTURE_WRAP_S, o.wrap_u);
        c.glTexParameteri(o.target, c.GL_TEXTURE_WRAP_T, o.wrap_v);

        //c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST_MIPMAP_NEAREST);
        c.glTexParameteri(o.target, c.GL_TEXTURE_MIN_FILTER, o.min_filter);
        c.glTexParameteri(o.target, c.GL_TEXTURE_MAG_FILTER, o.mag_filter);

        c.glTexParameterfv(o.target, c.GL_TEXTURE_BORDER_COLOR, &o.border_color);

        c.glEnable(c.GL_BLEND);
        c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);
        c.glBlendEquation(c.GL_FUNC_ADD);

        c.glBindTexture(c.GL_TEXTURE_2D, 0);
        return Texture{ .w = w, .h = h, .id = tex_id };
    }

    pub fn initMipped(w: i32, h: i32, o: Options) Texture {
        var tex_id: glID = 0;
        c.glPixelStorei(c.GL_UNPACK_ALIGNMENT, o.pixel_store_alignment);
        c.glGenTextures(1, &tex_id);
        c.glBindTexture(o.target, tex_id);
        c.glTexParameteri(o.target, c.GL_TEXTURE_WRAP_S, o.wrap_u);
        c.glTexParameteri(o.target, c.GL_TEXTURE_WRAP_T, o.wrap_v);

        //c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST_MIPMAP_NEAREST);
        c.glTexParameteri(o.target, c.GL_TEXTURE_MIN_FILTER, o.min_filter);
        c.glTexParameteri(o.target, c.GL_TEXTURE_MAG_FILTER, o.mag_filter);

        c.glTexParameterfv(o.target, c.GL_TEXTURE_BORDER_COLOR, &o.border_color);
        c.glBindTexture(c.GL_TEXTURE_2D, 0);
        return Texture{ .w = w, .h = h, .id = tex_id };
    }

    pub fn setMipLevel(self: *const Texture, w: i32, h: i32, buffer: ?[]const u8, o: Options, level: c.GLint) void {
        c.glBindTexture(o.target, self.id);
        if (o.is_compressed) {
            c.glCompressedTexImage2D(
                o.target,
                level,
                o.pixel_format,
                w,
                h,
                0,
                @intCast(if (buffer) |bmp| bmp.len else 0),
                if (buffer) |bmp| &bmp[0] else null,
            );
        } else {
            c.glTexImage2D(
                o.target,
                level, //Level of detail number
                o.internal_format,
                w,
                h,
                0, //khronos.org: this value must be 0
                o.pixel_format,
                o.pixel_type,
                if (buffer) |bmp| &bmp[0] else null,
            );
        }
        c.glBindTexture(c.GL_TEXTURE_2D, 0);
    }

    pub fn initFromBitmap(bitmap: Bitmap, o: Options) Texture {
        var opt = o;
        opt.pixel_format = bitmap.format.toGLFormat();
        opt.pixel_type = bitmap.format.toGLType();
        return initFromBuffer(bitmap.data.items, @intCast(bitmap.w), @intCast(bitmap.h), opt);
    }

    pub fn initEmpty() Texture {
        return .{ .w = 0, .h = 0, .id = 0 };
    }

    pub fn deinit(self: *Texture) void {
        c.glDeleteTextures(1, &self.id);
    }
};
