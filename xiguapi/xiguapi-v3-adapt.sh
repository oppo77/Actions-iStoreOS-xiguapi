#!/bin/bash
set -euo pipefail
# 适配GitHub Actions工作流的Xiguapi V3设备适配脚本（最终修复版）
# 工作流中已export OPENWRT_ROOT=${WORKDIR}/openwrt

# ====================== 1. 检查环境变量 ======================
if [ -z "${OPENWRT_ROOT:-}" ]; then
    echo "❌ 错误：未设置OPENWRT_ROOT环境变量！"
    exit 1
fi
if [ ! -d "${OPENWRT_ROOT}" ]; then
    echo "❌ 错误：OPENWRT_ROOT=${OPENWRT_ROOT} 目录不存在！"
    exit 1
fi

# ====================== 2. 定义路径常量 ======================
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UBOOT_MK="${OPENWRT_ROOT}/package/boot/uboot-rockchip/Makefile"
ARMv8_MK="${OPENWRT_ROOT}/target/linux/rockchip/image/armv8.mk"
DTS_DEST="${OPENWRT_ROOT}/target/linux/rockchip/dts/rk3568/rk3568-xiguapi-v3.dts"
DEFCONFIG_DEST="${OPENWRT_ROOT}/package/boot/uboot-rockchip/src/configs/rk3568-xiguapi-v3_defconfig"
UBOOT_DTSI_DEST="${OPENWRT_ROOT}/package/boot/uboot-rockchip/src/arch/arm/dts/rk3568/rk3568-xiguapi-v3-u-boot.dtsi"

# ====================== 3. 辅助函数 ======================
check_file() {
    local file_path="$1"
    local desc="$2"
    if [ ! -f "$file_path" ]; then
        echo "❌ 错误：${desc} 文件不存在 -> ${file_path}"
        exit 1
    fi
}

# 安全检查字符串是否存在（避免反斜杠报错）
safe_grep() {
    local pattern="$1"
    local file="$2"
    # 用fgrep（固定字符串匹配）替代grep，避免正则转义问题
    fgrep -q -F "${pattern}" "${file}" 2>/dev/null
}

# ====================== 4. 检查核心文件 ======================
echo -e "\n【1/5】检查核心文件..."
check_file "${SRC_DIR}/rk3568-xiguapi-v3.dts" "Xiguapi V3设备树"
check_file "${SRC_DIR}/rk3568-xiguapi-v3_defconfig" "U-Boot配置"
check_file "${SRC_DIR}/rk3568-xiguapi-v3-u-boot.dtsi" "U-Boot设备树片段"
check_file "${UBOOT_MK}" "uboot-rockchip Makefile"
check_file "${ARMv8_MK}" "rockchip armv8.mk"
echo -e "✅ 核心文件检查通过"

# ====================== 5. 修改uboot-rockchip/Makefile ======================
echo -e "\n【2/5】修改 ${UBOOT_MK}..."

# 5.1 插入U-Boot定义块
if ! safe_grep "U-Boot/nlnet_xiguapi-v3" "${UBOOT_MK}"; then
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

# 5.2 在easepi-rk3588 \前添加 rk3568-xiguapi-v3 \（修复local+grep/sed语法）
target_line="  rk3568-xiguapi-v3 \\"  # 移除local，改为全局变量
if ! safe_grep "${target_line}" "${UBOOT_MK}"; then
    # 改用换行符转义的sed语法，兼容Ubuntu 22.04
    sed -i '/easepi-rk3588 \\/i \  rk3568-xiguapi-v3 \\' "${UBOOT_MK}"
    echo -e "✅ 已在easepi-rk3588前添加rk3568-xiguapi-v3列表项"
else
    echo -e "⚠️ rk3568-xiguapi-v3列表项已存在，跳过"
fi

# ====================== 6. 修改armv8.mk（修复sed多行插入语法） ======================
echo -e "\n【3/5】修改 ${ARMv8_MK}..."

if ! safe_grep "Device/nlnet_xiguapi-v3" "${ARMv8_MK}"; then
    # 方案：先创建临时文件，再用cat插入（避免sed多行语法错误）
    TMP_FILE=$(mktemp)
    cat > "${TMP_FILE}" << 'EOF'
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
EOF
    # 用sed插入临时文件内容到include legacy.mk前
    sed -i "/^include legacy.mk/e cat ${TMP_FILE}" "${ARMv8_MK}"
    rm -f "${TMP_FILE}"
    echo -e "✅ 已添加Device/nlnet_xiguapi-v3设备定义"
else
    echo -e "⚠️ Device/nlnet_xiguapi-v3设备定义已存在，跳过"
fi

# ====================== 7. 复制文件 ======================
echo -e "\n【4/5】部署设备树/UBOOT文件..."

mkdir -p "$(dirname "${DTS_DEST}")"
cp -f "${SRC_DIR}/rk3568-xiguapi-v3.dts" "${DTS_DEST}"
echo -e "✅ 已复制设备树文件 -> ${DTS_DEST}"

mkdir -p "$(dirname "${DEFCONFIG_DEST}")"
cp -f "${SRC_DIR}/rk3568-xiguapi-v3_defconfig" "${DEFCONFIG_DEST}"
echo -e "✅ 已复制U-Boot配置 -> ${DEFCONFIG_DEST}"

mkdir -p "$(dirname "${UBOOT_DTSI_DEST}")"
cp -f "${SRC_DIR}/rk3568-xiguapi-v3-u-boot.dtsi" "${UBOOT_DTSI_DEST}"
echo -e "✅ 已复制U-Boot设备树片段 -> ${UBOOT_DTSI_DEST}"

# ====================== 8. 验证 ======================
echo -e "\n【5/5】验证修改结果..."
verify_pass=0  # 移除local，改为全局变量
if safe_grep "rk3568-xiguapi-v3 \\" "${UBOOT_MK}" && safe_grep "U-Boot/nlnet_xiguapi-v3" "${UBOOT_MK}"; then
    echo -e "✅ UBOOT Makefile修改验证通过"
else
    echo -e "❌ UBOOT Makefile修改验证失败"
    verify_pass=1
fi
if safe_grep "Device/nlnet_xiguapi-v3" "${ARMv8_MK}" && safe_grep "nlnet_xiguapi-v3" "${ARMv8_MK}"; then
    echo -e "✅ armv8.mk修改验证通过"
else
    echo -e "❌ armv8.mk修改验证失败"
    verify_pass=1
fi
if [ -f "${DTS_DEST}" ] && [ -f "${DEFCONFIG_DEST}" ] && [ -f "${UBOOT_DTSI_DEST}" ]; then
    echo -e "✅ 设备树/UBOOT文件复制验证通过"
else
    echo -e "❌ 设备树/UBOOT文件复制验证失败"
    verify_pass=1
fi

# ====================== 9. 完成提示 ======================
if [ ${verify_pass} -eq 0 ]; then
    echo -e "\n🎉 所有适配操作完成！"
else
    echo -e "\n❌ 适配操作验证失败，请检查上述错误！"
    exit 1
fi

exit 0
