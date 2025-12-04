#!/bin/bash
set -euo pipefail  # 严格模式，出错立即退出

# ===================== 核心路径配置 =====================
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DEVICE_FILES_DIR="${SCRIPT_DIR}"

# 【修改1】修正源码根目录：优先读取环境变量，默认指向脚本上级的openwrt目录
OPENWRT_ROOT="${OPENWRT_ROOT:-${SCRIPT_DIR}/../openwrt}"
SOURCE_ROOT_DIR=$(cd "${OPENWRT_ROOT}" && pwd) || { 
    echo "ERROR: 未找到OpenWRT源码目录！请检查："
    echo "  1. 是否克隆了OpenWRT源码到 ${SCRIPT_DIR}/../openwrt 目录；"
    echo "  2. 或通过 export OPENWRT_ROOT=「你的源码目录」 指定路径；"
    exit 1; 
}

# ===================== 设备固定配置 =====================
DEVICE_NAME="xiguapi-v3"
SOC="rk3568"
DEVICE_DEF="nlnet_xiguapi-v3"
UBOOT_CONFIG="rk3568-xiguapi-v3"
# 新增：统一board名称（逗号分隔，匹配01_leds原有格式）
BOARD_FULL_NAME="nlnet,${DEVICE_NAME}"

# ===================== 工具函数 =====================
info() {
    echo -e "\033[32m[INFO] $1\033[0m"
}

warn() {
    echo -e "\033[33m[WARN] $1\033[0m"
}

error() {
    echo -e "\033[31m[ERROR] $1\033[0m"
    # 调试：输出文件内容帮助定位
    if [ -f "${SOURCE_ROOT_DIR}/target/linux/rockchip/armv8/base-files/etc/board.d/01_leds" ]; then
        echo -e "\033[31m[DEBUG] 01_leds 文件内容：\033[0m"
        cat "${SOURCE_ROOT_DIR}/target/linux/rockchip/armv8/base-files/etc/board.d/01_leds"
    fi
    exit 1
}

ensure_dir() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir" || error "创建目录失败: $dir"
        info "创建目录: $dir"
    fi
}

copy_file_with_backup() {
    local src="$1"
    local dest="$2"
    ensure_dir "$(dirname "$dest")"
    
    if [ ! -f "$src" ]; then
        error "源文件不存在: $src"
    fi
    
    # 仅在第一次复制时备份目标文件
    if [ -f "$dest" ] && [ ! -f "${dest}.bak.xiguapi" ]; then
        cp -f "$dest" "${dest}.bak.xiguapi" || error "备份文件失败: $dest"
        info "备份原文件: ${dest}.bak.xiguapi"
    fi
    
    cp -f "$src" "$dest" || error "复制文件失败: $src -> $dest"
    info "复制文件: $src -> $dest"
}

# ===================== 核心操作函数 =====================
init_check() {
    info "===== 1. 初始化检查 ====="
    info "脚本目录: ${SCRIPT_DIR}"
    info "源码根目录: ${SOURCE_ROOT_DIR}"

    # 检查关键设备文件
    local required_files=(
        "${DEVICE_FILES_DIR}/rk3568-xiguapi-v3.dts"
        "${DEVICE_FILES_DIR}/rk3568-xiguapi-v3_defconfig"
        "${DEVICE_FILES_DIR}/rk3568-xiguapi-v3-u-boot.dtsi"
    )
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            error "必需设备文件缺失: $file"
        fi
    done
    info "所有必需设备文件验证通过"

    # 切换工作目录到源码根目录
    cd "${SOURCE_ROOT_DIR}" || error "无法进入源码根目录: ${SOURCE_ROOT_DIR}"
    info "当前工作目录: $(pwd)"
}

