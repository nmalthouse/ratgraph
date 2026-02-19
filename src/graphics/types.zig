const std = @import("std");
const lcast = std.math.lossyCast;
pub const za = @import("zalgebra");

pub const Orientation = enum {
    horizontal,
    vertical,

    pub fn vec2fComponent(self: Orientation, v: Vec2f) f32 {
        return switch (self) {
            .horizontal => v.x,
            .vertical => v.y,
        };
    }

    pub fn rectH(self: Orientation, r: Rect) Rect {
        return switch (self) {
            .horizontal => r,
            .vertical => r.swapAxis(),
        };
    }
};

pub const RectBound = struct {
    pub const zero: RectBound = .{};
    x0: f32 = 0,
    y0: f32 = 0,
    x1: f32 = 0,
    y1: f32 = 0,
};

pub const Rect = struct {
    const Self = @This();
    pub const Empty = Rect{};

    x: f32 = 0,
    y: f32 = 0,
    w: f32 = 0,
    h: f32 = 0,

    pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        _ = fmt;
        try writer.print("R({d:.2} {d:.2} {d:.2} {d:.2})", .{ self.x, self.y, self.w, self.h });
    }

    pub fn NewAny(x: anytype, y: anytype, w: anytype, h: anytype) Rect {
        return .{
            .x = std.math.lossyCast(f32, x),
            .y = std.math.lossyCast(f32, y),
            .w = std.math.lossyCast(f32, w),
            .h = std.math.lossyCast(f32, h),
        };
    }

    pub fn new(x: f32, y: f32, w: f32, h: f32) @This() {
        return .{ .x = x, .y = y, .w = w, .h = h };
    }

    pub fn round(self: @This()) Self {
        return .{
            .x = @round(self.x),
            .y = @round(self.y),
            .w = @round(self.w),
            .h = @round(self.h),
        };
    }

    pub fn containsPoint(r: Self, p: anytype) bool {
        return rectContainsPoint(r, p);
    }

    pub fn center(r: Self) Vec2f {
        return .{ .x = r.x + r.w / 2, .y = r.y + r.h / 2 };
    }

    pub fn overlap(r1: Self, r2: Self) bool {
        return !(r1.x > r2.x + r2.w or r2.x > r1.x + r1.w or r1.y > r2.y + r2.h or r2.y > r1.y + r1.h);
    }

    pub fn overlapExclusive(r1: Self, r2: Self) bool {
        return !(r1.x >= r2.x + r2.w or r2.x >= r1.x + r1.w or r1.y >= r2.y + r2.h or r2.y >= r1.y + r1.h);
    }

    pub fn newV(_pos: Vec2f, dim_: Vec2f) @This() {
        return .{ .x = _pos.x, .y = _pos.y, .w = dim_.x, .h = dim_.y };
    }

    pub fn addV(self: @This(), x: anytype, y: anytype) @This() {
        return .{ .x = self.x + lcast(f32, x), .y = self.y + lcast(f32, y), .w = self.w, .h = self.h };
    }

    pub fn setPos(self: @This(), pos_: Vec2f) @This() {
        return .{
            .x = pos_.x,
            .y = pos_.y,
            .w = self.w,
            .h = self.h,
        };
    }

    pub fn subVec(self: Self, s: Vec2f) Self {
        return .{ .x = self.x - s.x, .y = self.y - s.y, .w = self.w, .h = self.h };
    }

    pub fn addVec(self: @This(), v: Vec2f) @This() {
        return .{ .x = self.x + v.x, .y = self.y + v.y, .w = self.w, .h = self.h };
    }

    pub fn mul(self: Self, scalar: f32) Self {
        return .{ .x = self.x * scalar, .y = self.y * scalar, .w = self.w * scalar, .h = self.h * scalar };
    }

    pub fn vmul(self: Self, v: Vec2f) @This() {
        return .{ .x = self.x * v.x, .y = self.y * v.y, .w = self.w * v.x, .h = self.h * v.y };
    }

    pub fn inset(self: Self, amount: f32) Self {
        return .{ .x = self.x + amount, .y = self.y + amount, .w = self.w - amount * 2, .h = self.h - amount * 2 };
    }

    pub fn centerR(self: Self, w: f32, h: f32) Self {
        return self.insetV((self.w - w) / 2, (self.h - h) / 2);
    }

    pub fn insetV(self: Self, ax: f32, ay: f32) Self {
        return .{ .x = self.x + ax, .y = self.y + ay, .w = self.w - ax * 2, .h = self.h - ay * 2 };
    }

    pub fn dimR(self: Self) Self {
        return .{ .x = 0, .y = 0, .w = self.w, .h = self.h };
    }

    pub fn dim(self: Self) Vec2f {
        return Vec2f.new(self.w, self.h);
    }

    pub fn pos(self: Self) Vec2f {
        return .{ .x = self.x, .y = self.y };
    }

    pub fn topL(self: Self) Vec2f {
        return .{ .x = self.x, .y = self.y };
    }

    pub fn topR(self: Self) Vec2f {
        return .{ .x = self.x + self.w, .y = self.y };
    }

    pub fn botL(self: Self) Vec2f {
        return .{ .x = self.x, .y = self.y + self.h };
    }

    pub fn botR(self: Self) Vec2f {
        return .{ .x = self.x + self.w, .y = self.y + self.h };
    }

    pub fn farY(self: Self) f32 {
        return self.y + self.h;
    }

    pub fn farX(self: Self) f32 {
        return self.x + self.w;
    }

    pub fn toAbsoluteRect(self: Self) RectBound {
        return .{ .x0 = self.x, .y0 = self.y, .x1 = self.x + self.w, .y1 = self.y + self.h };
    }

    pub fn eql(a: Self, b: Self) bool {
        return (a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h);
    }

    pub fn hull(a: Self, b: Self) Self {
        const x = @min(a.x, b.x);
        const y = @min(a.y, b.y);
        return Rect.NewAny(x, y, @max(a.farX(), b.farX()) - x, @max(a.farY(), b.farY()) - y);
    }

    /// cpos is where the cut should occur, relative to the rectangles origin
    pub fn split(a: Self, orientation: Orientation, cpos: f32) struct { Self, Self } {
        return switch (orientation) {
            .vertical => .{ Self.new(a.x, a.y, cpos, a.h), Self.new(a.x + cpos, a.y, a.w - cpos, a.h) },
            .horizontal => .{ Self.new(a.x, a.y, a.w, cpos), Self.new(a.x, a.y + cpos, a.w, a.h - cpos) },
        };
    }

    //pub fn param(
    //    self: Self,
    //) @This() {
    //    return .{
    //        .x = parseParam(self.x, xop),
    //        .y = parseParam(self.y, yop),
    //        .w = parseParam(self.w, wop),
    //        .h = parseParam(self.h, hop),
    //    };
    //}

    pub fn toIntRect(self: @This(), comptime int_type: type, comptime vec_type: type) vec_type {
        return vec_type{
            .x = @as(int_type, @intFromFloat(self.x)),
            .y = @as(int_type, @intFromFloat(self.y)),
            .w = @as(int_type, @intFromFloat(self.w)),
            .h = @as(int_type, @intFromFloat(self.h)),
        };
    }

    pub fn swapAxis(self: Self) Self {
        return Rect.NewAny(self.y, self.x, self.h, self.w);
    }

    pub fn invX(self: Self) Self {
        return Rect.NewAny(self.x + self.w, self.y, -self.w, self.h);
    }

    pub fn invY(self: Self) Self {
        return Rect.NewAny(self.x, self.y + self.h, self.w, -self.h);
    }

    pub fn replace(self: Self, x: ?f32, y: ?f32, w: ?f32, h: ?f32) Self {
        return .{
            .x = x orelse self.x,
            .y = y orelse self.y,
            .w = w orelse self.w,
            .h = h orelse self.h,
        };
    }
};

