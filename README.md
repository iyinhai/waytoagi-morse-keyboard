# 摩斯电码练习机

> WaytoAGI 第七期 AI 硬件训练营 · 第 8 课作业
> 硬件：EasyInput V2（ESP32-S3R8 / 16MB Flash / 8MB Octal PSRAM）

把一块"按住说话"的语音助手板子，改造成一台摩斯电码发报机，配一个能练、能判、能校准手速的网页练习机。

---

## 成果

| 部分 | 说明 |
|---|---|
| **网页练习机** | [`web/morse-machine.html`](web/morse-machine.html) —— 单文件、零依赖、双击就能开 |
| **板子** | KEY1 按下发空格，按住时长就是点和划；KEY3 换词、KEY4 删字、KEY5 提交 |
| **过程记录** | [`docs/过程记录.md`](docs/过程记录.md) —— 完整复盘，含所有踩过的坑 |

### 直接体验

下载 `web/morse-machine.html`，双击用浏览器打开，**先点一下页面任意位置**（让网页拿到键盘焦点），然后按空格练。

没有板子也能玩：直接用键盘空格键，按住时间长短就是点和划。

### 键位对照

| 板子按键 | 功能 | HID 键码 |
|---|---|---|
| KEY1 | 发报（短按 = 点，长按 = 划） | `0x2C` Space |
| KEY3 | 换下一个词 | `0x2B` Tab |
| KEY4 | 删掉一个字母 | `0x2A` Backspace |
| KEY5 | 提交当前字母 | `0x28` Enter |
| KEY2 / 6 / 7 / 8、旋钮三向 | 关闭（防误触） | — |

---

## 网页练习机做了什么

- **摩斯表 48 条目**：A–Z、0–9、常用标点，逐条跟标准码比对过
- **点划判定**：按住 < 200ms 记为点，否则记为划（可自动校准）
- **两级断字**：字母内间隔超过 600ms 提交字母，超过 1600ms 算换词
- **即时判错**：每提交一个字母立刻跟目标词比对，错字当场变红并显示正确码
- **自动校准**：连收 5 个样本，取平均 × 2.2 作为新阈值，限 80–400ms
- **对焦保护**：Backspace / Tab / Enter 全部 `preventDefault()`，按 KEY3 不会把焦点切走

逻辑用「最小 DOM 桩 + 假时钟」跑了 21 项断言，全通过（详见过程记录）。

---

## 硬件改造：一共改了 3 处

### ① 根因：让按键绕过 Codex 语音槽位机

最关键的一处。`handle_input_event()` 里 KEY1–KEY8 被无条件交给 Codex 语音槽位状态机，然后 `return`：

```cpp
if (is_codex_slot_input(event.input)) {   // KEY1..KEY8 全部命中
  handle_codex_slot_transition(app, app->codex_slots.handle_input(...));
  return;                                 // ← 键位表永远走不到
}
```

而纯键盘场景（没配 Wi-Fi、没有 audio host）下 `connection_generation == 0`，槽位机对每个按下的键只回一个 `RejectedBusy` —— 只打一条日志，什么也不做。

**所以现象是：按 KEY1 灯会变红，但一个键码都不发。** 灯亮只是按键反馈色（`{28,0,0}`），跟动作解析无关，这点极易误判。

修法是加一个条件，只有真连上语音路由时才交给槽位机：

```cpp
const bool codex_owns_keys =
    app->codex_route_generation != 0 || app->codex_slots.capture_active();
if (is_codex_slot_input(event.input) && codex_owns_keys) { ... }
```

### ② 固件默认键位改成摩斯键位

新增 `MorseKeymap()`，并让 `DefaultKeymap()` 返回它；同时保留 `UpstreamDefaultKeymap()`（课程原始出厂键位）方便对照和回退。改回原键位只需改 `DefaultKeymap()` 里的一行 `return`。

### ③ host 工具加离线配置模式

板子的 `audio_enabled` 是**推导值**而不是开关：

```cpp
return !wifi_ssid.empty() && !audio_host.empty() && port in 1024..=65535;
```

所以空 ssid + 空 host 就是合法的"纯键盘"态。基于这点加了 `LanProvisioning::offline()`，下发键位不用再问 Wi-Fi 密码。

> 坑：`audio_port` 仍必须给合法值，写 0 会让整份配置被判为 `InvalidJson`。离线模式保留默认的 17333。

### 键位怎么下发（不用重新编译）

```bash
# 只看要下发什么，不碰板子
easy-codex-host provision-lan --offline --scene morse --preview

# 真正写入
easy-codex-host provision-lan --offline --scene morse
```

成功返回：

```
status=provisioned transport=usb_hid payload_bytes=627 chunks=13 crc16=822
```

---

## 踩过的坑（这部分可能比结论有用）

