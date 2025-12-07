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
# 注意：在GitHub Actions中，脚本位于仓库根目录下的xiguapi目录，自定义配置在xiguapi/custom
CUSTOM_CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/custom"
echo -e "✅ 自动识别自定义配置目录：CUSTOM_CONFIG_DIR=${CUSTOM_CONFIG_DIR}"

# OpenWRT 源码内的目标路径
DTS_CHECK_PATH="${OPENWRT_ROOT}/target/linux/rockchip/dts/rk3568/rk3568-xiguapi-v3.dts"
UBOOT_MAKEFILE_CHECK_PATH="${OPENWRT_ROOT}/package/boot/uboot-rockchip/Makefile"
PATCH_CHECK_PATH="${OPENWRT_ROOT}/package/boot/uboot-rockchip/patches/108-add-xiguapi-v3-support.patch"
LEGACY_MK_PATH="${OPENWRT_ROOT}/target/linux/rockchip/image/legacy.mk"

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
        echo -e "💡 提示：请确保 ${desc} 目录已放在 ${CUSTOM_CONFIG_DIR} 目录下"
        exit 1
    fi
}

# 4. 清理残留的侵入式修改
echo -e "\n【1/6】清理可能的残留侵入式修改..."
cd "${OPENWRT_ROOT}"

# 清理可能的旧UBoot配置片段
sed -i '/define U-Boot\/xiguapi-v3-rk3568/,/endef/ d' "${UBOOT_MAKEFILE_CHECK_PATH}" 2>/dev/null || true
sed -i '/xiguapi-v3-rk3568 \\/d' "${UBOOT_MAKEFILE_CHECK_PATH}" 2>/dev/null || true

# 清理旧的设备定义（如果存在）
if [ -f "${LEGACY_MK_PATH}" ]; then
    sed -i '/define Device\/nlnet_xiguapi-v3/,/endef/d' "${LEGACY_MK_PATH}" 2>/dev/null || true
    sed -i '/TARGET_DEVICES += nlnet_xiguapi-v3/d' "${LEGACY_MK_PATH}" 2>/dev/null || true
fi

echo -e "✅ 已清理源码中残留的侵入式配置"

# 5. 检查自定义配置目录和核心文件
echo -e "\n【2/6】检查自定义配置核心文件..."
check_dir "${CUSTOM_CONFIG_DIR}" "自定义配置根目录"

required_files=(
    "${CUSTOM_CONFIG_DIR}/target/linux/rockchip/dts/rk3568/rk3568-xiguapi-v3.dts:Xiguapi V3 主设备树"
    "${CUSTOM_CONFIG_DIR}/package/boot/uboot-rockchip/Makefile:自定义 UBoot Makefile"
    "${CUSTOM_CONFIG_DIR}/package/boot/uboot-rockchip/patches/108-add-xiguapi-v3-support.patch:U-Boot 补丁文件"
)
for file_info in "${required_files[@]}"; do
    file_path=$(echo "$file_info" | cut -d: -f1)
    file_desc=$(echo "$file_info" | cut -d: -f2)
    check_file "${file_path}" "${file_desc}"
done
echo -e "✅ 自定义配置核心文件检查通过"

# 6. 部署自定义配置到 OpenWRT 源码
echo -e "\n【3/6】部署自定义配置到 OpenWRT 源码..."
# 创建必要的目标目录
mkdir -p "$(dirname "${DTS_CHECK_PATH}")"
mkdir -p "$(dirname "${UBOOT_MAKEFILE_CHECK_PATH}")"
mkdir -p "$(dirname "${PATCH_CHECK_PATH}")"

# 按需复制文件
cp -f "${CUSTOM_CONFIG_DIR}/target/linux/rockchip/dts/rk3568/rk3568-xiguapi-v3.dts" "${DTS_CHECK_PATH}"
cp -f "${CUSTOM_CONFIG_DIR}/package/boot/uboot-rockchip/Makefile" "${UBOOT_MAKEFILE_CHECK_PATH}"
cp -f "${CUSTOM_CONFIG_DIR}/package/boot/uboot-rockchip/patches/108-add-xiguapi-v3-support.patch" "${PATCH_CHECK_PATH}"

