# ImmortalWrt for NanoPi R5S

自用固件构建脚本。GitHub Actions 云编译，产物在 Actions 的 Artifacts 里。

## 配置

| 项 | 值 |
|---|---|
| 上游 | [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) `openwrt-24.10`（内核 6.6） |
| 设备 | `rockchip / armv8 / friendlyarm_nanopi-r5s` |
| 网卡驱动 | `kmod-r8125`（ImmortalWrt 自带，厂商驱动，优于官方 OpenWrt 的 `r8169`） |
| 根文件系统 | squashfs + overlay，分区 2 = **2048 MB**（其余 eMMC 空间留给 Docker） |
| 默认地址 | `192.168.0.1`（主机名 `OpenWrt`） |

## 内容

- **代理**：PassWall / OpenClash / HomeProxy / Nikki(mihomo)
- **DNS**：MosDNS（feed 自带 5.3.3 本体 + sbwml 的 LuCI 界面）
- **容器**：dockerd + docker-compose + DockerMan
- **NAS**：DiskMan、Samba4、qBittorrent、FileBrowser
- **广告过滤**：AdGuardHome（feed 自带后端 + sirpdboy `js` 分支界面）
- **组网**：ZeroTier、frpc
- **下载**：aria2
- **运维**：nlbwmon 流量统计、watchcat 断网重连、commands 自定义命令、advanced-reboot、eqos 限速
- **商店**：iStore（含 `taskd` / `luci-lib-taskd` / `luci-lib-xterm` 依赖）
- **OpenClash 内核**：构建期预置 `clash_meta` + GeoIP/GeoSite，开箱即用不需联网下载
- **离线 kmod 源**：全量 kmod 打包进固件 `/usr/lib/opkg/kmods`，`opkg` 通过 `file://` 直接安装，不依赖网络

## 为什么要内置 kmod 源

kmod 的 opkg 路径带 vermagic（内核配置指纹）：

```
targets/rockchip/armv8/kmods/6.6.x-1-<md5>/
```

自己编译的内核配置跟官方不一样，哈希对不上，官方 kmod 源用不了。而 `include/feeds.mk` 里那行 kmods feed 只在 `CONFIG_BUILDBOT=y` 时才写进 `distfeeds.conf`，自编译固件默认根本没有 kmod 源。

所以这里开 `CONFIG_ALL_KMODS=y` 编出全部 kmod，`make package/index` 生成签名索引，塞进 rootfs，用 opkg 原生支持的 `file:` 协议（`libopkg/opkg_download.c` 里直接走 `file_copy`）当本地源。

## 关于 MosDNS 的版本选择

sbwml `v5` 分支里的 mosdns 是 **5.3.4**，`go.mod` 要求 **Go 1.24.9**；而 ImmortalWrt
24.10 自带的 golang 是 **1.23.12**，直接用会编译失败。feed 自带的 mosdns **5.3.3**
只要求 Go 1.22，能正常编译。

所以这里只从 sbwml 取 `luci-app-mosdns` 和 `geo2txt`（纯 C），本体用 feed 里的，
**不动 golang 工具链**——换 golang 会连带影响 xray / sing-box / mihomo 等一整串
Go 包的编译。

## 关于 AdGuardHome 界面的分支选择

`sirpdboy/luci-app-adguardhome` 有两个分支，**必须用 `js`**：

| 分支 | 内容 | 适用 |
|---|---|---|
| `js` | `htdocs/` | LuCI 24.10（JS 版）✅ |
| `main` | `luasrc/` | 老 Lua 版，24.10 上界面打不开 ❌ |

后端 `adguardhome` 用 ImmortalWrt feed 自带的，不额外引入。

## 如何定制

仓库只有四个地方需要动，改完 push 就会自动触发构建（`configs/**`、`scripts/**`、
`.github/workflows/build.yml` 任一变化都会触发；只改 README 不会）。

```
configs/r5s.config      装哪些包、分区多大        ← 90% 的改动在这
scripts/diy-part1.sh    拉第三方源码、动 feeds    （feeds update 之前跑）
scripts/diy-part2.sh    改默认配置                （make defconfig 之前跑）
files/                  直接塞进固件的文件         （由 CI 在构建中生成，见下）
```

### 加插件

在 `configs/r5s.config` 里加一行就行，**不用改 workflow**：

```
CONFIG_PACKAGE_luci-app-xxx=y
```

加之前先确认包名真的存在，否则 `make defconfig` 会静默丢弃（校验会拦下来，
但白等三分钟）：

```sh
# luci 应用
curl -sI https://raw.githubusercontent.com/immortalwrt/luci/openwrt-24.10/applications/luci-app-xxx/Makefile
# 主题在 themes/，协议插件在 protocols/，别只找 applications/
# 用户态软件
curl -sI https://raw.githubusercontent.com/immortalwrt/packages/openwrt-24.10/net/xxx/Makefile
```

