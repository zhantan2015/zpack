const std = @import("std");

// 构建入口：`zig build` 时会调用这个函数。
// 参数 b 就是前面说的“项目经理”，所有产物、步骤都通过它来登记。
pub fn build(b: *std.Build) void {
    // 解析命令行 `-Dtarget=xxx` 选项，未指定则用本机目标。
    const target = b.standardTargetOptions(.{});
    // 解析命令行 `-Doptimize=xxx` 选项，未指定则用 Debug 模式。
    const optimize = b.standardOptimizeOption(.{});

    const common_mod = b.addModule("common", .{
        .root_source_file = b.path("src/common.zig"),
        .target = target,
    });

    const decode_mod = b.addModule("decode", .{
        .root_source_file = b.path("src/decode/decode.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "common", .module = common_mod },
        },
    });
    const decode_tests = b.addTest(.{
        .root_module = decode_mod,
    });

    const run_decode_tests = b.addRunArtifact(decode_tests);

    const codec_mod = b.addModule("codec", .{
        .root_source_file = b.path("src/codec/codec.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "common", .module = common_mod },
        },
    });

    const zpack_mod = b.addModule("zpack", .{
        .root_source_file = b.path("src/zpack/zpack.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "common", .module = common_mod },
            .{ .name = "codec", .module = codec_mod },
            .{ .name = "decode", .module = decode_mod },
        },
    });

    const zpack_tests = b.addTest(.{
        .root_module = zpack_mod,
    });

    const run_zpack_tests = b.addRunArtifact(zpack_tests);

    const main_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "common", .module = common_mod },
            .{ .name = "codec", .module = codec_mod },
            .{ .name = "decode", .module = decode_mod },
        },
    });
    // 创建可执行文件产物。名字叫 "zpack"（会生成 zpack.exe / zpack）。
    const exe = b.addExecutable(.{
        .name = "zpack",
        // 可执行文件自己的“根模块”，也就是程序入口 main.zig 所在的模块。
        .root_module = main_mod,
    });
    // 把 exe 挂到内置的 install 步骤上。
    // `zig build`（不带参数）默认就走 install，会产出到 zig-out/bin/ 下。
    b.installArtifact(exe);

    // 登记一个自定义步骤，名字叫 "run"。
    // 之后 `zig build run` 就会执行这个步骤。
    const run_step = b.step("run", "Run the app");
    // 创建一个“运行 exe”的动作（Artifact 只是产物，“运行”是另一个动作）。
    const run_cmd = b.addRunArtifact(exe);
    // 让 run 步骤依赖“运行 exe”这个动作 —— 即 zig build run 会去运行 exe。
    run_step.dependOn(&run_cmd.step);

    // 运行之前先确保 exe 已经被构建并安装，避免跑的是旧二进制。
    run_cmd.step.dependOn(b.getInstallStep());

    // 允许把 `zig build run -- arg1 arg2` 里 `--` 后面的参数透传给程序本身。
    run_cmd.addPassthruArgs();

    // 为可执行文件创建测试产物。
    // 这里复用了 exe.root_module（而不是重新 createModule），
    // 好处是会自动继承 exe 的 imports 配置——即也能 @import("zpack")。
    // 测试的是 src/main.zig 里的 test 块。
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    // 创建“运行可执行文件测试”的动作。
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const codec_tests = b.addTest(.{
        .root_module = codec_mod,
    });
    const run_codec_tests = b.addRunArtifact(codec_tests);

    // 登记一个自定义步骤，名字叫 "test"。
    // 之后 `zig build test` 就会执行这个步骤。
    const test_step = b.step("test", "Run tests");
    // test 步骤依赖两组测试动作：库的测试 + 可执行文件的测试。
    // 所以 zig build test 会先把两套测试都跑一遍。
    test_step.dependOn(&run_exe_tests.step);
    test_step.dependOn(&run_zpack_tests.step);
    test_step.dependOn(&run_codec_tests.step);
    test_step.dependOn(&run_decode_tests.step);
}
