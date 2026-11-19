const std = @import("std");
pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    const cmd_info = try parseArgs(args);
    _ = cmd_info;
}
const CmdInfo = struct {
    option: []const u8,
    input: []const u8,
    output: ?[]const u8,
};
// 实现一个命令行解析状态机，分步填充进cmdInfo
const CmdParseState = enum {
    Option,
    Input,
    Output,
};
fn parseArgs(args: []const []const u8) !CmdInfo {
    _ = args;
}
