const std = @import("std");
const mz = @import("graphics/c.zig").miniz;

const Status = enum(c_int) {
    ok = mz.MZ_OK,
    stream_end = mz.MZ_STREAM_END,
    stream_error = mz.MZ_STREAM_ERROR,
    param_error = mz.MZ_PARAM_ERROR,
    buf_error = mz.MZ_BUF_ERROR,
    mem_error = mz.MZ_MEM_ERROR,
    _,
};

pub fn writeGzipHeader(writer: anytype) !void {
    const gzipHeader = [_]u8{ 0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03 };
    try writer.writeAll(&gzipHeader);
}

const AllocWrap = struct {
    const _align = std.mem.Alignment.@"1";
    alloc: std.mem.Allocator,

    map: std.AutoHashMapUnmanaged(*anyopaque, usize) = .{},

    pub export fn alloc_fn(opaque_self: ?*anyopaque, count: usize, size: usize) ?*anyopaque {
        const self: *@This() = @ptrCast(@alignCast(opaque_self orelse return null));
        const length = count * size;
        const raw = self.alloc.rawAlloc(length, _align, 0) orelse return null;
        const item: *anyopaque = @ptrCast(raw);
        self.map.put(self.alloc, item, length) catch {
            self.alloc.rawFree(raw[0..length], _align, 0);
            return null;
        };
        return item;
    }

    pub export fn free_fn(opaque_self: ?*anyopaque, addr_o: ?*anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(opaque_self orelse return));

        const addr = addr_o orelse return;
        const mp: [*]u8 = @ptrCast(addr);

        if (self.map.get(addr)) |len| {
            const slice = mp[0..len];
            self.alloc.rawFree(slice, _align, 0);
        }
    }

    pub fn deinit(self: *@This()) void {
        self.map.deinit(self.alloc);
    }
};

pub fn compressGzip(alloc: std.mem.Allocator, input: []const u8, wr: anytype) !void {
    var awrap = AllocWrap{ .alloc = alloc };
    defer awrap.deinit();

    var out: [65535]u8 = undefined;
    var stream: mz.mz_stream = .{
        .next_in = &input[0],
        .avail_in = @intCast(input.len),
        .total_in = 0,

        .next_out = &out[0],
        .avail_out = @intCast(out.len),
        .total_out = 0,

        .msg = null,
        .state = null,
        .zalloc = AllocWrap.alloc_fn,
        .zfree = AllocWrap.free_fn,
        .@"opaque" = @ptrCast(&awrap),
        .data_type = 0,
        .adler = 0,
        .reserved = 0,
    };

    try writeGzipHeader(wr);

    const defel: Status = @enumFromInt(mz.mz_deflateInit2(
        &stream,
        mz.MZ_BEST_COMPRESSION,
        mz.MZ_DEFLATED,
        -mz.MZ_DEFAULT_WINDOW_BITS,
        8,
        mz.MZ_DEFAULT_STRATEGY,
    ));
    if (defel != .ok)
        return error.init;

    while (true) {
        const s: Status = @enumFromInt(mz.mz_deflate(&stream, mz.MZ_FINISH));
        switch (s) {
            .stream_end => break,
            else => return error.broken,
            .ok => {
                stream.next_out = &out[0];
                stream.avail_out = out.len;
                try wr.writeAll(&out);
            },
        }
    }
    try wr.writeAll(out[0 .. out.len - stream.avail_out]);
    var bits: [4]u8 = undefined;

    const crc = mz.mz_crc32(mz.mz_crc32(0, null, 0), &input[0], input.len);

    std.mem.writeInt(u32, &bits, @intCast(crc & 0xffffffff), .little);
    try wr.writeAll(&bits);

    std.mem.writeInt(u32, &bits, @intCast(input.len), .little);
    try wr.writeAll(&bits);
    _ = mz.mz_deflateEnd(&stream);
}

//tdefl_compress
//tdefl_compress_normal
