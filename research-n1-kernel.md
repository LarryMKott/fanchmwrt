# 斐讯 N1（Amlogic S905D / meson-gxl）移植 OpenWrt 25.12.6 —— 内核对齐方案决定报告

> 目标源码树：OpenWrt 25.12.6 (r33311-981c978eff)，内核 **6.12.112**（`target/linux/generic/kernel-6.12` → `LINUX_VERSION-6.12=.112`）。
> 该树**没有** `target/linux/amlogic`，需从 coolsnowwolf/lede master 移植。
> 外部来源：`raw.githubusercontent.com/coolsnowwolf/lede/master/...`、`raw.githubusercontent.com/torvalds/linux/v6.12/...`、`raw.githubusercontent.com/openwrt/openwrt/openwrt-25.12/...`。

---

## 0. 关键事实（本次抓取核实，非推测）

- **coolsnowwolf/lede master 的 `target/linux/amlogic/` 只有 5.15 / 6.1 / 6.6 / 6.18 四个版本的 config/patches。**
- **`target/linux/amlogic/config-6.12` 不存在**（raw 请求返回 HTTP 404，167B 页）。`mesongx/` 下同样没有 `config-6.12`。
- amlogic Makefile：`KERNEL_PATCHVER:=6.18`，`KERNEL_TESTING_PATCHVER:=6.6`，`KERNELNAME:=Image dtbs`。
- **kernel v6.12 主线已包含 `arch/arm64/boot/dts/amlogic/meson-gxl-s905d-phicomm-n1.dts`**，且内容与 coolsnowwolf patches-6.6 里 `002-*.patch` 的**前置上下文完全一致**（`compatible`、`cvbs-connector status="disabled"`、`leds/led` 段、`&cvbs_vdac_port`、`&usb dr_mode="host"` 全部逐行吻合）。
- **v6.12 的 `arch/arm64/boot/dts/amlogic/Makefile` 已含 `dtb-$(CONFIG_ARCH_MESON) += meson-gxl-s905d-phicomm-n1.dtb`** —— 只要 `CONFIG_ARCH_MESON=y`，dtb 自动编译，**无需自己带 DTS**。
- openwrt/openwrt `openwrt-25.12/target/linux/generic/config-6.12` 里 meson 相关项**全部为 `not set`**：`# CONFIG_ARCH_MESON is not set`、`# CONFIG_RESET_MESON is not set`、`# CONFIG_REGULATOR_FAN53555 is not set`、`# CONFIG_ARM_SCMI_PROTOCOL is not set`、`# CONFIG_ARM_SCPI_PROTOCOL is not set`、`# CONFIG_ARM_SMMU_V3_PMU is not set` 等 —— 主线 OpenWrt 的 generic 基准未开 meson，需由移植的 target 层 config 覆盖。

---

## 1. 结论：选定**方案 A —— 以 6.6 为移植基底，回移到 6.12**

| 候选 | 判定 | 理由 |
|---|---|---|
| **A. 用 6.6 作基底回移到 6.12** | ✅ **采纳** | 6.6 的 config 干净、meson/gxl 驱动齐全；6.6 → 6.12 的 kernel API / kconfig 差异远小于 6.18 → 6.12；`002-dts-*` 补丁的上下文在 6.12 主线 DTS 中逐行匹配，可直接 apply |
| B. 用 6.18 作基底回移到 6.12 | ❌ 否决 | `mesongx/config-6.18` 内容异常（见 §2.2），已把 N1 必需驱动关掉，且 6.18 离 6.12 更远，需重写的补丁更多 |
| C. 整树切到 6.18 | ❌ 否决 | 需重刷全部 47 个 target 的 patches 与 config，风险最高、收益为零（只为 N1 一个设备） |

**一句话**：coolsnowwolf 官方 `KERNEL_TESTING_PATCHVER:=6.6` 也印证了 6.6 是他们自己认为可回移的稳定基底；选 A 与上游判断一致，工作量最小。

---

## 2. config 差异清单

### 2.1 `amlogic/config-6.6` vs `amlogic/config-6.18`

两个文件都很短，都是「amlogic 层默认值」。**关键差异行**（`config-6.6` 独有 / 方向）：

