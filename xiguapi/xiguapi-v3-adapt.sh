#!/bin/bash
set -euo pipefail

OPENWRT_ROOT=${OPENWRT_ROOT:-$(pwd)/openwrt}
if [ ! -d "${OPENWRT_ROOT}" ]; then
    echo -e "\n❌ OPENWRT_ROOT=${OPENWRT_ROOT} 目录不存在！"
    echo -e "💡 export OPENWRT_ROOT=你的openwrt源码路径"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CUSTOM_CONFIG_DIR="${SCRIPT_DIR}/custom"
echo -e "✅ CUSTOM_CONFIG_DIR=${CUSTOM_CONFIG_DIR}"

if [ ! -d "${CUSTOM_CONFIG_DIR}" ]; then
    echo -e "\n❌ 自定义配置目录不存在 -> ${CUSTOM_CONFIG_DIR}"
    exit 1
fi

DTS_NEW_PATH="${OPENWRT_ROOT}/target/linux/rockchip/files/arch/arm64/boot/dts/rockchip/rk3568-xiguapi-v3.dts"
BOARD_NETWORK_PATH="${OPENWRT_ROOT}/target/linux/rockchip/armv8/base-files/etc/board.d/02_network"
BOARD_INIT_PATH="${OPENWRT_ROOT}/target/linux/rockchip/armv8/base-files/lib/board/init.sh"
ARMV8_MK_PATH="${OPENWRT_ROOT}/target/linux/rockchip/image/armv8.mk"
UBOOT_MAKEFILE_PATH="${OPENWRT_ROOT}/package/boot/uboot-rockchip/Makefile"

check_file() {
    local file_path="$1"
    local desc="$2"
    if [ ! -f "$file_path" ]; then
        echo -e "\n❌ ${desc} 文件不存在 -> ${file_path}"
        exit 1
    fi
}

echo -e "\n【1/5】清理残留文件..."
cd "${OPENWRT_ROOT}"

if [ -f "${DTS_NEW_PATH}" ]; then
    rm -f "${DTS_NEW_PATH}"
    echo -e "✅ 清理旧设备树文件"
fi

echo -e "\n【2/5】检查自定义文件..."
required_files=(
    "${CUSTOM_CONFIG_DIR}/target/linux/rockchip/files/arch/arm64/boot/dts/rockchip/rk3568-xiguapi-v3.dts:Xiguapi V3 设备树文件"
    "${CUSTOM_CONFIG_DIR}/target/linux/rockchip/armv8/base-files/etc/board.d/02_network:02_network 文件"
    "${CUSTOM_CONFIG_DIR}/target/linux/rockchip/armv8/base-files/lib/board/init.sh:init.sh 文件"
    "${CUSTOM_CONFIG_DIR}/target/linux/rockchip/image/armv8.mk:armv8.mk 文件"
    "${CUSTOM_CONFIG_DIR}/package/boot/uboot-rockchip/Makefile:uboot-rockchip Makefile"
)

for file_info in "${required_files[@]}"; do
    file_path=$(echo "$file_info" | cut -d: -f1)
    file_desc=$(echo "$file_info" | cut -d: -f2)
    check_file "${file_path}" "${file_desc}"
done
echo -e "✅ 所有自定义文件检查通过"

echo -e "\n【3/5】部署设备树文件..."
mkdir -p "$(dirname "${DTS_NEW_PATH}")"
cp -f "${CUSTOM_CONFIG_DIR}/target/linux/rockchip/files/arch/arm64/boot/dts/rockchip/rk3568-xiguapi-v3.dts" "${DTS_NEW_PATH}"
echo -e "✅ 设备树文件部署完成：${DTS_NEW_PATH}"

echo -e "\n【4/5】替换配置文件..."
mkdir -p "$(dirname "${BOARD_NETWORK_PATH}")"
cp -f "${CUSTOM_CONFIG_DIR}/target/linux/rockchip/armv8/base-files/etc/board.d/02_network" "${BOARD_NETWORK_PATH}"
echo -e "✅ 02_network 文件替换完成"

mkdir -p "$(dirname "${BOARD_INIT_PATH}")"
cp -f "${CUSTOM_CONFIG_DIR}/target/linux/rockchip/armv8/base-files/lib/board/init.sh" "${BOARD_INIT_PATH}"
echo -e "✅ init.sh 文件替换完成"

mkdir -p "$(dirname "${ARMV8_MK_PATH}")"
cp -f "${CUSTOM_CONFIG_DIR}/target/linux/rockchip/image/armv8.mk" "${ARMV8_MK_PATH}"
echo -e "✅ armv8.mk 文件替换完成"

