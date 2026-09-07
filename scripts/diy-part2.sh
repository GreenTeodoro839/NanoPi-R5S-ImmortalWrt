#!/bin/bash
# 在写入 .config 之后、make defconfig 之前执行：改默认配置
set -e

echo ">>> diy-part2: 修改默认配置"

# 默认 LAN IP
sed -i 's/192\.168\.1\.1/192.168.0.1/g' package/base-files/files/bin/config_generate

# 主机名
sed -i "s/hostname='ImmortalWrt'/hostname='OpenWrt'/g" package/base-files/files/bin/config_generate

# Go 构建缓存：golang-values.mk:257 默认放在 $(TMP_DIR)/go-build，
# 而 tmp/ 每次 make 都会重建，等于没有缓存。挪到树根下，CI 才能存下来。
# （GOMODCACHE 在 dl/go-mod-cache，不用改。）
sed -i '/^CONFIG_GOLANG_BUILD_CACHE_DIR=/d' .config
echo "CONFIG_GOLANG_BUILD_CACHE_DIR=\"$PWD/.go-build-cache\"" >> .config
echo ">>> diy-part2: Go 构建缓存 -> $PWD/.go-build-cache"

echo ">>> diy-part2: 完成"
