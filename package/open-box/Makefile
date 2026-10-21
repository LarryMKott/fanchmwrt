# SPDX-License-Identifier: GPL-2.0-only
#
# Open-Box 一体化透明代理：自有面板程序 + 随包 sing-box 内核 + 随包 Node 运行时 +
# 内置 GeoSite/GeoIP 规则库。上游：https://github.com/liandu2024/Open-Box
#
# 上游只发布「预编译发布包」，没有可交叉编译的源码（自有程序闭源，第三方组件按各自
# 许可随包分发），所以这里按预编译二进制包处理：build 时从官方 GitHub Release 取
# tarball，按上游 scripts/install.sh 的落点铺进镜像。升级 Open-Box 只改 PKG_VERSION
# 和 PKG_HASH 两行（hash 在 release 的 *.tar.gz.sha256 里）。
#
# 体积参考（v0.1.344 / arm64）：发布包 76 MiB，解包后 /opt/open-box 约 168 MiB。
# N1 默认 rootfs 分区只有 104 MiB，装不下 —— 所以 .github/workflows/build-n1.yml 里
# CONFIG_TARGET_ROOTFS_PARTSIZE 已放大到 1024。
#
# 许可提醒：上游 LICENSE 声明自有程序闭源、「未经许可禁止复制传播、再分发」。
# 自己刷机 / 内部使用不受影响；把本包打进镜像再对外分发镜像属于再分发上游二进制，
# 发布前请自行确认授权。
#
include $(TOPDIR)/rules.mk

PKG_NAME:=open-box
PKG_VERSION:=0.1.344
PKG_RELEASE:=1

OPENBOX_REPO:=liandu2024/Open-Box

# 上游 asset 命名：open-box-v<version>-linux-{arm64,x64}.tar.gz
# 目前只支持这两种架构，其它架构在 Build/Prepare 里明确报错，避免装进去一个跑不起来的镜像。
ifeq ($(ARCH),aarch64)
  OPENBOX_ASSET:=arm64
else ifeq ($(ARCH),x86_64)
  OPENBOX_ASSET:=x64
else
  OPENBOX_ASSET:=
endif

ifneq ($(OPENBOX_ASSET),)
  PKG_SOURCE:=open-box-v$(PKG_VERSION)-linux-$(OPENBOX_ASSET).tar.gz
  PKG_SOURCE_URL:=https://github.com/$(OPENBOX_REPO)/releases/download/v$(PKG_VERSION)
  PKG_HASH:=09454da9b3e918387616996a5515f1c32061bb2fc1b6b24de7d5aacd71cf6952
  # 发布包没有顶层目录（tar 根就是 bin/ node/ panel/ openwrt/ ...），默认 PKG_UNPACK
  # 会把内容解到 $(BUILD_DIR) 而不是 $(PKG_BUILD_DIR)，所以自己指定解包目录。
  PKG_UNPACK:=$(HOST_TAR) -xzf $(DL_DIR)/$(PKG_SOURCE) -C $(PKG_BUILD_DIR)
endif

PKG_LICENSE:=Proprietary
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=LarryMKott

include $(INCLUDE_DIR)/package.mk

define Package/open-box
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Web Servers/Proxies
  TITLE:=Open-Box 一体化透明代理（面板 + sing-box + 随包 Node）
  URL:=https://github.com/$(OPENBOX_REPO)
  DEPENDS:=+kmod-tun +kmod-nft-queue +kmod-nft-nat +kmod-veth \
	+ip-full +ca-bundle +curl +luci-base +rpcd
endef

define Package/open-box/description
 Open-Box 一体化透明代理，浏览器面板（默认端口 3036）管理，LuCI 服务菜单里也有入口。
 依赖按内核能力而非包名挑：TUN 设备、nftables queue/nat、veth、ip-full（RTNL 建命名空间）、
 ca-bundle（HTTPS 下载规则库）、curl（面板抓订阅时 Node 侧被拒的兜底通道）。
endef

# 发布包里的可执行文件是 aarch64 / x86_64 的预编译产物，装错架构的镜像能刷进去但起不来，
# 所以在解包前就报错，别等开机才发现。
define Build/Prepare
	@test -n "$(OPENBOX_ASSET)" || { \
		echo "*** open-box: 上游只提供 aarch64 / x86_64 预编译包，当前 ARCH=$(ARCH) ***"; \
		exit 1; }
	mkdir -p $(PKG_BUILD_DIR)
	$(PKG_UNPACK)
endef

# 预编译包，没有编译步骤。
define Build/Compile
endef

# 落点对齐上游 scripts/install.sh（连线细节见下面各组注释），不自己发明路径：
# 面板服务硬编码 /opt/open-box，改路径等于改上游代码。
define Package/open-box/install
	$(INSTALL_DIR) $(1)/opt/open-box
	$(CP) $(PKG_BUILD_DIR)/bin $(1)/opt/open-box/
	$(CP) $(PKG_BUILD_DIR)/node $(1)/opt/open-box/
	$(CP) $(PKG_BUILD_DIR)/panel $(1)/opt/open-box/
	$(CP) $(PKG_BUILD_DIR)/openwrt $(1)/opt/open-box/
	$(CP) $(PKG_BUILD_DIR)/debian $(1)/opt/open-box/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/meta.json $(1)/opt/open-box/meta.json
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/LICENSE $(1)/opt/open-box/LICENSE
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/COPYRIGHT.md $(1)/opt/open-box/COPYRIGHT.md
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/update.sh $(1)/opt/open-box/update.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/uninstall.sh $(1)/opt/open-box/uninstall.sh

	$(INSTALL_DIR) $(1)/opt/open-box/data
	$(INSTALL_DATA) ./files/panel-port $(1)/opt/open-box/data/panel-port

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/openwrt/initd/openbox-panel $(1)/etc/init.d/openbox-panel
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/openwrt/initd/openbox $(1)/etc/init.d/openbox

	$(INSTALL_DIR) $(1)/etc/rc.d
	$(LN) ../init.d/openbox-panel $(1)/etc/rc.d/S98openbox-panel

	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/openbox
	$(INSTALL_DATA) \
		$(PKG_BUILD_DIR)/openwrt/luci/htdocs/luci-static/resources/view/openbox/main.js \
		$(1)/www/luci-static/resources/view/openbox/main.js
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) \
		$(PKG_BUILD_DIR)/openwrt/luci/root/usr/share/luci/menu.d/luci-app-openbox.json \
		$(1)/usr/share/luci/menu.d/luci-app-openbox.json
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) \
		$(PKG_BUILD_DIR)/openwrt/luci/root/usr/share/rpcd/acl.d/luci-app-openbox.json \
		$(1)/usr/share/rpcd/acl.d/luci-app-openbox.json

	$(INSTALL_DIR) $(1)/usr/bin
	$(LN) /opt/open-box/openwrt/bin/open-box $(1)/usr/bin/open-box
endef

$(eval $(call BuildPackage,open-box))
