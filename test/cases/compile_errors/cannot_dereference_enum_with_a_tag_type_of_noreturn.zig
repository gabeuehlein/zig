fn entry() void {
    const E = enum(noreturn) {};
    const e = @as(*E, undefined);
    _ = e.*;
}

// error
// backend=stage2
// target=native
//
// :4:10: error: cannot dereference enum with a tag type of noreturn