pub const Vec2i = struct {
    const Self = @This();
    x: i32,
    y: i32,

    pub fn toF(self: Self) Vec2f {
        return .{ .x = @floatFromInt(self.x), .y = @floatFromInt(self.y) };
    }
};

pub const IRect = struct {
    x: i32,
    y: i32,
    w: i32,
    h: i32,

    pub fn new(x: i32, y: i32, w: i32, h: i32) @This() {
        return .{ .x = x, .y = y, .w = w, .h = h };
    }

    pub fn toF32(self: @This()) Rect {
        return .{ .x = @as(f32, @floatFromInt(self.x)), .y = @as(f32, @floatFromInt(self.y)), .w = @as(f32, @floatFromInt(self.w)), .h = @as(f32, @floatFromInt(self.h)) };
    }
};

pub fn RecV(pos: Vec2f, w: f32, h: f32) Rect {
    return .{ .x = pos.x, .y = pos.y, .w = w, .h = h };
}

pub fn IRec(x: i32, y: i32, w: i32, h: i32) Rect {
    return .{
        .x = @as(f32, @floatFromInt(x)),
        .y = @as(f32, @floatFromInt(y)),
        .w = @as(f32, @floatFromInt(w)),
        .h = @as(f32, @floatFromInt(h)),
    };
}