一般只写 `luci-app-*` 就够，后端会被 `LUCI_DEPENDS` 自动拉进来。**例外**：依赖
里没列的东西不会自动带。踩过的坑——`luci-proto-wireguard` 的依赖不含
`kmod-wireguard`，而本项目开了 `ALL_KMODS` 让所有 kmod 默认 `=m`（只进离线源、
不装进固件），结果建隧道时才发现模块不在。所以拿不准就把关键依赖显式写上，
让 `verify-config.sh` 盯住。

改完可以先本地干跑校验，不用等 CI：

```sh
./scripts/verify-config.sh configs/r5s.config <某次构建产出的.config>
```

### 加第三方软件源

有两种，选哪种取决于要不要跟 feed 里的同名包冲突。

**A. 整个源码目录塞进 `package/`** —— 适合单个插件仓库，在 `scripts/diy-part1.sh` 里：

```sh
git clone --depth=1 https://github.com/OWNER/REPO package/community/REPO
```

如果这个仓库带的包和 feed 里重名，**必须先删掉 feed 里的**，否则构建会因重复包报错：

```sh
rm -rf feeds/packages/net/mosdns          # 先删 feed 版
git clone --depth=1 -b v5 https://github.com/sbwml/luci-app-mosdns package/mosdns
```

只想要仓库里的一部分时，克隆到临时目录再挑（本项目对 mosdns 就是这么做的，
因为 sbwml 的 mosdns 5.3.4 要 Go 1.24.9，超过自带的 1.23.12）：

```sh
git clone --depth=1 -b v5 https://github.com/sbwml/luci-app-mosdns /tmp/src
cp -r /tmp/src/luci-app-mosdns package/mosdns/     # 只要界面
cp -r /tmp/src/geo2txt          package/mosdns/     # 和它的纯 C 依赖
rm -rf /tmp/src                                     # 本体继续用 feed 里的
```

**B. 加成 feed** —— 适合大型包集合，在 `diy-part1.sh` 里追加到 `feeds.conf.default`：

```sh
echo 'src-git-full smallpkg https://github.com/kenzok8/small-package;main' >> feeds.conf.default
```

顺序有讲究：**放在 packages/luci 之后**，同名包才会被第三方版本覆盖。装的时候
建议点名装而不是 `-a` 全装，否则一堆重名冲突：

```sh
./scripts/feeds install -p smallpkg luci-app-xxx
```

### 加自定义脚本 / 塞文件进固件

**改默认配置**（IP、主机名等）用 `scripts/diy-part2.sh`，它在 `make defconfig`
之前跑，改的是"生成默认配置的逻辑"：

```sh
sed -i 's/192\.168\.1\.1/192.168.11.1/g' package/base-files/files/bin/config_generate
```

**直接塞文件进固件**用 `files/` 目录——源码根目录下叫 `files` 的目录会被原样
叠加进 rootfs（机制在 `package/Makefile` 的 `prepare_rootfs`）。路径即固件里的
绝对路径：

```sh
mkdir -p files/etc/config
cp my-network files/etc/config/network        # 会覆盖 config_generate 生成的
mkdir -p files/etc/dropbear
echo "ssh-ed25519 AAAA... you@host" > files/etc/dropbear/authorized_keys
```

`files/` 优先级高于 `diy-part2.sh` 改的生成逻辑，两者别混用同一个文件。

**时机很关键**：`files/` 必须在 `make package/install` 之前填好。本项目的
workflow 已经把构建拆成了多段，正是为了在中间插入这类操作：

```
package/compile → package/index → [预置 OpenClash 内核] → [塞 kmod 离线源] → package/install → target/install
                                   ↑ 往 files/ 写东西就插在这一段
```

要加自己的预置脚本，写成 `scripts/preset-xxx.sh`（参考
`scripts/preset-clash-core.sh`），然后在 `build.yml` 里 `Generate package index`
和 `Build rootfs & image` 之间加一步调用即可。脚本里记得校验下载结果非空——
宁可构建失败，也别出一个内核是 0 字节的固件。

## 构建校验

`scripts/verify-config.sh` 在 `make defconfig` 之后比对种子配置与最终 `.config`，
**校验清单从 `configs/r5s.config` 推导，不在 workflow 里硬编码包名**——加包只改
种子配置一处。

必要性：`make defconfig` 遇到无法解析的符号（包名写错、依赖不满足、符号被
`menu ... depends on` 挡住）会**静默丢弃且不报错**。本项目被坑过两次：

- `CONFIG_TARGET_DEVICE_..._nanopi-r5s=y` 因为漏了 `TARGET_MULTI_PROFILE` 被丢弃，
  等于根本没选设备
- 若干包名写错，静默不进固件

`scripts/verify-rootfs`（内联在 workflow）另外拦截 squashfs 超出分区的情况，
见下文分区规划。

## 分区规划（重要）

镜像本身只有两个分区（`gen_image_generic.sh` 里 `ptgen` 只切两个）：

