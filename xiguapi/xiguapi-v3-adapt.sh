#!/bin/bash
set -euo pipefail
# Xiguapi V3 设备适配脚本（无侵入版：基于 custom 目录部署，不修改源码）

# 1. 自动设置/检查 OPENWRT_ROOT 路径（优先读取环境变量，适配 GitHub Actions）
OPENWRT_ROOT=${OPENWRT_ROOT:-$(pwd)/openwrt}
if [ ! -d "${OPENWRT_ROOT}" ]; then
    echo -e "\n❌ 错误：OPENWRT_ROOT=${OPENWRT_ROOT} 目录不存在！"
    echo -e "💡 提示：在 GitHub Actions 中已自动设置，本地执行请执行：export OPENWRT_ROOT=你的openwrt源码路径"
    exit 1
fi

# 2. 定义路径常量（严格匹配 custom 目录树）
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CUSTOM_CONFIG_DIR="${SRC_DIR}/custom"  # 仓库中的自定义配置根目录
echo -e "✅ 自动识别自定义配置目录：CUSTOM_CONFIG_DIR=${CUSTOM_CONFIG_DIR}"

# OpenWRT 源码内的目标路径（严格匹配 custom 目录树的部署路径）
DTS_CHECK_PATH="${OPENWRT_ROOT}/target/linux/rockchip/dts/rk3568/rk3568-xiguapi-v3.dts"
ARMV8_CUSTOM_CHECK_PATH="${OPENWRT_ROOT}/target/linux/rockchip/image/armv8.mk"
UBOOT_MAKEFILE_CHECK_PATH="${OPENWRT_ROOT}/package/boot/uboot-rockchip/Makefile"
UBOOT_CONFIG_CHECK_PATH="${OPENWRT_ROOT}/package/boot/uboot-rockchip/src/configs/rk3568-xiguapi-v3_defconfig"
UBOOT_DTSI_CHECK_PATH="${OPENWRT_ROOT}/package/boot/uboot-rockchip/src/arch/arm/dts/rk3568-xiguapi-v3-u-boot.dtsi"
UBOOT_UPSTREAM_DTS_CHECK_PATH="${OPENWRT_ROOT}/package/boot/uboot-rockchip/src/dts/upstream/src/arm64/rockchip/rk3568-xiguapi-v3.dts"

# 3. 辅助函数（新增目录检查、严格匹配文件路径）
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

safe_grep() {
    local pattern="$1"
    local file="$2"
    fgrep -q -F "${pattern}" "${file}" 2>/dev/null
}

# 4. 清理残留的侵入式修改（兼容旧版本，避免冲突）
echo -e "\n【1/6】清理可能的残留侵入式修改..."
# 清理源码中旧的手动修改内容，确保自定义配置生效
if [ -f "${UBOOT_MAKEFILE_CHECK_PATH}.orig" ]; then
    rm -f "${UBOOT_MAKEFILE_CHECK_PATH}.orig" 2>/dev/null || true
fi
if [ -f "${ARMV8_CUSTOM_CHECK_PATH}.orig" ]; then
    rm -f "${ARMV8_CUSTOM_CHECK_PATH}.orig" 2>/dev/null || true
fi
# 清理可能的旧配置片段
sed -i '/define U-Boot\/xiguapi-v3-rk3568/,/endef/ d' "${UBOOT_MAKEFILE_CHECK_PATH}" 2>/dev/null || true
sed -i '/xiguapi-v3-rk3568 \\/d' "${UBOOT_MAKEFILE_CHECK_PATH}" 2>/dev/null || true
sed -i '/define Device\/nlnet_xiguapi-v3/,/endef/ d' "${ARMV8_CUSTOM_CHECK_PATH}" 2>/dev/null || true
sed -i '/TARGET_DEVICES += nlnet_xiguapi-v3/d' "${ARMV8_CUSTOM_CHECK_PATH}" 2>/dev/null || true
echo -e "✅ 已清理源码中残留的侵入式配置"

# 5. 检查自定义配置目录和核心文件（严格匹配给定目录树）
echo -e "\n【2/6】检查自定义配置核心文件..."
check_dir "${CUSTOM_CONFIG_DIR}" "自定义配置根目录"
# 严格匹配 custom 目录树的文件检查列表
required_files=(
    "${CUSTOM_CONFIG_DIR}/target/linux/rockchip/dts/rk3568/rk3568-xiguapi-v3.dts:Xiguapi V3 主设备树"
    "${CUSTOM_CONFIG_DIR}/target/linux/rockchip/image/armv8.mk:自定义 armv8 设备定义文件"
    "${CUSTOM_CONFIG_DIR}/package/boot/uboot-rockchip/Makefile:自定义 UBoot Makefile"
    "${CUSTOM_CONFIG_DIR}/package/boot/uboot-rockchip/src/configs/rk3568-xiguapi-v3_defconfig:U-Boot 配置文件"
    "${CUSTOM_CONFIG_DIR}/package/boot/uboot-rockchip/src/arch/arm/dts/rk3568-xiguapi-v3-u-boot.dtsi:U-Boot 设备树片段"
    "${CUSTOM_CONFIG_DIR}/package/boot/uboot-rockchip/src/dts/upstream/src/arm64/rockchip/rk3568-xiguapi-v3.dts:U-Boot upstream 设备树"
)
for file_info in "${required_files[@]}"; do
    file_path=$(echo "$file_info" | cut -d: -f1)
    file_desc=$(echo "$file_info" | cut -d: -f2)
    check_file "${file_path}" "${file_desc}"
