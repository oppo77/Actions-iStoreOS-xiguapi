#!/bin/bash
set -euo pipefail
# 适配GitHub Actions工作流的Xiguapi V3设备适配脚本
# 工作流中已export OPENWRT_ROOT=${WORKDIR}/openwrt（即${GITHUB_WORKSPACE}/workdir/openwrt）
# 脚本位置：${GITHUB_WORKSPACE}/xiguapi/xiguapi-v3-adapt.sh

# ====================== 1. 检查环境变量（工作流必须导出OPENWRT_ROOT） ======================
if [ -z "${OPENWRT_ROOT:-}" ]; then
    echo "❌ 错误：未设置OPENWRT_ROOT环境变量！"
    echo "请在执行脚本前执行：export OPENWRT_ROOT=<iStoreOS源码根目录>"
    exit 1
fi

if [ ! -d "${OPENWRT_ROOT}" ]; then
    echo "❌ 错误：OPENWRT_ROOT=${OPENWRT_ROOT} 目录不存在！"
    exit 1
fi

# ====================== 2. 定义路径常量（适配工作流目录结构） ======================
# 源文件目录（工作流中：脚本和dts/defconfig/dtsi都在${GITHUB_WORKSPACE}/xiguapi/）
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 目标文件路径（基于OPENWRT_ROOT，对应iStoreOS源码内的真实路径）
UBOOT_MK="${OPENWRT_ROOT}/package/boot/uboot-rockchip/Makefile"
ARMv8_MK="${OPENWRT_ROOT}/target/linux/rockchip/image/armv8.mk"
DTS_DEST="${OPENWRT_ROOT}/target/linux/rockchip/dts/rk3568/rk3568-xiguapi-v3.dts"
DEFCONFIG_DEST="${OPENWRT_ROOT}/package/boot/uboot-rockchip/src/configs/rk3568-xiguapi-v3_defconfig"
UBOOT_DTSI_DEST="${OPENWRT_ROOT}/package/boot/uboot-rockchip/src/arch/arm/dts/rk3568-xiguapi-v3-u-boot.dtsi"

# ====================== 3. 辅助函数：检查文件是否存在 ======================
check_file() {
    local file_path="$1"
    local desc="$2"
    if [ ! -f "$file_path" ]; then
        echo "❌ 错误：${desc} 文件不存在 -> ${file_path}"
        exit 1
    fi
}

# ====================== 4. 检查核心文件（源文件+目标源码文件） ======================
echo -e "\n【1/5】检查核心文件..."
# 检查源文件（dts/defconfig/dtsi）
check_file "${SRC_DIR}/rk3568-xiguapi-v3.dts" "Xiguapi V3设备树"
check_file "${SRC_DIR}/rk3568-xiguapi-v3_defconfig" "U-Boot配置"
check_file "${SRC_DIR}/rk3568-xiguapi-v3-u-boot.dtsi" "U-Boot设备树片段"
# 检查目标源码文件（确保iStoreOS源码完整）
check_file "${UBOOT_MK}" "uboot-rockchip Makefile"
check_file "${ARMv8_MK}" "rockchip armv8.mk"
echo -e "✅ 核心文件检查通过"

# ====================== 5. 修改uboot-rockchip/Makefile ======================
echo -e "\n【2/5】修改 ${UBOOT_MK}..."

# 5.1 插入U-Boot/nlnet_xiguapi-v3定义块（避免重复插入）
if ! grep -q "U-Boot/nlnet_xiguapi-v3" "${UBOOT_MK}"; then
    cat >> "${UBOOT_MK}" << 'EOF'

define U-Boot/nlnet_xiguapi-v3
	$(U-Boot/rk3568/Default)
	NAME:=Xiguapi V3
	BUILD_DEVICES := \
		nlnet_xiguapi-v3
endef
EOF
    echo -e "✅ 已添加U-Boot/nlnet_xiguapi-v3定义块"
else
    echo -e "⚠️ U-Boot/nlnet_xiguapi-v3定义块已存在，跳过"
fi

# 5.2 在easepi-rk3588 \前一行添加 rk3568-xiguapi-v3 \（严格匹配空格）
if ! grep -q "rk3568-xiguapi-v3 \\" "${UBOOT_MK}"; then
    sed -i '/easepi-rk3588 \\/i \ \ rk3568-xiguapi-v3 \\' "${UBOOT_MK}"
    echo -e "✅ 已在easepi-rk3588前添加rk3568-xiguapi-v3列表项"
