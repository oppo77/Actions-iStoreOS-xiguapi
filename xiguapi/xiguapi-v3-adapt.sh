#!/bin/bash
set -euo pipefail

# ===================== 核心配置（关键修复：路径）=====================
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)  # 脚本所在目录：Actions-iStoreOS-xiguapi/xiguapi/
DEVICE_FILES_DIR="${SCRIPT_DIR}"  # 设备文件和脚本同目录，无需额外拼接xiguapi
OPENWRT_ROOT="${OPENWRT_ROOT:-${SCRIPT_DIR}/../workdir/openwrt}"  # 适配OpenWRT实际路径
SOURCE_ROOT_DIR=$(cd "${OPENWRT_ROOT}" && pwd) || { 
    echo "ERROR: 未找到OpenWRT源码目录！"; exit 1; 
}

DEVICE_NAME="xiguapi-v3"
SOC="rk3568"
DEVICE_DEF="nlnet_xiguapi-v3"
UBOOT_CONFIG="rk3568-xiguapi-v3"
BOARD_FULL_NAME="nlnet,${DEVICE_NAME}"
NETWORK_DRIVER="kmod-r8169"
TARGET_DEVICE="${DEVICE_NAME}-${SOC}"

# ===================== 工具函数 =====================
info() { echo -e "\033[32m[INFO] $1\033[0m"; }
warn() { echo -e "\033[33m[WARN] $1\033[0m"; }
error() {
    echo -e "\033[31m[ERROR] $1\033[0m"
    local uboot_make="${SOURCE_ROOT_DIR}/package/boot/uboot-rockchip/Makefile"
    [ -f "$uboot_make" ] && {
        echo -e "\033[31m[DEBUG] 错误位置上下文：\033[0m"
        grep -A10 -B10 "UBOOT_TARGETS" "$uboot_make" || true
    }
    # 额外输出路径调试信息
    echo -e "\033[31m[DEBUG] 脚本目录：${SCRIPT_DIR}\033[0m"
    echo -e "\033[31m[DEBUG] 设备文件目录：${DEVICE_FILES_DIR}\033[0m"
    echo -e "\033[31m[DEBUG] OpenWRT目录：${SOURCE_ROOT_DIR}\033[0m"
    exit 1
}

ensure_dir() { [ -d "$1" ] || mkdir -p "$1" || error "创建目录失败: $1"; }
copy_file() {
    local src="$1" dest="$2"
    ensure_dir "$(dirname "$dest")"
    [ -f "$src" ] || error "源文件不存在: $src"
    cp -f "$src" "$dest" || error "复制失败: $src -> $dest"
    info "复制文件: $src -> $dest"
}

# ===================== 核心逻辑 =====================
init_check() {
    info "===== 1. 初始化检查 ====="
    local required_files=(
        "${DEVICE_FILES_DIR}/rk3568-xiguapi-v3.dts"
        "${DEVICE_FILES_DIR}/rk3568-xiguapi-v3_defconfig"
        "${DEVICE_FILES_DIR}/rk3568-xiguapi-v3-u-boot.dtsi"
    )
    # 输出待检查的文件路径（调试）
    info "待检查的设备文件路径："
    for file in "${required_files[@]}"; do
        echo " - $file"
    done
    # 检查文件是否存在
    for file in "${required_files[@]}"; do
        [ -f "$file" ] || error "必需文件缺失: $file"
    done
    info "所有必需文件验证通过"

    local uboot_make="${SOURCE_ROOT_DIR}/package/boot/uboot-rockchip/Makefile"
    grep -q "define U-Boot/rk3568/Default" "$uboot_make" || error "U-Boot核心依赖缺失"
    info "U-Boot rk3568 Default 依赖验证通过"

    cd "${SOURCE_ROOT_DIR}" || error "无法进入源码目录"
    [ -x "${BASH_SOURCE[0]}" ] || chmod +x "${BASH_SOURCE[0]}" && warn "已添加脚本执行权限"
}

