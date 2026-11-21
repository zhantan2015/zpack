comptime {
    _ = @import("tests.zig");
}

const rle = @import("rle.zig");

pub const rleDecodeGetCrc = rle.rleDecodeGetCrc;