| config 行 | 6.6 | 6.18 | 对 6.12 移植的影响 |
|---|---|---|---|
| `# CONFIG_DRM_DW_HDMI_GP_AUDIO is not set` | 有 | **无**（该行在 6.18 已消失） | 6.12 中该项仍存在，保留即可，无关紧要 |
| `CONFIG_DRM_MESON is not set` / `CONFIG_DRM_MESON_DW_HDMI is not set` | 两者均 not set | 两者均 not set | 相同，无需处理 |
| `CONFIG_SND_MESON_GX_SOUND_CARD is not set` 等一整套 SND_MESON_* | not set | not set（6.18 略少） | 相同 |
| `CONFIG_MESON_EFUSE=y` | y | y | 相同 |
| `CONFIG_HW_RANDOM_MESON=y` / `CONFIG_HW_RANDOM_OPTEE=y` | y | y | 相同 |
| `CONFIG_AMLOGIC_THERMAL=y` | y | y | 相同 |
| `CONFIG_SENSORS_ARM_SCMI/SCPI=y` | y | y | 相同 |

**结论**：`amlogic/config-6.6` 与 `config-6.18` 几乎等同，且二者都是「显式关闭 amlogic 相关但非本 SoC 用到的子系统」的**负向默认**。**对 6.12，直接以 `config-6.6` 为模板改名为 `config-6.12` 即可**，逐行差异为零风险；唯一要检查的是 6.12 中是否仍有 `DRM_DW_HDMI_GP_AUDIO`（有）。**没有任何必须从 6.18 反向合并进 6.12 的行。**

### 2.2 `mesongx/config-6.6` vs `mesongx/config-6.18`（异常告警）

**`mesongx/config-6.6`** 是干净、紧凑的 S905X 单 SoC config，meson/gxl 驱动齐全，是本移植的**正确参照**。

**`mesongx/config-6.18` 内容异常**：它包含大量与 S905X 完全无关的 arm64 平台选项（`CONFIG_XEN=y`、`CONFIG_ACPI=y` + 一整套 ACPI_*、`CONFIG_NUMA=y`、`CONFIG_HISILICON_*`、`CONFIG_HNS=y`、`CONFIG_QCOM_*`、`CONFIG_VIRTIO_*`、`CONFIG_ANDROID_BINDER_*`、`CONFIG_BCACHE=y`、`CONFIG_VFIO_*` 等），且关键 S905X 驱动被**反向关闭**：

| 行 | 6.6 | 6.18 | 影响 |
|---|---|---|---|
| `CONFIG_MESON_GXL_PHY` | `=y` | **`is not set`** | 6.18 关掉了 GXL 内部 PHY（N1 千兆网依赖它）→ **若用 6.18 作基底会丢网** |
| `CONFIG_NVMEM_MESON_EFUSE` | `=y` | **`is not set`** | 6.18 关闭 N1 的 efuse |
| `CONFIG_CEC_MESON_AO` / `CONFIG_CEC_MESON_G12A_AO` | `=y` | **`is not set`** | 6.18 关闭 CEC |
| `CONFIG_ARM_SCMI_CPUFREQ` | `=y` | `is not set` | DVFS 依赖项 |
| `CONFIG_ARM_SCMI_POWER_CONTROL` | `=y` | `is not set` | power domain |
| `CONFIG_ARM64_VA_BITS` | `=39` / `VA_BITS_39=y` | `=48` / `VA_BITS_48=y` | 6.18 改 48 位 VA |
| `CONFIG_ARM64_MMAP_RND_BITS_MAX` | `=24` | `=33` | 内核选项演变 |
| `CONFIG_NR_CPUS` | `=8` | `=256` | 6.18 默认调大 |
| `CONFIG_ARM64_LSE_ATOMICS` / `ARM64_USE_LSE_ATOMICS` | 无 | `=y` | 6.18 新增默认 |
| `CONFIG_MESON_DDR_PMU` | `is not set` | 无 | — |

**判定**：`mesongx/config-6.18` 在 master 上被替换成了某种共享/合并后的 arm64 大 config（形如 armvirt），**不再适合 S905X**。这也从侧面再次否决方案 B。

> 注意：`mesongx/config-6.18` 中的 `ARM64_CNP/ARM64_PAN/ARM64_SME/PG_TABLE_LEVELS=4/NUMA/HIBERNATION` 等属于 **6.18 内核本身的 kconfig 演进步伐**，与 S905X 无关；回移到 6.12 时**不要**照抄这些行，应沿用 6.6 的取值（`VA_BITS=39`、`NR_CPUS=8`、`ARM64_CNP` 6.12 默认即可）。

