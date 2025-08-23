pub const DELTA: f32 = 1e-5;
const std = @import("std");
const Reg = @import("registry.zig");
const ID_TYPE = Reg.ID_TYPE;

//TODO
//Delete col3d and use ColCtx(3,f32)
//add slide and bounce response types
//Given two objects which response should we use?
pub fn ColCtx(DIM: usize, FT: type) type {
    return struct {
        pub const V = [DIM]FT;
        pub const ZeroV = [_]FT{0} ** DIM;

        fn DimMixin(comptime dim: usize) type {
            return switch (dim) {
                else => struct {},
                2 => struct {
                    pub fn detectCollision(r1: anytype, r2: anytype, goal: anytype, other_i: ID_TYPE) ?CollisionResult {
                        return detectCollisionRaw(
                            .{
                                .p = [2]FT{ r1.x, r1.y },
                                .x = [2]FT{ r1.w, r1.h },
                            },
                            .{
                                .p = [2]FT{ r2.x, r2.y },
                                .x = [2]FT{ r2.w, r2.h },
                            },
                            [2]FT{ goal.x, goal.y },
                            other_i,
                        );
                    }

                    pub fn rectToAABB(r: anytype) AABB {
                        return .{
                            .p = [2]FT{ r.x, r.y },
                            .x = [2]FT{ r.w, r.h },
                        };
                    }
                },
                3 => struct {
                    pub fn detectCollision(c1: anytype, c2: anytype, goal: anytype, other_i: ID_TYPE) ?CollisionResult {
                        return detectCollisionRaw(
                            .{ .p = c1.pos.data, .x = c1.ext.data },
                            .{ .p = c2.pos.data, .x = c2.ext.data },
                            goal.data,
                            other_i,
                        );
                    }
                },
            };
        }
        const AABB = struct {
            p: V,
            x: V,
        };
        const Plane = [DIM]V;

        pub const extra = DimMixin(DIM);

        /// a[i] - b[i]
        pub fn subV(a: V, b: V) V {
            var ret = a;
            for (0..DIM) |i| {
                ret[i] -= b[i];
            }
            return ret;
        }
        pub fn addV(a: V, b: V) V {
            var ret = a;
            for (0..DIM) |i| {
                ret[i] += b[i];
            }
            return ret;
        }

        pub fn lenV(a: V) FT {
            var sum: FT = 0;
            for (0..DIM) |i| {
                sum += a[i] * a[i];
            }
            return @sqrt(sum);
        }

        /// Return the minimum component
        pub fn minV(a: V) FT {
            var min = std.math.floatMax(FT);
            for (0..DIM) |i| {
                min = @min(min, a[i]);
            }
            return min;
        }

        pub const LBRes = struct {
            ti: FT = 0,
            ti2: FT = 0,
            normal: V,
            norm2: V = ZeroV,
        };

        pub const CollisionResult = struct {
            overlaps: bool,
            ti: FT,
            move: V,
            normal: V,
            touch: V,
            other_i: ID_TYPE,

            item: AABB,
            other: AABB,

            pub fn lessThan(ctx: void, lhs: @This(), rhs: @This()) bool {
                _ = ctx;
                if (lhs.ti == rhs.ti)
                    return squareDistance(lhs.item, lhs.other) < squareDistance(lhs.item, rhs.other);
                return lhs.ti < rhs.ti;
            }
        };

        pub fn squareDistance(r1: AABB, r2: AABB) FT {
            var total: FT = 0;
            for (0..DIM) |i| {
                total += std.math.pow(FT, r1.p[i] - r2.p[i] + (r1.x[i] - r2.x[i]) / 2, 2);
            }
            return total;
        }

        /// Return the 1d point[a,b] nearest to x
        pub fn nearest(x: FT, a: FT, b: FT) FT {
            return if (@abs(a - x) < @abs(b - x)) a else b;
        }

        pub fn sign(a: FT) FT {
            if (a < 0)
                return -1;
            if (a == 0)
                return 0;
            return 1;
        }

        pub fn nearestCorner(r: AABB, p: V) V {
            var ret: V = undefined;
            for (0..DIM) |i| {
                ret[i] = nearest(p[i], r.p[i], r.p[i] + r.x[i]);
            }
            return ret;
        }

        pub fn containsPoint(r: AABB, p: V) bool {
            var ret = true;
            for (0..DIM) |i| {
                ret = ret and p[i] - r.p[i] > DELTA and r.p[i] + r.x[i] - p[i] > DELTA;
            }
            return ret;
        }

        pub fn minkowsky_diff(r1: AABB, r2: AABB) AABB {
            var ret: AABB = undefined;
            for (0..DIM) |i| {
                ret.p[i] = r2.p[i] - r1.p[i] - r1.x[i];
                ret.x[i] = r1.x[i] + r2.x[i];
            }
            return ret;
        }

        pub fn lbClip(norm: V, p: FT, q: FT, ti1: *FT, ti2: *FT, n1: *V, n2: *V) bool {
            if (p == 0) {
                if (q <= 0) return false;
            } else {
                const r = q / p;
                if (p < 0) {
                    if (r > ti2.*)
                        return false;
                    if (r > ti1.*) {
                        ti1.* = r;
                        n1.* = norm;
                    }
                } else {
                    if (r < ti1.*) return false;
                    if (r < ti2.*) {
                        ti2.* = r;
                        n2.* = norm;
                    }
                }
            }
            return true;
        }

        pub fn liang_barsky(clip_window: AABB, start: V, end: V, ti1_: ?FT, ti2_: ?FT) ?LBRes {
            var ti1 = ti1_ orelse 0;
            var ti2 = ti2_ orelse 1;
            var delta = end;
            for (0..DIM) |i| {
                delta[i] -= start[i];
            }
            var norm1 = ZeroV;
            var norm2 = ZeroV;

            for (0..DIM) |i| {
                var nneg = ZeroV;
                var npos = ZeroV;
                nneg[i] = -1;
                npos[i] = 1;
                if (!lbClip(nneg, -delta[i], start[i] - clip_window.p[i], &ti1, &ti2, &norm1, &norm2))
                    return null;
                if (!lbClip(npos, delta[i], clip_window.p[i] + clip_window.x[i] - start[i], &ti1, &ti2, &norm1, &norm2))
                    return null;
            }

            return LBRes{
                .ti = ti1,
                .ti2 = ti2,
                .normal = norm1,
                .norm2 = norm2,
            };
        }

        //If either x1 == x2 or y1 == y2, decomposes into a aabb
        //

        //AABB vs line in 2d
        //2 line-line intersection checks, either intersects, they collide there

        //pub fn detectCollisionAABB_planeRaw(r1:AABB, plane: )
        //
        //position,

        pub fn polygonContainsPoint2d(verts: []const V, p: V) bool {
            if (DIM != 2)
                return false;

            var angle: FT = 0;
            var p1: V = ZeroV;
            var p2: V = ZeroV;
            for (verts, 1..) |vert, i| {
                p1[0] = vert[0] - p[0];
                p1[1] = vert[1] - p[1];
                p2[0] = verts[i % verts.len][0] - p[0];
                p2[1] = verts[i % verts.len][1] - p[1];
                angle += angle2d(p1, p2);
            }
            return !(@abs(angle) < std.math.pi);
        }

        fn angle2d(v1: V, v2: V) FT {
            const th1 = std.math.atan2(v1[1], v1[0]);
            const th2 = std.math.atan2(v2[1], v2[0]);
            var dth = th2 - th1;
            while (dth > std.math.pi) : (dth -= std.math.tau) {}
            while (dth < -std.math.pi) : (dth += std.math.tau) {}
            return dth;
        }

        pub fn lineIntersect(a1: V, a2: V, b1: V, b2: V) ?V {
            if (DIM != 2)
                return null;
            const al = subV(a1, a2);
            const bl = subV(b1, b2);
            var all: FT = 0;
            var bll: FT = 0;

            for (0..DIM) |i| {
                all += al[i];
                bll += bl[i];
            }
            if (all == 0 or bll == 0)
                return null;
            const denom = (b2[1] - b1[1]) * (a2[0] - a1[0]) - (b2[0] - b1[0]) * (a2[1] - a1[1]);
            if (denom == 0)
                return null;

            const ua = ((b2[0] - b1[0]) * (a1[1] - b1[1]) - (b2[1] - b1[1]) * (a1[0] - b1[0])) / denom;
            const ub = ((a2[0] - a1[0]) * (a1[1] - b1[1]) - (a2[1] - a1[1]) * (a1[0] - b1[0])) / denom;
            if (ua < 0 or ua > 1 or ub < 0 or ub > 1)
                return null;
            return [2]FT{
                a1[0] + ua * (a2[0] - a1[0]),
                a1[0] + ua * (a2[1] - a1[0]),
            };
        }

        pub fn minkl(r1: AABB, s1: V, en1: V, ret: *[6]V) []V {
            if (s1[0] == en1[0] or s1[1] == en1[1]) {
                ret[0][0] = @min(s1[0] - r1.p[0], en1[0] - r1.p[0]) - r1.x[0];
                ret[0][1] = @min(s1[1] - r1.p[1], en1[1] - r1.p[1]) - r1.x[1];
                ret[2][0] = @max(s1[0] - r1.p[0] + r1.x[0], en1[0] - r1.p[0] + r1.x[0]) - r1.x[0];
                ret[2][1] = @max(s1[1] - r1.p[1] + r1.x[1], en1[1] - r1.p[1] + r1.x[1]) - r1.x[1];
                ret[1][0] = ret[2][0];
                ret[1][1] = ret[0][1];
                ret[3][0] = ret[0][0];
                ret[3][1] = ret[2][1];
                return ret[0..4];
            }
            var en = en1;
            var s = s1;

            if ((en[0] - s[0]) / (en[1] - s[1]) < 0) {
                if (en[0] < s[0]) {
                    s = en1;
                    en = s1;
                }
                ret[0][0] = s[0] - r1.p[0] - r1.x[0];
                ret[0][1] = s[1] - r1.p[1] - r1.x[1];

                ret[1][0] = en[0] - r1.p[0] - r1.x[0];
                ret[1][1] = en[1] - r1.p[1] - r1.x[1];

                ret[2][0] = en[0] - r1.p[0];
                ret[2][1] = en[1] - r1.p[1] - r1.x[1];

                ret[3][0] = en[0] - r1.p[0];
                ret[3][1] = en[1] - r1.p[1];

                ret[4][0] = s[0] - r1.p[0];
                ret[4][1] = s[1] - r1.p[1];

                ret[5][0] = s[0] - r1.p[0] - r1.x[0];
                ret[5][1] = s[1] - r1.p[1];
                return ret;
            } else {
                if (en[1] < s[1]) {
                    s = en1;
                    en = s1;
                }
                ret[0][0] = s[0] - r1.p[0] - r1.x[0];
                ret[0][1] = s[1] - r1.p[1] - r1.x[1];

                ret[1][0] = s[0] - r1.p[0];
                ret[1][1] = ret[0][1];

                ret[2][0] = en[0] - r1.p[0];
                ret[2][1] = en[1] - r1.p[1] - r1.x[1];

                ret[3][0] = ret[2][0];
                ret[3][1] = ret[2][1] + r1.x[1];

                ret[4][0] = ret[3][0] - r1.x[0];
                ret[4][1] = ret[3][1];

                ret[5][0] = ret[0][0];
                ret[5][1] = ret[0][1] + r1.x[1];
                return ret;
            }
        }

        pub fn detectCollisionLine(r1: AABB, l1: V, l2: V, goal: V, other_i: ID_TYPE) ?CollisionResult {
            _ = other_i;
            if (DIM != 2)
                @compileError("unsupported");
            const delta = subV(goal, r1.p);
            var verts: [6]V = undefined;
            const mdiff = minkl(r1, l1, l2, &verts);
            if (polygonContainsPoint2d(mdiff, ZeroV)) {} else {
                const intersection = delta;
                for (verts, 1..) |v, i| {
                    _ = lineIntersect(ZeroV, delta, v, verts[i % verts.len]);
                    //Find nearest intersection
                    _ = intersection;
                }
            }
        }

        pub fn detectCollisionRaw(r1: AABB, r2: AABB, goal: V, other_i: ID_TYPE) ?CollisionResult {
            const delta = subV(goal, r1.p);
            const mdiff = minkowsky_diff(r1, r2);
            var overlaps = false;
            var ti: ?f32 = null;

            var norm = ZeroV;

            //if the Minkowsky diff intersects the origin it is already overlapping
            if (containsPoint(mdiff, ZeroV)) {
                const point = nearestCorner(mdiff, ZeroV);
                var area: FT = -1.0;
                for (0..DIM) |i| {
                    area *= @min(r1.x[i], @abs(point[i]));
                }
                //econst wi = @min(r1.w, @abs(point.x));
                //econst hi = @min(r1.h, @abs(point.y));
                ti = area;
                //ti = -wi * hi; // ti is the negative area of intersection
                overlaps = true;
            } else {
                if (liang_barsky(mdiff, ZeroV, delta, -std.math.floatMax(FT), std.math.floatMax(FT))) |lb| {
                    if (lb.ti < 1 and @abs(lb.ti - lb.ti2) >= DELTA and (0 < lb.ti + DELTA or 0 == ti and lb.ti2 > 0)) {
                        ti = lb.ti;
                        norm = lb.normal;
                        overlaps = false;
                    }
                }
            }
            if (ti == null) return null;

            var tv = ZeroV;
            if (overlaps) {
                if (lenV(delta) == 0) {
                    var np = nearestCorner(mdiff, ZeroV);
                    //Find the minimum component and set all others to zero
                    var mi: usize = 0;
                    var min: FT = std.math.floatMax(FT);
                    for (0..DIM) |i| {
                        if (@abs(np[i]) < min) {
                            min = @abs(np[i]);
                            mi = i;
                        }
                    }
                    for (0..DIM) |i| {
                        if (i == mi)
                            continue;
                        np[i] = 0;
                    }
                    for (0..DIM) |i| {
                        norm[i] = sign(np[i]);
                        tv[i] = r1.p[i] + np[i];
                    }

                    //tv = ZeroV;
                    //tx = r1.x + np.x;
                    //ty = r1.y + np.y;
                } else {
                    const lb = liang_barsky(mdiff, ZeroV, delta, -std.math.floatMax(FT), 1) orelse return null;
                    norm = lb.normal;
                    ti = lb.ti;
                    for (0..DIM) |i| {
                        tv[i] = r1.p[i] + delta[i] * lb.ti;
                    }
                }

                //norm = Norm.fromSigns(if(np.x > 0) 1, np.y);
            } else {
                for (0..DIM) |i| {
                    tv[i] = r1.p[i] + delta[i] * ti.?;
                }
            }

            return CollisionResult{
                .overlaps = overlaps,
                .item = r1,
                .other = r2,
                .ti = ti.?,
                .move = delta,
                .normal = norm,
                .touch = tv,
                .other_i = other_i,
            };
        }
    };
}