copy_device_files() {
    info "===== 2. 复制设备文件 ====="
    
    # 【修改2】补全所有目标路径为绝对路径
    local dts_dest="${SOURCE_ROOT_DIR}/target/linux/rockchip/dts/rk3568/rk3568-xiguapi-v3.dts"
    copy_file_with_backup "${DEVICE_FILES_DIR}/rk3568-xiguapi-v3.dts" "$dts_dest"

    local defconfig_dest="${SOURCE_ROOT_DIR}/package/boot/uboot-rockchip/src/configs/${UBOOT_CONFIG}_defconfig"
    copy_file_with_backup "${DEVICE_FILES_DIR}/rk3568-xiguapi-v3_defconfig" "$defconfig_dest"

    local dtsi_dest="${SOURCE_ROOT_DIR}/package/boot/uboot-rockchip/src/arch/arm/dts/rk3568-xiguapi-v3-u-boot.dtsi"
    copy_file_with_backup "${DEVICE_FILES_DIR}/rk3568-xiguapi-v3-u-boot.dtsi" "$dtsi_dest"

    local upstream_dts_dest="${SOURCE_ROOT_DIR}/package/boot/uboot-rockchip/src/dts/upstream/src/arm64/rockchip/rk3568-xiguapi-v3.dts"
    copy_file_with_backup "${DEVICE_FILES_DIR}/rk3568-xiguapi-v3.dts" "$upstream_dts_dest"
}

modify_armv8_mk() {
    info "===== 3. 修改armv8.mk ====="
    # 【修改3】补全路径 + 前置检查
    local armv8_mk="${SOURCE_ROOT_DIR}/target/linux/rockchip/image/armv8.mk"
    local armv8_dir=$(dirname "$armv8_mk")

    # 确保目录存在
    ensure_dir "$armv8_dir"

    # 避免重复添加
    if grep -q "define Device/${DEVICE_DEF}" "$armv8_mk"; then
        warn "${DEVICE_DEF} 已存在于 armv8.mk，跳过追加"
        return
    fi

    # 添加设备定义
    cat >> "$armv8_mk" << EOF

# Added for Xiguapi V3 (rk3568)
define Device/${DEVICE_DEF}
  DEVICE_VENDOR := NLNET
  DEVICE_MODEL := Xiguapi V3
  SOC := ${SOC}
  DEVICE_DTS_DIR := ../dts/${SOC}
  DEVICE_DTS := ${UBOOT_CONFIG}
  UBOOT_DEVICE_NAME := ${UBOOT_CONFIG}
  KERNEL_LOADADDR := 0x04000000
  BOOT_SCRIPT := rockchip
  DEVICE_PACKAGES := kmod-r8169
endef
TARGET_DEVICES += ${DEVICE_DEF}
EOF
    info "已添加 ${DEVICE_DEF} 到 armv8.mk"
}

modify_uboot_makefile() {
    info "===== 4. 修改uboot-rockchip Makefile ====="
    # 【修改4】补全路径
    local uboot_makefile="${SOURCE_ROOT_DIR}/package/boot/uboot-rockchip/Makefile"
    
    # 备份原文件
    if [ ! -f "${uboot_makefile}.bak.xiguapi" ]; then
        cp -f "$uboot_makefile" "${uboot_makefile}.bak.xiguapi" || error "备份uboot Makefile失败"
        info "备份uboot Makefile: ${uboot_makefile}.bak.xiguapi"
    fi

    # 添加U-Boot定义
    local uboot_def="U-Boot/${DEVICE_NAME}-${SOC}"
    if ! grep -q "$uboot_def" "$uboot_makefile"; then
        cat >> "$uboot_makefile" << EOF

# Added for Xiguapi V3 (rk3568)
define ${uboot_def}
  \$(U-Boot/${SOC}/Default)
  NAME:=Xiguapi V3
  UBOOT_CONFIG:=${UBOOT_CONFIG}
  BUILD_DEVICES:= \
    ${DEVICE_DEF}
endef
EOF
        info "已添加 ${uboot_def} 定义"
    else
        warn "${uboot_def} 已存在，跳过"
    fi

    # 添加到UBOOT_TARGETS - 【核心修复】修正sed语法
    if ! grep -q "${DEVICE_NAME}-${SOC}" "$uboot_makefile"; then
        # 修复点1：改用-e分隔表达式，单行写法避免括号不匹配
        # 步骤1：给UBOOT_TARGETS行末尾加反斜杠（如果没有）
        sed -i -e "/^UBOOT_TARGETS :=/ { /\\$/! s/\$/ \\/; }" \
             # 步骤2：在UBOOT_TARGETS行下追加设备名
             -e "/^UBOOT_TARGETS :=/ a\  ${DEVICE_NAME}-${SOC} \\" \
             "$uboot_makefile"
        
        # 修复点2：清理多余反斜杠 - 改用单行循环语法
        sed -i -e '/^UBOOT_TARGETS :=/ { :loop; n; /^[^ \t]/! { s/\\$//; b loop; }; }' "$uboot_makefile"
        
        info "已添加 ${DEVICE_NAME}-${SOC} 到 UBOOT_TARGETS"
    else
        warn "${DEVICE_NAME}-${SOC} 已在UBOOT_TARGETS中，跳过"
    fi
}

