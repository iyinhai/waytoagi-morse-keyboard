#!/bin/bash
# 把当前的「摩斯键位」固件刷进板子。
#
# 为什么需要手动进下载模式：这块板子跑的是 TinyUSB HID，同一个 USB 口
# 不再提供串口，esptool 没法用 DTR/RTS 自动复位，只能让 ROM 自己暴露
# USB-Serial-JTAG。所以要手动：按住 BOOT（KEY1 那侧的 BOOT 键）→ 插 USB
# （或按一下 RST）→ 松手。这时 /dev/cu.usbmodem* 会出现。
#
# 注意：本脚本刻意不擦 0x9000 的 nvs。那一块同时存着蓝牙配对密钥和键位
# 配置，擦掉会导致要重新配对。

set -u

IDF_PATH_DEFAULT="/Users/xiangjixiansheng/esp/esp-idf-v5.5.5"
IDF_PATH="${IDF_PATH:-$IDF_PATH_DEFAULT}"
HERE="$(cd "$(dirname "$0")" && pwd)"
BUILD="$HERE/build"

if [ ! -f "$BUILD/easy_codex_input.bin" ]; then
  echo "没找到 $BUILD/easy_codex_input.bin，先编译："
  echo "  cd \"$HERE\" && idf.py build"
  exit 1
fi

PORT="$(ls /dev/cu.usbmodem* 2>/dev/null | head -1)"
if [ -z "$PORT" ]; then
  echo "没有找到 /dev/cu.usbmodem*（板子不在下载模式）。"
  echo
  echo "请按这个顺序操作："
  echo "  1. 拔掉板子的 USB 线"
  echo "  2. 按住板子上的 BOOT 键不放"
  echo "  3. 插上 USB 线"
  echo "  4. 等 1 秒松开 BOOT 键"
  echo "  5. 重新运行本脚本"
  exit 1
fi

echo "端口：$PORT"
echo "写入：bootloader + 分区表 + 应用（不碰 nvs）"
echo

export IDF_PATH
export PATH="/Users/xiangjixiansheng/.espressif/python_env/idf5.5_py3.14_env/bin:$PATH"
# 本机代理是死的，esptool 走串口不受影响，但保险起见清掉。
no_proxy='*' NO_PROXY='*' python -m esptool \
  --chip esp32s3 -p "$PORT" -b 460800 \
  --before default_reset --after hard_reset \
  write_flash --flash_mode dio --flash_size 16MB --flash_freq 80m \
  0x0 "$BUILD/bootloader/bootloader.bin" \
  0x8000 "$BUILD/partition_table/partition-table.bin" \
  0x10000 "$BUILD/easy_codex_input.bin"
STATUS=$?

echo
if [ $STATUS -eq 0 ]; then
  echo "刷写完成。"
  echo
  echo "注意：ESP32-S3 经 USB 触发的复位会停在下载模式。如果刷完板子没反应："
  echo "  拔掉 USB 线，用电池启动（或拔插一次），再连蓝牙。"
  echo
  echo "验证：$HERE/../target/release/easy-codex-host hid-watch 10"
  echo "按住 KEY1 应该看到报告 ID 01 的报文，第二个字节之后是 2C（空格）。"
else
  echo "刷写失败（退出码 $STATUS）。"
  echo "多半是没进下载模式，或者端口选错了。重试一次上面的 1-5 步。"
fi
exit $STATUS