const TC3 = ColCtx(3, f32);
test "3dfail" {
    //newcol.ColCtx(3,f32).CollisionResult{ .overlaps = true, .ti = -1.37082266e-8, .move = { 0e0, 0e0, 1.9326568e-2 }, .normal = { 0e0, 0e0, -1e0 }, .touch = { 5.48e0, 9.99999e-3, -6e-1 }, .other_i = 31, .item = newcol.ColCtx(3,f32).AABB{ .p = { 5.48e0, 9.99999e-3, 1.9193107e0 }, .x = { 6e-1, 1.7e0, 6e-1 } }, .other = newcol.ColCtx(3,f32).AABB{ .p = { 6.08e0, 0e0, 0e0 }, .x = { 9.0999997e-1, 2.9e-1, 2.33e0 } } }
    const item = TC3.AABB{ .p = [_]f32{ 5.48e0, 9.99999e-3, 1.9193107e0 }, .x = [_]f32{ 6e-1, 1.7e0, 6e-1 } };
    const other = TC3.AABB{ .p = [_]f32{ 6.08e0, 0e0, 0e0 }, .x = [_]f32{ 9.0999997e-1, 2.9e-1, 2.33e0 } };
    const move = [_]f32{ 0e0, 0e0, 1.9326568e-2 };
    const col = TC3.detectCollisionRaw(item, other, TC3.addV(item.p, move), 0);
    _ = col;
    const mdiff = TC3.minkowsky_diff(item, other);
    std.debug.print("{any}\n", .{mdiff});
}

const TC = ColCtx(2, f32);
const ex = std.testing.expectEqual;
test "nearest" {
    try ex(1, TC.nearest(0, 1, 2));
    try ex(2, TC.nearest(3, 1, 2));
    try ex(-3, TC.nearest(-1, -3, 2));
}

test "nearestCorner" {
    try ex([_]f32{ 0, 1 }, TC.nearestCorner(.{
        .p = [_]f32{ 0, 0 },
        .x = [_]f32{ 1, 1 },
    }, [_]f32{ 0, 10 }));
}

test "containsPoint" {
    try ex(TC.containsPoint(.{
        .p = [_]f32{ 0, 0 },
        .x = [_]f32{ 1, 1 },
    }, [_]f32{ 0.5, 0.5 }), true);
}

test "minkowskyDiff" {
    const a = TC.AABB{ .p = [_]f32{ 1, 1 }, .x = [_]f32{ 1, 1 } };
    const b = TC.AABB{ .p = [_]f32{ 3, 3 }, .x = [_]f32{ 1, 1 } };
    const e = TC.AABB{ .p = [_]f32{ 1, 1 }, .x = [_]f32{ 2, 2 } };

    try ex(TC.minkowsky_diff(a, b), e);
}
