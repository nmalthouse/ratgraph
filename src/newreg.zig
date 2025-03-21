const std = @import("std");
const SparseSet = @import("graphics/sparse_set.zig").SparseSet;
const CompId = ?usize;

const Ta = struct {
    var Component_id: CompId = null;
    a: f32,
    b: f32,
};

const Tb = struct {
    var Component_id: CompId = null;

    a: f32,
};

const VTable = struct {
    const CreateError = error{ IndexOccupied, OutOfMemory };
    const DestroyError = error{InvalidIndex};
    const DestroyAllError = error{OutOfMemory};

    deinit: *const fn (*@This(), std.mem.Allocator) void,

    create: *const fn (*@This(), id: ID_TYPE, comp_ptr: *const anyopaque) CreateError!void,
    destroy: *const fn (*@This(), id: ID_TYPE) DestroyError!void,
    destroyAll: *const fn (*@This()) DestroyAllError!void,
};

fn wrapStruct(comptime child: type) type {
    return struct {
        set: SparseSet(child, u32),
        vtable: VTable,

        fn Self(vtptr: *VTable) *@This() {
            return @fieldParentPtr("vtable", vtptr);
        }

        pub fn init(alloc: std.mem.Allocator) !@This() {
            return .{
                .set = try SparseSet(child, u32).init(alloc),
                .vtable = .{
                    .deinit = &@This().deinit,
                    .create = &@This().create,
                    .destroy = &@This().destroy,
                    .destroyAll = &@This().destroyAll,
                },
            };
        }

        pub fn create(vtable: *VTable, id: ID_TYPE, comp: *const anyopaque) VTable.CreateError!void {
            const self = Self(vtable);
            try self.set.insert(id, @as(*const child, @alignCast(@ptrCast(comp))).*);
        }

        pub fn destroy(vt: *VTable, id: ID_TYPE) VTable.DestroyError!void {
            const self = Self(vt);
            _ = try self.set.remove(id);
        }

        pub fn destroyAll(vt: *VTable) VTable.DestroyAllError!void {
            const self = Self(vt);
            try self.set.empty();
        }

        pub fn deinit(vtable: *VTable, alloc: std.mem.Allocator) void {
            const self: *@This() = @fieldParentPtr("vtable", vtable);
            self.set.deinit();
            alloc.destroy(self);
        }
    };
}

const ID_TYPE = u32;
const Reg = struct {
    const Self = @This();
    const MAX_COMPONENT = 63;
    const tombstone_component = MAX_COMPONENT - 1;
    pub const EntBitset = std.bit_set.StaticBitSet(MAX_COMPONENT + 1);

    comp_counter: usize = 0,
    vtables: std.ArrayList(*VTable),
    alloc: std.mem.Allocator,

    entities: std.ArrayList(EntBitset),

    pub fn init(alloc: std.mem.Allocator) Self {
        return .{
            .alloc = alloc,
            .vtables = std.ArrayList(*VTable).init(alloc),
            .entities = std.ArrayList(EntBitset).init(alloc),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.vtables.items) |vt| {
            vt.deinit(vt, self.alloc);
        }
        self.vtables.deinit();
        self.entities.deinit();
    }

    fn getVtable(self: *Self, comp_index: usize) *VTable {
        return @alignCast(@ptrCast(self.vtables.items[comp_index]));
    }

    pub fn register(self: *Self, comptime T: type) !void {
        if (self.comp_counter >= MAX_COMPONENT) return error.OutOfComponentIds;
        if (@hasDecl(T, "Component_id")) {
            const cid = @field(T, "Component_id");
            if (@TypeOf(cid) != CompId) @compileError("must be of type CompId");

            if (@field(T, "Component_id") != null) {
                return error.mustBeNull;
            }
            @field(T, "Component_id") = self.comp_counter;
            const wrap = wrapStruct(T);
            const new_set = try self.alloc.create(wrap);
            new_set.* = try wrap.init(self.alloc);
            try self.vtables.append(&new_set.vtable);

            self.comp_counter += 1;
        } else {
            @compileError("Component must decl");
        }
    }

    pub fn attach(self: *Self, id: u32, comp: anytype) !void {
        const compT = @TypeOf(comp);
        if (!@hasDecl(compT, "Component_id")) @compileError("not a component");
        const cid = compT.Component_id orelse return error.ComponentNotRegistered;

        const ent = try self.getEntity(id);
        if (ent.isSet(cid)) return error.ComponentAlreadyAttached;

        const ptr = self.getVtable(cid);
        try ptr.create(ptr, id, @ptrCast(&comp));
        ent.set(cid);
    }

    pub fn createEntity(self: *Self) !ID_TYPE {
        const index: ID_TYPE = @intCast(self.entities.items.len);
        try self.entities.append(EntBitset.initEmpty());
        return index;
    }

    pub fn getEntity(self: *const Self, entity_index: ID_TYPE) !*EntBitset {
        if (entity_index >= self.entities.items.len) {
            std.debug.print("ID {d}\n", .{entity_index});
            return error.invalidEntityId;
        }

        const ent = &self.entities.items[entity_index];
        if (ent.isSet(tombstone_component)) {
            std.debug.print("ID {d}\n", .{entity_index});
            return error.invalidEntityId;
        }
        return ent;
    }

    pub fn destroyEntity(self: *Self, index: ID_TYPE) !void {
        const ent = try self.getEntity(index);
        for (self.vtables.items, 0..) |vt, i| {
            if (ent.isSet(i))
                try vt.destroy(vt, index);
        }
        //inline for (field_names_l, 0..) |field, i| {
        //    if (ent.isSet(i)) {
        //        var d = (try @field(self.data, field.name).remove(index));
        //        self.call_destroy_callback(@enumFromInt(i), &d, index);
        //    }
        //}
        ent.* = EntBitset.initEmpty();
        ent.set(tombstone_component);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.detectLeaks();
    const alloc = gpa.allocator();
    var reg = Reg.init(alloc);
    defer reg.deinit();

    try reg.register(Tb);
    try reg.register(Ta);
    std.debug.print("{any}\n", .{Tb.Component_id});
    std.debug.print("{any}\n", .{Ta.Component_id});
    const e1 = try reg.createEntity();
    const e2 = try reg.createEntity();
    try reg.attach(e1, Tb{ .a = 0 });
    try reg.attach(e2, Tb{ .a = 1 });
    try reg.destroyEntity(e2);
}
