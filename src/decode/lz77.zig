const std = @import("std");
const Errors = @import("common").Errors;
const DecodeError = Errors.DecodeError;

pub fn lz77DecodeGetCrc(reader: *std.Io.Reader, writer: *std.Io.Writer, original_size: u64) !u32 {
    var hasher = std.hash.Crc32.init();
    var w_buf: [4 * 1024]u8 = undefined;
    var total_fill_len: usize = 0;
    var curr_fill_len: usize = 0;

    var bytes: []u8 = reader.buffered();
    // std.debug.print("---------original_size:{d} - total_fill_len:{d}\r\n", .{ original_size, total_fill_len });
    while (total_fill_len < original_size) : (bytes = reader.buffered()) {
        if (bytes.len < 3) {
            reader.fillMore() catch |err| {
                // std.debug.print("------------err:{}\r\n", .{err});
                if (err == error.EndOfStream) return DecodeError.CorruptData;
                return err;
            };
            continue;
        }

        var idx: usize = 0;
        while (idx < bytes.len) : (idx += 3) {
            // std.debug.print("{d}:{s}\r\n", .{ total_fill_len, w_buf[0..total_fill_len] });

            const offset = bytes[idx];
            const length = bytes[idx + 1];

            // 没匹配到
            if (offset == 0) {
                if (length > 0) return DecodeError.CorruptData;
                w_buf[curr_fill_len] = bytes[idx + 2];
                curr_fill_len += 1;
                total_fill_len += 1;
                // if (idx < 30)
                //     std.debug.print(
                //         "没匹配到 total_fill_len:{d} - original_size:{d}\r\n",
                //         .{ total_fill_len, original_size },
                //     );
                continue;
            }

            // 数据错误
            if (offset > total_fill_len) return DecodeError.CorruptData;

            // 匹配到开始复制
            for (0..length) |i| {
                _ = i;
                const data_idx = curr_fill_len - offset;
                w_buf[curr_fill_len] = w_buf[data_idx];
                curr_fill_len += 1;
                total_fill_len += 1;
            }
            w_buf[curr_fill_len] = bytes[idx + 2];
            curr_fill_len += 1;
            total_fill_len += 1;

            // 缓冲区不足
            if (curr_fill_len + 255 > w_buf.len or total_fill_len >= original_size) {
                const data = w_buf[0..curr_fill_len];
                try writer.writeAll(data);
                hasher.update(data);
                curr_fill_len = 0;
                break;
            }
            if (idx + 3 > bytes.len) reader.toss(idx);
        }
    }
    if (curr_fill_len > 0) {
        const data = w_buf[0..curr_fill_len];
        try writer.writeAll(data);
        hasher.update(data);
    }
    if (total_fill_len > original_size) return DecodeError.CorruptData;
    return hasher.final();
}

const testing = std.testing;

fn decodeAll(
    input: []const u8,
    original_size: u64,
    out_buf: []u8,
) !struct { out: []u8, crc: u32 } {
    var reader = std.Io.Reader.fixed(input);
    var writer = std.Io.Writer.fixed(out_buf);
    const crc = try lz77DecodeGetCrc(&reader, &writer, original_size);
    return .{ .out = writer.buffered(), .crc = crc };
}

test "lz77: 纯 literal" {
    const input = [_]u8{ 0, 0, 'H', 0, 0, 'i', 0, 0, '!' };
    var out_buf: [16]u8 = undefined;
    const r = try decodeAll(&input, 3, &out_buf);
    try testing.expectEqualStrings("Hi!", r.out);
    try testing.expectEqual(std.hash.Crc32.hash("Hi!"), r.crc);
}

test "lz77: 简单复制" {
    const input = [_]u8{ 0, 0, 'A', 1, 3, 'B' };
    var out_buf: [16]u8 = undefined;
    const r = try decodeAll(&input, 5, &out_buf);
    try testing.expectEqualStrings("AAAAB", r.out);
}

test "lz77: RLE 重叠复制" {
    const input = [_]u8{ 0, 0, 'x', 1, 10, 'x' };
    var out_buf: [16]u8 = undefined;
    const r = try decodeAll(&input, 12, &out_buf);
    try testing.expectEqualStrings("xxxxxxxxxxxx", r.out);
}

test "lz77: CRC 与标准一致" {
    const input = [_]u8{ 0, 0, 'H', 0, 0, 'e', 0, 0, 'l', 0, 0, 'l', 0, 0, 'o' };
    var out_buf: [8]u8 = undefined;
    const r = try decodeAll(&input, 5, &out_buf);
    try testing.expectEqualStrings("Hello", r.out);
    try testing.expectEqual(std.hash.Crc32.hash("Hello"), r.crc);
}

test "lz77: 拒绝 offset 超限" {
    const input = [_]u8{ 2, 1, 'A' };
    var out_buf: [8]u8 = undefined;
    const r = decodeAll(&input, 2, &out_buf);
    try testing.expectError(DecodeError.CorruptData, r);
}

test "lz77: 拒绝 length>0 且 offset=0" {
    const input = [_]u8{ 0, 0, 'A', 0, 1, 'B' };
    var out_buf: [8]u8 = undefined;
    try testing.expectError(DecodeError.CorruptData, decodeAll(&input, 2, &out_buf));
}

test "lz77: 拒绝截断输入" {
    const input = [_]u8{ 0, 0 };
    var out_buf: [8]u8 = undefined;
    try testing.expectError(DecodeError.CorruptData, decodeAll(&input, 1, &out_buf));
}

test "lz77: 拒绝输出超 original_size" {
    const input = [_]u8{ 0, 0, 'A', 0, 0, 'B' };
    var out_buf: [8]u8 = undefined;
    try testing.expectError(DecodeError.CorruptData, decodeAll(&input, 1, &out_buf));
}

test "lz77: 拒绝 length 跨过 original_size" {
    const input = [_]u8{ 0, 0, 'A', 1, 5, 'B' };
    var out_buf: [8]u8 = undefined;
    try testing.expectError(DecodeError.CorruptData, decodeAll(&input, 3, &out_buf));
}
