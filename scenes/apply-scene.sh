#!/bin/bash
# 场景切换工具：同一块板子，换一份配置就是另一个产品。
#
# 用法：
#   apply-scene.sh                       列出所有场景
#   apply-scene.sh <场景名>               预览 + 确认后下发（离线模式，不用 Wi-Fi 密码）
#   apply-scene.sh <场景名> --preview     只看要下发什么，不碰板子
#   apply-scene.sh <场景名> --wifi        连同 Wi-Fi/语音一起下发（要用语音功能时）
#
# 为什么默认离线：这几个场景（摩斯、速记、写作、讲课）全是纯键位，
# 板子当键盘用根本不需要联网。固件的 audio_enabled 是「ssid 非空且
# audio_host 非空」推导出来的，留空即关闭，所以不必每次输 Wi-Fi 密码。

set -u

REPO="/Users/xiangjixiansheng/WorkBuddy/Worktrees/waytoagi硬件/Codex_Keyboard"
BIN="$REPO/target/release/easy-codex-host"

if [ ! -x "$BIN" ]; then
  echo "找不到可执行文件：$BIN"
  echo "先在仓库里编译：cd \"$REPO\" && cargo build --release -p easy-codex-host"
  exit 1
fi

if [ $# -eq 0 ]; then
  "$BIN" scenes-list
  echo
  echo "用法：$0 <场景名>              预览 + 确认后下发（离线，免 Wi-Fi 密码）"
  echo "      $0 <场景名> --preview    只看要下发什么，不动板子"
  echo "      $0 <场景名> --wifi       连 Wi-Fi/语音一起下发"
  exit 0
fi

SCENE="$1"
MODE="${2:-}"

echo "场景：$SCENE"

if [ "$MODE" != "--wifi" ]; then
  echo "模式：离线（只改键位，不动板子的 Wi-Fi/语音配置）"
  echo
  if [ "$MODE" = "--preview" ]; then
    "$BIN" provision-lan --offline --scene "$SCENE" --preview
    exit $?
  fi
  echo "==== 要写进板子的配置 ===="
  "$BIN" provision-lan --offline --scene "$SCENE" --preview
  echo
  read -r -p "确认无误，写入板子？(y/N) " GO
  case "$GO" in
    y|Y) ;;
    *) echo "已取消，板子没动。"; exit 0 ;;
  esac
  echo
  "$BIN" provision-lan --offline --scene "$SCENE"
  STATUS=$?
  echo
  if [ $STATUS -ne 0 ]; then
    echo "下发失败（退出码 $STATUS）。"
    echo "排查顺序："
    echo "  1) 板子连蓝牙了吗：$BIN hid-probe"
    echo "  2) 板子在不在：系统设置 → 蓝牙 → EasyInput AI"
    exit $STATUS
  fi
  echo "已下发。现在可以直接试键位（不用拔插 USB）。"
  echo "换回出厂键位：$0 factory"
  exit 0
fi

# —— 以下是要用语音功能时才走的分支 ——
LAN_IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)"
if [ -z "$LAN_IP" ]; then
  echo "拿不到本机局域网 IP，请确认已连上 Wi-Fi。"
  exit 1
fi
echo "模式：联网（键位 + Wi-Fi + 语音端点）"
echo "本机地址：$LAN_IP"
echo
read -r -p "Wi-Fi 名称（SSID）：" SSID
SSID="${SSID%\"}"; SSID="${SSID#\"}"
read -r -s -p "Wi-Fi 密码（输入不显示）：" WIFI_PASS
echo
echo

if [ "$MODE" = "--preview" ]; then
  printf '%s' "$WIFI_PASS" | "$BIN" provision-lan --scene "$SCENE" --preview "$SSID" "$LAN_IP"
  exit $?
fi

echo "==== 第一步：预览要写进板子的配置 ===="
printf '%s' "$WIFI_PASS" | "$BIN" provision-lan --scene "$SCENE" --preview "$SSID" "$LAN_IP"
echo
read -r -p "确认无误，写入板子？(y/N) " GO
case "$GO" in
  y|Y) ;;
  *) echo "已取消，板子没动。"; exit 0 ;;
esac

echo
echo "==== 第二步：下发 ===="
printf '%s' "$WIFI_PASS" | "$BIN" provision-lan --scene "$SCENE" "$SSID" "$LAN_IP"
STATUS=$?
echo
if [ $STATUS -ne 0 ]; then
  echo "下发失败（退出码 $STATUS）。板子多半没连蓝牙，或不在配置模式。"
  echo "排查：$BIN hid-probe"
  exit $STATUS
fi

echo "已下发。拔掉 USB 之前先按键试一遍："
echo "  KEY1 按住说话 → 松手，看板子灯和喇叭是否响应"
echo "回滚到出厂键位：$0 factory"
