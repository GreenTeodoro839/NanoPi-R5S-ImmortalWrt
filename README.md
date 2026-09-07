# ImmortalWrt for NanoPi R5S

自用固件构建脚本。GitHub Actions 云编译，产物在 Actions 的 Artifacts 里。

## 配置

| 项 | 值 |
|---|---|
| 上游 | [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) `openwrt-24.10`（内核 6.6） |
| 设备 | `rockchip / armv8 / friendlyarm_nanopi-r5s` |
| 网卡驱动 | `kmod-r8125`（ImmortalWrt 自带，厂商驱动，优于官方 OpenWrt 的 `r8169`） |
| 根文件系统 | ext4，8192 MB（跑 Docker + NAS，刷 32GB eMMC） |
| 默认地址 | `192.168.11.1` |

## 内容

- **代理**：PassWall / OpenClash / HomeProxy / Nikki(mihomo)
- **DNS**：MosDNS（feed 自带 5.3.3 本体 + sbwml 的 LuCI 界面）
- **容器**：dockerd + docker-compose + DockerMan
- **NAS**：DiskMan、Samba4、qBittorrent、FileBrowser
- **广告过滤**：AdGuardHome（feed 自带后端 + sirpdboy `js` 分支界面）
- **组网**：ZeroTier、frpc
- **下载**：aria2
- **运维**：nlbwmon 流量统计、watchcat 断网重连、commands 自定义命令、advanced-reboot、eqos 限速
- **商店**：iStore
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

## 刷机

用 `*-ext4-sysupgrade.img.gz`：

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
