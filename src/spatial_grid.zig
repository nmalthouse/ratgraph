const std = @import("std");
const graph = @import("graphics.zig");
const Allocator = std.mem.Allocator;

const Rect = graph.Rect;
const Vec2i = graph.Vec2i;
/// 2d integer Spatial lookups. Used for collision detection
pub fn Spatial(comptime value_T: type) type {
    const lossyCast = std.math.lossyCast;
    return struct {
        const Self = @This();

        pub const Key = Vec2i;

        pub const Value = std.ArrayList(value_T);

        pub const HashMapContext = struct {
            pub fn hash(self: @This(), k: Key) u64 {
                _ = self;
                var hasher = std.hash.Wyhash.init(0);
                std.hash.autoHashStrat(&hasher, k, .Shallow);
                return hasher.final();
            }

            pub fn eql(self: @This(), a: Key, b: Key) bool {
                _ = self;
                return a.x == b.x and a.y == b.y;
            }
        };

        pub const RectIt = struct {
            x0: i32,
            xf: i32,
            y0: i32,
            yf: i32,

            x: i32,
            y: i32,

            pub fn init(top_left: Key, bot_right: Key) RectIt {
                if (bot_right.x - top_left.x < 0 or bot_right.y - top_left.y < 0) unreachable;
                return .{
                    .x0 = top_left.x,
                    .xf = bot_right.x,
                    .y0 = top_left.y,
                    .yf = bot_right.y,
                    .x = top_left.x,
                    .y = top_left.y,
                };
            }

            pub fn next(self: *RectIt) ?Key {
                const res = .{ .x = self.x, .y = self.y };
                if (self.x > self.xf) {
                    return null;
                }
                self.y += 1;
                if (self.y > self.yf) {
                    self.x += 1;
                    self.y = self.y0;
                }
                return res;
            }
        };

        pub const MapT = std.HashMap(Key, Value, HashMapContext, std.hash_map.default_max_load_percentage);

        map: MapT,
        cell_w: i32,
        cell_h: i32,
        alloc: Allocator,

        pub fn init(alloc: Allocator, cw: i32, ch: i32) Self {
            return .{
                .alloc = alloc,
                .map = MapT.init(alloc),
                .cell_w = cw,
                .cell_h = ch,
            };
        }
        pub fn deinit(self: *Self) void {
            var v_it = self.map.valueIterator();
            while (v_it.next()) |item| {
                item.deinit();
            }
            self.map.deinit();
        }
        pub fn reset(self: *Self) void {
            self.deinit();
            self.map = MapT.init(self.alloc);
        }

        fn addToCell(self: *Self, cell: Key, v: value_T) !void {
            const res = try self.map.getOrPut(cell);
            if (!res.found_existing) {
                res.value_ptr.* = Value.init(self.alloc);
            }
            var already_exists: bool = false;
            for (res.value_ptr.items) |item| {
                if (item == v) {
                    already_exists = true;
                }
            }
            if (!already_exists)
                try res.value_ptr.append(v);
        }

        fn removeFromCell(self: *Self, cell: Key, v: value_T) !void {
            if (self.map.getPtr(cell)) |val_ptr| {
                for (val_ptr.items, 0..) |item, i| {
                    if (item == v) {
                        _ = val_ptr.swapRemove(i);
                        break;
                    }
                }
            }
        }

        pub fn toCell(self: Self, x: anytype, y: anytype) Vec2i {
            return .{
                .x = @divFloor(lossyCast(i32, x), self.cell_w),
                .y = @divFloor(lossyCast(i32, y), self.cell_h),
            };
        }

        pub fn insertRect(self: *Self, r: Rect, value: value_T) !void {
            var r_it = RectIt.init(self.toCell(r.x, r.y), self.toCell(r.x + r.w, r.y + r.h));
            while (r_it.next()) |key| {
                try self.addToCell(key, value);
            }
        }

        pub fn moveRect(self: *Self, r0: Rect, rf: Rect, value: value_T) !void {
            try self.removeRect(r0, value);
            try self.insertRect(rf, value);
        }

        pub fn removeRect(self: *Self, r: Rect, value: value_T) !void {
            var r_it = RectIt.init(self.toCell(r.x, r.y), self.toCell(r.x + r.w, r.y + r.h));
            while (r_it.next()) |key| {
                try self.removeFromCell(key, value);
            }
        }

        fn lessThanValue(ctx: void, a: value_T, b: value_T) bool {
            _ = ctx;
            return a < b;
        }

        fn cmpValue(ctx: void, key: value_T, mid: value_T) std.math.Order {
            _ = ctx;
            if (key < mid) return .lt;
            if (key > mid) return .gt;
            return .eq;
        }

        pub fn getObjectsInArea(self: *Self, alloc: std.mem.Allocator, r: Rect) !std.ArrayList(value_T) {
            var list = std.ArrayList(value_T).init(alloc);
            var r_it = RectIt.init(self.toCell(r.x, r.y), self.toCell(r.x + r.w, r.y + r.h));
            while (r_it.next()) |key| {
                if (self.map.get(key)) |vals| {
                    for (vals.items) |item| {
                        if (std.sort.binarySearch(value_T, item, list.items, {}, cmpValue)) |index| {
                            _ = index;
                            continue;
                        } else {
                            try list.append(item);
                            std.sort.insertion(value_T, list.items, {}, lessThanValue);
                        }
                    }
                }
            }
            return list;
        }
    };
}

//moving a rect.
//query what rects occupy an area

pub fn main() !void {}

test "basic" {
    const alloc = std.testing.allocator;
    const ST = Spatial(u32);
    var map = ST.init(alloc, 10, 10);
    defer map.deinit();
    std.debug.print("\n", .{});

    try map.insertRect(.{ .x = 0, .y = 0, .w = 20, .h = 20 }, 69);
    try map.insertRect(.{ .x = 0, .y = 0, .w = 19, .h = 19 }, 32);
    try map.insertRect(.{ .x = -11, .y = -9, .w = 19, .h = 19 }, 33);
    try map.removeRect(.{ .x = -11, .y = -9, .w = 19, .h = 19 }, 33);
}
