const std = @import("std");

fn foo() !void {}
fn bar() void {}

comptime {
    const FooFn = @TypeOf(foo);
    const foo_info = @typeInfo(FooFn);
    const foo_ret = foo_info.@"fn".return_type.?;

    switch (@typeInfo(foo_ret)) {
        .error_union => |err_info| {
            if (err_info.payload != void) {
                @compileError("expected void payload");
            }
        },
        else => @compileError("expected error union"),
    }

    const BarFn = @TypeOf(bar);
    const bar_info = @typeInfo(BarFn);
    const bar_ret = bar_info.@"fn".return_type.?; // this is void

    switch (@typeInfo(bar_ret)) {
        .error_union => @compileError("bar should not be error union"),
        else => {},
    }
}

pub fn main() void {}