pub fn rectContainsPoint(r: anytype, p: anytype) bool {
    return (p.x >= r.x and p.x <= r.x + r.w and p.y >= r.y and p.y <= r.y + r.h);
}

pub const Vec2f = packed struct {
    pub const zero = Vec2f{ .x = 0, .y = 0 };
    x: f32,
    y: f32,

    pub fn Zero() @This() {
        return .{ .x = 0, .y = 0 };
    }

    pub fn toArray(self: @This()) [2]f32 {
        return [2]f32{ self.x, self.y };
    }

    pub fn new(x: anytype, y: anytype) @This() {
        return .{
            .x = std.math.lossyCast(f32, x),
            .y = std.math.lossyCast(f32, y),
        };
    }

    pub fn normal(a: @This()) @This() {
        const len = a.length();
        if (len == 0)
            return .{ .x = 0, .y = 0 };
        return a.scale(1.0 / len);
    }

    pub fn dot(a: @This(), b: @This()) f32 {
        return a.x * b.x + a.y * b.y;
    }

    pub fn length(s: @This()) f32 {
        return @sqrt(s.x * s.x + s.y * s.y);
    }

    pub fn mul(s: @This(), b: @This()) @This() {
        return .{ .x = s.x * b.x, .y = s.y * b.y };
    }

    pub fn inv(s: @This()) @This() {
        return .{ .x = 1 / s.x, .y = 1 / s.y };
    }

    pub fn smul(s: @This(), scalar: f32) @This() {
        return .{ .x = s.x * scalar, .y = s.y * scalar };
    }

    pub fn scale(s: @This(), scalar: f32) @This() {
        return .{ .x = s.x * scalar, .y = s.y * scalar };
    }

    pub fn add(a: @This(), b: @This()) @This() {
        return .{ .x = a.x + b.x, .y = a.y + b.y };
    }

    /// a - b
    pub fn sub(a: @This(), b: @This()) @This() {
        return .{ .x = a.x - b.x, .y = a.y - b.y };
    }

    pub fn swapAxis(a: @This()) @This() {
        return .{ .x = a.y, .y = a.x };
    }

    pub fn toI(s: @This(), comptime I: type, comptime V: type) V {
        return V{
            .x = @as(I, @intFromFloat(s.x)),
            .y = @as(I, @intFromFloat(s.y)),
        };
    }
};
pub const Vec3f = packed struct {
    x: f32,
    y: f32,
    z: f32,

    pub fn new(x: f32, y: f32, z: f32) @This() {
        return .{ .x = x, .y = y, .z = z };
    }

    pub fn fromZa(v: za.Vec3) @This() {
        return .{
            .x = v.data[0],
            .y = v.data[1],
            .z = v.data[2],
        };
    }

    pub fn scale(self: @This(), factor: f32) @This() {
        return .{
            .x = self.x * factor,
            .y = self.y * factor,
            .z = self.z * factor,
        };
    }
};

