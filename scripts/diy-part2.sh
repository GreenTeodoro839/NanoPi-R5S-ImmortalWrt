#!/bin/bash
# 在写入 .config 之后、make defconfig 之前执行：改默认配置
set -e

echo ">>> diy-part2: 修改默认配置"

# 默认 LAN IP
sed -i 's/192\.168\.1\.1/192.168.0.1/g' package/base-files/files/bin/config_generate

# 主机名
sed -i "s/hostname='ImmortalWrt'/hostname='OpenWrt'/g" package/base-files/files/bin/config_generate

echo ">>> diy-part2: 完成"