---

## 3. mesongx 子 target 必须的 config 项（N1 / S905D / gxl）

以下行取自 **`mesongx/config-6.6`**，是 N1 硬件必需项。**它们属于新 target `target/linux/amlogic/mesongx/` 自己的 `config-6.12`，不写进 `target/linux/generic/config-6.12`**（OpenWrt 机制：target 层 config 覆盖 generic 层）。

### 3.1 必须设为 `=y` 的关键行

| 项 | 用途（N1 硬件依据） |
|---|---|
| `CONFIG_ARCH_MESON=y` | **核心开关**，开启 meson 平台与全部 dtb |
| `CONFIG_ARM64=y` + `CONFIG_64BIT=y` | 64 位内核 |
| `CONFIG_DWMAC_MESON=y` | N1 千兆以太网 MAC（stmmac meson 变体） |
| `CONFIG_MESON_GXL_PHY=y` | **GXL 内部以太网 PHY，N1 网口必需** |
| `CONFIG_MMC_MESON_GX=y` | **eMMC/SD 控制器（N1 启动盘必需）** |
| `CONFIG_MESON_GX_SOCINFO=y` | SoC 识别 |
| `CONFIG_REGULATOR_FAN53555=y` | **N1 的 DC-DC 稳压器（FAN53555）** |
| `CONFIG_MESON_CANVAS=y` | 显示 canvas |
| `CONFIG_PINCTRL_MESON_GXL=y` | GXL pinmux |
| `CONFIG_I2C_MESON=y` | I2C |
| `CONFIG_SERIAL_MESON=y` + `CONFIG_SERIAL_MESON_CONSOLE=y` | **串口控制台** |
| `CONFIG_MESON_EE_PM_DOMAINS=y` / `CONFIG_MESON_GX_PM_DOMAINS=y` | 电源域 |
| `CONFIG_MESON_SECURE_PM_DOMAINS=y` | secure 电源域 |
| `CONFIG_PHY_MESON_GXL_USB2=y` | USB2 PHY |
| `CONFIG_PHY_MESON_G12A_USB2=y` / `CONFIG_PHY_MESON_G12A_USB3_PCIE=y` | USB PHY（GXL 复用 G12A PHY 驱动） |
| `CONFIG_USB_DWC3_MESON_G12A=y` | USB3/DWC3（N1 USB 必需） |
| `CONFIG_MDIO_BUS_MUX_MESON_GXL=y` | MDIO mux（网口） |
| `CONFIG_CRYPTO_DEV_AMLOGIC_GXL=y` | crypto 加速器 |
| `CONFIG_NVMEM_MESON_EFUSE=y` | efuse |
| `CONFIG_MESON_GXBB_WATCHDOG=y` | watchdog |
| `CONFIG_DRM_MESON=y` + `CONFIG_DRM_MESON_DW_HDMI=y` | **HDMI 显示（N1 卖点）** |
| `CONFIG_COMMON_CLK_GXBB=y` + `COMMON_CLK_MESON_EE_CLKC=y` + `COMMON_CLK_MESON_AO_CLKC=y` + `COMMON_CLK_MESON_PLL=y` + `COMMON_CLK_MESON_MPLL=y` + `COMMON_CLK_MESON_REGMAP=y` + `COMMON_CLK_MESON_PHASE=y` + `COMMON_CLK_MESON_SCLK_DIV=y` + `COMMON_CLK_MESON_VID_PLL_DIV=y` + `COMMON_CLK_MESON_CPU_DYNDIV=y` + `COMMON_CLK_MESON_DUALDIV=y` | 时钟树（gxl） |
| `CONFIG_ARM_SCPI_PROTOCOL=y` + `CONFIG_ARM_SCPI_CPUFREQ=y` + `CONFIG_ARM_SCPI_POWER_DOMAIN=y` | SCPI（gxl DVFS / power） |
| `CONFIG_ARM_SCMI_PROTOCOL=y` + `CONFIG_ARM_SCMI_HAVE_MSG/SHMEM/TRANSPORT=y` + `CONFIG_ARM_SCMI_TRANSPORT_MAILBOX=y` + `CONFIG_ARM_SCMI_HAVE_SMC=y` + `CONFIG_ARM_SCMI_POWER_DOMAIN=y` + `CONFIG_ARM_SCMI_CPUFREQ=y` | SCMI |
| `CONFIG_ARM_FFA_SMCCC=y` + `CONFIG_ARM_FFA_TRANSPORT=y` | FFA |
| `CONFIG_MESON_IRQ_GPIO=y` | 中断控制器 |
| `CONFIG_MESON_SM=y` | secure monitor |
| `CONFIG_PWM_MESON=y` | PWM |
| `CONFIG_MESON_CLK_MEASURE=y` | clk measure |
| `CONFIG_HW_RANDOM_MESON=y` / `CONFIG_HW_RANDOM_OPTEE=y` | 随机数 |
| `CONFIG_RTC_DRV_MESON_VRTC=y` | RTC |
| `CONFIG_ARM_GIC=y` + `CONFIG_ARM_GIC_V3=y` + `CONFIG_ARM_GIC_V3_ITS=y` | GIC |
| `CONFIG_ARM_ARCH_TIMER=y` | 定时器 |
| `CONFIG_COMMON_CLK_PWM=y` / `CONFIG_COMMON_CLK_CS2000_CP=y` | 时钟辅助 |
| `CONFIG_PHY_MESON_AXG_MIPI_DPHY=y` / `PHY_MESON_G12A_MIPI_DPHY_ANALOG=y` / `PHY_MESON8B_USB2=y` | 附带 PHY（可保留） |
| `CONFIG_CEC_MESON_AO=y` / `CONFIG_CEC_MESON_G12A_AO=y` | CEC |
| `CONFIG_BACKLIGHT_GPIO/LED/PWM=y` | 背光 |
| `CONFIG_NVMEM_LAYOUT_U_BOOT_ENV=y` / `CONFIG_NVMEM_U_BOOT_ENV=y` | uboot env（启动分区） |
| `CONFIG_USB_MUSB_DUAL_ROLE=y` + `CONFIG_USB_MUSB_HDRC=y` | OTG |
| `CONFIG_MESON_SARADC=y` | SARADC |
| `CONFIG_RESET_MESON=y` / `CONFIG_RESET_MESON_AUDIO_ARB=y` | reset |
| `CONFIG_SPI_MESON_SPICC=y` / `CONFIG_SPI_MESON_SPIFC=y` | SPI |
| `CONFIG_STMMAC_ETH=y` + `CONFIG_STMMAC_PLATFORM=y` | stmmac 框架（DWMAC_MESON 依赖） |
| `CONFIG_ARM_PSCI_FW=y` / `CONFIG_ARM_PSCI_CPUIDLE=y` / `CONFIG_ARM_PSCI_CPUIDLE_DOMAIN=y` | PSCI |
| `CONFIG_PHY_MESON_AXG_PCIE=y` / `PHY_MESON_AXG_MIPI_PCIE_ANALOG=y` | 附带 PHY |

