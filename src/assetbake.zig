const std = @import("std");
const graph = @import("graphics.zig");
const Rect = graph.Rect;
const Tiled = @import("tiled.zig");
const ArgUtil = graph.ArgGen;

//TODO
//Have a top level json file that specifies how asset map should be loaded.
//I want to be able to disable directories from being added to tiled tsj but still added to atlas
//some images I want as a separate texture.
//be able to specify texture settings?
//
//Ok so we have a top level assetbake_config.json
//Actually Andrew Kelly's rucksack is way better.
//Just load a my_package.json
//my_package specifies which dirs to include and how to pack them.
//
//TODO perserve any extra tiled data
//allow the assets to be packed in a specific way

const log = std.log.scoped(.AssetBake);
pub const PackageConfigJson = struct {
    // Global tiled tileset

    //my_path/*.png
    //*/crasshunter/*.png

    //Sections:
    //textures
    //Random files
    //files
};

pub const AssetIdT = u32;
const IDT = AssetIdT;
pub const BakedManifestJson = struct {
    pub const IdRect = struct {
        pub const SearchCtx = struct {
            key: IDT,
        };
        id: IDT,
        x: u32,
        y: u32,
        w: u32,
        h: u32,

        pub fn sortAscById(_: void, lhs: IdRect, rhs: IdRect) bool {
            return lhs.id < rhs.id;
        }

        pub fn compare(ctx: SearchCtx, item: IdRect) std.math.Order {
            return std.math.order(ctx.key, item.id);
        }
    };
    pub const IdInfo = struct {
        id: IDT,
        //mtime: u64 = 0,
    };
    pub const IdMap = std.json.ArrayHashMap(IdInfo);
    //What we need to store
    //path to the atlas.png
    //an array mapping names to id
    //array mapping ids to rects
    name_id_map: IdMap,
    rects: []IdRect,
    version: usize = 1,
    build_timestamp: u64 = 0,

    //collected_json: std.json.ArrayHashMap()
};

