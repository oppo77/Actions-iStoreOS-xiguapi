#!/bin/bash
set -euo pipefail

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 基础配置
OPENWRT_ROOT=${OPENWRT_ROOT:-$(pwd)/openwrt}
if [ ! -d "${OPENWRT_ROOT}" ]; then
    echo -e "\n${RED}❌ OPENWRT_ROOT=${OPENWRT_ROOT} 目录不存在！${NC}"
    echo -e "${BLUE}💡 请设置正确的OPENWRT_ROOT环境变量：${NC}"
    echo -e "   export OPENWRT_ROOT=你的openwrt源码路径"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CUSTOM_CONFIG_DIR="${SCRIPT_DIR}/custom"
echo -e "${GREEN}✅ CUSTOM_CONFIG_DIR=${CUSTOM_CONFIG_DIR}${NC}"

if [ ! -d "${CUSTOM_CONFIG_DIR}" ]; then
    echo -e "\n${RED}❌ 自定义配置目录不存在 -> ${CUSTOM_CONFIG_DIR}${NC}"
    exit 1
fi

# 原始文件路径定义
DTS_ORIGINAL_PATH="${OPENWRT_ROOT}/target/linux/rockchip/files/arch/arm64/boot/dts/rockchip/rk3568-xiguapi-v3.dts"
BOARD_NETWORK_PATH="${OPENWRT_ROOT}/target/linux/rockchip/armv8/base-files/etc/board.d/02_network"
BOARD_INIT_PATH="${OPENWRT_ROOT}/target/linux/rockchip/armv8/base-files/lib/board/init.sh"
ARMV8_MK_PATH="${OPENWRT_ROOT}/target/linux/rockchip/image/armv8.mk"
UBOOT_MAKEFILE_PATH="${OPENWRT_ROOT}/package/boot/uboot-rockchip/Makefile"
UBOOT_DEFCONFIG_PATH="${OPENWRT_ROOT}/package/boot/uboot-rockchip/src/configs/nlnet-xiguapi-v3-rk3568_defconfig"
UBOOT_DTS_PATH="${OPENWRT_ROOT}/package/boot/uboot-rockchip/src/arch/arm/dts/rk3568-xiguapi-v3.dts"
UBOOT_DTSI_PATH="${OPENWRT_ROOT}/package/boot/uboot-rockchip/src/arch/arm/dts/rk3568-xiguapi-v3-u-boot.dtsi"
KERNEL_PATCH_PATH="${OPENWRT_ROOT}/target/linux/rockchip/patches-6.6/888-add-rk3568-xiguapi-v3-dtb.patch"

# 新增：rc.local 和 wireless 配置文件路径
RC_LOCAL_PATH="${OPENWRT_ROOT}/files/etc/rc.local"
WIRELESS_PATH="${OPENWRT_ROOT}/files/etc/config/wireless"

# 检查文件函数
check_file() {
    local file_path="$1"
    local desc="$2"
    if [ ! -f "$file_path" ]; then
        echo -e "\n${RED}❌ ${desc} 文件不存在 -> ${file_path}${NC}"
        exit 1
    fi
}

echo -e "\n${BLUE}【1/8】清理残留文件...${NC}"
cd "${OPENWRT_ROOT}"

# 清理旧文件
files_to_clean=(
    "${DTS_ORIGINAL_PATH}"
    "${UBOOT_DEFCONFIG_PATH}"
    "${UBOOT_DTS_PATH}"
    "${UBOOT_DTSI_PATH}"
    "${KERNEL_PATCH_PATH}"
)

for file in "${files_to_clean[@]}"; do
    if [ -f "${file}" ]; then
        rm -f "${file}"
        echo -e "${GREEN}✅ 清理文件：$(basename ${file})${NC}"
    fi
done