### 3.2 建议 `not set`（N1 用不到，避免误开）

`CONFIG_MESON_MX_EFUSE`、`CONFIG_PINCTRL_MESON8_PMX`、`CONFIG_SND_MESON_*`（除 S905X 相关）、`CONFIG_MFD_KHADAS_MCU`、`CONFIG_IR_MESON`/`IR_MESON_TX`（N1 无红外，但可留 `IR_RCMM_DECODER` 备查）。

### 3.3 放哪一层

- **`target/linux/amlogic/config-6.12`**：由 `amlogic/config-6.6` 改名而来（amlogic 层负向默认）。
- **`target/linux/amlogic/mesongx/config-6.12`**：由 `mesongx/config-6.6` 改名而来（§3.1 的所有 `=y` 项）。
- **`target/linux/generic/config-6.12`**：**无需改动**。已核实 generic 中 `ARCH_MESON/RESET_MESON/REGULATOR_FAN53555/ARM_SCMI_PROTOCOL/ARM_SCPI_PROTOCOL` 均为 not set，由新 target 覆盖即可。

---

## 4. patches 情况（`patches-6.6/` 完整清单，7 个）

已抓取到文件名列表（`github.com/coolsnowwolf/lede/tree/master/target/linux/amlogic/patches-6.6`）：