/// AssetMap
pub const AssetMap = struct {
    const Self = @This();

    pub const UserResources = struct {
        const USelf = @This();

        //Keys are owned by parent AssetMap. Values are owned by self
        name_map: std.StringHashMap([]const u8),
        alloc: std.mem.Allocator,

        pub fn deinit(self: *USelf) void {
            var it = self.name_map.iterator();
            while (it.next()) |item| {
                self.alloc.free(item.value_ptr.*);
            }
            self.name_map.deinit();
        }
    };

    pub const FreeListItem = struct { start: u32, end: u32 };

    fn createFreelist(alloc: std.mem.Allocator, old_map: ?*const BakedManifestJson.IdMap) !std.ArrayList(FreeListItem) {
        var freelist = std.ArrayList(FreeListItem){};

        var sorted_ids = std.ArrayList(u32){};
        defer sorted_ids.deinit(alloc);
        if (old_map) |ob| {
            var it = ob.map.iterator();
            while (it.next()) |item| {
                try sorted_ids.append(alloc, item.value_ptr.id);
            }
            std.sort.heap(u32, sorted_ids.items, {}, std.sort.asc(u32));
        }
        var start: u32 = 0;
        if (sorted_ids.items.len > 0) {
            for (sorted_ids.items) |t| {
                if (start == t) {
                    start += 1;
                    continue;
                }
                var end = start;
                while (end < t) : (end += 1) {}
                try freelist.append(alloc, .{ .start = start, .end = end });
                start = t + 1;
            }
        }
        try freelist.append(alloc, .{ .start = start, .end = std.math.maxInt(u32) });

        return freelist;
    }

    ///Indices are resource ids, some ids don't have textures as they refer user resources
    resource_rect_lut: std.ArrayList(?Rect),
    id_name_lut: std.ArrayList(?[]const u8),
    alloc: std.mem.Allocator,
    name_id_map: std.StringHashMap(u32),

    dir: std.fs.Dir,
    file_prefix: []const u8,

    pub fn initTesting(alloc: std.mem.Allocator, test_names: []const []const u8) !Self {
        var ret = Self{
            .resource_rect_lut = .{},
            .id_name_lut = .{},
            .alloc = alloc,
            .name_id_map = std.StringHashMap(u32).init(alloc),
            .dir = undefined,
            .file_prefix = try alloc.dupe(u8, "testing"),
        };

        for (test_names) |tn| {
            const str = try alloc.dupe(u8, tn);
            try ret.name_id_map.put(str, @intCast(ret.id_name_lut.items.len));
            try ret.id_name_lut.append(ret.alloc, str);
        }

        return ret;
    }

    pub fn initFromManifest(alloc: std.mem.Allocator, dir: std.fs.Dir, file_prefix: []const u8) !Self {
        var arena = std.heap.ArenaAllocator.init(alloc);
        defer arena.deinit();
        const talloc = arena.allocator();
        const manifest_filename = try suffix(talloc, file_prefix, "_manifest.json");
        //TODO notify if the file isn't found
        const jslice = try dir.readFileAlloc(talloc, manifest_filename, std.math.maxInt(usize));
        const parsed = try std.json.parseFromSlice(BakedManifestJson, talloc, jslice, .{ .ignore_unknown_fields = true });

        var ret = Self{
            .file_prefix = try alloc.dupe(u8, file_prefix),
            .dir = dir,
            .resource_rect_lut = .{},
            .id_name_lut = .{},
            .alloc = alloc,
            .name_id_map = std.StringHashMap(u32).init(alloc),
        };
        std.sort.heap(BakedManifestJson.IdRect, parsed.value.rects, {}, BakedManifestJson.IdRect.sortAscById);
        var i: usize = 0;
        for (parsed.value.rects) |r| {
            while (i != @as(usize, @intCast(r.id))) : (i += 1) {
                try ret.resource_rect_lut.append(alloc, null);
            }
            i += 1;
            try ret.resource_rect_lut.append(alloc, graph.Rec(r.x, r.y, r.w, r.h));
        }

        //Ensure names are inserted in proper order. Iterate the mapping, put each item into a list, sort by id, and apply same routine as above
        const TmpMap = struct {
            name: []const u8,
            id: u32,

            fn sortAsc(_: void, lhs: @This(), rhs: @This()) bool {
                return lhs.id < rhs.id;
            }
        };
        var tmp_name_mapping = std.ArrayList(TmpMap){};
        defer tmp_name_mapping.deinit(alloc);
        var it = parsed.value.name_id_map.map.iterator();
        while (it.next()) |item| {
            try tmp_name_mapping.append(alloc, .{ .name = item.key_ptr.*, .id = item.value_ptr.id });
            //const name = try alloc.dupe(u8, item.key_ptr.*);
            //try ret.id_name_lut.append(name);
            //try ret.name_id_map.put(name, item.value_ptr.*);
        }
        std.sort.heap(TmpMap, tmp_name_mapping.items, {}, TmpMap.sortAsc);
        i = 0;
        for (tmp_name_mapping.items) |n| {
            while (i != @as(usize, @intCast(n.id))) : (i += 1) {
                try ret.id_name_lut.append(ret.alloc, null);
            }
            i += 1;
            const name_a = try alloc.dupe(u8, n.name);
            try ret.id_name_lut.append(ret.alloc, name_a);
            try ret.name_id_map.put(name_a, n.id);
        }

        return ret;
    }

    pub fn initTextureFromManifest(alloc: std.mem.Allocator, dir: std.fs.Dir, file_prefix: []const u8) !graph.Texture {
        const atlas_filename = try suffix(alloc, file_prefix, "_atlas.png");
        defer alloc.free(atlas_filename);

        return try graph.Texture.initFromImgFile(alloc, dir, atlas_filename, .{
            .mag_filter = graph.c.GL_NEAREST,
            //.min_filter = graph.c.GL_NEAREST,
        });
    }

    pub fn loadUserResources(self: *Self) !UserResources {
        const udata_filename = try suffix(self.alloc, self.file_prefix, "_userdata.bin");
        defer self.alloc.free(udata_filename);

        var ret = UserResources{
            .alloc = self.alloc,
            .name_map = std.StringHashMap([]const u8).init(self.alloc),
        };

        const file = try self.dir.openFile(udata_filename, .{});
        defer file.close();
        var read_buf: [1024]u8 = undefined;
        var read = file.reader(&read_buf);
        const re = &read.interface;

        var path_buf = std.ArrayList(u8){};
        defer path_buf.deinit(self.alloc);
        var data_buf = std.ArrayList(u8){};
        defer data_buf.deinit(self.alloc);

        const num_items = try re.takeInt(u32, .big);
        for (0..num_items) |i| {
            _ = i;

            const path_len = try re.takeInt(u32, .big);
            try path_buf.resize(self.alloc, path_len);
            _ = try re.readSliceAll(path_buf.items);
            const data_len = try re.takeInt(u32, .big);

            try data_buf.resize(self.alloc, data_len);
            _ = try re.readSliceAll(data_buf.items);

            if (self.name_id_map.getEntry(path_buf.items)) |entry| {
                try ret.name_map.put(entry.key_ptr.*, try self.alloc.dupe(u8, data_buf.items));
            } else {
                log.err("Can't find user resource {s}", .{path_buf.items});
            }
        }
        return ret;
    }

    pub fn getIdFromName(self: *Self, name: []const u8) ?u32 {
        const id = self.name_id_map.get(name) orelse {
            log.err("Unknown asset {s}", .{name});
            return null;
        };
        return id;
    }

    pub fn addSymbol(self: *Self, name: []const u8) !u32 {
        const str_all = try self.alloc.dupe(u8, name);
        errdefer self.alloc.free(str_all);
        try self.id_name_lut.append(self.alloc, str_all);
        const id: u32 = @intCast(self.id_name_lut.items.len - 1);
        try self.name_id_map.put(str_all, id);
        return id;
    }

    pub fn addExistingSymbol(self: *Self, name: []const u8) !u32 {
        if (self.name_id_map.get(name)) |id| {
            return id;
        }
        return try self.addSymbol(name);
    }

    pub fn getNameFromId(self: *Self, id: u32) []const u8 {
        return self.id_name_lut.items[id].?;
    }

    pub fn getRectFromId(self: *Self, id: u32) ?graph.Rect {
        return self.resource_rect_lut.items[id];
    }

    pub fn getRectFromName(self: *Self, name: []const u8) ?graph.Rect {
        const id = self.name_id_map.get(name) orelse {
            log.err("Unknown asset {s}", .{name});
            return null;
        };
        return self.resource_rect_lut.items[id];
    }

    pub fn deinit(self: *Self) void {
        self.resource_rect_lut.deinit(
            self.alloc,
        );

        for (self.id_name_lut.items) |on| {
            if (on) |n|
                self.alloc.free(n);
        }
        self.id_name_lut.deinit(
            self.alloc,
        );
        self.name_id_map.deinit();
        self.alloc.free(self.file_prefix);
    }
};

