const std = @import("std");
const graph = @import("../graphics.zig");

pub const EventCb = fn (user: *iEvent, data: ?*anyopaque) void;
pub const iEvent = struct {
    cb: *const EventCb,
};

pub const EventId = enum(u32) {
    _,
};

pub const ListenerId = enum(u32) {
    _,
};

pub const Event = struct {
    subs: std.ArrayList(ListenerId) = .{},

    /// Force waitEvent to switch to minimum wait time when pushed
    force_redraw: bool,

    size: usize = 0,
};

pub const EventCtx = struct {
    const ArrayList = std.ArrayListUnmanaged;
    pub var SdlEventPokeId: u32 = 0;
    pub var SdlEventAllocId: u32 = 0;
    const Self = @This();

    alloc: std.mem.Allocator,
    listeners: ArrayList(*iEvent) = .{},

    events: ArrayList(Event) = .{},

    pub fn create(alloc: std.mem.Allocator) !*Self {
        const ret = try alloc.create(Self);
        ret.* = .{
            .alloc = alloc,
        };
        return ret;
    }

    pub fn destroy(self: *Self) void {
        self.listeners.deinit(self.alloc);
        for (self.events.items) |*sub|
            sub.deinit(self.alloc);
        self.events.deinit(self.alloc);
        self.alloc.destroy(self);
    }

    pub fn registerEvent(self: *Self, opts: struct { force_redraw: bool = false }) !EventId {
        const id = self.listeners.items.len;
        try self.events.append(self.alloc, .{ .force_redraw = opts.force_redraw });
        return @enumFromInt(id);
    }

    pub fn registerListener(self: *Self, l: *iEvent) !ListenerId {
        const id = self.listeners.items.len;
        try self.listeners.append(self.alloc, l);
        return @enumFromInt(id);
    }

    pub fn subscribe(self: *Self, listener: usize, event_id: EventId) !void {
        if (listener >= self.listeners.items.len) return error.invalidListener;

        if (@intFromEnum(event_id) >= self.events.items.len) return error.invalidEventId;

        try self.events.items[@intFromEnum(event_id)].subs.append(self.alloc, listener);
    }

    ///Thread safe
    pub fn pushEventPoke(self: *Self, event_id: EventId, event_ptr: ?*anyopaque) void {
        graph.SDL.pushEvent(SdlEventPokeId, @intFromEnum(event_id), @ptrCast(self), event_ptr) catch {
            std.debug.print("Error creating sdl event\n", .{});
        };
    }

    pub fn graph_event_cb(ev: graph.c.SDL_UserEvent) void {
        if (ev.type == SdlEventPokeId) {
            const self: *Self = @ptrCast(@alignCast(ev.data1 orelse return));
            const id = ev.code;
            if (id >= 0 and id < self.events.items.len) {
                for (self.events.items[@intCast(id)].subs.items) |sub| {
                    const l = self.listeners.items[sub];
                    l.cb(l, ev.data2);
                }
            } else {
                std.debug.print("Invalid event id {d}\n", .{id});
            }
        } else if (ev.type == SdlEventAllocId) {} else {
            std.debug.print("unknown sdl event {d}\n", .{ev.type});
        }
    }
};
