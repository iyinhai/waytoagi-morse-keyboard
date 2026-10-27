# 场景键位表（scenes）

同一块 EasyInput V2.0，换一份场景表就是另一个产品。板子不用刷、固件不用改。

## 用法

```bash
# 编译
cd <仓库根> && cargo build --release -p easy-codex-host

# 列出全部场景
./app/host/scenes/apply-scene.sh

# 只看要写进板子的内容（密码打码），不动板子
./app/host/scenes/apply-scene.sh writing --preview

# 预览 + 确认后下发（会顺带写回 Wi-Fi，所以每次都要提供 SSID 和密码）
./app/host/scenes/apply-scene.sh writing

# 键位乱了回滚
./app/host/scenes/apply-scene.sh factory
```

配置走 **USB HID feature report** 下发：分块 64 字节、带 CRC16、等板子回 ACK。
所以必须插 USB 线。没有设备时会在打开设备一步就退出，不会写入任何东西。

## 场景文件格式

```json
{
  "id": "writing",
  "name": "公众号写作",
  "keys": {
    "KEY1": "voice_ptt_hold",
    "KEY4": { "text": "【结论】" },
    "KEY5": "hotkey:cmd+b"
  },
  "encoder": {
    "left": "disabled",
    "right": "disabled",
    "press": "scroll_axis_toggle"
  }
}
```

- `id`、`name`：必填。`id` 要和文件名一致（`writing.json` → `writing`）。
- `keys`：**必须写全 KEY1~KEY8**，少一个会报错；多写 KEY9 之类的会被白名单拒绝。
- `encoder`：`left` / `right` / `press` 三个都必填。

### 动作可以怎么写

| 写法 | 含义 | 固件里的类型 |
|---|---|---|
| `"disabled"` | 这个键不用 | `Disabled` |
| `"voice_ptt_hold"` | 按住说话，松手提交 | `VoicePttHold` |
| `"edit_ptt_hold"` | 按住改上一句 | `EditPttHold` |
| `"paste_last"` | 贴回上一轮结果 | `PasteLast` |
| `"history"` | 打开历史 | `OpenHistory` |
| `"select_all"` `"copy"` `"paste"` `"undo"` | 编辑动作 | 对应枚举 |
| `"scroll_axis_toggle"` | 旋钮滚动轴切换 | `ScrollAxisToggle` |
| `"hotkey:cmd+shift+4"` | 打一个组合键（简写，会自动展开成 `{"hotkey": ...}`） | `Hotkey` |
| `{ "text": "【结论】" }` | 直接在光标处打出这段文字 | `FixedText` |

### 热键能用的词

解析在固件 `hid_keycode.cpp`，用 `+` 分隔，不区分大小写。

- **修饰键**：`cmd` / `command` / `meta`、`opt` / `alt` / `option`、`ctrl` / `control`、`shift`，以及 `rightcmd` / `rightopt` / `rightctrl` 等右侧版本
- **键名**：字母 `a`~`z`、数字 `0`~`9`、`return` / `enter`、`escape` / `esc`、`backspace`、`tab`、`space`、`left` / `right` / `up` / `down`

写错词会让整个按键失效（固件返回空报告），所以改完先跑一次 `--preview` 核对。

## 几个硬限制

| 限制 | 数值 | 出处 |
|---|---|---|
| 配置总大小 | 2048 字节 | `provisioning.rs` `MAX_CONFIG_BYTES` |
| 单键固定文本 | 960 字节 | `fixed_text_protocol.h` `kFixedTextMaxUtf8Bytes` |
| 同时生效的场景数 | **1** | 固件只解析 `profiles[0]` |

最后一条是关键约束：当前固件不支持板内切场景，所以「换场景」= 重新下发一次配置。
`toggle_profile` / `next_profile` 这些动作在现有固件上不产生效果。

## 现有场景

| id | 名字 | 用途 |
|---|---|---|
| `factory` | 出厂键位 | 与固件 `DefaultKeymap()` 一致，用于回滚 |
| `writing` | 公众号写作 | 说话成文 + 三个小标题 + 编辑动作 |
| `notes` | 教研速记 | 四个标记键把听到的东西就地分类 |
| `slides` | 讲课演示 | 翻页 / 黑屏 / 全屏 |

加新场景：在 `scenes/` 下放一个 `<名字>.json`，`apply-scene.sh` 会自动列出来，不用改代码。
