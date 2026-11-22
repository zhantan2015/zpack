# Changelog

本项目所有重要变更都会记录在此文件中。

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

## [Unreleased]

## [1.1.0] - 2026-11-23

新增 LZ77 压缩算法，与 RLE 算法并存，通过 `-a lz77` 显式选择。

### Added

- **Codec**：新增 LZ77 编码 `lz77CodecGetCrc`，基于滑动窗口的字节级匹配
- **Codec**：新增 LZ77 解码 `lz77DecodeGetCrc`，支持重叠复制（RLE 退化）与跨缓冲边界的历史引用
- **CLI**：`-a <algorithm>` 新增可选值 `lz77`，缺省仍为 `rle`
- **Tests**：为 LZ77 编解码补充 roundtrip、纯 literal、重叠复制、跨 flush 边界、CRC 一致性、非法 offset 拒绝等用例

### Changed

- **CLI**：`-a <algorithm>` 的合法值集合扩展为 `{rle, lz77}`
- **Container**：`.zpack` 文件头新增算法标识，解码端据此选择解码器（见下方兼容性说明）

### Compatibility

- **向后兼容**：v1.0.0 生成的 `.zpack` 文件（RLE 编码）仍可被 v1.1.0 解码
- **向前不兼容**：v1.1.0 生成的 LZ77 编码文件无法被 v1.0.0 解码，会返回 `UnsupportedVersion`

### Known Limitations

- LZ77 编码器当前使用固定窗口（255 字节），未做最优匹配搜索
- 对高熵数据（随机/加密内容）LZ77 可能产生 1.5–2 倍膨胀
- RLE 对不可压缩数据的 2 倍膨胀问题未在本次改动中处理
- 解压路径的 fuzz 测试仍未补充

[1.1.0]: https://github.com/zhantan2015/zpack/releases/tag/v1.1.0

### Planned

- 支持更多压缩算法（Huffman、LZ77）
- 解压路径的 fuzz 测试
- 大文件分块编解码
- 为 `-d` 省略 output 的场景增加 `--force` / `--output-required` 等可选行为

## [1.0.0] - 2026-11-21

首个正式版本。

### Added

- **CLI**：新增 `zpack [-a <algorithm>] <-c|-d> <input> [output]` 命令行语法
  - `-a <algorithm>` 可选，缺省 `rle`
  - `-c` / `-d` 二选一，必选其一
  - `<input>` 为必需的位置参数
  - `[output]` 为可选位置参数
- **CLI**：`-c` 省略 output 时默认输出为 `input + ".zpack"`
- **CLI**：`-d` 省略 output 时要求 input 以 `.zpack` 结尾，输出为去掉后缀的原名；不满足则报错
- **CLI**：新增 `router.zig`，按 `-c` / `-d` 路由到对应处理逻辑
- **Codec**：新增 RLE 编码 `rleCodecGetCrc`，编码同时计算原始数据 CRC32
- **Codec**：新增 RLE 解码 `rleDecodeGetCrc`，解码同时校验 CRC32
- **Container**：新增 `.zpack` 容器格式（magic、version、original_size、payload、CRC32、EOF 标记）
- **Compress**：实现 `compress`，将输入文件按 RLE 编码为 `.zpack` 文件
- **Decompress**：实现 `decompress`，将 `.zpack` 文件还原为原始文件
- **Infra**：新增 `Streamer`，统一管理输入流与原子输出流
- **Infra**：新增 `CmdInfo`，结构化表示命令行参数
- **Tests**：为 codec、compress、decompress、common、router 等模块补充单元测试

### Changed

- **Build**：`build.zig` 改为模块化导入（`addModule` + `imports`），每个模块独立 `addTest`
- **Build**：引入 `zig build test` 作为统一测试入口
- **Refactor**：项目结构按职责拆分为 `common`、`utils`、`codec`、`decode`、`zpack`、`router` 六个模块
- **IO**：输出文件统一使用 `createFileAtomic`，确保失败时不产生半成品

### Removed

- 移除临时的批量测试脚本，测试职责收敛到 `zig build test`

### Fixed

- `common.zig` 与 `root` 模块归属冲突（改为通过模块名 `@import("common")` 引用）
- `compress` 写入 `.zpack` 后文件不存在（`createFileAtomic` 漏掉 `replace`，已补上）

### Known Limitations

- 当前仅支持 RLE 算法
- `.zpack` 格式暂不承诺跨版本兼容
- 暂无解压路径的 fuzz 测试
- `-d` 省略 output 时强依赖 `.zpack` 后缀

[Unreleased]: https://github.com/zhantan2015/zpack/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/zhantan2015/zpack/releases/tag/v1.0.0
