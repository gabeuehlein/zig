export fn a() void {
    const E = enum {};
    var e: E = undefined;
    _ = &e;
    _ = @intFromEnum(e);
    // :2:15: note: enum declared here
}

// error
// backend=stage2
// target=native
//
// :2:15: error: uninstantiable exhaustive enum must have an explicit tag type of noreturn