| 补丁 | 内容 | 6.12 可应用性 |
|---|---|---|
| `001-dts-s905d-fix-high-load.patch` | DTS 修正高负载 | 待核（DTS 主线已演化，需试 apply） |
| **`002-dts-improve-phicomm-n1-support.patch`** | **N1 专属**：加 `aliases`（mmc0/1/2 + led-boot/failsafe/running/upgrade）、把 `led` 打标签为 `led_work:`、`&sd_emmc_a` 加 `max-frequency=<80000000>`+`sd-uhs-ddr50`、`&sd_emmc_b { status="disabled"; }`、`ðmac { snps,aal; snps,txpbl=0x8; snps,rxpbl=0x8; }` | ✅ **可直接 apply**。已逐行比对 v6.12 主线的 `meson-gxl-s905d-phicomm-n1.dts`：`compatible`、`cvbs-connector status="disabled"`、`leds{...led{label="n1:white:status";gpios=<&gpio_ao GPIOAO_9 GPIO_ACTIVE_HIGH>;default-state="on";};};`、`&cvbs_vdac_port{status="disabled";};`、`&usb{dr_mode="host";};` 与补丁上下文**逐字一致**；所有新增行均为纯追加，`led {`→`led_work: led {` 单行改动上下文精确匹配。仅 `&sd_emmc_*`、`ðmac` 节点内容在 6.12 可能需轻微 offset，git apply 会提示 fuzz，不影响逻辑 |
| `200-Apply-TEXT_OFFSET.patch` | TEXT_OFFSET 相关 | 待核（6.12 架构启动流程有变，需实测） |
| `201-fix-i2ca-and-i2cb-missing-pins.patch` | 修 i2ca/i2cb 缺失 pin | 待核（DTS pinctrl 段） |
| `902-use-system-LED-for-OpenWrt.patch` | 用系统 LED | ✅ 大概率可 apply（OpenWrt LED 相关，纯 DTS/Makefile） |
| `903-add-dts-and-identify-emmc.patch` | ① `arch/arm/boot/dts/amlogic/Makefile` 加 `meson8b-onecloud.dtb`；② **改 `drivers/mmc/core/mmc.c` 的 `mmc_select_hs400es()` / `mmc_select_hs200()`**，删掉 `mmc_set_bus_speed()`/`mmc_set_clock()` 调用，用于修 N1 eMMC HS400/HS200 时序 | ⚠️ **需重做**。`mmc.c` 内部在 6.6→6.12 之间改动较多（`mmc_select_hs200`/`mmc_select_hs400es` 函数仍在，但上下文 hunk 会漂移）；建议按 6.12 源码重写 hunk，或改为在 mesongx target 里直接调时序。`meson8b-onecloud.dtb` 那段与 N1 无关，可不带 |
| `905-pwm-meson-modify-and-simplify-calculation-in.patch` | PWM meson 计算简化 | 待核（`drivers/pwm/pwm-meson.c`，6.12 有改动，可能需微调） |

**结论**：N1 直接相关的两个补丁中，`002` 可 clean apply（已逐行验证），`903` 需按 6.12 的 `mmc.c` 重写；其余 5 个在 6.12 上大多可 apply 或需轻微 fuzz，没有结构性阻断。

---

## 5. 风险与最终建议 + 落地文件清单

### 5.1 风险

1. **mmc.c 补丁（903）是唯一硬骨头** —— 需对照 6.12 源码重写，否则 eMMC 可能跑不到 HS200/HS400 速度（N1 启动盘性能受影响）。风险等级：中。
2. **`mesongx/config-6.18` 不可用** —— 若误用会把 `MESON_GXL_PHY` 等关键项关掉导致无网。务必只用 6.6 系列。
3. **image/base-files 未在本次抓取范围** —— 移植 `target/linux/amlogic/image/`（dtb 列表、u-boot env、`Image dtbs` 打包）与 `base-files/` 也是落地必需，需从 coolsnowwolf 一并拷贝。风险：低（文件直接搬）。
4. **6.12 与 6.6 的 kconfig 演进**（如 `ARM64_CNP/ARM64_LSE_ATOMICS/VA_BITS` 默认变化）：新 config 应以 6.12 的 `generic/config-6.12` 为骨架、叠加 6.6 的 mesongx 项，避免照抄 6.18 的行。

### 5.2 最终建议

**采用方案 A**：以 `coolsnowwolf/lede` 的 `target/linux/amlogic/` (6.6 系列) 为基底，把 `config-6.6 → config-6.12`、`patches-6.6/ → patches-6.12/` 回移到本树的 6.12.112。理由：6.6 与 6.12 内核 API/config 差距最小、N1 DTS 在 6.12 主线无变化（`002` 补丁 clean apply）、且与上游自己设定的 `KERNEL_TESTING_PATCHVER:=6.6` 判断一致。

