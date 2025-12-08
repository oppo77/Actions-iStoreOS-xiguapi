#!/bin/bash
set -euo pipefail

OPENWRT_ROOT=${OPENWRT_ROOT:-$(pwd)/openwrt}
if [ ! -d "${OPENWRT_ROOT}" ]; then
    echo -e "\n❌ 错误：OPENWRT_ROOT=${OPENWRT_ROOT} 目录不存在！"
    echo -e "💡 提示：在 GitHub Actions 中已自动设置，本地执行请执行：export OPENWRT_ROOT=你的openwrt源码路径"
    exit 1
fi

CUSTOM_CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/custom"
echo -e "✅ 自动识别自定义配置目录：CUSTOM_CONFIG_DIR=${CUSTOM_CONFIG_DIR}"

DTS_CHECK_PATH="${OPENWRT_ROOT}/target/linux/rockchip/dts/rk3568/rk3568-xiguapi-v3.dts"
LEGACY_MK_PATH="${OPENWRT_ROOT}/target/linux/rockchip/image/legacy.mk"

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

echo -e "\n【1/5】清理可能的残留侵入式修改..."
cd "${OPENWRT_ROOT}"

if [ -f "${LEGACY_MK_PATH}" ]; then
    sed -i '/define Device\/nlnet_xiguapi-v3/,/endef/d' "${LEGACY_MK_PATH}" 2>/dev/null || true
    sed -i '/TARGET_DEVICES += nlnet_xiguapi-v3/d' "${LEGACY_MK_PATH}" 2>/dev/null || true
fi

echo -e "✅ 已清理源码中残留的侵入式配置"

echo -e "\n【2/5】检查自定义配置和设备树文件..."
check_dir "${CUSTOM_CONFIG_DIR}" "自定义配置根目录"

required_files=(
    "${CUSTOM_CONFIG_DIR}/target/linux/rockchip/dts/rk3568/rk3568-xiguapi-v3.dts:Xiguapi V3 主设备树"
)
for file_info in "${required_files[@]}"; do
    file_path=$(echo "$file_info" | cut -d: -f1)
    file_desc=$(echo "$file_info" | cut -d: -f2)
    check_file "${file_path}" "${file_desc}"
done
echo -e "✅ 自定义配置和设备树文件检查通过"

echo -e "\n【3/5】部署设备树文件到 OpenWRT 源码..."
mkdir -p "$(dirname "${DTS_CHECK_PATH}")"
cp -f "${CUSTOM_CONFIG_DIR}/target/linux/rockchip/dts/rk3568/rk3568-xiguapi-v3.dts" "${DTS_CHECK_PATH}"
echo -e "✅ 设备树文件部署完成"
echo -e "  📍 主设备树：${DTS_CHECK_PATH}"

echo -e "\n【4/5】添加设备定义到 legacy.mk 文件..."

if [ ! -f "${LEGACY_MK_PATH}" ]; then
    echo -e "⚠️  legacy.mk 文件不存在，不可创建"
    verify_pass=1
else
    if grep -q "define Device/nlnet_xiguapi-v3" "${LEGACY_MK_PATH}"; then
        echo -e "⚠️  设备定义已存在，先清理旧的"
        sed -i '/define Device\/nlnet_xiguapi-v3/,/TARGET_DEVICES += nlnet_xiguapi-v3/d' "${LEGACY_MK_PATH}" 2>/dev/null || true
    fi

    if [ -n "$(tail -c1 "${LEGACY_MK_PATH}")" ]; then
        echo "" >> "${LEGACY_MK_PATH}"
    fi

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

echo -e "\n【5/5】验证自定义配置部署结果..."
verify_pass=0

if [ -f "${DTS_CHECK_PATH}" ]; then
    echo -e "✅ 主设备树文件部署成功"
else
    echo -e "❌ 主设备树文件部署失败"
    verify_pass=1
fi

if [ -f "${LEGACY_MK_PATH}" ]; then
    if grep -q "define Device/nlnet_xiguapi-v3" "${LEGACY_MK_PATH}"; then
        echo -e "✅ legacy.mk 中已添加 nlnet_xiguapi-v3 设备定义"
        
        start_line=$(grep -n "define Device/nlnet_xiguapi-v3" "${LEGACY_MK_PATH}" | cut -d: -f1)
        if [ -n "$start_line" ]; then
            echo -e "\n📄 显示完整的设备定义内容："
            echo -e "=========================================="
            
            total_lines=$(wc -l < "${LEGACY_MK_PATH}")
            end_line=$((start_line + 14))
            if [ $end_line -gt $total_lines ]; then
                end_line=$total_lines
            fi
            
            sed -n "${start_line},${end_line}p" "${LEGACY_MK_PATH}" | cat -n
            
            echo -e "=========================================="
            
            if sed -n "${start_line},${end_line}p" "${LEGACY_MK_PATH}" | grep -q "TARGET_DEVICES += nlnet_xiguapi-v3"; then
                echo -e "✅ 设备定义完整（包含 TARGET_DEVICES 行）"
            else
                echo -e "⚠️  设备定义可能不完整，未找到 TARGET_DEVICES 行"
                if grep -q "TARGET_DEVICES += nlnet_xiguapi-v3" "${LEGACY_MK_PATH}"; then
                    t_line=$(grep -n "TARGET_DEVICES += nlnet_xiguapi-v3" "${LEGACY_MK_PATH}" | cut -d: -f1)
                    echo -e "🔍 TARGET_DEVICES 行位于第 ${t_line} 行"
                fi
            fi
        else
            echo -e "❌ 无法找到设备定义的具体位置"
            verify_pass=1
        fi
        
        echo -e "\n🔍 检查设备定义格式："
        if grep -B1 "define Device/nlnet_xiguapi-v3" "${LEGACY_MK_PATH}" | head -1 | grep -q "^$"; then
            echo -e "✅ 设备定义前面有空行，格式正确"
        else
            echo -e "⚠️  设备定义前面缺少空行（非致命警告）"
        fi
    else
        echo -e "❌ legacy.mk 中未找到 nlnet_xiguapi-v3 设备定义"
        verify_pass=1
    fi
else
    echo -e "❌ legacy.mk 文件不存在: ${LEGACY_MK_PATH}"
    verify_pass=1
fi

if [ ${verify_pass} -eq 0 ]; then
    echo -e "\n🎉 Xiguapi V3 设备适配成功！"
    echo -e "=========================================="
    echo -e "✅ 设备树文件已部署"
    echo -e "✅ 设备定义已添加到 legacy.mk"
    echo -e "✅ 设备定义格式已验证"
    echo -e "=========================================="
    echo -e "📋 说明："
    echo -e "  - 此脚本只完成了硬件适配的基础部分"
    echo -e "  - 设备树文件已复制到正确位置"
    echo -e "  - 设备定义已添加到编译系统中"
    echo -e "  - 请在工作流后续步骤中加载 .config 文件"
    echo -e "  - 确保 .config 中包含设备配置选项"
    echo -e "=========================================="
    exit 0
else
    echo -e "\n❌ 设备适配失败，请检查以上错误！"
    echo -e "\n💡 调试建议："
    echo -e "  1. 检查自定义设备树文件是否正确"
    echo -e "  2. 检查 legacy.mk 文件是否可写"
    echo -e "  3. 查看上面的详细错误信息"
    exit 1
fi