mkdir -p "$(dirname "${UBOOT_MAKEFILE_PATH}")"
cp -f "${CUSTOM_CONFIG_DIR}/package/boot/uboot-rockchip/Makefile" "${UBOOT_MAKEFILE_PATH}"
echo -e "✅ uboot-rockchip Makefile 替换完成"

echo -e "\n【5/5】验证部署结果..."
verify_pass=0

show_file_context() {
    local file_path="$1"
    local search_pattern="$2"
    local desc="$3"
    
    echo -e "\n🔍 ${desc}："
    echo -e "=========================================="
    
    if [ -f "${file_path}" ]; then
        if grep -n "${search_pattern}" "${file_path}" >/dev/null; then
            echo -e "✅ 找到匹配项：${search_pattern}"
            
            line_number=$(grep -n "${search_pattern}" "${file_path}" | head -1 | cut -d: -f1)
            if [ -n "$line_number" ]; then
                start_line=$((line_number - 10))
                end_line=$((line_number + 10))
                if [ $start_line -lt 1 ]; then
                    start_line=1
                fi
                total_lines=$(wc -l < "${file_path}")
                if [ $end_line -gt $total_lines ]; then
                    end_line=$total_lines
                fi
                
                sed -n "${start_line},${end_line}p" "${file_path}" | cat -n
            fi
        else
            echo -e "⚠️  未找到匹配项：${search_pattern}"
            verify_pass=1
        fi
    else
        echo -e "❌ 文件不存在：${file_path}"
        verify_pass=1
    fi
    
    echo -e "=========================================="
}

files_to_check=(
    "${DTS_NEW_PATH}:xiguapi-v3:Xiguapi V3 设备树文件"
    "${BOARD_NETWORK_PATH}:xiguapi-v3:02_network 文件"
    "${BOARD_INIT_PATH}:xiguapi-v3:init.sh 文件"
    "${ARMV8_MK_PATH}:xiguapi-v3:armv8.mk 文件"
    "${UBOOT_MAKEFILE_PATH}:xiguapi-v3:uboot-rockchip Makefile"
)

for file_info in "${files_to_check[@]}"; do
    file_path=$(echo "$file_info" | cut -d: -f1)
    search_pattern=$(echo "$file_info" | cut -d: -f2)
    desc=$(echo "$file_info" | cut -d: -f3)
    show_file_context "${file_path}" "${search_pattern}" "${desc}"
done

echo -e "\n📋 详细检查："

all_files=("${DTS_NEW_PATH}" "${BOARD_NETWORK_PATH}" "${BOARD_INIT_PATH}" "${ARMV8_MK_PATH}" "${UBOOT_MAKEFILE_PATH}")
for file_path in "${all_files[@]}"; do
    if [ -f "${file_path}" ]; then
        file_size=$(stat -c%s "${file_path}")
        if [ "${file_size}" -gt 0 ]; then
            echo -e "  ✅ $(basename "${file_path}"): ${file_size} 字节"
        else
            echo -e "  ❌ $(basename "${file_path}"): 0 字节"
            verify_pass=1
        fi
    else
        echo -e "❌ 文件不存在：$(basename "${file_path}")"
        verify_pass=1
    fi
done

if [ ${verify_pass} -eq 0 ]; then
    echo -e "\n🎉 Xiguapi V3 设备适配成功！"
    echo -e "=========================================="
    echo -e "✅ 设备树文件已部署"
    echo -e "✅ 所有配置文件已替换"
    echo -e "✅ 所有文件格式已验证"
    echo -e "✅ 所有文件大小正常"
    echo -e "=========================================="
    echo -e "📋 部署的文件："
    echo -e "  1. ${DTS_NEW_PATH}"
    echo -e "  2. ${BOARD_NETWORK_PATH}"
    echo -e "  3. ${BOARD_INIT_PATH}"
    echo -e "  4. ${ARMV8_MK_PATH}"
    echo -e "  5. ${UBOOT_MAKEFILE_PATH}"
    echo -e "=========================================="
    exit 0
else
    echo -e "\n❌ 设备适配失败！"
    echo -e "\n🔧 调试建议："
    echo -e "  1. 检查自定义文件中的关键词"
    echo -e "  2. 检查文件权限"
    echo -e "  3. 查看详细错误信息"
    
    echo -e "\n📁 自定义目录结构："
    find "${CUSTOM_CONFIG_DIR}" -type f -name "*.dts" -o -name "*.mk" -o -name "02_network" -o -name "init.sh" -o -name "Makefile" | sort
    
    exit 1
fi
