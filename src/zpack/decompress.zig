const std = @import("std");
const Streamer = @import("utils.zig").Streamer;
const common = @import("common");
const decode = @import("decode");
const DecodeError = common.Errors.DecodeError;
const CmdError = common.Errors.CmdError;
const ZpackConfig = common.ZpacckConfig;
const CmdInfo = common.CmdInfo;
const testing = std.testing;

pub fn decompress(io: std.Io, gpa: std.mem.Allocator, cmd_info: CmdInfo) !void {
    _ = gpa;
    if (cmd_info.output == null) return CmdError.InvalidArgument;
    var streamer: Streamer = try .init(
        io,
        cmd_info.input,
        cmd_info.output.?,
    );
    defer streamer.deinit();

    var r_buf: [4 * 1024]u8 = undefined;
    var in_reader = streamer.in_file.reader(io, &r_buf);
    const reader = &in_reader.interface;

    var w_buf: [4 * 1024]u8 = undefined;
    var out_writer = streamer.out_file.writer(io, &w_buf);
    const writer = &out_writer.interface;

    const original_size = try readHeaderGetOriginalSize(reader);

    var hashed_crc: ?u32 = null;
    switch (cmd_info.algorithm) {
        .rle => {
            hashed_crc = try decode.rleDecodeGetCrc(reader, writer, original_size);
        },
        .lz77 => {
            hashed_crc = try decode.lz77DecodeGetCrc(reader, writer, original_size);
        },
    }
    if (hashed_crc) |crc| {
        const read_crc = try reader.takeInt(u32, .little);
        if (read_crc != crc) return DecodeError.CorruptData;
        const read_eof = try reader.takeArray(ZpackConfig.eof_mark.len);
        if (!std.mem.eql(u8, read_eof, ZpackConfig.eof_mark)) return DecodeError.InvalidEof;
        try writer.flush();
        try streamer.out_file_atomic.replace(io);
    } else {
        return DecodeError.CorruptData;
    }
}
test "decompress测试 - rle）" {
    const io = testing.io;
    const gpa = testing.allocator;
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const dir = tmp_dir.dir;
    const input_content = "aabbccdd";

    // 1. 手工构造 .zpack 字节流
    var compressed: std.ArrayList(u8) = .empty;
    defer compressed.deinit(gpa);

    try compressed.appendSlice(gpa, &ZpackConfig.magic);
    try compressed.append(gpa, ZpackConfig.version);
    try compressed.appendSlice(gpa, &std.mem.toBytes(@as(u64, input_content.len)));
    // RLE 数据：2a 2b 2c 2d
    try compressed.appendSlice(gpa, &[_]u8{ 2, 'a', 2, 'b', 2, 'c', 2, 'd' });
    try compressed.appendSlice(gpa, &std.mem.toBytes(std.hash.Crc32.hash(input_content)));
    try compressed.appendSlice(gpa, ZpackConfig.eof_mark);

    // 2. 写入临时文件
    {
        const f = try dir.createFile(io, "test.txt.zpack", .{ .read = true });
        defer f.close(io);
        try f.writeStreamingAll(io, compressed.items);
    }

    // 3. 获取绝对路径
    var dir_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path_len = try dir.realPath(io, &dir_path_buf);
    const dir_path = dir_path_buf[0..dir_path_len];

    const compressed_path = try std.fs.path.join(gpa, &.{ dir_path, "test.txt.zpack" });
    defer gpa.free(compressed_path);
    const restored_path = try std.fs.path.join(gpa, &.{ dir_path, "test_restored.txt" });
    defer gpa.free(restored_path);

    // 4. 解压
    try decompress(io, gpa, CmdInfo{
        .option = 'd',
        .input = compressed_path,
        .output = restored_path,
        .algorithm = .rle,
    });

    // 5. 读回并比对
    const output = try dir.readFileAlloc(io, "test_restored.txt", gpa, .limited(4096));
    defer gpa.free(output);
    try testing.expectEqualSlices(u8, input_content, output);
}

pub fn readHeaderGetOriginalSize(reader: *std.Io.Reader) !u64 {
    const magic = &ZpackConfig.magic;
    const read_magin = try reader.takeArray(5);
    if (!std.mem.eql(u8, magic, read_magin)) return DecodeError.UnsupportedFormat;

    const version = ZpackConfig.version;
    const read_version = try reader.takeByte();
    if (read_version == 0 or version < read_version) return DecodeError.UnsupportedVersion;

    return try reader.takeInt(u64, .little);
}
test "readHeaderGetOriginalSize测试" {
    const header_original_size: u64 = 128;
    var header: [14]u8 = undefined;
    @memcpy(header[0..5], &ZpackConfig.magic);
    std.mem.writeInt(u8, header[5..6], ZpackConfig.version, .little);
    std.mem.writeInt(u64, header[6..], header_original_size, .little);

    var reader = std.Io.Reader.fixed(&header);

    const original_size = try readHeaderGetOriginalSize(&reader);

    try testing.expectEqual(header_original_size, original_size);
}
