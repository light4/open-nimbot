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

## 项目结构

```text
src/nimbot_connect.py  BLE 连接与 B1 V4 栅格打印脚本
docs/implementation.md 协议、命令和限制说明
```

实现及完整命令说明见 [docs/implementation.md](docs/implementation.md)。
