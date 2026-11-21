const std = @import("std");
const common = @import("common");
const DecodeError = common.Errors.DecodeError;
const testing = std.testing;

pub fn rleDecodeGetCrc(
    reader: *std.Io.Reader,
    writer: *std.Io.Writer,
    original_size: u64,
) !u32 {
    var hasher = std.hash.Crc32.init();

    try decodeImpl(
        original_size,
        reader,
        writer,
        &hasher,
    );

    // crc校验
    const hashed_crc = hasher.final();
    return hashed_crc;
}
fn decodeImpl(
    original_size: u64,
    reader: *std.Io.Reader,
    writer: *std.Io.Writer,
    hasher: *std.hash.Crc32,
) !void {
    var expect_count = true;
    var curr_fill_len: usize = 0;
    var total_fill_len: usize = 0;
    var count: u8 = 0;
    var writer_buffer: [1024]u8 = undefined;
    var consumed: usize = 0;

    while (total_fill_len < original_size) {
        var bytes = reader.buffered();
        if (bytes.len == 0) {
            reader.fillMore() catch |err| {
                if (err == error.EndOfStream) break;
                return err;
            };
            bytes = reader.buffered();
            if (bytes.len == 0) continue;
        }
        for (bytes, 0..bytes.len) |b, idx| {
            consumed = idx + 1;
            // 读计数
            if (expect_count) {
                expect_count = false;

                if (b == 0) return DecodeError.CorruptData;
                count = b;
                total_fill_len += b;
            }
            // 读数据
            else {
                expect_count = true;

                // 缓冲区不足，写流并重置填充计数
                if (curr_fill_len + count > writer_buffer.len) {
                    const data = writer_buffer[0..curr_fill_len];
                    hasher.update(data);
                    try writer.writeAll(data);
                    curr_fill_len = 0;
                }

                // 写入缓冲区、更新填充计数
                @memset(writer_buffer[curr_fill_len .. curr_fill_len + count], b);
                curr_fill_len += count;

                // 已经读满，写入缓冲区剩余数据并重置计数
                if (total_fill_len >= original_size) {
                    const data = writer_buffer[0..curr_fill_len];
                    hasher.update(data);
                    try writer.writeAll(data);
                    curr_fill_len = 0;
                    break;
                }
            }
        }
    }
    if (!expect_count) return DecodeError.CorruptData;

    if (curr_fill_len > 0) {
        const data = writer_buffer[0..curr_fill_len];
        try writer.writeAll(data);
        hasher.update(data);
    }
    reader.toss(consumed);
}
test "rleDecodeGetCrc测试" {
    var expect = "aaabcccc";
    var input = [_]u8{ 3, 'a', 1, 'b', 4, 'c' };
    var reader = std.Io.Reader.fixed(&input);

    var w_buf: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&w_buf);

    const crc = try rleDecodeGetCrc(
        &reader,
        &writer,
        8,
    );
    const hashed_crc = std.hash.Crc32.hash(&input);

    testing.expectEqual(hashed_crc, crc);
    testing.expectEqualSlices(
        u8,
        w_buf[0..expect.len],
        &expect,
    );
    testing.expect(false);
}
