#!/bin/bash
# 在 feeds update/install 之前执行：注入第三方软件包
set -e

echo ">>> diy-part1: 注入第三方包"

mkdir -p package/community
pushd package/community >/dev/null

# iStore 应用商店（ImmortalWrt feed 里没有 luci-app-store）
git clone --depth=1 https://github.com/linkease/istore

# Nikki（mihomo/Clash 内核）—— feed 里没有
# mihomo 1.19.30 的 go.mod 只要 Go 1.20，自带的 1.23.12 够用
git clone --depth=1 https://github.com/nikkinikki-org/OpenWrt-nikki

popd >/dev/null

# ---------------------------------------------------------------------------
# MosDNS
#
# ImmortalWrt feed 里有 mosdns 本体（5.3.3）但没有 LuCI 界面。
#
# 注意：不要用 sbwml v5 分支里的 mosdns 本体——那是 5.3.4，它的 go.mod 要求
# Go 1.24.9，而 ImmortalWrt 24.10 自带的 golang 是 1.23.12，会编译失败：
#     ERROR: package/mosdns/mosdns failed to build.
# 自带的 5.3.3 只要求 Go 1.22，能正常编译。
#
# 所以这里只取 sbwml 的 LuCI 界面和 geo2txt（纯 C，不涉及 Go），
# 本体继续用 feed 里的，golang 工具链保持不动。
# ---------------------------------------------------------------------------
rm -rf /tmp/mosdns-src
git clone --depth=1 -b v5 https://github.com/sbwml/luci-app-mosdns /tmp/mosdns-src
mkdir -p package/mosdns
cp -r /tmp/mosdns-src/luci-app-mosdns package/mosdns/
cp -r /tmp/mosdns-src/geo2txt        package/mosdns/
rm -rf /tmp/mosdns-src

echo ">>> diy-part1: 完成"
echo "    package/mosdns 内容: $(ls package/mosdns | tr '\n' ' ')"