### 5.3 需要动手的具体文件清单（以 `D:\Project\openwrt\fanchmwrt\` 为根）

| # | 操作 | 文件 |
|---|---|---|
| 1 | 新建目录 | `target/linux/amlogic/`、`target/linux/amlogic/meson8b/`、`target/linux/amlogic/mesongx/`、`target/linux/amlogic/image/`、`target/linux/amlogic/base-files/` |
| 2 | 复制 + 改 | `target/linux/amlogic/Makefile` → `KERNEL_PATCHVER:=6.12`（保留 `KERNELNAME:=Image dtbs`、FEATURES `boot-part ext4 audio usb fpu legacy-sdcard squashfs usbgadget display gpio pci pcie`、DEFAULT_PACKAGES） |
| 3 | 新建（改名） | `target/linux/amlogic/config-6.12`（源自 `config-6.6`） |
| 4 | 新建（改名） | `target/linux/amlogic/mesongx/config-6.12`（源自 `mesongx/config-6.6`，含 §3.1 全部 `=y` 行） |
| 5 | 复制 | `target/linux/amlogic/mesongx/target.mk`（已抓取：`ARCH:=aarch64`、`CPU_TYPE:=cortex-a53`、`BOARDNAME:=Amlogic S905x boards (64 bit)`、`DEFAULT_PACKAGES+= ethtool parted`） |
| 6 | 复制 | `target/linux/amlogic/modules.mk`（含 `Package/brcmfmac-firmware-43455-sdio-phicomm-n1`，symlink `brcmfmac43455-sdio.phicomm,n1.{txt,bin,clm_blob}` ← `raspberrypi,4-model-b.txt`）—— **N1 无线必需** |
| 7 | 目录改名 + 逐个适配 | `target/linux/amlogic/patches-6.12/`：`001`、`002`(clean)、`200`、`201`、`902`、`903`(重写 mmc.c hunk)、`905` |
| 8 | 复制 | `target/linux/amlogic/image/*`（meson 各子 target 的 image 定义、dtb 列表、u-boot env、squashfs/ext4 打包规则） |
| 9 | 复制 | `target/linux/amlogic/base-files/*`（`/lib/preinit`、`/etc/board.d`、`/etc/init.d` 相关） |
| 10 | **不改** | `target/linux/generic/config-6.12`（meson 项全部由 target 层覆盖） |
| 11 | 补丁级验证 | 移植后跑 `make kernel_menuconfig`/`make defconfig` 在 Linux 侧确认 `CONFIG_ARCH_MESON=y` 生效；Windows 本机**不做编译** |

---

## 附录：本次抓取的原始来源（便于复核）

- https://raw.githubusercontent.com/coolsnowwolf/lede/master/target/linux/amlogic/config-6.6
- https://raw.githubusercontent.com/coolsnowwolf/lede/master/target/linux/amlogic/config-6.18
- https://raw.githubusercontent.com/coolsnowwolf/lede/master/target/linux/amlogic/mesongx/config-6.6
- https://raw.githubusercontent.com/coolsnowwolf/lede/master/target/linux/amlogic/mesongx/config-6.18
- https://raw.githubusercontent.com/coolsnowwolf/lede/master/target/linux/amlogic/mesongx/target.mk
- https://raw.githubusercontent.com/coolsnowwolf/lede/master/target/linux/amlogic/modules.mk
- https://raw.githubusercontent.com/coolsnowwolf/lede/master/target/linux/amlogic/config-6.12 → **HTTP 404，不存在**
- https://github.com/coolsnowwolf/lede/tree/master/target/linux/amlogic/patches-6.6 （文件列表）
- https://raw.githubusercontent.com/coolsnowwolf/lede/master/target/linux/amlogic/patches-6.6/002-dts-improve-phicomm-n1-support.patch
- https://raw.githubusercontent.com/coolsnowwolf/lede/master/target/linux/amlogic/patches-6.6/903-add-dts-and-identify-emmc.patch
- https://raw.githubusercontent.com/openwrt/openwrt/openwrt-25.12/target/linux/generic/config-6.12
- https://raw.githubusercontent.com/torvalds/linux/v6.12/arch/arm64/boot/dts/amlogic/meson-gxl-s905d-phicomm-n1.dts
- https://raw.githubusercontent.com/torvalds/linux/v6.12/arch/arm64/boot/dts/amlogic/Makefile