pub const Camera2D = struct {
    const Self = @This();

    cam_area: Rect,
    screen_area: Rect,

    pub fn factor(self: Self) Vec2f {
        const fx = (self.cam_area.w / self.screen_area.w);
        const fy = (self.cam_area.h / self.screen_area.h);
        return .{ .x = fx, .y = fy };
    }

    pub fn syncAspect(self: *Self) void {
        const screen_aspect = self.screen_area.w / self.screen_area.h;
        const cam_aspect = self.cam_area.w / self.cam_area.h;
        if (@abs(screen_aspect - cam_aspect) > 0.1) {
            self.cam_area.w = screen_aspect * self.cam_area.h;
        }
    }

    pub fn toWorld(self: *const Self, local: Rect) Rect {
        const f = self.factor().inv();
        const cam_area = self.cam_area.pos();
        return local.subVec(cam_area).vmul(f).addVec(self.screen_area.pos());
    }

    pub fn toWorldV(self: *const Self, local: Vec2f) Vec2f {
        const f = self.factor().inv();
        const cam_area = self.cam_area.pos();
        return local.sub(cam_area).mul(f).add(self.screen_area.pos());
    }

    pub fn toCamV(self: *const Self, world: Vec2f) Vec2f {
        const f = self.factor();
        const cam_area = self.cam_area.pos();
        const v = world.sub(self.screen_area.pos()).mul(f).add(cam_area);
        return v;
    }

    pub fn toCam(self: *const Self, world: Rect) Rect {
        const f = self.factor();
        const cam_area = self.cam_area.pos();
        const v = world.subVec(self.screen_area.pos()).vmul(f).addVec(cam_area);
        return v;
    }

    pub fn zoom(self: *Self, dist_: f32, zoom_target: Vec2f, w_range: ?Vec2f, h_range: ?Vec2f) void {
        var dist = dist_;
        if (@abs(dist) > 0.00001) {
            const m_init = self.toCamV(zoom_target);
            var h = self.cam_area.w * dist;

            if (w_range) |wr| {
                const inith = self.cam_area.w - h * 2;
                if (inith < wr.x) {
                    dist = (1 - wr.x / self.cam_area.w) / 2;
                } else if (inith > wr.y) {
                    dist = (1 - wr.y / self.cam_area.w) / 2;
                    //minw = self.cam_area.w - (self.cam_area.w * dist) * 2;
                    //minw = caw * ( 1-2dist)
                    //dist = (1 - minw / caw) / 2
                }
            }
            var v = self.cam_area.h * dist;
            if (h_range) |hr| {
                const initw = self.cam_area.h - v * 2;
                if (initw < hr.x) {
                    dist = (1 - hr.x / self.cam_area.h) / 2;
                } else if (initw > hr.y) {
                    dist = (1 - hr.y / self.cam_area.h) / 2;
                }
            }

            h = self.cam_area.w * dist;
            v = self.cam_area.h * dist;

            self.cam_area.x += h;
            self.cam_area.w -= h * 2;

            self.cam_area.y += v;
            self.cam_area.h -= v * 2;
            const m_final = self.toCamV(zoom_target);
            self.cam_area = self.cam_area.subVec(m_final.sub(m_init));
        }
    }

    pub fn pan(self: *Self, mouse_delta: Vec2f) void {
        self.cam_area = self.cam_area.subVec(mouse_delta.mul(self.factor()));
    }
};

