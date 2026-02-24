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

    pub fn toGLFormat(self: ImageFormat) gl.@"enum" {
        return switch (self) {
            .rgba_8 => gl.RGBA,
            .g_8 => gl.RED,
            .rgb_8 => gl.RGB,
            .ga_8 => gl.RG,
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

    pub fn toGLType(self: ImageFormat) gl.@"enum" {
        return switch (self) {
            else => gl.UNSIGNED_BYTE,
        };
    }
};

format: ImageFormat = .rgba_8,
alloc: std.mem.Allocator,
data: std.ArrayList(u8),
w: u32,
h: u32,

pub fn rect(self: Bitmap) Rect {
    return Rec(0, 0, self.w, self.h);
}

pub fn initBlank(alloc: std.mem.Allocator, width: anytype, height: anytype, format: ImageFormat) !Bitmap {
    const h = lcast(u32, height);
    const w = lcast(u32, width);
    var ret = Bitmap{ .format = format, .data = .{}, .w = lcast(u32, width), .h = lcast(u32, height), .alloc = alloc };
    try ret.data.appendNTimes(alloc, 0, w * h * ImageFormat.toChannelCount(format));
    return ret;
}

pub fn initFromBuffer(alloc: std.mem.Allocator, buffer: []const u8, width: anytype, height: anytype, format: ImageFormat) !Bitmap {
    const copy = try alloc.dupe(u8, buffer);
    return Bitmap{ .data = .fromOwnedSlice(copy), .w = lcast(u32, width), .h = lcast(u32, height), .format = format, .alloc = alloc };
}

pub fn initFromPngBuffer(alloc: std.mem.Allocator, buffer: []const u8) !Bitmap {
    const pngctx = c.spng_ctx_new(0);
    defer c.spng_ctx_free(pngctx);
    try spngError(c.spng_set_png_buffer(pngctx, &buffer[0], buffer.len));

    var ihdr: c.spng_ihdr = undefined;
    try spngError(c.spng_get_ihdr(pngctx, &ihdr));
    //ihdr.bit_depth;
    //ihdr.color_type;
    const fmt: ImageFormat = switch (ihdr.color_type) {
        c.SPNG_COLOR_TYPE_GRAYSCALE => .g_8,
        c.SPNG_COLOR_TYPE_GRAYSCALE_ALPHA => .rgba_8,
        c.SPNG_COLOR_TYPE_TRUECOLOR => .rgba_8,
        c.SPNG_COLOR_TYPE_TRUECOLOR_ALPHA => .rgba_8,
        c.SPNG_COLOR_TYPE_INDEXED => .rgba_8,
        else => return error.unsupportedColorFormat,
    };

    var out_size: usize = 0;
    try spngError(c.spng_decoded_image_size(pngctx, @intCast(@intFromEnum(fmt)), &out_size));

    const decoded_data = try alloc.alloc(u8, out_size);

    try spngError(c.spng_decode_image(pngctx, &decoded_data[0], out_size, @intCast(@intFromEnum(fmt)), 0));

    return Bitmap{ .format = fmt, .w = ihdr.width, .h = ihdr.height, .data = .fromOwnedSlice(decoded_data), .alloc = alloc };
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

pub fn initFromPngFile(alloc: std.mem.Allocator, dir: std.fs.Dir, sub_path: []const u8) !Bitmap {
    const file_slice = try dir.readFileAlloc(alloc, sub_path, std.math.maxInt(usize));
    defer alloc.free(file_slice);

    return try initFromPngBuffer(alloc, file_slice);
}

pub fn initFromImageFile(alloc: std.mem.Allocator, dir: std.fs.Dir, sub_path: []const u8) !Bitmap {
    const file_slice = try dir.readFileAlloc(alloc, sub_path, std.math.maxInt(usize));
    defer alloc.free(file_slice);

    return try initFromImageBuffer(alloc, file_slice);
}

pub fn initFromImageBuffer(alloc: std.mem.Allocator, buffer: []const u8) !Bitmap {
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

pub fn deinit(self: *Bitmap) void {
    self.data.deinit(self.alloc);
}

pub fn resize(self: *Bitmap, new_width: anytype, new_height: anytype) !void {
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
    try self.data.resize(self.alloc, num_comp * w * h);
}

pub fn replaceColor(self: *Bitmap, color: u32, replacement: u32) void {
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

//assumes ctx is a *io.writer
fn stbi_write_func(ctx: ?*anyopaque, data: ?*anyopaque, size: c_int) callconv(.c) void {
    const wr: *std.io.Writer = @ptrCast(@alignCast(ctx orelse return));

    const dat: [*]u8 = @ptrCast(@alignCast(data orelse return));
    _ = wr.write(dat[0..@intCast(size)]) catch return;
}

pub fn writeToBmpFile(self: *Bitmap, dir: std.fs.Dir, file_name: []const u8) !void {
    const out = try dir.createFile(file_name, .{});
    defer out.close();
    var write_buf: [4096]u8 = undefined;
    var wr = out.writer(&write_buf);

    _ = c.stbi_write_tga_to_func(
        &stbi_write_func,
        @ptrCast(&wr.interface),
        @as(c_int, @intCast(self.w)),
        @as(c_int, @intCast(self.h)),
        self.format.toChannelCount(),
        @as([*c]u8, @ptrCast(self.data.items[0..self.data.items.len])),
    );
    try wr.interface.flush();
}

pub fn writeToPngFile(self: *Bitmap, dir: std.fs.Dir, sub_path: []const u8) !void {
    var out_file = try dir.createFile(sub_path, .{});
    defer out_file.close();
    var out_buf: [1024]u8 = undefined;
    var out_wr = out_file.writer(&out_buf);
    const pngctx = c.spng_ctx_new(c.SPNG_CTX_ENCODER);
    defer c.spng_ctx_free(pngctx);

    try spngError(c.spng_set_option(pngctx, c.SPNG_ENCODE_TO_BUFFER, 1));

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
    try spngError(c.spng_set_ihdr(pngctx, &ihdr));
    try spngError(c.spng_encode_image(pngctx, &self.data.items[0], self.data.items.len, c.SPNG_FMT_PNG, c.SPNG_ENCODE_FINALIZE));
    var png_size: usize = 0;
    const data = c.spng_get_png_buffer(pngctx, &png_size, &err);
    try spngError(err);
    if (data) |d| {
        const sl = @as([*]u8, @ptrCast(d));
        _ = try out_wr.interface.write(sl[0..png_size]);
        var c_alloc = std.heap.raw_c_allocator;
        c_alloc.free(sl[0..png_size]);
    } else {
        return error.failedToEncodePng;
    }
    try out_wr.interface.flush();
}

pub fn writeQoi(self: *Bitmap, wr: *std.io.Writer) !void {
    const alloc = self.alloc;
    var qd = c.qoi_desc{
        .width = self.w,
        .height = self.h,
        .channels = switch (self.format) {
            .rgba_8 => 4,
            .rgb_8 => 3,
            .g_8 => 3,
            .ga_8 => 4,
        },
        .colorspace = c.QOI_LINEAR,
    };
    var reencoded: std.ArrayList(u8) = .{};
    defer reencoded.deinit(alloc);
    var out_data = self.data.items;
    switch (self.format) {
        .rgba_8, .rgb_8 => {}, //Nothing to be done
        .g_8 => {
            try reencoded.resize(alloc, 3 * self.data.items.len);
            for (0..self.data.items.len) |i| {
                const ii = i * 3;
                reencoded.items[ii] = self.data.items[i];
                reencoded.items[ii + 1] = self.data.items[i];
                reencoded.items[ii + 2] = self.data.items[i];
            }

            out_data = reencoded.items;
        },
        .ga_8 => {
            if (self.data.items.len % 2 != 0) return error.invalidBitmap;
            const pxcount = @divExact(self.data.items.len, 2);
            try reencoded.resize(alloc, 4 * pxcount);
            for (0..pxcount) |i| {
                const in = i * 2;
                const ii = i * 4;
                reencoded.items[ii] = self.data.items[in];
                reencoded.items[ii + 1] = self.data.items[in];
                reencoded.items[ii + 2] = self.data.items[in];
                reencoded.items[ii + 3] = self.data.items[in + 1];
            }

            out_data = reencoded.items;
        },
    }

    var qoi_len: c_int = 0;
    if (c.qoi_encode(@ptrCast(out_data.ptr), &qd, &qoi_len)) |qoi_data| {
        const qoi_s: [*c]const u8 = @ptrCast(qoi_data);
        const qlen: usize = if (qoi_len > 0) @intCast(qoi_len) else 0;
        const slice: []const u8 = qoi_s[0..qlen];

        try wr.writeAll(slice);
        c.QOI_FREE(qoi_data);
    }
}

pub fn copySubR(dest: *Bitmap, des_x: u32, des_y: u32, source: *Bitmap, src_x: u32, src_y: u32, src_w: u32, src_h: u32) !void {
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

pub fn invertY(self: *Bitmap) !void {
    var new = std.ArrayList(u8){};
    try new.resize(self.alloc, self.data.items.len);
    const nchannel = self.format.toChannelCount();

    const w = nchannel * self.w;
    for (0..self.h) |hi| {
        const old_start = hi * self.w * nchannel;
        const new_start = (self.h - hi - 1) * self.w * nchannel;
        @memcpy(new.items[new_start .. new_start + w], self.data.items[old_start .. old_start + w]);
    }
    self.data.deinit(self.alloc);
    self.data = new;
}

fn spngError(errno: c_int) !void {
    if (errno == c.SPNG_OK) return;

    std.debug.print("spng error: {s}\n", .{c.spng_strerror(errno)});

    return error.spng;
}

const std = @import("std");
const lcast = std.math.lossyCast;
const c = @import("c.zig").c;
const Bitmap = @This();
const intToColor = ptypes.intToColor;
const gl = @import("gl");
const Rect = ptypes.Rect;
const ptypes = @import("types.zig");
const Rec = Rect.NewAny;
