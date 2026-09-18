# NIMBOT B1 蓝牙打印

[`../src/nimbot_connect.py`](../src/nimbot_connect.py) 用 macOS 蓝牙低功耗（BLE）连接并打印 NIMBOT B1 标签机。

## 前提

- 打印机已开机、装有标签纸，且未被手机 NIMBOT App 占用。
- macOS 已允许终端使用蓝牙。
- 已安装 [`uv`](https://docs.astral.sh/uv/)；脚本会自动安装 `bleak` 和 `Pillow`。

## 使用

```bash
# 列出附近 BLE 设备
./src/nimbot_connect.py --list

# 连接打印机，列出其 GATT 服务后断开
./src/nimbot_connect.py --hold 0

# 内建测试标签
./src/nimbot_connect.py --test-label --hold 0

# 打印英文或中文；$'...' 可输入换行
./src/nimbot_connect.py --text '你好，NIMBOT' --hold 0
./src/nimbot_connect.py --text $'订单 12345\nBLE 打印成功' --hold 0
```

默认设备名是 `B1-G801041103`。若广播名称变化，使用 `--name` 指定：

```bash
./src/nimbot_connect.py --name 'B1-实际名称' --text '测试' --hold 0
```

## 参数

| 参数 | 作用 |
| --- | --- |
| `--list` | 扫描附近蓝牙设备，不连接。 |
| `--name NAME` | 打印机的 BLE 广播名称。 |
| `--text TEXT` | 打印文字；支持中文和多行。 |
| `--test-label` | 打印 `NIMBOT / BLE OK` 测试标签。 |
| `--hold 秒数` | 打印或连接后保持连接的时间；批处理时用 `0`。 |
| `--timeout 秒数` | 扫描和连接超时，默认 10 秒。 |
| `--self-check` | 运行离线协议及命令行自检。 |

## 实现细节

- 扫描和连接使用 `bleak`；B1 的可写 GATT 特征是 `bef8d6c9-9c21-4c9e-b632-bd58c1009f9f`。
- 命令帧格式为 `55 55 <命令> <长度> <数据> <XOR 校验> AA AA`。
- B1 使用 NIMBOT V4 流程：设置浓度/标签类型、开始任务和页面、传输单色栅格行、结束页面和任务。
- 文本由 Pillow 渲染为 160 px 宽的 1-bit 位图；macOS 优先使用 `Hiragino Sans GB` 以显示中文。

## macOS App

原生应用位于 [`../macos/OpenNimbot`](../macos/OpenNimbot)。构建和打开 Bundle：

```bash
cd macos/OpenNimbot
uv run scripts/build_app.py
open dist/OpenNimbot.app
```

### 模块

| 文件 | 职责 |
| --- | --- |
| `OpenNimbotApp.swift` | SwiftUI 应用入口。 |
| `ContentView.swift` | 设备选择、画布选择、图层检查器和打印预览。 |
| `CanvasDocument.swift` | 标签画布与文本、图片、路径图层模型。 |
| `CanvasEditor.swift` | 图层选择、移动、缩放和自由路径绘制。 |
| `BluetoothManager.swift` | CoreBluetooth 扫描、连接、通知处理与打印传输队列。 |
| `NimbotProtocol.swift` | B1 V4 报文、RFID 解析和画布栅格编码。 |
| `LabelMedia.swift` | 标签介质尺寸模型。 |

App 连接后会自动读取 RFID，并显示标签条码、序列号、介质类型与已用/总长度。介质类型 `1` 表示有间隙标签。条码 `6971501227682` 已映射为 30 × 15 mm / 2R 标签，即 203 dpi 下单张 240 × 120 px。2R 的上下两张是独立标签；编辑器会按物理的上、下顺序同时展示两块画布，分别编辑、预览。打印时会将两块画布拼为同一个物理页面，避免被当作两个页面的上标签。

画布将文本、图片和自由路径保存为独立图层。文本图层可从 macOS 已安装字体中选择字体、字号、粗体、斜体和左/中/右对齐；图片通过 **Image…** 插入。选择文本或图片图层后显示贴合内容尺寸的虚线边框，右下角手柄可缩放；选中后可用方向键每次移动 1 px；开启 **Draw** 可绘制路径。**Copy Top → Bottom** 会复制全部图层。画布坐标与热敏打印坐标均以标签左上角为原点。画布、预览和打印共用同一个 Core Graphics 栅格渲染器。

## 测试

```bash
cd macos/OpenNimbot
swift test
```

集成测试覆盖从 RFID 条码识别 2R 介质、画布渲染、单物理页打印帧生成，以及图层编辑/复制后的预览与打印流程。

## 已知限制

- 当前固定为 B1 的 V4 协议和 160 像素打印宽度；尚未根据 RFID 条码映射实际标签尺寸。
- Bundle 使用 ad-hoc 签名；分发到其他电脑前需要 Apple Developer ID 公证。
