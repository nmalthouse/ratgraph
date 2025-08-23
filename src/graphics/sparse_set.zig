const std = @import("std");
const testing = std.testing;

pub fn container_struct(comptime t: type, comptime id: type) type {
    return struct { item: t, i: id = 0 };
}

pub fn NullMarker(comptime index_type: type) index_type {
    return std.math.maxInt(index_type);
}

pub fn SparseSet(comptime child_type: type, comptime index_type: type) type {
    return struct {
        const Self = @This();
        const max_index = std.math.maxInt(index_type);
        pub const sparse_null_marker: index_type = max_index;
        pub const dense_null_marker: index_type = max_index;

        //TODO write tests that ensure addition and removal during iteration does not invalidate anything
        pub const Iterator = struct {
            dense: *std.ArrayList(child_type), //Pointer so reallocation during iteration won't invalidate iterator
            dense_index_lut: *std.ArrayList(index_type),
            //This is an index into dense
            index: usize,

            //This is a sparse index
            i: index_type,

            pub fn next(self: *Iterator) ?*child_type {
                defer self.index += 1;
                if (self.index >= self.dense.items.len)
                    return null;
                while (self.dense_index_lut.items[self.index] == dense_null_marker) : (self.index += 1) {
                    if (self.index == self.dense.items.len - 1) {
                        return null;
                    }
                }
                self.i = self.dense_index_lut.items[self.index];
                return &self.dense.items[self.index];
                //return .{ .item = &self.dense.items[self.index], .i = self.dense_index_lut.items[self.index] };
            }

            pub fn getCurrent(self: *Iterator) ?*child_type {
                if (self.index < self.dense.items.len)
                    return &self.dense.items[self.index];
                return null;
            }
        };

        //TODO implement cool algorothim for sparse array
        //ALGO:
        //  sparse is an array of chunks.
        //  A chunk contains a sparse array and a range
        //
        //  Determine a pack factor.
        //  Whenever a sub sparse array contains too few contigous items,
        //  split it into multiple sparse sub arrays
        //  range refers to the index distance to the next sub sparse array
        //
        //  Initially:
        //      our memory looks like: sparse_arrs[sub01{data: [], range = int32_max}]
        //
        //  To store the first item at index 1000:
        //      our memory looks like: sparse_arrs[sub01{data: [], range =999}, sub02{data = [item01_dense_index], range = (arbitrary)],
        //
        //
        //

        /// Sparse maps a global index to a 'dense' index
        sparse: std.ArrayList(index_type),
        dense: std.ArrayList(child_type),
        /// dense_index_lut is parallel to dense, mapping dense indices to global indices
        dense_index_lut: std.ArrayList(index_type),

        // Optimize insertions
        _had_removal: bool = true,

        _freelist: std.ArrayList(index_type),

        pub fn denseIterator(self: *Self) Iterator {
            return Iterator{ .dense = &self.dense, .index = 0, .dense_index_lut = &self.dense_index_lut, .i = 0 };
        }

        pub fn init(alloc: std.mem.Allocator) !Self {
            const ret = Self{
                .sparse = std.ArrayList(index_type).init(alloc),
                .dense_index_lut = std.ArrayList(index_type).init(alloc),
                .dense = std.ArrayList(child_type).init(alloc),
                ._freelist = std.ArrayList(index_type).init(alloc),
            };
            return ret;
        }

        pub fn fromOwnedDenseSlice(alloc: std.mem.Allocator, slice: []child_type, lut: []index_type) !Self {
            if (slice.len != lut.len)
                return error.mismatchedIndexSlice;
            var ret: Self = undefined;
            ret.dense = (std.ArrayList(child_type)).fromOwnedSlice(alloc, slice);
            ret.dense_index_lut = (std.ArrayList(index_type).fromOwnedSlice(alloc, lut));
            ret.sparse = std.ArrayList(index_type).init(alloc);

            for (ret.dense_index_lut.items, 0..) |item, i| {
                if (item == dense_null_marker)
                    return error.InvalidIndex;

                if (item >= ret.sparse.items.len)
                    try ret.sparse.appendNTimes(sparse_null_marker, item - ret.sparse.items.len + 1);

                ret.sparse.items[item] = @as(index_type, @intCast(i));
            }

            return ret;
        }

        pub fn deinit(self: *Self) void {
            self.sparse.deinit();
            self.dense_index_lut.deinit();
            self.dense.deinit();
            self._freelist.deinit();
        }

        pub fn empty(self: *Self) !void {
            try self.sparse.resize(0);
            try self.dense_index_lut.resize(0);
            try self.dense.resize(0);
            try self._freelist.resize(0);
        }

        pub fn insert(self: *Self, index: index_type, item: child_type) !void {
            if (index < self.sparse.items.len and self.sparse.items[index] != sparse_null_marker)
                return error.IndexOccupied;

            if (index >= self.sparse.items.len)
                try self.sparse.appendNTimes(sparse_null_marker, index - self.sparse.items.len + 1);

            const dense_index = blk: {
                if (self._had_removal) {
                    if (self._freelist.pop()) |free| {
                        if (free < self.dense_index_lut.items.len)
                            break :blk free;
                    }
                }
                const new_size = self.dense_index_lut.items.len + 1;
                try self.dense_index_lut.resize(new_size);
                try self.dense.resize(new_size);
                break :blk self.dense_index_lut.items.len - 1;
            };
            self._had_removal = false;

            self.sparse.items[index] = @as(index_type, @intCast(dense_index));
            self.dense.items[dense_index] = item;
            self.dense_index_lut.items[dense_index] = @intCast(index);
            //try self.dense.append(new_item);
            //TODO use errdefer to prevent garbage in sparse
        }

        //TODO iteration safe, but not deterministic, item added during iteration getting seen during that iteration is random
        //pub fn add(self: *Self, item: child_type) !index_type {
        //    var empty_index: ?index_type = null;
        //    for (self.sparse.items, 0..) |item_index, sp_i| {
        //        if (item_index == sparse_null_marker and sp_i != sparse_null_marker) {
        //            empty_index = @as(index_type, @intCast(sp_i));
        //            break;
        //        }
        //    }

        //    if (empty_index == null) {
        //        empty_index = @as(index_type, @intCast(self.sparse.items.len));
        //        try self.sparse.append(sparse_null_marker);
        //    }

        //    self.sparse.items[empty_index.?] = @as(index_type, @intCast(self.dense.items.len));
        //    try self.dense.append(item);
        //    try self.dense_index_lut.append(@intCast(empty_index.?));
        //    return empty_index.?;
        //}

        pub fn get(self: *Self, index: index_type) !child_type {
            const di = try self.getDenseIndex(index);
            return self.dense.items[di];
        }

        pub fn getOpt(self: *Self, index: index_type) ?child_type {
            if (index >= self.sparse.items.len or self.sparse.items[index] == sparse_null_marker)
                return null;

            return self.dense.items[self.sparse.items[index]];
        }

        pub fn getOptPtr(self: *Self, index: index_type) ?*child_type {
            if (index >= self.sparse.items.len or self.sparse.items[index] == sparse_null_marker)
                return null;

            return &self.dense.items[self.sparse.items[index]];
        }

        pub fn getPtr(self: *Self, index: index_type) !*child_type {
            const di = try self.getDenseIndex(index);
            return &self.dense.items[di];
        }

        pub fn getDenseIndex(self: *Self, index: index_type) !index_type {
            if (index >= self.sparse.items.len or self.sparse.items[index] == sparse_null_marker) {
                return error.InvalidIndex;
            }

            return self.sparse.items[index];
        }

        /// iterators remain valid
        pub fn remove(self: *Self, index: index_type) !child_type {
            self._had_removal = true;
            const di = try self.getDenseIndex(index);
            try self._freelist.append(di);
            self.sparse.items[index] = sparse_null_marker;
            //get copy of component to remove
            //set dense sparse_index value to dense_null_marker;
            //update iterator to discard null values
            const item = self.dense.items[di];
            self.dense_index_lut.items[di] = dense_null_marker;
            return item;

            //if (self.dense.items.len - 1 == di) return self.dense.pop();

            //const replacement_item = self.dense.pop();
            //const old_item = self.dense.items[di];
            //self.sparse.items[replacement_item.i] = di;
            //self.dense.items[di] = replacement_item;
            //return old_item;
        }
    };
}

const SetType = SparseSet([]const u8, u32);
test "Sparse set basic usage" {
    const a = testing.allocator;
    var sset = try SetType.init(a);
    defer sset.deinit();

    try sset.insert(0, "first item");

    const next_id = 300;
    try sset.insert(next_id, "my item");

    _ = try sset.remove(0);
}
//TODO add more tests