| # | 坑 | 真相 |
|---|---|---|
| 1 | ESP-IDF 报 `idf5.5_py3.13_env not found` | PATH 上有别的 Python 抢前面，把真 venv 顶到最前再 `source export.sh` |
| 2 | 配置下发一直 `HidAck` 超时 | 板子其实在正常回 ACK，但格式是分片 JSON，跟 host 期待的"单帧 phase/ok/bytes/crc16"不兼容 |
| 3 | 刷完固件卡在下载模式 | `--after hard_reset` 和 4 组手写 DTR/RTS 时序全废，**`--after watchdog_reset` 有效** |
| 4 | 拔插 USB 也没用 | 板子带电池，拔线后芯片一直由电池供电，**根本没断电** |
| 5 | 擦 NVS 后蓝牙消失 | 蓝牙配对密钥和键位配置都在 `0x9000`，一起被清了 |
| 6 | `hid-watch` 一条键盘报文都收不到 | macOS 对键盘集合有输入保护，厂商通道读得到、键盘通道读不到。**假阴性** |
| 7 | 我自己的判据也写错两次 | filter 用了不存在的 `usage_page=0x0006`；用"报文里出现 `2C`"判空格，而厂商 JSON 里的逗号正好是 `0x2C` |

坑 3 是最实用的收获：**ESP32-S3 走 USB 触发的复位必然回下载模式，走 RTC 看门狗复位不会**。所以刷完不用再物理拔线：

```bash
esptool --chip esp32s3 -p /dev/cu.usbmodem3101 \
  --before no_reset --after watchdog_reset run
```

坑 6 是最坑人的一条：唯一的观测手段本身就是坏的，导致我拿着"0 帧"这个假证据推错了方向很久。**唯一可信的判据是：在真实应用里有没有打出字符。**

---

## 目录

```
├── web/morse-machine.html          练习机网页（单文件，直接打开）
├── docs/过程记录.md                 完整复盘
├── patches/                        相对课程原始仓库的改动
│   ├── 01-firmware-codex-slot-bypass.patch     ← 根因修复
│   ├── 02-firmware-morse-keymap.patch          ← 摩斯键位
│   ├── 03-firmware-tests.patch                 ← 对应断言
│   └── 04-host-offline-provisioning.patch      ← 离线下发 + hid-watch
├── scenes/                         一键切换板子用途
│   ├── morse.json                  摩斯键位
│   ├── factory.json                出厂键位
│   ├── notes.json / slides.json / writing.json
│   ├── apply-scene.sh              场景切换脚本（默认离线模式）
│   └── README.md
├── tools/
│   ├── flash-morse.sh              一键刷写（含 watchdog_reset 复位）
│   ├── verify-morse.py             按键验证（含 macOS 限制说明）
│   └── board-status.rs             通过 HID 索取板子运行状态
└── evidence/board-status.json      板子实测状态（验证配置已生效）
```

### patch 怎么用

patch 是相对**课程原始仓库**（`course repo v0.1.0-local-training`）的 diff：

```bash
cd <课程仓库根目录>
git apply /path/to/patches/01-firmware-codex-slot-bypass.patch
git apply /path/to/patches/02-firmware-morse-keymap.patch
git apply /path/to/patches/03-firmware-tests.patch
git apply /path/to/patches/04-host-offline-provisioning.patch
```

---

## 验证数据

| 项 | 结果 |
|---|---|
| 网页逻辑断言 | 21 / 21 通过 |
| 摩斯表 | 48 条目 vs 标准码，逐条无差异 |
| host 工具测试 | 269 项全通过 |
| 固件主机测试 | 56 / 57（唯一失败的 `eci_protocol_test` 是改动前就编译不过的桩代码） |
| 固件编译 | `easy_codex_input.bin` 2,159,328 字节，分区空闲 31% |
| 刷写 | `Hash of data verified`，bootloader + 分区表 + 应用三段全过 |
| 板上配置指纹 | `bytes=627 / crc16=822`，与 `--scene morse --preview` 完全一致 |
| **KEY1 实际按键** | **打出空格** |

### 配置指纹这个办法值得单独说

板子的状态报文里会回 `bytes` 和 `crc16`，描述的是**当前生效的那份配置**。拿它跟 host 端算出来的值对比，就能在完全不依赖固件日志的情况下确认板上跑的到底是不是你要的那份键位。

本次两边都是 `627 / 822`，所以板上确实是 morse 场景。

---

## 遗留问题

1. KEY3 / KEY4 / KEY5 没有逐键真机验证 —— 受坑 6 限制，本机无法可靠观测键盘报文。它们走同一套 keymap，有单元测试覆盖精确 HID 码，但没逐个按过。
2. 语音功能会抢占按键 —— 连上 Wi-Fi、audio host 可用后，KEY1–KEY8 会重新交给 Codex 语音槽位机。这是设计如此（语音是这块板子的原生用途），要用摩斯就别连 Wi-Fi。
3. `--after watchdog_reset` 是实测量出来的解，不是官方文档方案。对 ESP32-S3 + TinyUSB 的组合有效，换芯片型号需重新验证。