modify_device_configs() {
    info "===== 5. 修改设备配置文件 ====="
    
    # 【修改5】修复01_leds配置（核心问题修复）
    local leds_file="${SOURCE_ROOT_DIR}/target/linux/rockchip/armv8/base-files/etc/board.d/01_leds"
    ensure_dir "$(dirname "$leds_file")"
    [ ! -f "$leds_file" ] && touch "$leds_file" && info "创建空文件: $leds_file"
    [ ! -f "${leds_file}.bak.xiguapi" ] && cp -f "$leds_file" "${leds_file}.bak.xiguapi" && info "备份01_leds: ${leds_file}.bak.xiguapi"

    if ! grep -q "${BOARD_FULL_NAME}" "$leds_file"; then
        # 修复点：使用Shell变量替换，适配原有case结构（允许case行有缩进，插入到esac上方）
        # 改用printf构造sed脚本，确保变量正确替换
        local leds_config=$(printf '%s' "${BOARD_FULL_NAME})\n\tucidef_set_led_default \"power\" \"POWER\" \"blue:power\" \"1\"\n\tucidef_set_led_netdev \"status\" \"STATUS\" \"blue:status\" \"eth0\"\n\tucidef_set_led_netdev \"network\" \"NETWORK\" \"blue:network\" \"eth1\"\n\t;;")
        sed -i -e "/^[[:space:]]*esac/i\\
${leds_config}
" "$leds_file" || error "修改LED配置失败"
        info "已添加 ${DEVICE_NAME} LED配置"
        # 调试：输出插入后的内容
        info "DEBUG: 01_leds 插入后关键内容："
        grep -A5 -B1 "${BOARD_FULL_NAME}" "$leds_file" || true
    else
        warn "${DEVICE_NAME} LED配置已存在，跳过"
    fi

    # 【修改6】补全路径 + 修复变量替换
    local network_file="${SOURCE_ROOT_DIR}/target/linux/rockchip/armv8/base-files/etc/board.d/02_network"
    ensure_dir "$(dirname "$network_file")"
    [ ! -f "$network_file" ] && touch "$network_file" && info "创建空文件: $network_file"
    [ ! -f "${network_file}.bak.xiguapi" ] && cp -f "$network_file" "${network_file}.bak.xiguapi"

    if ! grep -q "${BOARD_FULL_NAME}" "$network_file"; then
        # 接口配置 - 修复变量替换
        local network_iface_config=$(printf '%s' "\t${BOARD_FULL_NAME})\n\t\tucidef_set_interfaces_lan_wan \"eth0\" \"eth1\"\n\t\t;;")
        sed -i -e "/rockchip_setup_interfaces()/,/^}/ { /^\s*\*)/i\\
${network_iface_config}
        }" "$network_file" || error "修改网络接口配置失败"
        
        # MAC地址配置 - 修复变量替换
        local network_mac_config=$(printf '%s' "\t${BOARD_FULL_NAME})\n\t\twan_mac=\$(generate_mac_from_boot_mmc)\n\t\tlan_mac=\$(macaddr_add \"\$wan_mac\" 1)\n\t\t;;")
        sed -i -e "/rockchip_setup_macs()/,/^}/ { /^\s*\*)/i\\