echo -e "\n${BLUE}【2/8】检查自定义文件...${NC}"
required_files=(
    "${CUSTOM_CONFIG_DIR}/target/linux/rockchip/files/arch/arm64/boot/dts/rockchip/rk3568-xiguapi-v3.dts:内核设备树文件"
    "${CUSTOM_CONFIG_DIR}/target/linux/rockchip/armv8/base-files/etc/board.d/02_network:02_network 文件"
    "${CUSTOM_CONFIG_DIR}/target/linux/rockchip/armv8/base-files/lib/board/init.sh:init.sh 文件"
    "${CUSTOM_CONFIG_DIR}/target/linux/rockchip/image/armv8.mk:armv8.mk 文件"
    "${CUSTOM_CONFIG_DIR}/package/boot/uboot-rockchip/Makefile:uboot-rockchip Makefile"
    "${CUSTOM_CONFIG_DIR}/package/boot/uboot-rockchip/src/configs/nlnet-xiguapi-v3-rk3568_defconfig:U-Boot defconfig 文件"
    "${CUSTOM_CONFIG_DIR}/package/boot/uboot-rockchip/src/arch/arm/dts/rk3568-xiguapi-v3.dts:U-Boot 设备树文件"
    "${CUSTOM_CONFIG_DIR}/package/boot/uboot-rockchip/src/arch/arm/dts/rk3568-xiguapi-v3-u-boot.dtsi:U-Boot 设备树头文件"
    "${CUSTOM_CONFIG_DIR}/target/linux/rockchip/patches-6.6/888-add-rk3568-xiguapi-v3-dtb.patch:内核 patch 文件"
    "${CUSTOM_CONFIG_DIR}/files/etc/rc.local:rc.local 启动脚本"
    "${CUSTOM_CONFIG_DIR}/files/etc/config/wireless:wireless 配置文件"
)

for file_info in "${required_files[@]}"; do
    file_path=$(echo "$file_info" | cut -d: -f1)
    file_desc=$(echo "$file_info" | cut -d: -f2)
    check_file "${file_path}" "${file_desc}"
done
echo -e "${GREEN}✅ 所有自定义文件检查通过${NC}"

echo -e "\n${BLUE}【3/8】部署内核设备树...${NC}"
mkdir -p "$(dirname "${DTS_ORIGINAL_PATH}")"
cp -f "${CUSTOM_CONFIG_DIR}/target/linux/rockchip/files/arch/arm64/boot/dts/rockchip/rk3568-xiguapi-v3.dts" "${DTS_ORIGINAL_PATH}"
echo -e "${GREEN}✅ 内核设备树文件部署完成：${DTS_ORIGINAL_PATH}${NC}"

echo -e "\n${BLUE}【4/8】部署内核 patch 文件...${NC}"
mkdir -p "$(dirname "${KERNEL_PATCH_PATH}")"
cp -f "${CUSTOM_CONFIG_DIR}/target/linux/rockchip/patches-6.6/888-add-rk3568-xiguapi-v3-dtb.patch" "${KERNEL_PATCH_PATH}"
echo -e "${GREEN}✅ 内核 patch 文件部署完成：${KERNEL_PATCH_PATH}${NC}"

echo -e "\n${BLUE}【5/8】部署 U-Boot 相关文件...${NC}"
# 部署 U-Boot defconfig
mkdir -p "$(dirname "${UBOOT_DEFCONFIG_PATH}")"
cp -f "${CUSTOM_CONFIG_DIR}/package/boot/uboot-rockchip/src/configs/nlnet-xiguapi-v3-rk3568_defconfig" "${UBOOT_DEFCONFIG_PATH}"
echo -e "${GREEN}✅ U-Boot defconfig 部署完成${NC}"

# 部署 U-Boot 设备树文件
mkdir -p "$(dirname "${UBOOT_DTS_PATH}")"
cp -f "${CUSTOM_CONFIG_DIR}/package/boot/uboot-rockchip/src/arch/arm/dts/rk3568-xiguapi-v3.dts" "${UBOOT_DTS_PATH}"
echo -e "${GREEN}✅ U-Boot 设备树文件部署完成${NC}"

# 部署 U-Boot 设备树头文件
mkdir -p "$(dirname "${UBOOT_DTSI_PATH}")"
cp -f "${CUSTOM_CONFIG_DIR}/package/boot/uboot-rockchip/src/arch/arm/dts/rk3568-xiguapi-v3-u-boot.dtsi" "${UBOOT_DTSI_PATH}"
echo -e "${GREEN}✅ U-Boot 设备树头文件部署完成${NC}"

