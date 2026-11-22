const std = @import("std");

pub const Algorithm = enum(u8) {
    rle = 0,
    lz77 = 1,
    // ... 可以添加更多算法
};

pub const Errors = struct {
    pub const CmdError = error{
        InvalidArgument,
        UnsupportedInput,
        UnknownAlgorithm,
        // ... 其他可能的错误
    };
    pub const CodecError = error{
        InputError,
        OutputError,
    };
    pub const DecodeError = error{
        UnsupportedFormat,
        UnsupportedVersion,
        CorruptData,
        InvalidEof,
    };
};

pub const CmdInfo = struct {
    option: u8,
    input: []const u8,
    output: ?[]const u8 = null,
    algorithm: Algorithm = .lz77,
};

pub const CmdParseState = enum {
    Begin,
    ReadedDash,
    ReadingValue,
    Option,
    Input,
    Output,
    Algorithm,
    End,
};

pub const ZpacckConfig = struct {
    pub const magic = [_]u8{ 'Z', 'P', 'A', 'C', 'K' };
    pub const version: u8 = 0x01;
    pub const eof_mark = "ZPACKEOF";
};