else
    echo -e "⚠️ rk3568-xiguapi-v3列表项已存在，跳过"
fi

# ====================== 6. 修改armv8.mk（添加设备定义） ======================
echo -e "\n【3/5】修改 ${ARMv8_MK}..."

# 在include legacy.mk前插入Device定义（避免重复插入）
if ! grep -q "Device/nlnet_xiguapi-v3" "${ARMv8_MK}"; then
    sed -i '/^include legacy.mk/i \
define Device/nlnet_xiguapi-v3
  DEVICE_VENDOR := NLNET
  DEVICE_MODEL := Xiguapi V3
  SOC := rk3568
  DEVICE_DTS_DIR := ../dts/rk3568
  DEVICE_DTS := rk3568-xiguapi-v3
  UBOOT_DEVICE_NAME := rk3568-xiguapi-v3
  KERNEL_LOADADDR := 0x04000000
  BOOT_SCRIPT := rockchip
  DEVICE_PACKAGES := kmod-r8169
endef
TARGET_DEVICES += nlnet_xiguapi-v3
' "${ARMv8_MK}"
    echo -e "✅ 已添加Device/nlnet_xiguapi-v3设备定义"
else
    echo -e "⚠️ Device/nlnet_xiguapi-v3设备定义已存在，跳过"
fi

# ====================== 7. 复制DTS/Defconfig/U-Boot.dtsi文件 ======================
echo -e "\n【4/5】部署设备树/UBOOT配置文件..."

# 7.1 复制rk3568-xiguapi-v3.dts
mkdir -p "$(dirname "${DTS_DEST}")"
cp -f "${SRC_DIR}/rk3568-xiguapi-v3.dts" "${DTS_DEST}"
echo -e "✅ 已复制设备树文件 -> ${DTS_DEST}"

# 7.2 复制rk3568-xiguapi-v3_defconfig
mkdir -p "$(dirname "${DEFCONFIG_DEST}")"
cp -f "${SRC_DIR}/rk3568-xiguapi-v3_defconfig" "${DEFCONFIG_DEST}"
echo -e "✅ 已复制U-Boot配置 -> ${DEFCONFIG_DEST}"

# 7.3 复制rk3568-xiguapi-v3-u-boot.dtsi
mkdir -p "$(dirname "${UBOOT_DTSI_DEST}")"
cp -f "${SRC_DIR}/rk3568-xiguapi-v3-u-boot.dtsi" "${UBOOT_DTSI_DEST}"
echo -e "✅ 已复制U-Boot设备树片段 -> ${UBOOT_DTSI_DEST}"

# ====================== 8. 验证修改结果 ======================
echo -e "\n【5/5】验证修改结果..."
local verify_pass=0
# 验证uboot Makefile
if grep -q "rk3568-xiguapi-v3 \\" "${UBOOT_MK}" && grep -q "U-Boot/nlnet_xiguapi-v3" "${UBOOT_MK}"; then
    echo -e "✅ UBOOT Makefile修改验证通过"
else
    echo -e "❌ UBOOT Makefile修改验证失败"
    verify_pass=1
fi
# 验证armv8.mk
if grep -q "Device/nlnet_xiguapi-v3" "${ARMv8_MK}" && grep -q "nlnet_xiguapi-v3" "${ARMv8_MK}"; then
    echo -e "✅ armv8.mk修改验证通过"
else
    echo -e "❌ armv8.mk修改验证失败"
    verify_pass=1
fi
# 验证文件复制
if [ -f "${DTS_DEST}" ] && [ -f "${DEFCONFIG_DEST}" ] && [ -f "${UBOOT_DTSI_DEST}" ]; then
    echo -e "✅ 设备树/UBOOT文件复制验证通过"
else
    echo -e "❌ 设备树/UBOOT文件复制验证失败"
    verify_pass=1
fi

# ====================== 9. 完成提示 ======================
if [ ${verify_pass} -eq 0 ]; then
    echo -e "\n🎉 所有适配操作完成！"
    echo -e "📌 关键信息："
    echo -e "  - OPENWRT源码根目录：${OPENWRT_ROOT}"
    echo -e "  - 设备名称：nlnet_xiguapi-v3"
    echo -e "  - 编译时需选择：Target System → Rockchip → ARMv8 → NLNET Xiguapi V3"
    echo -e "  - 已自动添加r8169驱动（适配RTL8211F网口）"
else
    echo -e "\n❌ 适配操作验证失败，请检查上述错误！"
    exit 1
fi

exit 0