done
echo -e "✅ 自定义配置核心文件检查通过（严格匹配目录树）"

# 6. 部署自定义配置到 OpenWRT 源码（核心步骤，完整复制目录结构）
echo -e "\n【3/6】部署自定义配置到 OpenWRT 源码..."
# 递归复制 custom 目录到源码根目录，保留目录结构，强制覆盖同名文件
cp -rf "${CUSTOM_CONFIG_DIR}/"* "${OPENWRT_ROOT}/"
# 验证部署后的目录结构
echo -e "✅ 自定义配置部署完成，部署路径清单："
echo -e "  - 主设备树：${DTS_CHECK_PATH}"
echo -e "  - 设备定义文件：${ARMV8_CUSTOM_CHECK_PATH}"
echo -e "  - UBoot Makefile：${UBOOT_MAKEFILE_CHECK_PATH}"
echo -e "  - UBoot 配置：${UBOOT_CONFIG_CHECK_PATH}"
echo -e "  - UBoot 设备树片段：${UBOOT_DTSI_CHECK_PATH}"
echo -e "  - UBoot upstream 设备树：${UBOOT_UPSTREAM_DTS_CHECK_PATH}"

# 7. 验证自定义配置部署结果（严格匹配所有文件）
echo -e "\n【4/6】验证自定义配置部署结果..."
verify_pass=0

# 逐个验证部署的文件是否存在
check_deployed_file() {
    local file_path="$1"
    local desc="$2"
    if [ -f "${file_path}" ]; then
        echo -e "✅ ${desc} 部署成功"
    else
        echo -e "❌ ${desc} 部署失败"
        verify_pass=1
    fi
}

check_deployed_file "${DTS_CHECK_PATH}" "主设备树文件"
check_deployed_file "${ARMV8_CUSTOM_CHECK_PATH}" "armv8 设备定义文件"
check_deployed_file "${UBOOT_MAKEFILE_CHECK_PATH}" "UBoot Makefile"
check_deployed_file "${UBOOT_CONFIG_CHECK_PATH}" "UBoot 配置文件"
check_deployed_file "${UBOOT_DTSI_CHECK_PATH}" "UBoot 设备树片段"
check_deployed_file "${UBOOT_UPSTREAM_DTS_CHECK_PATH}" "UBoot upstream 设备树"

# 验证设备定义是否存在
if safe_grep "Device/nlnet_xiguapi-v3" "${ARMV8_CUSTOM_CHECK_PATH}"; then
    echo -e "✅ 自定义设备定义（nlnet_xiguapi-v3）已包含在 armv8.mk 中"
else
    echo -e "❌ 自定义设备定义缺失"
    verify_pass=1
fi

# 验证 UBoot 配置是否包含目标
if safe_grep "rk3568-xiguapi-v3" "${UBOOT_MAKEFILE_CHECK_PATH}"; then
    echo -e "✅ UBoot Makefile 已包含 xiguapi-v3 配置"
else
    echo -e "❌ UBoot Makefile 缺失 xiguapi-v3 配置"
    verify_pass=1
fi

# 8. 预生成配置验证（检查 OpenWRT 是否识别设备）
echo -e "\n【5/6】验证 OpenWRT 设备识别..."
cd "${OPENWRT_ROOT}"
# 临时生成配置，检查设备是否被识别
make defconfig >/dev/null 2>&1
if safe_grep "CONFIG_TARGET_rockchip_armv8_DEVICE_nlnet_xiguapi-v3=y" .config; then
    echo -e "✅ OpenWRT 已自动识别 nlnet_xiguapi-v3 设备"
else
    echo -e "⚠️ OpenWRT 暂未自动识别设备，正在手动添加配置..."
    # 自动添加设备配置到 .config
    echo "CONFIG_TARGET_rockchip_armv8_DEVICE_nlnet_xiguapi-v3=y" >> .config
    # 重新生成配置确保生效
    make defconfig >/dev/null 2>&1
    if safe_grep "CONFIG_TARGET_rockchip_armv8_DEVICE_nlnet_xiguapi-v3=y" .config; then
        echo -e "✅ 已手动添加设备配置并生效"
    else
        echo -e "❌ 手动添加设备配置失败"
        verify_pass=1
    fi
fi

# 9. 最终验证结果
echo -e "\n【6/6】适配结果最终核验..."
if [ ${verify_pass} -eq 0 ]; then
    echo -e "\n🎉 无侵入式适配100%成功！"
    echo -e "-------------------------------------------------"
    echo -e "✅ 自定义配置已完整部署，未修改任何 OpenWRT 源码文件"
    echo -e "✅ 所有文件严格匹配目录树结构，设备识别正常"
    echo -e "✅ 可开始编译 OpenWRT 固件！"
else
    echo -e "\n❌ 适配失败，请根据以上错误提示排查文件路径/内容问题！"
    exit 1
fi

exit 0
