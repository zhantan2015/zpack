const std = @import("std");

pub const Streamer = struct {
    const Self = @This();
    io: std.Io,
    in_file: std.Io.File,
    out_file: std.Io.File,
    out_file_atomic: std.Io.File.Atomic,

    pub fn init(
        io: std.Io,
        in_file_path: []const u8,
        out_file_path: []const u8,
    ) !Self {
        const in_file = try std.Io.Dir.cwd().openFile(
            io,
            in_file_path,
            .{},
        );
        const out_file_atomic = try std.Io.Dir.cwd().createFileAtomic(
            io,
            out_file_path,
            .{ .replace = true },
        );
        const out_file = out_file_atomic.file;
        return .{
            .io = io,
            .in_file = in_file,
            .out_file = out_file,
            .out_file_atomic = out_file_atomic,
        };
    }
    pub fn deinit(self: *Self) void {
        self.in_file.close(self.io);
        self.out_file_atomic.deinit(self.io);
    }
};