```
p1  boot     64 MB   内核 + dtb
p2  rootfs 2048 MB   squashfs(只读) + 剩余空间做 overlay
--  剩余的 eMMC 空间：留白，刷完机后自己建 p3 给 Docker
```

Docker 数据**必须**放在 p3 这种真实 ext4 分区上，不能放 overlay。原因见下节。

### ROOTFS_PARTSIZE 定了就别改

`target/linux/rockchip/armv8/base-files/lib/upgrade/platform.sh`：

```sh
diff="$(grep -F -x -v -f /tmp/partmap.bootdisk /tmp/partmap.image)"
if [ -n "$diff" ]; then
    get_image "$@" | dd of="/dev/$diskdev" bs=4096 conv=fsync   # 整盘写，p3 全没
fi
while read part start size; do ...  # diff 为空时只写镜像里的 p1/p2，p3 保住
```

diff 算的是"镜像里有、磁盘上没有"的分区，你手工加的 p3 不在镜像里，所以不触发。
但只要你改了 `ROOTFS_PARTSIZE` 重编，分区表就对不上 → 整盘 dd → **Docker 数据全丢**。

## 为什么 Docker 不能放 overlay

Docker 27 已经没有"overlay2 不支持 overlayfs"的硬编码黑名单了，改成运行时探测，
而内核的栈深度限制是 `FILESYSTEM_MAX_STACK_DEPTH = 2`，overlay 套 overlay 正好
等于 2，**探测会通过，Docker 会选中 overlay2**。

问题在 xattr。`fs/overlayfs/super.c`：

```c
static int ovl_own_xattr_set(...) { return -EOPNOTSUPP; }

static const struct xattr_handler ovl_own_trusted_xattr_handler = {
	.prefix = OVL_XATTR_TRUSTED_PREFIX,   /* "trusted.overlay." */
	.set = ovl_own_xattr_set,
};
```

overlayfs 拒绝对自己私有 xattr 的读写。内层 overlay 要往 upperdir 写
`trusted.overlay.opaque` 来记录"此目录已删除"，落在外层 overlay 上就是 `-EOPNOTSUPP`。
内核不报错，而是降级：

```c
err = ovl_setxattr(ofs, ofs->workdir, OVL_XATTR_OPAQUE, "0", 1);
if (err) {
	pr_warn("failed to set xattr on upper\n");
	ofs->noxattr = true;      /* redirect_dir/metacopy/index/xino 全关 */
}
```

结果是**能跑但功能残缺**：容器里删掉来自底层镜像的目录记录不下来，重建时文件可能
复活；`index=off` 导致层间无法硬链接共享，磁盘占用膨胀。比干净地退回 vfs 更麻烦，
因为它看起来是正常的。

刷完机可以自查：

```sh
dmesg | grep -i overlay        # 不该出现 "failed to set xattr on upper"
docker info | grep -i 'storage driver'
```

## 刷机

用 `*-squashfs-sysupgrade.img.gz`：

1. 从[友善官网](https://wiki.friendlyelec.com/wiki/index.php/NanoPi_R5S/zh)下 eflasher 镜像烧到 TF 卡
2. 把本固件的 `.img.gz` 拷到卡上的 `FriendlyARM` 目录
3. 改卡根目录 `eflasher.conf` 的 `autoStart=` 指向该文件名
4. 插卡开机，自动写入 eMMC

注意上电引导优先级是 **TF 卡 > eMMC**，刷完记得拔卡。

## 刷完之后要做的

ImmortalWrt 给 firewall4 打了补丁，默认 `flow_offloading` / `flow_offloading_hw` /
`fullcone` 全开。**这几项跑透明代理时不需要关**：

firewall4 的 offload 规则只出现在 forward 链：

```
chain forward {
    type filter hook forward priority filter;
    meta l4proto { tcp, udp } flow offload @ft;
    ...
}
```

透明代理的流量在 `mangle prerouting` 被 TPROXY 标记后本地投递进 core，不经过
forward 链，因此永远不会进 flowtable。直连流量走 forward，正常吃到分载加速。
两者按设计共存。

`flow_offloading_hw` 在 R5S 上也无需操心：r8125/stmmac 没有 flowtable 硬件卸载
能力，fw4 的 `nft_try_hw_offload()` 会先用 `nft -c` 干跑测试，失败就打印
"Hardware flow offloading unavailable, falling back to software offloading"
并自动降级为软件分载。

### 需要留意的

- **SQM 与 flow offload 可能互斥**（社区普遍说法，本项目未验证）。若用
  `luci-app-sqm` 限速，实测一下限速是否生效；不生效就关掉 `flow_offloading`。
- 已被 offload 的直连连接不会重新匹配规则。把某域名从直连改到代理后，**已建立的
  连接**仍走直连，新连接才生效。

Docker 建议用 macvlan 或 host 网络，别用 bridge —— `dockerd` 依赖链会拉进 `br_netfilter`，Docker 启动时打开 `bridge-nf-call-iptables`，会让 PassWall 的 UDP 透明代理失效。