pub const Camera3D = struct {
    const Self = @This();
    pub const MoveState = struct {
        down: bool = false,
        up: bool = false,
        fwd: bool = false,
        bwd: bool = false,
        left: bool = false,
        right: bool = false,
        mouse_delta: Vec2f = .{ .x = 0, .y = 0 },
        scroll_delta: f32 = 0,
        speed_perc: f32 = 1, // The percentage of move speed we move at
    };
    pos: za.Vec3 = za.Vec3.new(0, 0, 0),
    front: za.Vec3 = za.Vec3.new(0, 0, 0),
    yaw: f32 = 0,
    pitch: f32 = 0,
    move_speed: f32 = 0.1,
    max_move_speed: f32 = 10,
    fov: f32 = 85,

    //With planar movement, fwd and back function like strafe keys, not changing the z component
    //normal moves position along camera's normal.
    fwd_back_kind: enum { planar, normal } = .normal,

    up: enum { x, y, z } = .y,

    near: f32 = 1,
    far: f32 = 4096,

    //Good default:
    //camera.updateDebugMove(.{
    //        .down = win.keyHigh(.LSHIFT),
    //        .up = win.keyHigh(.SPACE),
    //        .left = win.keyHigh(.A),
    //        .right = win.keyHigh(.D),
    //        .fwd = win.keyHigh(.W),
    //        .bwd = win.keyHigh(.S),
    //        .mouse_delta = win.mouse.delta,
    //        .scroll_delta = win.mouse.wheel_delta.y,
    //    });
    pub fn updateDebugMove(self: *Self, state: MoveState) void {
        const up = self.getUp();
        var move_vec = za.Vec3.new(0, 0, 0);
        const fwd_back = switch (self.fwd_back_kind) {
            .planar => self.front.mul(za.Vec3.set(1).sub(up)),
            .normal => self.front,
        };
        if (state.down)
            move_vec = move_vec.add(up.scale(-1));
        if (state.up)
            move_vec = move_vec.add(up);
        if (state.fwd)
            move_vec = move_vec.add(fwd_back);
        if (state.bwd)
            move_vec = move_vec.add(fwd_back.scale(-1));
        if (state.left)
            move_vec = move_vec.add(self.front.cross(up).norm().scale(-1));
        if (state.right)
            move_vec = move_vec.add(self.front.cross(up).norm());

        self.pos = self.pos.add(move_vec.norm().scale(self.move_speed * state.speed_perc));
        const mdelta = state.mouse_delta.smul(0.1);
        self.move_speed = std.math.clamp(self.move_speed + state.scroll_delta * (self.move_speed / 10), 0.01, self.max_move_speed);

        self.yaw += mdelta.x;
        self.yaw = @mod(self.yaw, 360);
        self.pitch = std.math.clamp(self.pitch - mdelta.y, -89, 89);

        self.setFront();
    }

    pub fn getUp(self: Self) za.Vec3 {
        return switch (self.up) {
            .x => za.Vec3.new(1, 0, 0),
            .y => za.Vec3.new(0, 1, 0),
            .z => za.Vec3.new(0, 0, 1),
        };
    }

    fn setFront(self: *Self) void {
        const sin = std.math.sin;
        const rad = std.math.degreesToRadians;
        const cos = std.math.cos;
        const xf = cos(rad(self.yaw)) * cos(rad(self.pitch));
        const zf = sin(rad(self.pitch));
        const yf = sin(rad(self.yaw)) * cos(rad(self.pitch));
        const dir = switch (self.up) {
            .x => za.Vec3.new(zf, xf, yf), //TODO this might be wrong
            .y => za.Vec3.new(xf, zf, yf),
            .z => za.Vec3.new(yf, xf, zf),
        };
        self.front = dir.norm();
    }

    pub fn getViewMatrix(self: Self) za.Mat4 {
        const la = za.lookAt(self.pos, self.pos.add(self.front), self.getUp());
        return la;
    }

    pub fn getMatrix(self: Self, aspect_ratio: f32) za.Mat4 {
        const la = self.getViewMatrix();
        const perp = za.perspective(self.fov, aspect_ratio, self.near, self.far);
        return perp.mul(la);
    }
};