${network_mac_config}
        }" "$network_file" || error "修改MAC配置失败"
        info "已添加 ${DEVICE_NAME} 网络配置"
    else
        warn "${DEVICE_NAME} 网络配置已存在，跳过"
    fi

    # 【修改7】补全路径 + 修复变量替换
    local init_file="${SOURCE_ROOT_DIR}/target/linux/rockchip/armv8/base-files/lib/board/init.sh"
    ensure_dir "$(dirname "$init_file")"
    [ ! -f "$init_file" ] && touch "$init_file" && info "创建空文件: $init_file"
    [ ! -f "${init_file}.bak.xiguapi" ] && cp -f "$init_file" "${init_file}.bak.xiguapi"

    if ! grep -q "${BOARD_FULL_NAME}" "$init_file"; then
        # 接口修复 - 修复变量替换
        local init_iface_config=$(printf '%s' "\t${BOARD_FULL_NAME})\n\t\t# No interface renaming needed\n\t\t;;")
        sed -i -e "/board_fixup_iface_name()/,/^}/ { /^\s*\*)/i\\
${init_iface_config}
        }" "$init_file" || error "修改接口修复配置失败"
        
        # SMP亲和性 - 修复变量替换
        local init_smp_config=$(printf '%s' "\t${BOARD_FULL_NAME})\n\t\tset_iface_cpumask 2 eth0\n\t\tset_iface_cpumask 4 eth1\n\t\t;;")
        sed -i -e "/board_set_iface_smp_affinity()/,/^}/ { /^\s*\*)/i\\
${init_smp_config}
        }" "$init_file" || error "修改SMP亲和性配置失败"
        info "已添加 ${DEVICE_NAME} 初始化配置"
    else
        warn "${DEVICE_NAME} 初始化配置已存在，跳过"
    fi
}

verify_changes() {
    info "===== 6. 验证修改结果 ====="
    local error_count=0
    # 【修改8】补全路径
    local dts_file="${SOURCE_ROOT_DIR}/target/linux/rockchip/dts/rk3568/${UBOOT_CONFIG}.dts"

    # 验证设备定义
    if ! grep -q "define Device/${DEVICE_DEF}" "${SOURCE_ROOT_DIR}/target/linux/rockchip/image/armv8.mk"; then
        error "armv8.mk 中未找到 ${DEVICE_DEF} 设备定义"
        error_count=$((error_count+1))
    else
        info "✓ armv8.mk 设备定义验证通过"
    fi

    # 验证UBOOT定义
    if ! grep -q "U-Boot/${DEVICE_NAME}-${SOC}" "${SOURCE_ROOT_DIR}/package/boot/uboot-rockchip/Makefile"; then
        error "uboot Makefile 中未找到 ${DEVICE_NAME}-${SOC} 定义"
        error_count=$((error_count+1))
    else
        info "✓ uboot Makefile 定义验证通过"
    fi

    # 验证DTS文件
    if [ ! -f "$dts_file" ]; then
        error "DTS文件不存在: $dts_file"
        error_count=$((error_count+1))
    else
        # 额外验证DTS中是否包含设备标识
        if grep -q "xiguapi-v3" "$dts_file"; then
            info "✓ DTS文件存在且包含设备标识"
        else
            error "DTS文件存在但不包含设备标识"
            error_count=$((error_count+1))
        fi
    fi

    # 验证LED/网络/init配置（使用统一的BOARD_FULL_NAME）
    local check_files=(
        "${SOURCE_ROOT_DIR}/target/linux/rockchip/armv8/base-files/etc/board.d/01_leds"
        "${SOURCE_ROOT_DIR}/target/linux/rockchip/armv8/base-files/etc/board.d/02_network"
        "${SOURCE_ROOT_DIR}/target/linux/rockchip/armv8/base-files/lib/board/init.sh"
    )
    for file in "${check_files[@]}"; do
        if [ ! -f "$file" ]; then
            error "配置文件不存在: $file"
            error_count=$((error_count+1))
        elif ! grep -q "${BOARD_FULL_NAME}" "$file"; then
            error "$file 中未找到 ${BOARD_FULL_NAME} 配置"
            error_count=$((error_count+1))
        else
            info "✓ $file 配置验证通过"
        fi
    done

    if [ $error_count -gt 0 ]; then
        error "共发现 ${error_count} 个验证错误，适配失败"
    else
        info "✓ 所有修改验证通过！"
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
