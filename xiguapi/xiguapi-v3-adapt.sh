#!/bin/bash
set -euo pipefail
# Xiguapi V3 设备适配脚本（专注硬件适配，不修改配置）

# 1. 自动设置/检查 OPENWRT_ROOT 路径
OPENWRT_ROOT=${OPENWRT_ROOT:-$(pwd)/openwrt}
if [ ! -d "${OPENWRT_ROOT}" ]; then
    echo -e "\n❌ 错误：OPENWRT_ROOT=${OPENWRT_ROOT} 目录不存在！"
    echo -e "💡 提示：在 GitHub Actions 中已自动设置，本地执行请执行：export OPENWRT_ROOT=你的openwrt源码路径"
    exit 1
fi

# 2. 定义路径常量
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CUSTOM_CONFIG_DIR="${SRC_DIR}/custom"
echo -e "✅ 自动识别自定义配置目录：CUSTOM_CONFIG_DIR=${CUSTOM_CONFIG_DIR}"

# OpenWRT 源码内的目标路径
DTS_CHECK_PATH="${OPENWRT_ROOT}/target/linux/rockchip/dts/rk3568/rk3568-xiguapi-v3.dts"
UBOOT_MAKEFILE_CHECK_PATH="${OPENWRT_ROOT}/package/boot/uboot-rockchip/Makefile"
UBOOT_CONFIG_CHECK_PATH="${OPENWRT_ROOT}/package/boot/uboot-rockchip/src/configs/rk3568-xiguapi-v3_defconfig"
UBOOT_DTSI_CHECK_PATH="${OPENWRT_ROOT}/package/boot/uboot-rockchip/src/arch/arm/dts/rk3568-xiguapi-v3-u-boot.dtsi"

# 添加nlnet_xiguapi-v3
echo -e "\\ndefine Device/nlnet_xiguapi-v3
\$(call Device/Legacy/rk3568,\$(1))
  DEVICE_VENDOR := NLNET
  DEVICE_MODEL := Xiguapi V3
  DEVICE_DTS := rk3568/rk3568-xiguapi-v3
  DEVICE_PACKAGES += kmod-r8169
endef
TARGET_DEVICES += nlnet_xiguapi-v3 >> target/linux/rockchip/image/legacy.mk

# 3. 辅助函数
check_file() {
    local file_path="$1"
    local desc="$2"
    if [ ! -f "$file_path" ]; then
        echo -e "\n❌ 错误：${desc} 文件不存在 -> ${file_path}"
        echo -e "💡 提示：请确保 ${desc} 文件已放在 ${CUSTOM_CONFIG_DIR} 目录下的对应路径"
        exit 1
    fi
}

check_dir() {
    local dir_path="$1"
    local desc="$2"
    if [ ! -d "$dir_path" ]; then
        echo -e "\n❌ 错误：${desc} 目录不存在 -> ${dir_path}"
        echo -e "💡 提示：请确保 ${desc} 目录已放在 ${SRC_DIR} 目录下"
        exit 1
    fi
}

# 4. 清理残留的侵入式修改
echo -e "\n【1/4】清理可能的残留侵入式修改..."
cd "${OPENWRT_ROOT}"
# 清理可能的旧配置片段
sed -i '/define U-Boot\/xiguapi-v3-rk3568/,/endef/ d' "${UBOOT_MAKEFILE_CHECK_PATH}" 2>/dev/null || true
sed -i '/xiguapi-v3-rk3568 \\/d' "${UBOOT_MAKEFILE_CHECK_PATH}" 2>/dev/null || true
sed -i '/TARGET_DEVICES += nlnet_xiguapi-v3/d' "${ARMV8_CUSTOM_CHECK_PATH}" 2>/dev/null || true
echo -e "✅ 已清理源码中残留的侵入式配置"

# 5. 检查自定义配置目录和核心文件
echo -e "\n【2/4】检查自定义配置核心文件..."
check_dir "${CUSTOM_CONFIG_DIR}" "自定义配置根目录"

