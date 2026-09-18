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

## 已知限制

- 当前固定为 B1 的 V4 协议、160 像素宽标签和 24 px 字体。
- 长文本不会自动换行；每行建议不超过约 10 个中文字符。
- `--test-page` 是设备内建测试页命令，但 B1 不支持它；请使用 `--test-label`。
