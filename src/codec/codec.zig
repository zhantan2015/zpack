comptime {
    _ = @import("tests.zig");
}

pub const rleCodecGetCrc = @import("./rle.zig").rleCodecGetCrc;
pub const lz77CodecGetCrc = @import("lz77.zig").lz77CodecGetCrc;
