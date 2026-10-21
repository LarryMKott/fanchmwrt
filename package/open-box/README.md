# open-box（N1 固件内置包）

把 [Open-Box](https://github.com/liandu2024/Open-Box) 一体化透明代理打进 N1 镜像。
刷好即用，不需要 SSH 上去 `curl | sh`。

## 为什么是「预编译包」

上游只发布预编译发布包，没有可交叉编译的源码（自有面板程序闭源，sing-box / Node /
GeoSite 按各自许可随包分发）。所以这里不编译任何东西，只在 **build 时** 从官方 GitHub
Release 取 tarball，按上游 `scripts/install.sh` 的落点铺进 rootfs：

| 上游文件 | 落点 |
| --- | --- |
| `bin/ node/ panel/ openwrt/ debian/ meta.json LICENSE COPYRIGHT.md update.sh uninstall.sh` | `/opt/open-box/` |
| `openwrt/initd/openbox-panel`、`openwrt/initd/openbox` | `/etc/init.d/` |
| `openwrt/initd/openbox-panel` | `/etc/rc.d/S98openbox-panel`（开机自启） |
| `openwrt/luci/htdocs/luci-static/resources/view/openbox/main.js` | `/www/luci-static/resources/view/openbox/` |
| `openwrt/luci/root/usr/share/luci/menu.d/luci-app-openbox.json` | `/usr/share/luci/menu.d/` |
| `openwrt/luci/root/usr/share/rpcd/acl.d/luci-app-openbox.json` | `/usr/share/rpcd/acl.d/` |
| `openwrt/bin/open-box` | `/usr/bin/open-box`（软链接，SSH 下的 `open-box` 命令） |
| — | `/opt/open-box/data/panel-port`（预置 `3036`） |

面板服务脚本硬编码 `/opt/open-box`，基础路径不能改，改了等于 fork 上游。

`/etc/init.d/openbox`（sing-box 内核）只装**不启用**，与上游一致：内核由面板按配置拉起，
开机只拉起面板（`START=98`）。

## 依赖

由 `DEPENDS` 自动拉齐，不在 `.config` 里重复声明：

- `kmod-tun` — TUN 设备；`kmod-nft-queue` / `kmod-nft-nat` — nftables 队列与 NAT
- `kmod-veth` — 命名空间对；`ip-full` — RTNL 能力（busybox ip 不够）
- `ca-bundle` — 下载规则库/订阅；`curl` — 面板抓订阅被拒时的兜底通道
- `luci-base` / `rpcd` — LuCI 入口与 ACL

## 体积 / 分区

解包后 `/opt/open-box` 约 **168 MiB**（node 运行时 ~98 MiB、sing-box ~43 MiB、
panel ~30 MiB）。N1 默认 rootfs 只有 104 MiB，装不下 ——
`.github/workflows/build-n1.yml` 里已把 `CONFIG_TARGET_ROOTFS_PARTSIZE` 放大到 **1024**，
并在 `make defconfig` 之后校验这两个符号没有被打回默认值。N1 是 8 GiB eMMC，1 GiB rootfs
顺带给 Open-Box 自己的升级留了空间（每次下载完整发布包约 76 MiB）。

## 升级 Open-Box

改两行，重新打包镜像：

1. `PKG_VERSION` 换成新 tag（去掉 `v`，如 `v0.1.345` → `0.1.345`）
2. `PKG_HASH` 换成该 release 里 `open-box-v<version>-linux-arm64.tar.gz.sha256` 的值

另外该 release 的 `meta.json` 里记录 `nodeVersion` / `singboxVersion`，可用来核对。

已经刷机的设备也可以不动镜像，用面板或 `open-box update` 自升级（上游机制，
写到 `/opt/open-box`，rootfs 空间够）。

## 许可提醒

上游 `LICENSE` 声明自有程序闭源、「未经许可禁止复制传播、再分发」。自己刷机、内部使用
不受影响；把本包打进镜像后**对外分发镜像**属于再分发上游二进制，发布前请自行确认授权。
本包在 `PKG_LICENSE` 里如实标成 `Proprietary`。

## 架构

上游只提供 `aarch64`（arm64）和 `x86_64`（x64）两种预编译包。其它架构选到这个包会在
`Build/Prepare` 直接报错，不会产出「能刷进去但起不来」的镜像。