echo -e "✅ 自定义配置部署完成"
echo -e "  📍 主设备树：${DTS_CHECK_PATH}"
echo -e "  📍 UBoot Makefile：${UBOOT_MAKEFILE_CHECK_PATH}"
echo -e "  📍 UBoot 补丁文件：${PATCH_CHECK_PATH}"

# 7. 添加nlnet_xiguapi-v3设备定义（修正格式，确保有空行）
echo -e "\n【4/6】添加设备定义到 legacy.mk 文件..."

# 确保legacy.mk文件存在
if [ ! -f "${LEGACY_MK_PATH}" ]; then
    echo -e "⚠️  legacy.mk 文件不存在，将创建"
    mkdir -p "$(dirname "${LEGACY_MK_PATH}")"
    touch "${LEGACY_MK_PATH}"
fi

# 检查是否已存在设备定义，避免重复添加
if grep -q "define Device/nlnet_xiguapi-v3" "${LEGACY_MK_PATH}"; then
    echo -e "⚠️  设备定义已存在，跳过添加"
else
    # 添加新的设备定义，确保前面有空行
    # 注意：这里使用cat命令逐行写入，确保格式正确
    cat >> "${LEGACY_MK_PATH}" << 'EOF'

define Device/nlnet_xiguapi-v3
$(call Device/Legacy/rk3568,$(1))
  DEVICE_VENDOR := NLNET
  DEVICE_MODEL := Xiguapi V3
  DEVICE_DTS := rk3568/rk3568-xiguapi-v3
  DEVICE_PACKAGES += kmod-r8169
endef
TARGET_DEVICES += nlnet_xiguapi-v3
EOF
    echo -e "✅ 设备定义已添加到 legacy.mk"
fi

# 8. 验证自定义配置部署结果
echo -e "\n【5/6】验证自定义配置部署结果..."
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

if [ -f "${PATCH_CHECK_PATH}" ]; then
    echo -e "✅ UBoot 补丁文件部署成功"
else
    echo -e "❌ UBoot 补丁文件部署失败"
    verify_pass=1
fi

# 快速验证UBoot配置是否包含
if grep -q "rk3568-xiguapi-v3" "${UBOOT_MAKEFILE_CHECK_PATH}" 2>/dev/null; then
    echo -e "✅ UBoot Makefile 已包含 xiguapi-v3 配置"
else
    echo -e "❌ UBoot Makefile 缺失 xiguapi-v3 配置"
    verify_pass=1
fi

# 验证legacy.mk是否添加成功
if [ -f "${LEGACY_MK_PATH}" ]; then
    if grep -q "define Device/nlnet_xiguapi-v3" "${LEGACY_MK_PATH}"; then
        echo -e "✅ legacy.mk 中已添加 nlnet_xiguapi-v3 设备定义"
        echo -e "\n📄 展示 legacy.mk 中包含 nlnet_xiguapi-v3 的上下文（前后5行）："
        echo -e "=========================================="
        grep -n -A 5 -B 5 "define Device/nlnet_xiguapi-v3" "${LEGACY_MK_PATH}" 2>/dev/null || echo "未找到相关行"
        echo -e "=========================================="
        
        # 检查空行格式
        echo -e "\n🔍 检查设备定义格式："
        if grep -B1 "define Device/nlnet_xiguapi-v3" "${LEGACY_MK_PATH}" | head -1 | grep -q "^$"; then
            echo -e "✅ 设备定义前面有空行，格式正确"
        else
            echo -e "⚠️  设备定义前面缺少空行"
        fi
    else
        echo -e "❌ legacy.mk 中未找到 nlnet_xiguapi-v3 设备定义"
        verify_pass=1
    fi
else
    echo -e "❌ legacy.mk 文件不存在: ${LEGACY_MK_PATH}"
    verify_pass=1
fi

# 9. 最终结果
echo -e "\n【6/6】适配结果汇总..."
if [ ${verify_pass} -eq 0 ]; then
    echo -e "\n🎉 Xiguapi V3 设备适配成功！"
    echo -e "=========================================="
    echo -e "✅ 设备树文件已部署"
    echo -e "✅ UBoot Makefile 已更新"
    echo -e "✅ UBoot 补丁文件已部署"
    echo -e "✅ 设备定义已添加到 legacy.mk"
    echo -e "✅ 设备定义格式已验证（包括空行）"
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
