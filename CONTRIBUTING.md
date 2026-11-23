# 贡献指南

感谢你愿意改进这个小工具。提交前请先读下面的约定。

## 开发与构建

```sh
cd src
./build.sh                 # 生成 build/国内金价.app（arm64 + x86_64）
open "./build/国内金价.app"
```

- 只依赖系统框架（AppKit / Foundation / UserNotifications），不引入 SPM 依赖。
- 使用 Xcode 命令行工具即可，部署目标 macOS 12。
- 修改后请自检：`swiftc -typecheck -warnings-as-errors -target arm64-apple-macos12.0 src/**/*.swift` 通过，且实机能跑起来。

## 代码约定

- 最小必要改动：先找已有实现，不重复造轮子。
- 关键函数与分支写 `/** ... */` 注释，说明「为什么」而不是「做什么」。
- 新增文件按 `model / feature / ui / support` 归档，别把逻辑塞回 `main.swift`。
- 界面改动请在 `docs/DESIGN.md` 里同步一节说明。

## 隐私与安全（硬性要求）

提交到公开仓库前，必须确认代码、注释、文档与提交信息里**不含**能指明身份或环境的信息：

- 真实姓名、公司名、内网域名与内网 IP、主机名、内部项目代号
- 个人绝对路径（形如 `/home/<用户名>/...`、`/Users/<用户名>/...`）、密钥文件路径
- 任何 token、API Key、Cookie、一次性验证码

本项目的可配置项一律通过 `NSHomeDirectory()`、`Application Support` 推导路径，不要写死机器相关位置。

## 版本与发布

- 版本号只在发布时由 CI 写入 `src/Info.plist`，平时不要手改。
- 发布流程：合并到 `main` → `git tag v1.2.0` → `git push origin v1.2.0`，`release.yml` 会自动产出 Release。
- 需要临时发版时，可在 Actions 里手动触发 `release` 并填写版本号。

## 提交信息

使用简短的祈使句，例如 `capsule: 修正左侧内边距`、`feed: 增加备用行情源`。
提交身份请使用 GitHub 的 noreply 邮箱，不要使用工作邮箱。
