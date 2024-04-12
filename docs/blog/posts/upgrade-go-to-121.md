---
authors:
  - ionling
categories:
  - Backend
  - Golang
date: 2024-04-12
---

# Upgrade Golang to 1.21

日常升级.

## Changes

- Major
  - [x] go.mod
  - [x] Dockerfile
- Minor
  - [x] Use builtin `slices`, `slog`
  - [x] Use builtin `context.WithoutCause()`

## Check

- [x] Build all apps' image
- [x] Call a RPC which used `context.WithoutCause()`

## About 1.21

https://tonybai.com/2023/08/20/some-changes-in-go-1-21/

分章分成四个部分:

1. 语言本身
2. 编译器与运行时
3. 工具链
4. 标准库

其中比较重要的有: loopvar, GC 优化, slog, 以及兼容性部分

### Kimi

总结文章, 给出大纲以及重点, 使用 Markdown 的格式编写:

Go 1.21 版本更新概述:

- 语言变化
  - builtin 包新增预定义函数：min、max 和 clear
  - 明确了包初始化顺序算法
  - 增强泛型的类型推断能力
  - 修正 Go1 中的两个“陷阱”：panic(nil)和 for 循环变量
- Go 编译器与运行时变化
  - PGO 默认开启
  - 降低 GC 尾部延迟
  - 支持 WASI
- Go 工具链更新
  - 向后兼容：扩展和规范化 GODEBUG 的使用
  - 向前兼容：go.mod 文件中的 go line 作为约束规则，引入 toolchain 指示符和 GOTOOLCHAIN 环境变量
- Go 标准库更新
  - log/slog：结构化日志支持
  - slices、maps 和 cmp：泛型包加入标准库
  - 其他变化：errors.ErrUnsupported、flag.BoolFunc、
    net 的多路径 TCP 支持、 reflect.ValueOf 优化、sync.OnceFunc 等
- 参考资料
  - Go 1.21 Release Notes
  - Go 1.21 版本发布博客
  - 兼容性相关博客
  - Godebug 手册
  - LoopvarExperiment 页面
  - 如何 Golang Evolves without Breaking Programs 文章
  - PGO 用户指南

这个大纲总结了文章中关于 Go 1.21 版本的主要更新和变化，
包括语言特性的变更、编译器与运行时的改进、工具链的更新以及标准库的新增和改动。
同时，列出了文章末尾提供的参考资料链接，方便读者进一步阅读和了解。
