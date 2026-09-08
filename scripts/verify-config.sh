#!/bin/bash
#
# 校验 make defconfig 之后，种子配置里要求的每一项是否都还在。
#
# 为什么需要：defconfig 会静默丢弃无法解析的符号（包名写错、依赖不满足、
# 符号被 menu 的 depends on 挡住），不报任何错。不检查的话，要等固件刷进
# eMMC 才发现少了东西。本项目已经被坑过两次：
#   - CONFIG_TARGET_DEVICE_..._nanopi-r5s=y 因为没开 TARGET_MULTI_PROFILE
#     被丢弃，等于没选设备
#   - 早期若干包名写错，静默不进固件
#
# 用法: verify-config.sh <种子config> <make defconfig 后的 .config>
set -u

SEED="${1:?用法: $0 <seed-config> <final-.config>}"
FINAL="${2:?用法: $0 <seed-config> <final-.config>}"

[ -r "$SEED"  ] || { echo "读不到种子配置: $SEED";  exit 2; }
[ -r "$FINAL" ] || { echo "读不到最终配置: $FINAL"; exit 2; }

declare -a MISSING=()
total=0

while IFS= read -r line || [ -n "$line" ]; do
    # 跳过空行和注释（含 "# CONFIG_X is not set"，那是期望不选，不强制校验）
    [ -n "$line" ] || continue
    case "$line" in \#*) continue ;; esac

    total=$((total + 1))
    grep -qxF -- "$line" "$FINAL" || MISSING+=("$line")
done < "$SEED"

echo "种子配置共 $total 项要求"

if [ ${#MISSING[@]} -gt 0 ]; then
    echo
    echo "以下 ${#MISSING[@]} 项被 make defconfig 丢弃："
    for m in "${MISSING[@]}"; do
        echo "  ✗ $m"
        # 给出线索：同名符号在最终配置里是什么状态
        sym="${m%%=*}"
        hint=$(grep -E "^(# )?${sym}( is not set|=)" "$FINAL" | head -1)
        [ -n "$hint" ] && echo "      最终配置里: $hint" \
                       || echo "      最终配置里: 该符号完全不存在（包名错误或 feed 未提供）"
    done
    echo
    exit 1
fi

echo "全部保留 ✓"

# 附带信息：kmod 数量（本项目开了 ALL_KMODS 做离线源，数量骤降说明出问题了）
kmods=$(grep -c '^CONFIG_PACKAGE_kmod-.*=m$' "$FINAL" || true)
echo "kmod 模块数: $kmods"
