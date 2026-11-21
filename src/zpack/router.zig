const std = @import("std");
const common = @import("common");

const Errors = common.Errors;
const CmdError = Errors.CmdError;
const CmdInfo = common.CmdInfo;
const Algorithm = common.Algorithm;
const CmdParseState = common.CmdParseState;

const compress = @import("compress.zig").compress;
const decompress = @import("decompress.zig").decompress;

const testing = std.testing;

/// 处理输出路径，根据压缩选项生成默认输出路径或使用用户指定的输出路径
/// 返回 true 表示需要释放用户指定的输出路径，返回 false 表示不需要释放用户指定的输出路径
pub fn handleOutput(gpa: std.mem.Allocator, cmd_info: *CmdInfo) !?[]const u8 {
    switch (cmd_info.option) {
        'c' => {
            const output = if (cmd_info.output) |o| try gpa.dupe(u8, o) else try std.fmt.allocPrint(
                gpa,
                "{s}.{s}",
                .{ cmd_info.input, "zpack" },
            );
            cmd_info.output = output;
            return output;
        },
        'd' => {
            const output = cmd_info.output orelse blk: {
                if (!std.mem.endsWith(u8, cmd_info.input, ".zpack"))
                    return CmdError.UnsupportedInput;
                break :blk cmd_info.input[0 .. cmd_info.input.len - 6];
            };
            cmd_info.output = output;
            return null;
        },
        else => return CmdError.InvalidArgument,
    }
}
test "handleOutput测试" {
    const gpa = std.testing.allocator;
    var cmd_info = CmdInfo{
        .option = 'c',
        .input = "input.txt",
    };
    const dupedOutput = try handleOutput(gpa, &cmd_info);
    defer if (dupedOutput) |do| gpa.free(do);
    try std.testing.expectEqualSlices(
        u8,
        cmd_info.output.?,
        "input.txt.zpack",
    );
}
test "handleOutput测试 - 解压缩" {
    const gpa = std.testing.allocator;
    var cmd_info = CmdInfo{
        .option = 'd',
        .input = "input.txt.zpack",
    };
    const dupedOutput = try handleOutput(gpa, &cmd_info);
    defer if (dupedOutput) |do| gpa.free(do);
    try std.testing.expectEqualSlices(u8, cmd_info.output.?, "input.txt");
}
test "handleOutput测试 - 解压缩（不支持的输入类型）" {
    const gpa = std.testing.allocator;
    var cmd_info = CmdInfo{
        .option = 'd',
        .input = "input.txtnozpack",
    };
    const res = handleOutput(gpa, &cmd_info);
    try std.testing.expectError(
        CmdError.UnsupportedInput,
        res,
    );
}

pub fn cmdRouter(io: std.Io, gpa: std.mem.Allocator, cmd_info: CmdInfo) !void {
    switch (cmd_info.option) {
        'c' => {
            try compress(
                io,
                gpa,
                cmd_info,
            );
        },
        'd' => {
            try decompress(
                io,
                gpa,
                cmd_info,
            );
        },
        else => return CmdError.InvalidArgument,
    }
}

pub fn parseArgs(args: []const []const u8) !CmdInfo {
    var cmdParseState: CmdParseState = .Begin;
    var option: ?u8 = null;
    var input: ?[]const u8 = null;
    var output: ?[]const u8 = null;
    var algorithm: Algorithm = .rle;
    var algorithm_set: bool = false;
    for (args) |argv| {
        if (cmdParseState == .Algorithm) {
            if (algorithm_set or
                std.mem.startsWith(u8, argv, "-"))
                return CmdError.InvalidArgument;
            const alg = std.meta.stringToEnum(Algorithm, argv);
            if (alg == null) return CmdError.InvalidArgument;
            algorithm = alg.?;
            cmdParseState = .Input;
            algorithm_set = true;
            continue;
        }
        if (std.mem.startsWith(u8, argv, "-")) {
            switch (cmdParseState) {
                .Algorithm, .End, .Output => return CmdError.InvalidArgument,
                else => {},
            }
            if (argv[1] == 'a') {
                if (algorithm_set) return CmdError.InvalidArgument;
                cmdParseState = .Algorithm;
                continue;
            }
            if (argv[1] == 'c' or argv[1] == 'd') {
                if (option != null) return CmdError.InvalidArgument;
                cmdParseState = .Input;
                option = argv[1];
                continue;
            }
        }
        if (cmdParseState == .Input) {
            input = argv;
            cmdParseState = .Output;
            continue;
        }
        if (cmdParseState == .Output) {
            output = argv;
            cmdParseState = .End;
            continue;
        }
        return CmdError.InvalidArgument;
    }

    if (option == null or input == null) return CmdError.InvalidArgument;

    return .{
        .option = option.?,
        .input = input.?,
        .algorithm = algorithm,
        .output = output,
    };
}
test "parseArgs测试 - 正确性测试" {
    // var args = [_][]const u8{ "-c", "-a", "abc", "input", "output" };
    var args = [_][]const u8{ "-a", "rle", "-c", "abc", "output" };

    const cmd_info = try parseArgs(&args);

    try testing.expectEqual('c', cmd_info.option);
    try testing.expectEqualStrings("abc", cmd_info.input);
    try testing.expectEqualStrings("output", cmd_info.output.?);
    try testing.expectEqual(.rle, cmd_info.algorithm);
}
test "parseArgs测试 - 无效参数测试" {
    var args = [_][]const u8{ "-c", "input", "-a", "abc", "output" };
    const res = parseArgs(&args);
    try testing.expectError(CmdError.InvalidArgument, res);
}
test "parseArgs测试 - 双-测试" {
    var args = [_][]const u8{ "-a", "-a" };
    const res = parseArgs(&args);
    try testing.expectError(CmdError.InvalidArgument, res);

    var args2 = [_][]const u8{ "-c", "-d" };
    const res2 = parseArgs(&args2);
    try testing.expectError(CmdError.InvalidArgument, res2);
}
test "parseArgs测试 - 不支持的算法" {
    var args = [_][]const u8{ "-a", "a" };
    const res = parseArgs(&args);
    try testing.expectError(CmdError.InvalidArgument, res);
}
test "parseArgs测试 - 不指定可选参数" {
    var args = [_][]const u8{ "-c", "a" };
    const res = try parseArgs(&args);
    try testing.expectEqual(res.option, 'c');
    try testing.expectEqualStrings("a", res.input);
    try testing.expectEqual(.rle, res.algorithm);
    try testing.expectEqual(res.output, null);
}
test "parseArgs测试 - End测试" {
    var args = [_][]const u8{ "-a", "a", "-c", "input", "output", "end" };
    const res = parseArgs(&args);
    try testing.expectError(CmdError.InvalidArgument, res);
}