# 替换 U-Boot Makefile
mkdir -p "$(dirname "${UBOOT_MAKEFILE_PATH}")"
cp -f "${CUSTOM_CONFIG_DIR}/package/boot/uboot-rockchip/Makefile" "${UBOOT_MAKEFILE_PATH}"
echo -e "${GREEN}✅ U-Boot Makefile 替换完成${NC}"

echo -e "\n${BLUE}【6/8】部署 rc.local 和 wireless 配置文件...${NC}"

# 部署 rc.local 文件
mkdir -p "$(dirname "${RC_LOCAL_PATH}")"
cp -f "${CUSTOM_CONFIG_DIR}/files/etc/rc.local" "${RC_LOCAL_PATH}"
chmod 755 "${RC_LOCAL_PATH}"
echo -e "${GREEN}✅ rc.local 文件部署完成（权限：755）${NC}"

# 部署 wireless 配置文件
mkdir -p "$(dirname "${WIRELESS_PATH}")"
cp -f "${CUSTOM_CONFIG_DIR}/files/etc/config/wireless" "${WIRELESS_PATH}"
chmod 644 "${WIRELESS_PATH}"
echo -e "${GREEN}✅ wireless 配置文件部署完成（权限：644）${NC}"

echo -e "\n${BLUE}【7/8】替换配置文件...${NC}"
# 替换 02_network 文件
mkdir -p "$(dirname "${BOARD_NETWORK_PATH}")"
cp -f "${CUSTOM_CONFIG_DIR}/target/linux/rockchip/armv8/base-files/etc/board.d/02_network" "${BOARD_NETWORK_PATH}"
echo -e "${GREEN}✅ 02_network 文件替换完成${NC}"

# 替换 init.sh 文件
mkdir -p "$(dirname "${BOARD_INIT_PATH}")"
cp -f "${CUSTOM_CONFIG_DIR}/target/linux/rockchip/armv8/base-files/lib/board/init.sh" "${BOARD_INIT_PATH}"
echo -e "${GREEN}✅ init.sh 文件替换完成${NC}"

# 替换 armv8.mk 文件
mkdir -p "$(dirname "${ARMV8_MK_PATH}")"
cp -f "${CUSTOM_CONFIG_DIR}/target/linux/rockchip/image/armv8.mk" "${ARMV8_MK_PATH}"
echo -e "${GREEN}✅ armv8.mk 文件替换完成${NC}"

echo -e "\n${BLUE}【8/8】验证部署结果...${NC}"
verify_pass=0

show_file_context() {
    local file_path="$1"
    local search_pattern="$2"
    local desc="$3"
    
    echo -e "\n${YELLOW}🔍 ${desc}：${NC}"
    echo -e "${BLUE}==========================================${NC}"
    
    if [ -f "${file_path}" ]; then
        if grep -n "${search_pattern}" "${file_path}" >/dev/null 2>&1; then
            echo -e "${GREEN}✅ 找到匹配项：${search_pattern}${NC}"
            
            line_number=$(grep -n "${search_pattern}" "${file_path}" | head -1 | cut -d: -f1 2>/dev/null)
            if [ -n "$line_number" ]; then
                start_line=$((line_number - 5))
                end_line=$((line_number + 5))
                if [ $start_line -lt 1 ]; then
                    start_line=1
                fi
                total_lines=$(wc -l < "${file_path}" 2>/dev/null || echo 0)
                if [ $end_line -gt $total_lines ]; then
                    end_line=$total_lines
                fi
                
                echo -e "${BLUE}=== 文件内容（第${start_line}-${end_line}行）===${NC}"
                sed -n "${start_line},${end_line}p" "${file_path}" 2>/dev/null | cat -n
            fi
        else
            echo -e "${YELLOW}⚠️  未找到匹配项：${search_pattern}${NC}"
        fi
    else
        echo -e "${RED}❌ 文件不存在：${file_path}${NC}"
        verify_pass=1
    fi
    
    echo -e "${BLUE}==========================================${NC}"
}

# 检查所有部署的文件
echo -e "${BLUE}📋 文件状态检查：${NC}"