pub const Colori = struct {
    pub const DarkGreen: u32 = (0x006400ff);
    pub const Green: u32 = (0x008000ff);
    pub const DarkOliveGreen: u32 = (0x556B2Fff);
    pub const ForestGreen: u32 = (0x228B22ff);
    pub const SeaGreen: u32 = (0x2E8B57ff);
    pub const Olive: u32 = (0x808000ff);
    pub const OliveDrab: u32 = (0x6B8E23ff);
    pub const MediumSeaGreen: u32 = (0x3CB371ff);
    pub const LimeGreen: u32 = (0x32CD32ff);
    pub const Lime: u32 = (0x00FF00ff);
    pub const SpringGreen: u32 = (0x00FF7Fff);
    pub const MediumSpringGreen: u32 = (0x00FA9Aff);
    pub const DarkSeaGreen: u32 = (0x8FBC8Fff);
    pub const MediumAquamarine: u32 = (0x66CDAAff);
    pub const YellowGreen: u32 = (0x9ACD32ff);
    pub const LawnGreen: u32 = (0x7CFC00ff);
    pub const Chartreuse: u32 = (0x7FFF00ff);
    pub const LightGreen: u32 = (0x90EE90ff);
    pub const GreenYellow: u32 = (0xADFF2Fff);
    pub const PaleGreen: u32 = (0x98FB98ff);
    pub const MistyRose: u32 = (0xFFE4E1ff);
    pub const AntiqueWhite: u32 = (0xFAEBD7ff);
    pub const Linen: u32 = (0xFAF0E6ff);
    pub const Beige: u32 = (0xF5F5DCff);
    pub const WhiteSmoke: u32 = (0xF5F5F5ff);
    pub const LavenderBlush: u32 = (0xFFF0F5ff);
    pub const OldLace: u32 = (0xFDF5E6ff);
    pub const AliceBlue: u32 = (0xF0F8FFff);
    pub const Seashell: u32 = (0xFFF5EEff);
    pub const GhostWhite: u32 = (0xF8F8FFff);
    pub const Honeydew: u32 = (0xF0FFF0ff);
    pub const FloralWhite: u32 = (0xFFFAF0ff);
    pub const Azure: u32 = (0xF0FFFFff);
    pub const MintCream: u32 = (0xF5FFFAff);
    pub const Snow: u32 = (0xFFFAFAff);
    pub const Ivory: u32 = (0xFFFFF0ff);
    pub const White: u32 = (0xFFFFFFff);
    pub const Black: u32 = (0x000000ff);
    pub const DarkSlateGray: u32 = (0x2F4F4Fff);
    pub const DimGray: u32 = (0x696969ff);
    pub const SlateGray: u32 = (0x708090ff);
    pub const Gray: u32 = (0x808080ff);
    pub const LightSlateGray: u32 = (0x778899ff);
    pub const DarkGray: u32 = (0xA9A9A9ff);
    pub const Silver: u32 = (0xC0C0C0ff);
    pub const LightGray: u32 = (0xD3D3D3ff);
    pub const Gainsboro: u32 = (0xDCDCDCff);
    pub const Indigo: u32 = (0x4B0082ff);
    pub const Purple: u32 = (0x800080ff);
    pub const DarkMagenta: u32 = (0x8B008Bff);
    pub const DarkViolet: u32 = (0x9400D3ff);
    pub const DarkSlateBlue: u32 = (0x483D8Bff);
    pub const BlueViolet: u32 = (0x8A2BE2ff);
    pub const DarkOrchid: u32 = (0x9932CCff);
    pub const Fuchsia: u32 = (0xFF00FFff);
    pub const Magenta: u32 = (0xFF00FFff);
    pub const SlateBlue: u32 = (0x6A5ACDff);
    pub const MediumSlateBlue: u32 = (0x7B68EEff);
    pub const MediumOrchid: u32 = (0xBA55D3ff);
    pub const MediumPurple: u32 = (0x9370DBff);
    pub const Orchid: u32 = (0xDA70D6ff);
    pub const Violet: u32 = (0xEE82EEff);
    pub const Plum: u32 = (0xDDA0DDff);
    pub const Thistle: u32 = (0xD8BFD8ff);
    pub const Lavender: u32 = (0xE6E6FAff);
    pub const MidnightBlue: u32 = (0x191970ff);
    pub const Navy: u32 = (0x000080ff);
    pub const DarkBlue: u32 = (0x00008Bff);
    pub const MediumBlue: u32 = (0x0000CDff);
    pub const Blue: u32 = (0x0000FFff);
    pub const RoyalBlue: u32 = (0x4169E1ff);
    pub const SteelBlue: u32 = (0x4682B4ff);
    pub const DodgerBlue: u32 = (0x1E90FFff);
    pub const DeepSkyBlue: u32 = (0x00BFFFff);
    pub const CornflowerBlue: u32 = (0x6495EDff);
    pub const SkyBlue: u32 = (0x87CEEBff);
    pub const LightSkyBlue: u32 = (0x87CEFAff);
    pub const LightSteelBlue: u32 = (0xB0C4DEff);
    pub const LightBlue: u32 = (0xADD8E6ff);
    pub const PowderBlue: u32 = (0xB0E0E6ff);
    pub const Teal: u32 = (0x008080ff);
    pub const DarkCyan: u32 = (0x008B8Bff);
    pub const LightSeaGreen: u32 = (0x20B2AAff);
    pub const CadetBlue: u32 = (0x5F9EA0ff);
    pub const DarkTurquoise: u32 = (0x00CED1ff);
    pub const MediumTurquoise: u32 = (0x48D1CCff);
    pub const Turquoise: u32 = (0x40E0D0ff);
    pub const Aqua: u32 = (0x00FFFFff);
    pub const Cyan: u32 = (0x00FFFFff);
    pub const Aquamarine: u32 = (0x7FFFD4ff);
    pub const PaleTurquoise: u32 = (0xAFEEEEff);
    pub const LightCyan: u32 = (0xE0FFFFff);
    pub const MediumVioletRed: u32 = (0xC71585ff);
    pub const DeepPink: u32 = (0xFF1493ff);
    pub const PaleVioletRed: u32 = (0xDB7093ff);
    pub const HotPink: u32 = (0xFF69B4ff);
    pub const LightPink: u32 = (0xFFB6C1ff);
    pub const Pink: u32 = (0xFFC0CBff);
    pub const DarkRed: u32 = (0x8B0000ff);
    pub const Red: u32 = (0xFF0000ff);
    pub const Firebrick: u32 = (0xB22222ff);
    pub const Crimson: u32 = (0xDC143Cff);
    pub const IndianRed: u32 = (0xCD5C5Cff);
    pub const LightCoral: u32 = (0xF08080ff);
    pub const Salmon: u32 = (0xFA8072ff);
    pub const DarkSalmon: u32 = (0xE9967Aff);
    pub const LightSalmon: u32 = (0xFFA07Aff);
    pub const OrangeRed: u32 = (0xFF4500ff);
    pub const Tomato: u32 = (0xFF6347ff);
    pub const DarkOrange: u32 = (0xFF8C00ff);
    pub const Coral: u32 = (0xFF7F50ff);
    pub const Orange: u32 = (0xFFA500ff);
    pub const DarkKhaki: u32 = (0xBDB76Bff);
    pub const Gold: u32 = (0xFFD700ff);
    pub const Khaki: u32 = (0xF0E68Cff);
    pub const PeachPuff: u32 = (0xFFDAB9ff);
    pub const Yellow: u32 = (0xFFFF00ff);
    pub const PaleGoldenrod: u32 = (0xEEE8AAff);
    pub const Moccasin: u32 = (0xFFE4B5ff);
    pub const PapayaWhip: u32 = (0xFFEFD5ff);
    pub const LightGoldenrodYellow: u32 = (0xFAFAD2ff);
    pub const LemonChiffon: u32 = (0xFFFACDff);
    pub const LightYellow: u32 = (0xFFFFE0ff);
    pub const Maroon: u32 = (0x800000ff);
    pub const Brown: u32 = (0xA52A2Aff);
    pub const SaddleBrown: u32 = (0x8B4513ff);
    pub const Sienna: u32 = (0xA0522Dff);
    pub const Chocolate: u32 = (0xD2691Eff);
    pub const DarkGoldenrod: u32 = (0xB8860Bff);
    pub const Peru: u32 = (0xCD853Fff);
    pub const RosyBrown: u32 = (0xBC8F8Fff);
    pub const Goldenrod: u32 = (0xDAA520ff);
    pub const SandyBrown: u32 = (0xF4A460ff);
    pub const Tan: u32 = (0xD2B48Cff);
    pub const Burlywood: u32 = (0xDEB887ff);
    pub const Wheat: u32 = (0xF5DEB3ff);
    pub const NavajoWhite: u32 = (0xFFDEADff);
    pub const Bisque: u32 = (0xFFE4C4ff);
    pub const BlanchedAlmond: u32 = (0xFFEBCDff);
    pub const Cornsilk: u32 = (0xFFF8DCff);
};