required_files=(
    "${CUSTOM_CONFIG_DIR}/target/linux/rockchip/dts/rk3568/rk3568-xiguapi-v3.dts:Xiguapi V3 主设备树"
    "${CUSTOM_CONFIG_DIR}/package/boot/uboot-rockchip/Makefile:自定义 UBoot Makefile"
    "${CUSTOM_CONFIG_DIR}/package/boot/uboot-rockchip/src/configs/rk3568-xiguapi-v3_defconfig:U-Boot 配置文件"
    "${CUSTOM_CONFIG_DIR}/package/boot/uboot-rockchip/src/arch/arm/dts/rk3568-xiguapi-v3-u-boot.dtsi:U-Boot 设备树片段"
)
for file_info in "${required_files[@]}"; do
    file_path=$(echo "$file_info" | cut -d: -f1)
    file_desc=$(echo "$file_info" | cut -d: -f2)
    check_file "${file_path}" "${file_desc}"
done
echo -e "✅ 自定义配置核心文件检查通过"

# 6. 部署自定义配置到 OpenWRT 源码
echo -e "\n【3/4】部署自定义配置到 OpenWRT 源码..."
# 创建必要的目标目录
mkdir -p "$(dirname "${DTS_CHECK_PATH}")"
mkdir -p "$(dirname "${UBOOT_MAKEFILE_CHECK_PATH}")"
mkdir -p "$(dirname "${UBOOT_CONFIG_CHECK_PATH}")"
mkdir -p "$(dirname "${UBOOT_DTSI_CHECK_PATH}")"

# 按需复制文件
cp -f "${CUSTOM_CONFIG_DIR}/target/linux/rockchip/dts/rk3568/rk3568-xiguapi-v3.dts" "${DTS_CHECK_PATH}"
cp -f "${CUSTOM_CONFIG_DIR}/package/boot/uboot-rockchip/Makefile" "${UBOOT_MAKEFILE_CHECK_PATH}"
cp -f "${CUSTOM_CONFIG_DIR}/package/boot/uboot-rockchip/src/configs/rk3568-xiguapi-v3_defconfig" "${UBOOT_CONFIG_CHECK_PATH}"
cp -f "${CUSTOM_CONFIG_DIR}/package/boot/uboot-rockchip/src/arch/arm/dts/rk3568-xiguapi-v3-u-boot.dtsi" "${UBOOT_DTSI_CHECK_PATH}"

echo -e "✅ 自定义配置部署完成"
echo -e "  📍 主设备树：${DTS_CHECK_PATH}"
echo -e "  📍 设备定义文件：${ARMV8_CUSTOM_CHECK_PATH}"
echo -e "  📍 UBoot Makefile：${UBOOT_MAKEFILE_CHECK_PATH}"

# 7. 验证自定义配置部署结果
echo -e "\n【4/4】验证自定义配置部署结果..."
verify_pass=0

# 检查关键文件是否存在
if [ -f "${DTS_CHECK_PATH}" ]; then
    echo -e "✅ 主设备树文件部署成功"
else
    echo -e "❌ 主设备树文件部署失败"
    verify_pass=1
fi


if [ -f "${UBOOT_MAKEFILE_CHECK_PATH}" ]; then
    echo -e "✅ UBoot Makefile 部署成功"
else
    echo -e "❌ UBoot Makefile 部署失败"
    verify_pass=1
fi


# 快速验证UBoot配置是否包含
if grep -q "rk3568-xiguapi-v3" "${UBOOT_MAKEFILE_CHECK_PATH}" 2>/dev/null; then
    echo -e "✅ UBoot Makefile 已包含 xiguapi-v3 配置"
else
    echo -e "❌ UBoot Makefile 缺失 xiguapi-v3 配置"
    verify_pass=1
fi

# 最终结果
if [ ${verify_pass} -eq 0 ]; then
    echo -e "\n🎉 Xiguapi V3 设备适配成功！"
    echo -e "=========================================="
    echo -e "✅ 设备树文件已部署"
    echo -e "✅ UBoot配置已更新"
    echo -e "=========================================="
    echo -e "📋 说明："
    echo -e "  - 此脚本仅完成硬件适配"
    echo -e "  - 请在工作流后续步骤中加载 .config 文件"
    echo -e "  - 确保 .config 中包含设备配置选项"
    echo -e "=========================================="
else
    echo -e "\n❌ 设备适配失败，请检查以上错误！"
    exit 1
fi

exit 0
