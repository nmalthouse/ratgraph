const std = @import("std");
const testing = std.testing;
const ArrayList = std.ArrayListUnmanaged;
const Allocator = std.mem.Allocator;

pub fn NullMarker(comptime index_type: type) index_type {
    return std.math.maxInt(index_type);
}

const InvalidIndex = error{InvalidIndex};

pub fn SparseSet(comptime child_type: type, comptime index_type: type) type {
    return struct {
        const Self = @This();
        pub const sparse_null_marker: index_type = NullMarker(index_type);
        pub const dense_null_marker: index_type = NullMarker(index_type);

        //TODO write tests that ensure addition and removal during iteration does not invalidate anything
        pub const Iterator = struct {
            dense: *std.ArrayList(child_type),
            dense_index_lut: *ArrayList(index_type),
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
            }

            pub fn getCurrent(self: *Iterator) ?*child_type {
                if (self.index < self.dense.items.len)
                    return &self.dense.items[self.index];
                return null;
            }
        };

        /// Sparse maps a global index to a 'dense' index
        sparse: ArrayList(index_type) = .{},

        dense: std.ArrayList(child_type), //FIXME bug in 0.14.1 std prevents this from being unmanaged
        /// dense_index_lut is parallel to dense, mapping dense indices to global indices
        dense_index_lut: ArrayList(index_type) = .{},

        _freelist: ArrayList(index_type) = .{},
        alloc: std.mem.Allocator,

        pub fn denseIterator(self: *Self) Iterator {
            return Iterator{
                .dense = &self.dense,
                .dense_index_lut = &self.dense_index_lut,
                .index = 0,
                .i = 0,
            };
        }

        pub fn init(alloc: std.mem.Allocator) !Self {
            const ret = Self{
                .alloc = alloc,
                .dense = std.ArrayList(child_type).init(alloc),
            };
            return ret;
        }

        pub fn fromOwnedDenseSlice(alloc: std.mem.Allocator, slice: []child_type, lut: []index_type) (error{MismatchedIndexSlice} || InvalidIndex || Allocator.Error)!Self {
            if (slice.len != lut.len)
                return error.MismatchedIndexSlice;
            var ret: Self = .{
                .alloc = alloc,
                .dense = (std.ArrayList(child_type)).fromOwnedSlice(alloc, slice),
                .dense_index_lut = (std.ArrayList(index_type).fromOwnedSlice(alloc, lut)),
            };

            for (ret.dense_index_lut.items, 0..) |item, i| {
                if (item == dense_null_marker)
                    return error.InvalidIndex;

                if (item >= ret.sparse.items.len)
                    try ret.sparse.appendNTimes(ret.alloc, sparse_null_marker, item - ret.sparse.items.len + 1);

                ret.sparse.items[item] = @as(index_type, @intCast(i));
            }

            return ret;
        }

        pub fn deinit(self: *Self) void {
            self.sparse.deinit(self.alloc);
            self.dense_index_lut.deinit(self.alloc);
            self.dense.deinit();
            self._freelist.deinit(self.alloc);
        }

        pub fn empty(self: *Self) Allocator.Error!void {
            try self.sparse.resize(self.alloc, 0);
            try self.dense_index_lut.resize(self.alloc, 0);
            try self.dense.resize(0);
            try self._freelist.resize(self.alloc, 0);
        }

        pub fn insert(self: *Self, index: index_type, item: child_type) (error{IndexOccupied} || Allocator.Error)!void {
            if (index < self.sparse.items.len and self.sparse.items[index] != sparse_null_marker)
                return error.IndexOccupied;

            if (index >= self.sparse.items.len)
                try self.sparse.appendNTimes(self.alloc, sparse_null_marker, index - self.sparse.items.len + 1);

            const dense_index = blk: {
                if (self._freelist.pop()) |free| {
                    if (free < self.dense_index_lut.items.len)
                        break :blk free;
                }
                const new_size = self.dense_index_lut.items.len + 1;
                try self.dense_index_lut.resize(self.alloc, new_size);
                try self.dense.resize(new_size);
                break :blk self.dense_index_lut.items.len - 1;
            };

            self.sparse.items[index] = @as(index_type, @intCast(dense_index));
            self.dense.items[dense_index] = item;
            self.dense_index_lut.items[dense_index] = index;
        }

        /// iterators remain valid
        pub fn remove(self: *Self, index: index_type) (InvalidIndex || Allocator.Error)!child_type {
            const di = try self.getDenseIndex(index);
            try self._freelist.append(self.alloc, di);
            self.sparse.items[index] = sparse_null_marker;
            const item = self.dense.items[di];
            self.dense_index_lut.items[di] = dense_null_marker;
            return item;
        }

        pub fn getDenseIndex(self: *Self, index: index_type) InvalidIndex!index_type {
            if (index >= self.sparse.items.len or self.sparse.items[index] == sparse_null_marker) {
                return error.InvalidIndex;
            }

            return self.sparse.items[index];
        }

        pub fn get(self: *Self, index: index_type) InvalidIndex!child_type {
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

        pub fn getPtr(self: *Self, index: index_type) InvalidIndex!*child_type {
            const di = try self.getDenseIndex(index);
            return &self.dense.items[di];
        }
    };
}

const SetType = SparseSet([]const u8, u32);
test "Sparse set basic usage" {
    const a = testing.allocator;
    var sset = try SetType.init(a);
    defer sset.deinit();

    try sset.insert(0, "first item");
    for (1..100) |i| {
        try sset.insert(@intCast(i), "thingy");
    }

    _ = try sset.remove(40);
    _ = try sset.remove(41);

    const next_id = 300;
    try sset.insert(next_id, "my item");

    _ = try sset.remove(0);
}

test "random" {
    const a = testing.allocator;

    const SetType1 = SparseSet(u32, u32);
    var sset = try SetType1.init(a);
    defer sset.deinit();

    var map = std.AutoHashMap(u32, u32).init(a);
    defer map.deinit();

    var rand = std.Random.DefaultPrng.init(0);
    const r = rand.random();

    const max_i = 1000;
    const max_v = 100000;
    const count = 10000;

    for (0..count) |_| {
        switch (r.enumValue(enum { insert, remove })) {
            .insert => {
                const index = r.uintLessThan(u32, max_i);
                const value = r.uintLessThan(u32, max_v);
                const res = sset.insert(index, value);
                if (map.contains(index)) {
                    try std.testing.expectError(error.IndexOccupied, res);
                } else {
                    try res;
                    try map.put(index, value);
                }
            },
            .remove => {
                const index = r.uintLessThan(u32, max_i);
                const rem = sset.remove(index);
                if (map.get(index)) |val| {
                    _ = map.remove(index);
                    try std.testing.expectEqual(val, try rem);
                } else {
                    try std.testing.expectError(error.InvalidIndex, rem);
                }
            },
        }
    }
    var it = map.iterator();
    while (it.next()) |pot| {
        try std.testing.expectEqual(pot.value_ptr.*, try sset.get(pot.key_ptr.*));
    }

    var sit = sset.denseIterator();
    while (sit.next()) |po| {
        try std.testing.expectEqual(po.*, map.get(sit.i) orelse error.broken);
    }
}

// pub fn fromOwnedDenseSlice(alloc: std.mem.Allocator, slice: []child_type, lut: []index_type) !Self {
// pub fn insert(self: *Self, index: index_type, item: child_type) !void {
// pub fn remove(self: *Self, index: index_type) !index_type {