copy_device_files() {
    info "===== 2. 复制设备文件 ====="
    local dts_dest="${SOURCE_ROOT_DIR}/target/linux/rockchip/dts/rk3568/rk3568-xiguapi-v3.dts"
    local defconfig_dest="${SOURCE_ROOT_DIR}/package/boot/uboot-rockchip/src/configs/${UBOOT_CONFIG}_defconfig"
    local dtsi_dest="${SOURCE_ROOT_DIR}/package/boot/uboot-rockchip/src/arch/arm/dts/rk3568/rk3568-xiguapi-v3-u-boot.dtsi"

    # 直接复制（覆盖原有文件）
    copy_file "${DEVICE_FILES_DIR}/rk3568-xiguapi-v3.dts" "$dts_dest"
    copy_file "${DEVICE_FILES_DIR}/rk3568-xiguapi-v3_defconfig" "$defconfig_dest"
    copy_file "${DEVICE_FILES_DIR}/rk3568-xiguapi-v3-u-boot.dtsi" "$dtsi_dest"

    info "✓ U-Boot文件复制完成"
}

modify_armv8_mk() {
    info "===== 3. 修改armv8.mk ====="
    local armv8_mk="${SOURCE_ROOT_DIR}/target/linux/rockchip/image/armv8.mk"
    
    # 先删除原有定义，再重新添加
    sed -i '/^# Added for Xiguapi V3 (rk3568)/,/^TARGET_DEVICES += '"${DEVICE_DEF}"'/d' "$armv8_mk"
    
    # 单行添加，避免换行问题
    cat >> "$armv8_mk" <<-'EOF'

# Added for Xiguapi V3 (rk3568)
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
    info "已添加 ${DEVICE_DEF} 到 armv8.mk"
}

modify_uboot_makefile() {
    info "===== 4. 修改uboot-rockchip Makefile ====="
    local uboot_make="${SOURCE_ROOT_DIR}/package/boot/uboot-rockchip/Makefile"
    local uboot_def="U-Boot/${TARGET_DEVICE}"

    # 1. 删除原有定义，重新添加（单行格式，避免换行）
    sed -i '/^# Added for Xiguapi V3 (rk3568)/,/^endef$/d' "$uboot_make"
    
    # 使用单引号避免转义问题
    cat >> "$uboot_make" <<-'EOF'

# Added for Xiguapi V3 (rk3568)
define U-Boot/xiguapi-v3-rk3568
	$(U-Boot/rk3568/Default)
	NAME:=Xiguapi V3
	BUILD_DEVICES := \
		nlnet_xiguapi-v3
endef
EOF
    info "已添加 ${uboot_def} 定义"

    # 2. 修复UBOOT_TARGETS（单行sed，稳定适配所有shell）
    # 先删除旧的目标（避免重复）
    sed -i 's/ xiguapi-v3-rk3568//g' "$uboot_make"
    # 查找UBOOT_TARGETS的最后一行（以反斜杠结尾的行）
    local uboot_target_line=$(grep -n '^[[:space:]]*UBOOT_TARGETS' "$uboot_make" | cut -d: -f1 | tail -1)
    if [ -n "$uboot_target_line" ]; then
        # 找到最后一行，追加目标（单行sed，无换行）
        sed -i "${uboot_target_line},\$ { /[^\\]/ s/$/ \\\n  xiguapi-v3-rk3568/ }" "$uboot_make"
    else
        # 无UBOOT_TARGETS行，新增
        echo -e "\nUBOOT_TARGETS := xiguapi-v3-rk3568" >> "$uboot_make"
    fi
    info "已添加 ${TARGET_DEVICE} 到 UBOOT_TARGETS"

    # 最终验证写入结果
    if ! grep -q "\bxiguapi-v3-rk3568\b" "$uboot_make"; then
        error "UBOOT_TARGETS 写入失败！请手动添加 xiguapi-v3-rk3568 到 UBOOT_TARGETS"
    fi
}