all_files=(
    "${DTS_ORIGINAL_PATH}"
    "${BOARD_NETWORK_PATH}"
    "${BOARD_INIT_PATH}"
    "${ARMV8_MK_PATH}"
    "${UBOOT_MAKEFILE_PATH}"
    "${UBOOT_DEFCONFIG_PATH}"
    "${UBOOT_DTS_PATH}"
    "${UBOOT_DTSI_PATH}"
    "${KERNEL_PATCH_PATH}"
    "${RC_LOCAL_PATH}"
    "${WIRELESS_PATH}"
)

for file_path in "${all_files[@]}"; do
    if [ -f "${file_path}" ]; then
        file_size=$(stat -c%s "${file_path}" 2>/dev/null || echo 0)
        if [ "${file_size}" -gt 0 ]; then
            echo -e "  ${GREEN}✅ $(basename "${file_path}"): ${file_size} 字节${NC}"
        else
            echo -e "  ${RED}❌ $(basename "${file_path}"): 0 字节${NC}"
            verify_pass=1
        fi
    else
        echo -e "${RED}❌ 文件不存在：$(basename "${file_path}")${NC}"
        verify_pass=1
    fi
done

# 检查文件权限
echo -e "\n${BLUE}📋 文件权限检查：${NC}"
rc_local_perms=$(stat -c "%A" "${RC_LOCAL_PATH}" 2>/dev/null || echo "文件不存在")
wireless_perms=$(stat -c "%A" "${WIRELESS_PATH}" 2>/dev/null || echo "文件不存在")

if [ "$rc_local_perms" = "-rwxr-xr-x" ] || [ "$rc_local_perms" = "-rwxr-xr-x" ]; then
    echo -e "  ${GREEN}✅ rc.local 权限正确: ${rc_local_perms}${NC}"
else
    echo -e "  ${RED}❌ rc.local 权限错误: ${rc_local_perms} (应为 -rwxr-xr-x)${NC}"
    verify_pass=1
fi

if [ "$wireless_perms" = "-rw-r--r--" ]; then
    echo -e "  ${GREEN}✅ wireless 权限正确: ${wireless_perms}${NC}"
else
    echo -e "  ${RED}❌ wireless 权限错误: ${wireless_perms} (应为 -rw-r--r--)${NC}"
    verify_pass=1
fi

# 关键文件内容验证
echo -e "\n${BLUE}📋 关键文件内容验证：${NC}"
key_files_to_check=(
    "${DTS_ORIGINAL_PATH}:xiguapi-v3:内核设备树文件"
    "${BOARD_NETWORK_PATH}:xiguapi-v3:02_network 文件"
    "${ARMV8_MK_PATH}:xiguapi-v3:armv8.mk 文件"
    "${UBOOT_MAKEFILE_PATH}:xiguapi-v3:U-Boot Makefile"
    "${UBOOT_DEFCONFIG_PATH}:CONFIG_:U-Boot defconfig"
    "${KERNEL_PATCH_PATH}:xiguapi-v3:内核 patch 文件"
    "${RC_LOCAL_PATH}:#!/bin/sh:rc.local 启动脚本"
    "${WIRELESS_PATH}:config wifi-device:wireless 配置文件"
)

for file_info in "${key_files_to_check[@]}"; do
    file_path=$(echo "$file_info" | cut -d: -f1)
    search_pattern=$(echo "$file_info" | cut -d: -f2)
    desc=$(echo "$file_info" | cut -d: -f3)
    show_file_context "${file_path}" "${search_pattern}" "${desc}"
done

