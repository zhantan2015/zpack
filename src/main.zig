const std = @import("std");
const common = @import("common");
const Errors = common.Errors;
const CmdError = Errors.CmdError;
const router = @import("./zpack/router.zig");
const parseArgs = router.parseArgs;
const handleOutput = router.handleOutput;
const cmdRouter = router.cmdRouter;

test "确保所有模块被测试" {
    _ = @import("./zpack/router.zig");
    _ = @import("./zpack/compress.zig");
    _ = @import("./zpack/decompress.zig");
    _ = @import("./zpack/utils.zig");
    _ = @import("./zpack/router.zig");
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    var cmd_info = parseArgs(args[1..]) catch |err| {
        std.debug.print("出错了！{}", .{err});
        switch (err) {
            CmdError.InvalidArgument => {
                std.debug.print("无效的命令！\n", .{});
                return;
            },
            else => {
                std.debug.print("未知错误！\n", .{});
                return;
            },
        }
    };
    const dupedOutput = try handleOutput(gpa, &cmd_info);
    defer if (dupedOutput) |do| {
        gpa.free(do);
    };
    try cmdRouter(io, gpa, cmd_info);
}