modify_device_configs() {
    info "===== 5. 修改设备配置文件 ====="
    
    # 5.1 01_leds（单行sed，避免换行）
    local leds_file="${SOURCE_ROOT_DIR}/target/linux/rockchip/armv8/base-files/etc/board.d/01_leds"
    [ -f "$leds_file" ] || error "01_leds 不存在"
    # 删除原有配置
    sed -i '/nlnet,xiguapi-v3)/,/^	;;/d' "$leds_file"
    # 插入新配置（单行sed）
    sed -i '/^esac$/i\nlnet,xiguapi-v3)\n\tucidef_set_led_default "power" "POWER" "blue:power" "1"\n\tucidef_set_led_netdev "status" "STATUS" "blue:status" "eth0"\n\tucidef_set_led_netdev "network" "NETWORK" "blue:network" "eth1"\n\t;;' "$leds_file"
    info "已添加 LED 配置"

    # 5.2 02_network（拆分sed为单行）
    local network_file="${SOURCE_ROOT_DIR}/target/linux/rockchip/armv8/base-files/etc/board.d/02_network"
    [ -f "$network_file" ] || error "02_network 不存在"
    # 删除原有配置
    sed -i '/nlnet,xiguapi-v3)/,/^	;;/d' "$network_file"
    # 插入rockchip_setup_interfaces配置
    sed -i '/rockchip_setup_interfaces()/ {
        :a; N; /^\t\*)/!ba; s/^\t\*)/\tnlnet,xiguapi-v3)\n\t\tucidef_set_interfaces_lan_wan "eth0" "eth1"\n\t\t;;\n\t\*)/
    }' "$network_file"
    # 插入rockchip_setup_macs配置
    sed -i '/rockchip_setup_macs()/ {
        :a; N; /^\t\*)/!ba; s/^\t\*)/\tnlnet,xiguapi-v3)\n\t\twan_mac=$(generate_mac_from_boot_mmc)\n\t\tlan_mac=$(macaddr_add "$wan_mac" 1)\n\t\t;;\n\t\*)/
    }' "$network_file"
    info "已添加 网络 配置"

    # 5.3 init.sh（拆分sed为单行）
    local init_file="${SOURCE_ROOT_DIR}/target/linux/rockchip/armv8/base-files/lib/board/init.sh"
    [ -f "$init_file" ] || error "init.sh 不存在"
    # 删除原有配置
    sed -i '/nlnet,xiguapi-v3)/,/^	;;/d' "$init_file"
    # 插入board_fixup_iface_name配置
    sed -i '/board_fixup_iface_name()/ {
        :a; N; /^\t\*)/!ba; s/^\t\*)/\tnlnet,xiguapi-v3)\n\t\t# No interface renaming needed\n\t\t;;\n\t\*)/
    }' "$init_file"
    # 插入board_set_iface_smp_affinity配置
    sed -i '/board_set_iface_smp_affinity()/ {
        :a; N; /^\t\*)/!ba; s/^\t\*)/\tnlnet,xiguapi-v3)\n\t\tset_iface_cpumask 2 eth0\n\t\tset_iface_cpumask 4 eth1\n\t\t;;\n\t\*)/
    }' "$init_file"
    info "已添加 初始化 配置"
}