pub fn intColorFromVec3(v: za.Vec3, factor: f32) u32 {
    return charColorToInt(.{
        .r = @intFromFloat(std.math.clamp(v.x() * factor, 0, 255)),
        .g = @intFromFloat(std.math.clamp(v.y() * factor, 0, 255)),
        .b = @intFromFloat(std.math.clamp(v.z() * factor, 0, 255)),
        .a = 255,
    });
}

pub const CharColor = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub fn newFloat(r: f32, g: f32, b: f32, a: f32) CharColor {
        return .{
            .r = @intFromFloat(r * 255),
            .g = @intFromFloat(g * 255),
            .b = @intFromFloat(b * 255),
            .a = @intFromFloat(a * 255),
        };
    }

    pub fn newFloatF(r: f32, g: f32, b: f32, a: f32, fac: f32) CharColor {
        return .{
            .r = @intFromFloat(std.math.clamp(r * fac, 0, 255)),
            .g = @intFromFloat(std.math.clamp(g * fac, 0, 255)),
            .b = @intFromFloat(std.math.clamp(b * fac, 0, 255)),
            .a = @intFromFloat(std.math.clamp(a * fac, 0, 255)),
        };
    }

    pub fn new(r: u8, g: u8, b: u8, a: u8) CharColor {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }
    pub fn toFloat(col: CharColor) Color {
        return .{
            @as(f32, @floatFromInt(col.r)) / 255.0,
            @as(f32, @floatFromInt(col.g)) / 255.0,
            @as(f32, @floatFromInt(col.b)) / 255.0,
            @as(f32, @floatFromInt(col.a)) / 255.0,
        };
    }
};
//TODO orginize colors, we have 4 different types of colors
//hsva, (4 f32)
//u32
//Rgba (4 u8)
//Rgba (4 F32)

