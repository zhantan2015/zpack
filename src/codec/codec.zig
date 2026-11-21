comptime {
    _ = @import("tests.zig");
}

pub const rleCodecGetCrc = @import("./rle.zig").rleCodecGetCrc;
