#!/usr/bin/env python3
"""验证摩斯键位是否真的生效。

用法：
    python3 verify-morse.py            # 等板子启动，然后监听 15 秒
    python3 verify-morse.py 25         # 自定义监听秒数

流程：
  1. 轮询 hid-probe，等板子从下载模式回到正常固件（TinyUSB 重新枚举出键盘集合）
  2. 调 hid-watch 监听 N 秒
  3. 解析报文：键盘集合上的 report id 0x01，长度 9 字节，
     结构是 [01] [modifier] [apple_fn] [k1..k6]
     只要在键位字节里看到 0x2C 就是空格，说明 KEY1 生效了。

退出码：0 = 抓到了空格；1 = 没抓到；2 = 板子一直没出现。
"""
import re
import subprocess
import sys
import time

REPO = "/Users/xiangjixiansheng/WorkBuddy/Worktrees/waytoagi硬件/Codex_Keyboard"
BIN = f"{REPO}/target/release/easy-codex-host"
# 注意：macOS 对键盘集合有输入保护。厂商通道（report 0x11）读得到，
# 但标准键盘报文（report 0x01）非受信任进程收不到。所以本脚本抓不到
# 键盘报文不代表板子没发。唯一可信的判据是在真实应用里打出字符。
KEYBOARD_TAG = "usage_page=0x0001 usage=0x0006"  # 键盘集合


def run(*args, timeout=120):
    return subprocess.run(
        [BIN, *args], capture_output=True, text=True, timeout=timeout
    ).stdout


def wait_for_board(limit_seconds=180):
    """等板子从下载模式出来。判据：出现可打开的键盘集合。"""
    print("等待板子启动（如果它还在下载模式，请拔掉 USB 线再插回）...")
    deadline = time.time() + limit_seconds
    last_note = 0
    while time.time() < deadline:
        out = run("hid-probe")
        if "usage=0x0006" in out:
            count = out.count("usage_page")
            print(f"板子已上线，HID 集合 {count} 个。")
            return True
        if time.time() - last_note > 20:
            print("  ...还没出现，继续等")
            last_note = time.time()
        time.sleep(2)
    return False


def watch(seconds):
    print(f"监听 {seconds} 秒 —— 现在请按住 KEY1 两三下，每下按 100~300 毫秒。")
    out = run("hid-watch", str(seconds), timeout=seconds + 30)
    return out


def main():
    seconds = int(sys.argv[1]) if len(sys.argv) > 1 else 15

    if not wait_for_board():
        print("板子一直没出现。检查：USB 线是数据线吗？板子灯亮着吗？")
        return 2

    # 给 macOS 一点时间把键盘驱动挂上
    time.sleep(2)
    out = watch(seconds)

    # 严格判据：键盘报文必须以 01 开头且正好 9 字节
    # （[01][modifier][apple_fn][k1..k6]）。厂商报文是 11 开头 64 字节，
    # 里面常含 2C（JSON 的逗号），绝不能用「出现 2C」来判断。
    def is_keyboard_frame(line):
        if KEYBOARD_TAG not in line or "len=9" not in line:
            return False
        m = re.search(r"\[([0-9A-F ]+)\]", line)
        if not m:
            return False
        bs = m.group(1).split()
        return len(bs) == 9 and bs[0] == "01"

    keyboard_lines = [line for line in out.splitlines() if is_keyboard_frame(line)]
    other_count = sum(1 for line in out.splitlines() if "len=" in line) - len(
        keyboard_lines
    )

    print()
    if not keyboard_lines:
        print("没收到键盘报文。")
        print("提示：macOS 对键盘集合有输入保护，本脚本本来就可能读不到标准")
        print("键盘报文。所以「没抓到」不等于「板子没发」——请以真实应用里")
        print("是否打出字符为准。")
        if other_count:
            print(f"（收到 {other_count} 条其它通道的报文，说明 USB 通着，只是没发键盘报文）")
        print()
        print("可能的原因，按可能性排序：")
        print("  1. 按的时候没按到位 —— 灯变红才算按到")
        print("  2. 板子跑的还不是刚刷的固件（刷完没拔插，还在下载模式）")
        print("  3. 板上 NVS 里的键位配置不是 morse —— 跑 provision-lan --offline --scene morse 重下发")
        return 1

    hit = False
    for line in keyboard_lines:
        hex_part = re.search(r"\[([0-9A-F ]+)\]", line)
        if not hex_part:
            continue
        bytes_ = hex_part.group(1).split()
        print("键盘报文：" + " ".join(bytes_))
        # [0]=report id 01, [1]=modifier, [2]=apple_fn, [3..8]=keycodes
        if len(bytes_) >= 4 and "2C" in bytes_[3:]:
            hit = True

    print()
    if hit:
        print("成功：抓到空格键（键码 0x2C）。KEY1 已经是发报键了。")
        print("现在打开「摩斯电码练习机」网页，点一下输入框，就能开始练。")
        return 0

    print("收到键盘报文，但里面没有 0x2C。")
    print("说明按键已经能发 HID 了，只是这个键不是空格 —— 键位配置可能被改过。")
    print("重新下发：easy-codex-host provision-lan --offline --scene morse")
    return 1


if __name__ == "__main__":
    sys.exit(main())