fn suffix(alloc: std.mem.Allocator, str: []const u8, _suffix: []const u8) ![]const u8 {
    const sl = try alloc.alloc(u8, str.len + _suffix.len);
    @memcpy(sl[0..str.len], str);
    @memcpy(sl[str.len..], _suffix);
    return sl;
}

/// This may lead to odd cases on unix where filenames can contain a backslash.
pub fn sanitizePath(buf: []u8) void {
    for (buf) |*char| {
        char.* = switch (char.*) {
            '\\' => '/', //Windoze is great
            else => continue,
        };
    }
}

//TODO stop using this stupid garbage

//This function walks a directory, adding png files to a single packed atlas, all other files get packed into a userdata.bin.
//A manifest file describing the directory is created.
//The main reason for its existence to is:
//  A. assign assets ids so they can be used from Tiled.
//  B. Make distribution and loading simpler. An application only needs to distribute, manifest.json, userdata.bin and atlas.png, rather than a directory. These files could be embedded in the binary using @embedFile()
pub fn assetBake(
    alloc: std.mem.Allocator,
    dir: std.fs.Dir,
    sub_path: []const u8,
    output_dir: std.fs.Dir,
    output_filename_prefix: []const u8, //prefix.json prefix.png etc
    options: struct { pixel_extrude: u32 = 0, force_rebuild: bool = false, do_tiled: bool = false },
) !void {
    const TILED_SCRATCH_NAME = ".tiled_img";
    const pixel_extrude = options.pixel_extrude;
    //const pixel_extrude = 4; //How many pixels to extrude each texture
    const IdRect = BakedManifestJson.IdRect;
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const talloc = arena.allocator();

    const manifest_filename = try suffix(talloc, output_filename_prefix, "_manifest.json");
    const userdata_filename = try suffix(talloc, output_filename_prefix, "_userdata.bin");
    const atlas_filename = try suffix(talloc, output_filename_prefix, "_atlas.png");
    const tiled_filename = try suffix(talloc, output_filename_prefix, "_tiled.tsj");

    //Really just assign a numerical id to every item in the dir
    const old_bake: ?BakedManifestJson = blk: {
        const jslice = output_dir.readFileAlloc(talloc, manifest_filename, std.math.maxInt(usize)) catch break :blk null;
        const parsed = try std.json.parseFromSlice(BakedManifestJson, talloc, jslice, .{ .ignore_unknown_fields = true });
        break :blk parsed.value;
    };
    //store json files in seperate json file
    var out_name_id_map = std.StringArrayHashMap(BakedManifestJson.IdInfo).init(alloc);
    defer out_name_id_map.deinit();

    var tiled_substite_path = std.StringArrayHashMap([]const u8).init(alloc);
    defer tiled_substite_path.deinit();

    //if a resource has an id in old_bake then use that id otherwise get it from freelist
    //we create freelist by gathering all old ids, sorting then iterating and generating a freelist.
    var freelist = try AssetMap.createFreelist(alloc, if (old_bake) |ob| &ob.name_id_map else null);
    defer freelist.deinit(alloc);

    var idir = try dir.openDir(sub_path, .{ .iterate = true });
    defer idir.close();
    var walker = try idir.walk(
        alloc,
    );

    var bmps = std.ArrayList(graph.Bitmap){};
    defer {
        for (bmps.items) |bmp| {
            bmp.deinit();
        }
        bmps.deinit(alloc);
    }

    var rpack = graph.RectPack.init(alloc);
    defer rpack.deinit();

    //TODO rename this to userdata or something as it doesn't have to be json
    var json_files = std.ArrayList(struct {
        path: []const u8, //allocated
        basename: []const u8, //slice of path
        dir_path: []const u8, //slice of path
    }){};
    defer {
        json_files.deinit(alloc);
    }

    //First we walk the directory and all children, creating a list of images and a list of json files.
    var uid_bmp_index_map = std.AutoHashMap(u32, u32).init(alloc);
    defer uid_bmp_index_map.deinit();
    const ignore_tiled_name = "tignore";
    var need_rebuild = old_bake == null;
    var tiled_exclude = std.AutoHashMap(u32, void).init(alloc);
    defer tiled_exclude.deinit();
    while (try walker.next()) |w| {
        switch (w.kind) {
            .file => {
                const stat = try w.dir.statFile(w.basename);
                const mtime: u64 = @intCast(@divTrunc(stat.mtime, std.time.ns_per_s));
                if (old_bake) |ob| {
                    if (mtime >= ob.build_timestamp)
                        need_rebuild = true;
                }
                if (need_rebuild)
                    break;
            },
            else => {},
        }
    }
    walker.deinit();
    if (!need_rebuild and !options.force_rebuild) {
        const rp = try idir.realpathAlloc(talloc, ".");
        log.info("Cached manifest of {s} named: {s}, skipping rebuild.", .{ rp, output_filename_prefix });
        return;
    }
    walker = try idir.walk(
        alloc,
    );
    defer walker.deinit();
    var path_scratch = std.ArrayList(u8){};
    defer path_scratch.deinit(alloc);

    if (options.do_tiled) { //Make the tiled scratch directory
        dir.makeDir(TILED_SCRATCH_NAME) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
    }
    var tiled_scratch_dir: ?std.fs.Dir = if (options.do_tiled) try dir.openDir(TILED_SCRATCH_NAME, .{}) else null;
    defer {
        if (options.do_tiled)
            tiled_scratch_dir.?.close();
    }

    while (try walker.next()) |w| {
        path_scratch.clearRetainingCapacity();
        try path_scratch.appendSlice(alloc, w.path);
        sanitizePath(path_scratch.items);
        const wpath = path_scratch.items;
        switch (w.kind) {
            .file => {
                const ind = blk: {
                    if (old_bake) |ob| {
                        if (ob.name_id_map.map.get(wpath)) |id|
                            break :blk id.id;
                    }
                    var range = &freelist.items[0];
                    while (range.start == range.end) {
                        _ = freelist.orderedRemove(0);
                        if (freelist.items.len == 0)
                            return error.noIdsLeft;
                        range = &freelist.items[0];
                    }
                    defer range.start += 1;
                    break :blk range.start;
                };
                const nameid = try talloc.dupe(u8, wpath);
                try out_name_id_map.put(nameid, .{
                    .id = @intCast(ind),
                });
                if (std.mem.startsWith(u8, wpath, ignore_tiled_name)) {
                    try tiled_exclude.put(ind, {});
                }
                if (std.mem.endsWith(u8, w.basename, ".png")) {
                    const index = bmps.items.len;
                    try bmps.append(alloc, try graph.Bitmap.initFromPngFile(alloc, w.dir, w.basename));
                    try rpack.appendRect(index, bmps.items[index].w + pixel_extrude * 2, bmps.items[index].h + pixel_extrude * 2);
                    try uid_bmp_index_map.put(@intCast(index), @intCast(ind));
                    //names has the same indicies as bmps
                } else {
                    const path = try talloc.dupe(u8, wpath);
                    try json_files.append(alloc, .{
                        .path = path,
                        .dir_path = path[0 .. wpath.len - w.basename.len],
                        .basename = path[wpath.len - w.basename.len ..],
                    });
                }
            },
            else => {},
        }
    }
    var id_rects = std.ArrayList(IdRect){};
    defer id_rects.deinit(alloc);

    //Pack all the rectangles and output to a file
    const out_size = try rpack.packOptimalSize();
    var out_bmp = try graph.Bitmap.initBlank(alloc, out_size.x, out_size.y, .rgba_8);
    defer out_bmp.deinit();
    const comp_count = 4;
    for (rpack.rects.items) |rect| {
        const x: u32 = @intCast(rect.x);
        const yy: u32 = @intCast(rect.y);
        const i: usize = @intCast(rect.id);
        const w: u32 = @intCast(rect.w);
        const h: u32 = @intCast(rect.h);
        try graph.Bitmap.copySubR(
            &out_bmp,
            x + pixel_extrude,
            yy + pixel_extrude,
            &bmps.items[i],
            0,
            0,
            w - pixel_extrude * 2,
            h - pixel_extrude * 2,
        );
        const sx: u32 = x + pixel_extrude;
        const sy: u32 = @intCast(rect.y);
        for (0..pixel_extrude) |pi| {
            const bstart = ((sy + pi) * out_bmp.w + sx) * comp_count;
            const dist = (w - pixel_extrude * 2);
            @memcpy(
                out_bmp.data.items[bstart .. bstart + dist * comp_count],
                bmps.items[i].data.items[0 .. dist * comp_count],
            );

            const tstart = ((sy + h - pixel_extrude + pi) * out_bmp.w + sx) * comp_count;
            //const tstart = ((sy + pixel_extrude + pi) * out_bmp.w + sx) * comp_count;
            const sstart = (dist * ((h - pixel_extrude * 2) - 1)) * comp_count;
            @memcpy(
                out_bmp.data.items[tstart .. tstart + dist * comp_count],
                //bmps.items[i].data.items[0 .. dist * comp_count],
                bmps.items[i].data.items[sstart .. sstart + dist * comp_count],
            );
        }
        for (0..pixel_extrude) |pi| {
            for (0..h) |y| {
                const sts = ((sy + y) * out_bmp.w + x + pixel_extrude) * comp_count;
                const st = ((sy + y) * out_bmp.w + x + pi) * comp_count;

                //const ost = ((w - pixel_extrude * 2) * y) * comp_count;
                @memcpy(
                    out_bmp.data.items[st .. st + 4],
                    out_bmp.data.items[sts .. sts + 4],
                    //bmps.items[i].data.items[ost .. ost + 4],
                );

                const stf = ((sy + y) * out_bmp.w + x + w - pi - 1) * comp_count;
                const stfs = ((sy + y) * out_bmp.w + x + w - pixel_extrude - 1) * comp_count;

                //const ostf = ((w - pixel_extrude * 2) * (y + 1) - 1) * comp_count;
                @memcpy(
                    out_bmp.data.items[stf .. stf + 4],
                    out_bmp.data.items[stfs .. stfs + 4],
                    //bmps.items[i].data.items[ostf .. ostf + 4],
                );
            }
        }
        try id_rects.append(alloc, .{
            .id = uid_bmp_index_map.get(@intCast(rect.id)).?,
            .x = x + pixel_extrude,
            .y = yy + pixel_extrude,
            .w = w - pixel_extrude * 2,
            .h = h - pixel_extrude * 2,
        });
    }
    try out_bmp.writeToPngFile(output_dir, atlas_filename);

    var userdataout = try output_dir.createFile(userdata_filename, .{});
    defer userdataout.close();
    var udate_buf: [1024]u8 = undefined;
    var uwriter = userdataout.writer(&udate_buf);
    const wr = &uwriter.interface;
    try wr.writeInt(u32, @intCast(json_files.items.len), .big);

    for (json_files.items) |jf| {
        var f = try idir.openFile(jf.path, .{});
        defer f.close();
        const s = try f.readToEndAlloc(talloc, std.math.maxInt(usize));
        //var cout = try std.compress.gzip.compressor(uout, .{});
        //const wr = cout.writer();
        try wr.writeInt(u32, @intCast(jf.path.len), .big);
        _ = try wr.write(jf.path);
        try wr.writeInt(u32, @intCast(s.len), .big);
        _ = try wr.write(s);
    }
    std.sort.heap(IdRect, id_rects.items, {}, IdRect.sortAscById);

    var out = try output_dir.createFile(manifest_filename, .{});
    defer out.close();
    var out_buf: [1024]u8 = undefined;
    var ow = out.writer(&out_buf);
    try std.json.Stringify.value(BakedManifestJson{
        .rects = id_rects.items,
        .name_id_map = BakedManifestJson.IdMap{
            .map = out_name_id_map.unmanaged,
        },
        .build_timestamp = @intCast(std.time.timestamp()),
    }, .{}, &ow.interface);
    try ow.interface.flush();

    if (options.do_tiled) {
        const TileImage = Tiled.TileMap.ExternalTileset.TileImage;
        var max_w: u32 = 0;
        var max_h: u32 = 0;
        var tiles = std.ArrayList(TileImage){};
        defer tiles.deinit(alloc);
        var name_it = out_name_id_map.iterator();
        while (name_it.next()) |item| {
            //TODO .ora images need to be written to a scratch dir so tiled can load them
            var new_name = std.ArrayList(u8){};
            try new_name.appendSlice(alloc, sub_path);
            try new_name.append(alloc, '/');
            try new_name.appendSlice(alloc, item.key_ptr.*);
            //We might need to append the dir prefix to fileimage path?
            const binctx = IdRect.SearchCtx{ .key = item.value_ptr.id };
            if (std.sort.binarySearch(IdRect, id_rects.items, binctx, IdRect.compare)) |ri| {
                const r = id_rects.items[ri];
                const h = (r.h);
                const w = (r.w);
                if (tiled_exclude.get(item.value_ptr.id) != null) {
                    continue;
                }
                max_w = @max(max_w, w);
                max_h = @max(max_h, h);
                if (tiled_substite_path.get(item.key_ptr.*)) |sub_name| {
                    try new_name.resize(alloc, 0);
                    try new_name.appendSlice(alloc, TILED_SCRATCH_NAME);
                    try new_name.append(alloc, '/');
                    try new_name.appendSlice(alloc, sub_name);
                }
                try tiles.append(alloc, .{
                    .image = new_name.items,
                    .id = item.value_ptr.id,
                    .imageheight = h,
                    .imagewidth = w,
                });
            }
        }
        std.sort.heap(TileImage, tiles.items, {}, TileImage.compare);
        const new_tsj = Tiled.TileMap.ExternalTileset{
            .tiles = tiles.items,
            .tileheight = max_h,
            .tilewidth = max_w,
            .tilecount = @intCast(tiles.items.len),
            .name = output_filename_prefix,
        };
        //We output this to dir so that we don't need to backtrack in the image paths as dir is always above sub_path
        var outfile = try dir.createFile(tiled_filename, .{});
        var outbuf2: [1024]u8 = undefined;
        var out_wr = outfile.writer(&outbuf2);
        try std.json.Stringify.value(new_tsj, .{}, &out_wr.interface);
        try out_wr.interface.flush();
        outfile.close();
    }
    try wr.flush();
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.detectLeaks();
    const alloc = gpa.allocator();
    var args = try std.process.ArgIterator.initWithAllocator(alloc);
    defer args.deinit();
    const Arg = ArgUtil.Arg;

    const cli_opts = try (ArgUtil.parseArgs(&.{
        Arg("dir", .string, "The directory you want to process into a manifest"),
        Arg("name", .string, "name of the artifacts"),
        Arg("extrude", .number, "Amount of pixels to extrude each sprite"),
    }, &args));

    if (cli_opts.dir == null or cli_opts.name == null) {
        std.debug.print("Args not provided. run --help\n", .{});
        return;
    }

    try assetBake(
        alloc,
        std.fs.cwd(),
        cli_opts.dir.?,
        std.fs.cwd(),
        cli_opts.name.?,
        .{ .pixel_extrude = @intFromFloat(cli_opts.extrude orelse 0) },
    );
}