pub const Hsva = struct {
    h: f32,
    s: f32,
    v: f32,
    a: f32,

    pub fn fromInt(int: u32) @This() {
        return colorToHsva(intToColor(int));
    }

    pub fn toFloat(hsva: Hsva) Color {
        return intToColorF(hsva.toInt());
    }

    pub fn toInt(hsva: Hsva) u32 {
        //HSV
        //S is the x axis
        //V is the y axis
        const H = @min(hsva.h, 360);
        const S = @min(hsva.s, 1);
        const V = @min(hsva.v, 1);

        const C = V * S;
        const hp = (@mod(H, 360)) / 60.0;
        const X = C * (1 - @abs(@mod(hp, 2) - 1));
        const rgb1 = switch (@as(u32, @intFromFloat(hp))) {
            0 => za.Vec3.new(C, X, 0),
            1 => za.Vec3.new(X, C, 0),
            2 => za.Vec3.new(0, C, X),
            3 => za.Vec3.new(0, X, C),
            4 => za.Vec3.new(X, 0, C),
            5 => za.Vec3.new(C, 0, X),
            else => za.Vec3.new(0, 0, 0), //This should be optimized out
        };
        const M = V - C;

        return (@as(u32, @intFromFloat((M + rgb1.data[0]) * 255)) << 24) |
            (@as(u32, @intFromFloat((M + rgb1.data[1]) * 255))) << 16 |
            (@as(u32, @intFromFloat((M + rgb1.data[2]) * 255))) << 8 |
            (@as(u32, @intFromFloat(hsva.a * 255)));
    }
};

pub fn colorToHsva(color: CharColor) Hsva {
    const fl = color.toFloat();
    const max = @max(fl[0], fl[1], fl[2]);
    const min = @min(fl[0], fl[1], fl[2]);
    const C = max - min;

    const r = fl[0];
    const g = fl[1];
    const b = fl[2];

    const M = 0.001;
    const hue: f32 = 60 * blk: {
        if (@abs(C) < M) {
            break :blk 0;
        } else if (@abs(max - r) < M) {
            break :blk @mod((g - b) / C, 6);
        } else if (@abs(max - g) < M) {
            break :blk ((b - r) / C) + 2;
        } else if (@abs(max - b) < M) {
            break :blk ((r - g) / C) + 4;
        }
        break :blk 0; //This should be optimized out
    };

    const sat: f32 = if (@abs(max) < M) 0 else C / max;
    return .{ .h = hue, .s = sat, .v = max, .a = fl[3] };
}

pub fn hsvaToColor(hsva: Hsva) CharColor {
    //HSV
    //S is the x axis
    //V is the y axis
    const H = hsva.h;
    const S = hsva.s;
    const V = hsva.v;

    const C = V * S;
    const hp = (@mod(H, 360)) / 60.0;
    const X = C * (1 - @abs(@mod(hp, 2) - 1));
    const rgb1 = switch (@as(u32, @intFromFloat(hp))) {
        0 => za.Vec3.new(C, X, 0),
        1 => za.Vec3.new(X, C, 0),
        2 => za.Vec3.new(0, C, X),
        3 => za.Vec3.new(0, X, C),
        4 => za.Vec3.new(X, 0, C),
        5 => za.Vec3.new(C, 0, X),
        else => za.Vec3.new(0, 0, 0), //This should be optimized out
    };
    const M = V - C;

    return CharColor.new(
        @as(u8, @intFromFloat((M + rgb1.data[0]) * 255)),
        @as(u8, @intFromFloat((M + rgb1.data[1]) * 255)),
        @as(u8, @intFromFloat((M + rgb1.data[2]) * 255)),
        @as(u8, @intFromFloat(hsva.a * 255)),
    );
}

pub fn charColorToInt(co: CharColor) u32 {
    return (@as(u32, @intCast(co.r)) << 24) | (@as(u32, @intCast(co.g)) << 16) | (@as(u32, @intCast(co.b)) << 8) | co.a;
}

pub const itc = intToColor;

pub fn intToColor(color: u32) CharColor {
    return .{
        .r = @as(u8, @intCast((color >> 24) & 0xff)),
        .g = @as(u8, @intCast((color >> 16) & 0xff)),
        .b = @as(u8, @intCast((color >> 8) & 0xff)),
        .a = @as(u8, @intCast((color) & 0xff)),
    };
}

pub fn intToColorF(color: u32) Color {
    return intToColor(color).toFloat();
}

pub const Color = [4]f32;
