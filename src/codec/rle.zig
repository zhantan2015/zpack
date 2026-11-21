const std = @import("std");
const Reader = std.Io.Reader;
const Writer = std.Io.Writer;
pub fn rleCodecGetCrc(reader: *Reader, writer: *Writer) !u32 {
    var hasher = std.hash.Crc32.init();
    var bytes: []u8 = reader.buffered();
    while (true) : (bytes = reader.buffered()) {
        if (bytes.len == 0) {
            reader.fillMore() catch |err| {
                if (err == error.EndOfStream) break;
                return err;
            };
            continue;
        }
        hasher.update(bytes);
        var count: u8 = 0;
        var current_byte: u8 = undefined;
        for (bytes) |b| {
            if (count == 0) {
                current_byte = b;
                count = 1;
            } else if (b != current_byte or count == 255) {
                if (count > 0) {
                    try writer.writeByte(count);
                    try writer.writeByte(current_byte);
                }
                current_byte = b;
                count = 1;
            } else {
                count += 1;
            }
        }
        try writer.writeByte(count);
        try writer.writeByte(current_byte);
        reader.toss(bytes.len);
    }
    return hasher.final();
}

const testing = std.testing;
test "rleCodec测试 - 正确性测试" {
    const input = "aabbccdd";
    var expected = [_]u8{ 2, 'a', 2, 'b', 2, 'c', 2, 'd' };

    var reader = std.Io.Reader.fixed(input);

    var w_buf: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(w_buf[0..]);

    const crc = try rleCodecGetCrc(&reader, &writer);
    try writer.flush();

    try testing.expectEqualSlices(u8, &expected, w_buf[0..8]);
    try testing.expectEqual(std.hash.Crc32.hash(input), crc);
}
test "rleCodec测试 - 空输入测试" {
    const input = "";
    var expected = "";

    var reader = std.Io.Reader.fixed(input);

    var w_buf: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(w_buf[0..]);

    const crc = try rleCodecGetCrc(&reader, &writer);
    try writer.flush();

    try testing.expectEqualSlices(u8, expected[0..], writer.buffered());
    try testing.expectEqual(std.hash.Crc32.hash(input), crc);
}
test "rleCodec测试 - 大文件测试" {
    var input = @as([258]u8, @splat('a')) ++ @as([773]u8, @splat('b'));
    var expected = [_]u8{ 255, 'a', 3, 'a', 255, 'b', 255, 'b', 255, 'b', 8, 'b' };
    var reader = std.Io.Reader.fixed(&input);
    var w_buf: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(w_buf[0..]);
    const crc = try rleCodecGetCrc(&reader, &writer);
    try writer.flush();
    try testing.expectEqualSlices(u8, expected[0..], writer.buffered());
    try testing.expectEqual(std.hash.Crc32.hash(&input), crc);
}
