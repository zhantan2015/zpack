const std = @import("std");
const testing = std.testing;

pub fn lz77CodecGetCrc(reader: *std.Io.Reader, writer: *std.Io.Writer) !u32 {
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
        try lz77Impl(bytes, writer);
        hasher.update(bytes);
        reader.toss(bytes.len);
    }
    return hasher.final();
}
fn lz77Write(writer: *std.Io.Writer, offset: u8, len: u8, byte: u8) !void {
    try writer.writeByte(offset);
    try writer.writeByte(len);
    try writer.writeByte(byte);
}
fn lz77Impl(bytes: []const u8, writer: *std.Io.Writer) !void {
    if (bytes.len == 0) return;
    try writer.writeAll(&[_]u8{ 0, 0, bytes[0] });

    var pos: usize = 1;
    while (pos < bytes.len) : (pos += 1) {
        var start: usize = if (pos < 255) 0 else pos - 255;

        var offset: u8 = 0;
        var length: u8 = 0;
        var matched = false;

        var best_offset = offset;
        var best_length = length;
        const original_pos = pos;
        while (start < pos) : (start += 1) {
            if (bytes[start] == bytes[pos] and pos < bytes.len - 1 and length < 255) {
                if (!matched) {
                    offset = @intCast(pos - start);
                    matched = true;
                }
                length += 1;
                pos += 1;
                continue;
            } else {
                if (length > best_length) {
                    best_length = length;
                    best_offset = offset;
                }
                offset = 0;
                length = 0;
                matched = false;
                pos = original_pos;
                continue;
            }
        }
        pos = original_pos + best_length;
        try lz77Write(writer, best_offset, best_length, bytes[pos]);
    }
}

// ============================================================
// 测试专用简易 LZ77 解码器
// 不依赖用户代码，纯验证"token 流能否还原出原文"
// 每个 token 固定 3 字节: { offset(u8), length(u8), next_byte }
// ============================================================
fn simpleDecode(alloc: std.mem.Allocator, tokens: []const u8) ![]u8 {
    if (tokens.len % 3 != 0) return error.BadTokenStream;
    var out: std.ArrayListUnmanaged(u8) = .empty;
    errdefer out.deinit(alloc);

    var i: usize = 0;
    while (i < tokens.len) : (i += 3) {
        const off: usize = tokens[i];
        const len: usize = tokens[i + 1];
        const next = tokens[i + 2];

        if (off > out.items.len) return error.CorruptOffset;
        for (0..len) |_| {
            const src = out.items.len - off;
            try out.append(alloc, out.items[src]);
        }
        try out.append(alloc, next);
    }
    return out.toOwnedSlice(alloc);
}
const GUARD_CAP = 4096;
const SMALL_CAP = 128;

fn encodeOrLoop(input: []const u8, out: []u8) !usize {
    var writer = std.Io.Writer.fixed(out);
    try lz77Impl(input, &writer);
    return writer.end;
}

fn expectEncoded(input: []const u8, expected: []const u8) !void {
    var buf: [SMALL_CAP]u8 = undefined;
    const n = try encodeOrLoop(input, &buf);
    try testing.expectEqual(expected.len, n);
    try testing.expectEqualSlices(u8, expected, buf[0..n]);
}

fn expectRoundTrip(input: []const u8) !void {
    var buf: [GUARD_CAP]u8 = undefined;
    const n = try encodeOrLoop(input, &buf);
    const decoded = try simpleDecode(testing.allocator, buf[0..n]);
    defer testing.allocator.free(decoded);
    try testing.expectEqualSlices(u8, input, decoded);
}

test "empty and one byte" {
    var buf: [16]u8 = undefined;
    try testing.expectEqual(@as(usize, 0), try encodeOrLoop("", &buf));

    const n = try encodeOrLoop("x", &buf);
    try testing.expectEqualSlices(u8, &[_]u8{ 0, 0, 'x' }, buf[0..n]);
}

test "no match keeps every byte" {
    try expectEncoded("ab", &[_]u8{
        0, 0, 'a',
        0, 0, 'b',
    });

    try expectEncoded("abc", &[_]u8{
        0, 0, 'a',
        0, 0, 'b',
        0, 0, 'c',
    });
}

test "simple repeat matches" {
    try expectEncoded("aaaa", &[_]u8{
        0, 0, 'a',
        1, 2, 'a',
    });

    try expectEncoded("abcabc", &[_]u8{
        0, 0, 'a',
        0, 0, 'b',
        0, 0, 'c',
        3, 2, 'c',
    });
}

test "match followed by different tail" {
    try expectEncoded("abcabcd", &[_]u8{
        0, 0, 'a',
        0, 0, 'b',
        0, 0, 'c',
        3, 3, 'd',
    });

    try expectEncoded("abcabcxyz", &[_]u8{
        0, 0, 'a',
        0, 0, 'b',
        0, 0, 'c',
        3, 3, 'x',
        0, 0, 'y',
        0, 0, 'z',
    });
}

test "append respects total_fill_len" {
    var buf: [32]u8 = undefined;
    buf[0] = 'P';
    buf[1] = 'Q';
    buf[2] = 'R';

    const n = try encodeOrLoop("ab", buf[3..]);
    try testing.expectEqual(@as(usize, 9), 9);

    // prefix untouched
    try testing.expectEqualSlices(u8, "PQR", buf[0..3]);

    // encoded part appended after prefix
    try testing.expectEqualSlices(u8, &[_]u8{
        0, 0, 'a',
        0, 0, 'b',
    }, buf[3 .. n + 3]);
}

const Prng = struct {
    s: u64,

    fn next(self: *Prng) u64 {
        self.s ^= self.s << 13;
        self.s ^= self.s >> 7;
        self.s ^= self.s << 17;
        return self.s;
    }
};

test "fixed-seed roundtrip fuzz" {
    var prng = Prng{ .s = 0x9e3779b97f4a7c15 };
    var storage: [512]u8 = undefined;

    for (0..240) |case_idx| {
        const len: usize = @intCast(prng.next() % (storage.len + 1));
        const mode = case_idx % 4;

        switch (mode) {
            0 => { // random bytes, likely incompressible
                for (storage[0..len]) |*b| b.* = @intCast(prng.next() & 0xff);
            },
            1 => { // all same
                for (storage[0..len]) |*b| b.* = @intCast(prng.next() & 0xff);
                if (len > 0) @memset(storage[0..len], storage[0]);
            },
            2 => { // small alphabet, lots of matches
                for (storage[0..len]) |*b| b.* = @intCast('a' + (prng.next() % 4));
            },
            else => { // periodic pattern
                const pat = "abcde";
                for (storage[0..len], 0..) |*b, i| b.* = pat[i % pat.len];
            },
        }

        try expectRoundTrip(storage[0..len]);
    }
}

test "long runs and window-scale roundtrip" {
    var storage: [600]u8 = undefined;

    @memset(storage[0..300], 'a');
    try expectRoundTrip(storage[0..300]);

    // 跨 255 窗口；不手写 golden，用往返保证不损坏
    for (storage[0..300], 0..) |*b, i| b.* = @intCast((i * 31 + 7) & 0xff);
    try expectRoundTrip(storage[0..300]);

    for (storage[0..600], 0..) |*b, i| b.* = @intCast('a' + (i % 3));
    try expectRoundTrip(storage[0..600]);
}
