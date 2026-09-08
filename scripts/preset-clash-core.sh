#!/bin/bash
#
# 预置 OpenClash 内核与规则库到 files/，让固件开箱即用。
#
# OpenClash 的设计是运行时把内核下载到 /etc/openclash/core/，首次使用必须
# 联网——而这台机器的用途恰恰是"还没能联网时要靠它联网"。所以在构建期就塞进去。
#
# 与 SuLingGG 原版（骷髅头备份仓库 scripts/preset-clash-core.sh）的区别：
#   - 去掉 dev 核心：vernesong 的 core/master/dev/ 已 404，premium 核心停更
#   - 去掉 clash_tun：同上
#   - 只保留 meta 核心（即 mihomo），这是现在 OpenClash 实际用的
#
# 用法: preset-clash-core.sh <arch>    例: preset-clash-core.sh arm64
set -eu

ARCH="${1:-arm64}"
CORE_DIR="files/etc/openclash/core"
mkdir -p "$CORE_DIR" files/etc/openclash

META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-${ARCH}.tar.gz"
GEOIP_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat"
GEOSITE_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat"

echo ">>> 下载 OpenClash meta 内核 ($ARCH)"
curl -fsSL "$META_URL" | tar xOz > "$CORE_DIR/clash_meta"

echo ">>> 下载 GeoIP / GeoSite"
curl -fsSL "$GEOIP_URL"   > files/etc/openclash/GeoIP.dat
curl -fsSL "$GEOSITE_URL" > files/etc/openclash/GeoSite.dat

chmod +x "$CORE_DIR"/clash_meta

# 空文件说明下载失败了，宁可构建失败也不要出一个内核是 0 字节的固件
for f in "$CORE_DIR/clash_meta" files/etc/openclash/GeoIP.dat files/etc/openclash/GeoSite.dat; do
    [ -s "$f" ] || { echo "下载失败或文件为空: $f"; exit 1; }
    printf '    %-40s %s\n' "$(basename "$f")" "$(du -h "$f" | cut -f1)"
done

echo ">>> OpenClash 内核预置完成"
