const std = @import("std");
const common = @import("common");
const ZpackConfig = common.ZpacckConfig;
const CmdInfo = common.CmdInfo;
const codec = @import("codec");
const testing = std.testing;

const Streamer = @import("utils.zig").Streamer;

pub fn compress(io: std.Io, gpa: std.mem.Allocator, cmd_info: CmdInfo) !void {
    _ = gpa;
    if (cmd_info.output == null) return error.OutputError;
    var streamer = try Streamer.init(
        io,
        cmd_info.input,
        cmd_info.output.?,
    );
    defer streamer.deinit();

    var r_buf: [4 * 1024]u8 = undefined;
    var file_reader = streamer.in_file.reader(io, &r_buf);
    const reader = &file_reader.interface;

    const stat = try streamer.in_file.stat(io);
    const original_size = stat.size;

    var w_buf: [4 * 1024]u8 = undefined;
    var file_writer = streamer.out_file.writer(io, &w_buf);
    const writer = &file_writer.interface;

    try writeHeader(writer, original_size);

    var crc: ?u32 = null;
    switch (cmd_info.algorithm) {
        .rle => {
            crc = try codec.rleCodecGetCrc(reader, writer);
        },
        .lz77 => {
            crc = try codec.lz77CodecGetCrc(reader, writer);
        },
        // else => {
        //     return error.UnsupportedAlgorithm;
        // },
    }
    if (crc) |c| {
        try writer.writeInt(u32, c, .little);
        try writer.writeAll(ZpackConfig.eof_mark);
        try writer.flush();
        try streamer.out_file_atomic.replace(io);
    }
}
test "compress测试" {
    const io = testing.io;
    const gpa = testing.allocator;
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const dir = tmp_dir.dir;

    // 1. 创建输入文件（openFile 不能创建）
    {
        const f = try dir.createFile(io, "test.txt", .{ .read = true });
        defer f.close(io);
        try f.writeStreamingAll(io, "aabbccdd");
    }

    // 2. 获取临时目录绝对路径
    var dir_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path_len = try dir.realPath(io, &dir_path_buf);
    const dir_path = dir_path_buf[0..dir_path_len];

    // 3. 拼出输入/输出的绝对路径
    const in_path = try std.fs.path.join(gpa, &.{ dir_path, "test.txt" });
    defer gpa.free(in_path);
    const out_path = try std.fs.path.join(gpa, &.{ dir_path, "test.txt.zpack" });
    defer gpa.free(out_path);

    const cmd_info = CmdInfo{
        .option = 'c',
        .input = in_path,
        .output = out_path,
        .algorithm = .rle,
    };
    try compress(io, gpa, cmd_info);

    // 4. 用相对路径读回
    const output = try dir.readFileAlloc(io, "test.txt.zpack", gpa, .limited(4096));
    defer gpa.free(output);

    const input_content = "aabbccdd";
    try testing.expectEqualSlices(u8, &ZpackConfig.magic, output[0..5]);
    try testing.expectEqual(ZpackConfig.version, output[5]);
    const stored_size = std.mem.readInt(u64, output[6..14], .little);
    try testing.expectEqual(input_content.len, stored_size);

    const rle_data = output[14..22];
    try testing.expectEqualSlices(u8, &[_]u8{ 2, 'a', 2, 'b', 2, 'c', 2, 'd' }, rle_data);

    const stored_crc = std.mem.readInt(u32, output[22..26], .little);
    try testing.expectEqual(std.hash.Crc32.hash(input_content), stored_crc);

    try testing.expectEqualSlices(u8, ZpackConfig.eof_mark, output[26..]);
}

pub fn writeHeader(writer: *std.Io.Writer, original_size: u64) !void {
    var magic = ZpackConfig.magic;
    const version = ZpackConfig.version;
    try writer.writeAll(&magic);
    try writer.writeByte(version);
    try writer.writeInt(u64, original_size, .little);
}
test "writeHeader测试" {
    const original_size = 100;
    var expected: [14]u8 = ZpackConfig.magic ++ [_]u8{ZpackConfig.version} ++ @as([8]u8, @splat(0));
    std.mem.writeInt(
        u64,
        expected[6..expected.len],
        original_size,
        .little,
    );

    var w_buf: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(w_buf[0..]);
    try writeHeader(&writer, original_size);
    try writer.flush();
    try testing.expectEqualSlices(u8, &expected, w_buf[0..expected.len]);
}
