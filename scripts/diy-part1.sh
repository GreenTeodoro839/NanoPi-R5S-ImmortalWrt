#!/bin/bash
# 在 feeds update/install 之前执行：注入第三方软件包
set -e

echo ">>> diy-part1: 注入第三方包"

mkdir -p package/community
pushd package/community >/dev/null

# iStore 应用商店（ImmortalWrt feed 里没有 luci-app-store）
git clone --depth=1 https://github.com/linkease/istore

# Nikki（mihomo/Clash 内核）—— feed 里没有
git clone --depth=1 https://github.com/nikkinikki-org/OpenWrt-nikki

popd >/dev/null

# MosDNS：ImmortalWrt 只有 mosdns 本体、没有 LuCI 界面。
# sbwml 的仓库同时带本体和界面，所以必须先删掉 feed 里的本体，否则包名冲突。
rm -rf feeds/packages/net/mosdns
git clone --depth=1 -b v5 https://github.com/sbwml/luci-app-mosdns package/mosdns

echo ">>> diy-part1: 完成"
