comptime {
    _ = @import("tests.zig");
}

const rle = @import("rle.zig");
const lz77 = @import("lz77.zig");

pub const rleDecodeGetCrc = rle.rleDecodeGetCrc;
pub const lz77DecodeGetCrc = lz77.lz77DecodeGetCrc;