verify_changes() {
    info "===== 6. 验证修改结果（唯一检查） ====="
    local error_count=0
    local uboot_make="${SOURCE_ROOT_DIR}/package/boot/uboot-rockchip/Makefile"
    local escaped_board="${BOARD_FULL_NAME//,/\\,}"

    # 1. 验证armv8.mk
    if ! grep -q "define Device/${DEVICE_DEF}" "${SOURCE_ROOT_DIR}/target/linux/rockchip/image/armv8.mk"; then
        warn "armv8.mk 无 ${DEVICE_DEF} 定义"
        error_count=$((error_count+1))
    else
        info "✓ armv8.mk 验证通过"
    fi

    # 2. 验证U-Boot核心配置
    info "===== 验证U-Boot编译配置 ====="
    if ! grep -q "^define U-Boot/${TARGET_DEVICE}$" "$uboot_make"; then
        warn "uboot Makefile 无 U-Boot/${TARGET_DEVICE} 定义"
        error_count=$((error_count+1))
    else
        if ! grep -A3 "U-Boot/${TARGET_DEVICE}" "$uboot_make" | grep -q "\$(U-Boot/rk3568/Default)"; then
            warn "U-Boot 未继承 rk3568 Default"
            error_count=$((error_count+1))
        else
            info "✓ U-Boot 继承关系验证通过"
        fi
        if grep -A5 "U-Boot/${TARGET_DEVICE}" "$uboot_make" | grep -q "BUILD_DEVICES := \\\n\t\tnlnet_xiguapi-v3"; then
            info "✓ U-Boot BUILD_DEVICES 语法验证通过"
        else
            warn "U-Boot BUILD_DEVICES 语法疑似错误（仅警告）"
        fi
        info "✓ uboot Makefile 定义验证通过"
    fi

    # 3. 验证UBOOT_TARGETS
    if grep -q "\bxiguapi-v3-rk3568\b" "$uboot_make"; then
        info "✓ UBOOT_TARGETS 验证通过"
    else
        warn "UBOOT_TARGETS 无 ${TARGET_DEVICE}"
        error_count=$((error_count+1))
    fi

    # 4. 验证U-Boot文件
    local defconfig="${SOURCE_ROOT_DIR}/package/boot/uboot-rockchip/src/configs/${UBOOT_CONFIG}_defconfig"
    local dtsi="${SOURCE_ROOT_DIR}/package/boot/uboot-rockchip/src/arch/arm/dts/rk3568/rk3568-xiguapi-v3-u-boot.dtsi"
    if [ ! -f "$defconfig" ] || [ ! -s "$defconfig" ]; then
        warn "U-Boot defconfig 缺失/为空"
        error_count=$((error_count+1))
    else
        info "✓ U-Boot defconfig 验证通过"
    fi
    if [ ! -f "$dtsi" ] || [ ! -s "$dtsi" ]; then
        warn "U-Boot dtsi 缺失/为空"
        error_count=$((error_count+1))
    else
        info "✓ U-Boot dtsi 验证通过"
    fi

    # 5. 验证DTS
    local dts="${SOURCE_ROOT_DIR}/target/linux/rockchip/dts/rk3568/${UBOOT_CONFIG}.dts"
    if [ ! -f "$dts" ]; then
        warn "DTS 文件不存在"
        error_count=$((error_count+1))
    else
        if ! grep -q "xiguapi-v3" "$dts"; then
            warn "DTS 无设备标识"
            error_count=$((error_count+1))
        else
            info "✓ DTS文件存在且包含设备标识"
        fi
        grep -q "rk3568-xiguapi-v3-u-boot" "$dts" || warn "DTS 未关联U-Boot（仅警告）"
    fi

    # 6. 验证LED/网络/init配置
    local check_files=(
        "${SOURCE_ROOT_DIR}/target/linux/rockchip/armv8/base-files/etc/board.d/01_leds"
        "${SOURCE_ROOT_DIR}/target/linux/rockchip/armv8/base-files/etc/board.d/02_network"
        "${SOURCE_ROOT_DIR}/target/linux/rockchip/armv8/base-files/lib/board/init.sh"
    )
    local check_names=("LED" "网络" "初始化")
    for i in "${!check_files[@]}"; do
        local file="${check_files[$i]}"
        local name="${check_names[$i]}"
        if [ ! -f "$file" ]; then
            warn "${name}配置文件不存在"
            error_count=$((error_count+1))
            continue
        fi
        if ! grep -q "${escaped_board}" "$file"; then
            warn "$file 无 ${BOARD_FULL_NAME} 配置"
            error_count=$((error_count+1))
        else
            info "✓ ${name}配置验证通过: $(basename "$file")"
        fi
    done

    # 7. 验证mkimage
    command -v mkimage &>/dev/null && info "✓ U-Boot 编译工具 mkimage 已安装" || warn "mkimage 未安装（仅警告）"

    # 最终判断
    if [ $error_count -gt 0 ]; then
        error "共发现 ${error_count} 个验证错误，适配失败"
    else
        info "✓ 所有修改验证通过！适配成功"
    fi
}

# ===================== 主流程 =====================
main() {
    info "===== 开始Xiguapi V3 (rk3568) 固件适配 ====="
    init_check
    copy_device_files
    modify_armv8_mk
    modify_uboot_makefile
    modify_device_configs
    verify_changes
    info "===== Xiguapi V3 固件适配完成 ====="
}

main
exit 0
