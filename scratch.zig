const std = @import("std");

pub fn main() void {}

comptime {
    const info = @typeInfo(std.ArrayList(u8)).@"struct";
    for (info.fields) |field| {
        @compileLog(field.name, field.type);
    }
    @compileLog(@typeInfo(@TypeOf(std.ArrayList(u8).append)));
    const append_info = @typeInfo(@TypeOf(std.ArrayList(u8).append)).@"fn";
    for (append_info.params) |param| {
        @compileLog(param.type);
    }
    @compileLog(@hasDecl(std.array_list, "Managed"));
    const managed_info = @typeInfo(std.array_list.Managed(u8)).@"struct";
    for (managed_info.fields) |field| {
        @compileLog(field.name, field.type);
    }
    @compileLog(@hasDecl(std, "ArrayListManaged"));
    const managed_type = std.array_list.Managed(u8);
    @compileLog(@typeInfo(@TypeOf(managed_type.init)));
    const managed_init_info = @typeInfo(@TypeOf(managed_type.init)).@"fn";
    for (managed_init_info.params) |param| {
        @compileLog(param.type, param.is_generic);
    }
    @compileLog(@typeInfo(@TypeOf(managed_type.append)));
    const managed_append_info = @typeInfo(@TypeOf(managed_type.append)).@"fn";
    for (managed_append_info.params) |param| {
        @compileLog(param.type, param.is_generic);
    }
    @compileLog(@typeInfo(@TypeOf(managed_type.deinit)));
    @compileLog(@typeInfo(@TypeOf(managed_type.appendSlice)));
    const managed_append_slice_info = @typeInfo(@TypeOf(managed_type.appendSlice)).@"fn";
    for (managed_append_slice_info.params) |param| {
        @compileLog(param.type, param.is_generic);
    }
    @compileLog(@typeInfo(@TypeOf(managed_type.toOwnedSlice)));
    @compileLog(@typeInfo(@TypeOf(managed_type.initCapacity)));
    const managed_init_cap_info = @typeInfo(@TypeOf(managed_type.initCapacity)).@"fn";
    for (managed_init_cap_info.params) |param| {
        @compileLog(param.type, param.is_generic);
    }
}
