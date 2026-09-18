# open-nimbot

通过 macOS 蓝牙低功耗（BLE）连接并打印 NIMBOT B1 标签机的小型 Python 工具。

## 快速开始

```bash
# 扫描附近 BLE 设备
./src/nimbot_connect.py --list

# 打印中文或英文；$'...' 支持换行
./src/nimbot_connect.py --text '你好，NIMBOT' --hold 0
```

要求：打印机已开机、未被手机 App 占用；macOS 已允许终端使用蓝牙；已安装 [`uv`](https://docs.astral.sh/uv/)。首次运行会自动安装依赖。

## macOS App

原生 GUI 位于 [`macos/OpenNimbot`](macos/OpenNimbot)，使用 SwiftUI 和 CoreBluetooth，不依赖第三方库：

```bash
cd macos/OpenNimbot
open Package.swift       # 用 Xcode 打开

# 生成可直接打开的 .app Bundle
uv run scripts/build_app.py
open dist/OpenNimbot.app
```

它可扫描和连接 B1 打印机、输入中英文多行文字，并打印标签。构建脚本会进行 ad-hoc 签名；如需分发给其他电脑，仍需 Apple Developer ID 公证。

## 项目结构

```text
src/nimbot_connect.py       BLE 协议验证与命令行打印脚本
macos/OpenNimbot/           SwiftUI + CoreBluetooth 原生 macOS App
docs/implementation.md      Python 版协议、命令和限制说明
```

实现及完整命令说明见 [docs/implementation.md](docs/implementation.md)。