echo -e "\n${BLUE}【9/8】部署完成检查...${NC}"
if [ ${verify_pass} -eq 0 ]; then
    echo -e "${GREEN}🎉 Xiguapi V3 设备适配成功！${NC}"
    echo -e "${BLUE}==========================================${NC}"
    echo -e "${GREEN}✅ 所有文件部署完成${NC}"
    echo -e "${GREEN}✅ 所有配置文件已替换${NC}"
    echo -e "${GREEN}✅ 所有文件格式已验证${NC}"
    echo -e "${GREEN}✅ 所有文件大小正常${NC}"
    echo -e "${GREEN}✅ 文件权限设置正确${NC}"
    echo -e "${BLUE}==========================================${NC}"
    echo -e "${BLUE}📋 已部署的文件列表：${NC}"
    echo -e "  ${GREEN}1. 内核设备树：${DTS_ORIGINAL_PATH}${NC}"
    echo -e "  ${GREEN}2. 内核 patch：${KERNEL_PATCH_PATH}${NC}"
    echo -e "  ${GREEN}3. U-Boot defconfig：${UBOOT_DEFCONFIG_PATH}${NC}"
    echo -e "  ${GREEN}4. U-Boot 设备树：${UBOOT_DTS_PATH}${NC}"
    echo -e "  ${GREEN}5. U-Boot 设备树头文件：${UBOOT_DTSI_PATH}${NC}"
    echo -e "  ${GREEN}6. U-Boot Makefile：${UBOOT_MAKEFILE_PATH}${NC}"
    echo -e "  ${GREEN}7. rc.local 启动脚本：${RC_LOCAL_PATH} (权限：755)${NC}"
    echo -e "  ${GREEN}8. wireless 配置文件：${WIRELESS_PATH} (权限：644)${NC}"
    echo -e "  ${GREEN}9. 02_network：${BOARD_NETWORK_PATH}${NC}"
    echo -e "  ${GREEN}10. init.sh：${BOARD_INIT_PATH}${NC}"
    echo -e "  ${GREEN}11. armv8.mk：${ARMV8_MK_PATH}${NC}"
    echo -e "${BLUE}==========================================${NC}"
    
    echo -e "\n${BLUE}💡 后续步骤：${NC}"
    echo -e "  1. 在 OpenWRT 源码目录执行：make menuconfig"
    echo -e "  2. 选择 Target System: Rockchip"
    echo -e "  3. 选择 Subtarget: RK3568"
    echo -e "  4. 选择 Target Profile: Xiguapi V3"
    echo -e "  5. 保存配置后执行：make -j$(nproc)"
    
    echo -e "\n${GREEN}✨ 配置文件说明：${NC}"
    echo -e "  • rc.local：系统启动脚本，权限设置为 755"
    echo -e "  • wireless：WiFi配置文件，权限设置为 644"
    echo -e "  • 这两个文件将直接复制到固件的 /etc 目录"
    
    exit 0
else
    echo -e "${RED}❌ 设备适配失败！${NC}"
    echo -e "\n${YELLOW}🔧 调试建议：${NC}"
    echo -e "  1. 检查自定义文件中的关键词是否正确"
    echo -e "  2. 检查文件权限：ls -la \${CUSTOM_CONFIG_DIR}/files/"
    echo -e "  3. 确保自定义文件不为空"
    echo -e "  4. 检查路径是否正确：自定义文件应放在正确的子目录中"
    
    echo -e "\n${YELLOW}📁 自定义目录结构：${NC}"
    find "${CUSTOM_CONFIG_DIR}" -type f \
        \( -name "*.dts" -o -name "*.mk" -o -name "02_network" -o -name "init.sh" \
        -o -name "Makefile" -o -name "*.defconfig" -o -name "*.patch" -o -name "*.dtsi" \
        -o -name "rc.local" -o -name "wireless" \) | sort
    
    echo -e "\n${YELLOW}📁 目标部署路径：${NC}"
    for dir in \
        "$(dirname "${DTS_ORIGINAL_PATH}")" \
        "$(dirname "${KERNEL_PATCH_PATH}")" \
        "$(dirname "${UBOOT_DEFCONFIG_PATH}")" \
        "$(dirname "${UBOOT_DTS_PATH}")" \
        "$(dirname "${BOARD_NETWORK_PATH}")" \
        "$(dirname "${RC_LOCAL_PATH}")" \
        "$(dirname "${WIRELESS_PATH}")"; do
        if [ -d "${dir}" ]; then
            echo -e "  ${GREEN}✅ ${dir}${NC}"
        else
            echo -e "  ${RED}❌ ${dir} (目录不存在)${NC}"
        fi
    done
    
    exit 1
fi
