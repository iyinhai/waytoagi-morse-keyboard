# 板上实测状态

`board-status.json` 是板子自己报回来的运行状态，用 `tools/board-status.rs` 主动请求得到：

```bash
cargo run --release --example board_status
```

协议：往 feature report `0x13` 写一条请求，板子用 input report `0x11` 分片回传 JSON，工具负责拼接和 CRC16 校验。

`board-status-raw.txt` 是工具的原始输出，包含接口枚举过程和 CRC 校验结果。

## 这份数据证明了什么

| 字段 | 值 | 说明 |
|---|---|---|
| `bytes` / `crc16` | `627` / `822` | **板上生效的配置指纹**，与 `provision-lan --offline --scene morse --preview` 算出来的完全一致 —— 说明板上跑的就是 morse 场景 |
| `saved` | `true` | 配置已落盘到 NVS |
| `target_platform` | `macos` | 按 macOS 键位语义解析 |
| `firmware` | `0.6.2-easy-codex-board-volume` | 自己编译并刷入的版本 |
| `semantic_actions` | `true` | 支持 SelectAll / Copy / Paste 这类语义动作 |
| `usb_management_v1` | `true` | 配置下发走 USB 管理接口 |

## 为什么这个办法重要

板子跑的是 TinyUSB，同一个 USB 口不提供串口，**拿不到 `ESP_LOG` 日志**。所以判断"板上的键位到底对不对"，只能靠它自己报回来的配置指纹。

比 `bytes` + `crc16` 两个值，就能确认板上跑的是不是你想要的那份配置，完全不依赖日志。排查键位问题时这个手段比翻源码快得多。
