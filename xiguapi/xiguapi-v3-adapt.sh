#!/bin/bash
set -euo pipefail  # 严格模式，出错立即退出

# ===================== 核心路径配置 =====================
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DEVICE_FILES_DIR="${SCRIPT_DIR}"

# 优先读取环境变量，默认指向脚本上级的openwrt目录
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
UBOOT_CONFIG="rk3568-xiguapi-v3"  # 仅用于DTS命名，U-Boot定义中不再使用
# 统一board名称（匹配OpenWRT标准格式：厂商,设备名）
BOARD_FULL_NAME="nlnet,${DEVICE_NAME}"
# 网卡驱动可配置变量（按你的要求保留，未修改）
NETWORK_DRIVER="kmod-r8169"

# ===================== 工具函数 =====================
info() {
    echo -e "\033[32m[INFO] $1\033[0m"
}

warn() {
    echo -e "\033[33m[WARN] $1\033[0m"
}

error() {
    echo -e "\033[31m[ERROR] $1\033[0m"
    # 调试：输出关键文件内容帮助定位问题
    if [ -f "${SOURCE_ROOT_DIR}/target/linux/rockchip/armv8/base-files/etc/board.d/01_leds" ]; then
        echo -e "\033[31m[DEBUG] 01_leds 文件内容片段：\033[0m"
        grep -A10 -B2 "${BOARD_FULL_NAME//,/\\,}" "${SOURCE_ROOT_DIR}/target/linux/rockchip/armv8/base-files/etc/board.d/01_leds" || true
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

# 简化：移除备份逻辑，仅保留文件复制
copy_file() {
    local src="$1"
    local dest="$2"
    ensure_dir "$(dirname "$dest")"
    
    if [ ! -f "$src" ]; then
        error "源文件不存在: $src"
    fi
    
    # 直接覆盖（新环境无需备份）
    cp -f "$src" "$dest" || error "复制文件失败: $src -> $dest"
    info "复制文件: $src -> $dest"
}

# 安全的sed多行插入函数（解决括号/换行解析问题）
safe_sed_insert() {
    local file="$1"
    local match_pattern="$2"
    local insert_content="$3"
    
    # 使用临时文件避免sed直接修改的语法问题
    local tmp_file=$(mktemp)
    # 转义插入内容中的特殊字符（括号、换行、逗号）
    local escaped_content=$(echo "${insert_content}" | sed -e 's/[\/&]/\\&/g' -e 's/)/\\)/g' -e 's/(/\\(/g')
    
    \# 构造sed命令：在匹配行前插入内容
    sed "/${match_pattern}/i\\
${escaped_content}" "${file}" > "${tmp_file}"
    
    \# 替换原文件
    mv "${tmp_file}" "${file}" || {
        rm -f "${tmp_file}"
        error "sed插入失败: 无法替换原文件 ${file}"
    }
    rm -f "${tmp_file}"
}

\# ===================== 核心操作函数 =====================
init_check() {
    info "===== 1. 初始化检查 ====="
    info "脚本目录: ${SCRIPT_DIR}"
    info "源码根目录: ${SOURCE_ROOT_DIR}"

    \# 检查关键设备文件
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

    \# 新增：检查U-Boot核心依赖（rk3568 Default定义是否存在）
    local uboot_default_def="${SOURCE_ROOT_DIR}/package/boot/uboot-rockchip/Makefile"
    if ! grep -q "define U-Boot/rk3568/Default" "$uboot_default_def"; then
        error "U-Boot核心依赖缺失：未找到 U-Boot/rk3568/Default 定义，请检查uboot-rockchip包是否完整"
    fi
    info "U-Boot rk3568 Default 依赖验证通过"

    \# 切换工作目录到源码根目录
    cd "${SOURCE_ROOT_DIR}" || error "无法进入源码根目录: ${SOURCE_ROOT_DIR}"
    info "当前工作目录: $(pwd)"

    \# 脚本执行权限检查
    if [ ! -x "${BASH_SOURCE[0]}" ]; then
        warn "脚本无执行权限，自动添加..."
        chmod +x "${BASH_SOURCE[0]}" || error "添加执行权限失败"
    fi
}

copy_device_files() {
    info "===== 2. 复制设备文件 ====="
    
    \# 补全所有目标路径为绝对路径
    local dts_dest="${SOURCE_ROOT_DIR}/target/linux/rockchip/dts/rk3568/rk3568-xiguapi-v3.dts"
    copy_file "${DEVICE_FILES_DIR}/rk3568-xiguapi-v3.dts" "$dts_dest"

    local defconfig_dest="${SOURCE_ROOT_DIR}/package/boot/uboot-rockchip/src/configs/${UBOOT_CONFIG}_defconfig"
    copy_file "${DEVICE_FILES_DIR}/rk3568-xiguapi-v3_defconfig" "$defconfig_dest"

    local dtsi_dest="${SOURCE_ROOT_DIR}/package/boot/uboot-rockchip/src/arch/arm/dts/rk3568-xiguapi-v3-u-boot.dtsi"
    copy_file "${DEVICE_FILES_DIR}/rk3568-xiguapi-v3-u-boot.dtsi" "$dtsi_dest"

    \# 验证U-Boot文件复制完整性
    info "===== 验证U-Boot文件复制结果 ====="
    local uboot_copy_files=(
        "$defconfig_dest"
        "$dtsi_dest"
    )
    for file in "${uboot_copy_files[@]}"; do
        if [ ! -f "$file" ]; then
            error "U-Boot文件复制失败：$file 不存在"
        elif [ ! -s "$file" ]; then
            error "U-Boot文件复制异常：$file 为空文件"
        else
            info "✓ U-Boot文件验证通过: $file"
        fi
    done
}

modify_armv8_mk() {
    info "===== 3. 修改armv8.mk ====="
    local armv8_mk="${SOURCE_ROOT_DIR}/target/linux/rockchip/image/armv8.mk"
    local armv8_dir=$(dirname "$armv8_mk")

    \# 确保目录存在
    ensure_dir "$armv8_dir"

    \# 避免重复添加
    if grep -q "define Device/${DEVICE_DEF}" "$armv8_mk"; then
        warn "${DEVICE_DEF} 已存在于 armv8.mk，跳过追加"
        return
    fi

    \# 添加设备定义
    cat >> "$armv8_mk" << EOF

\# Added for Xiguapi V3 (rk3568)
define Device/${DEVICE_DEF}
  DEVICE_VENDOR := NLNET
  DEVICE_MODEL := Xiguapi V3
  SOC := ${SOC}
  DEVICE_DTS_DIR := ../dts/${SOC}
  DEVICE_DTS := ${UBOOT_CONFIG}
  UBOOT_DEVICE_NAME := ${UBOOT_CONFIG}
  KERNEL_LOADADDR := 0x04000000
  BOOT_SCRIPT := rockchip
  DEVICE_PACKAGES := ${NETWORK_DRIVER}
endef
TARGET_DEVICES += ${DEVICE_DEF}
EOF
    info "已添加 ${DEVICE_DEF} 到 armv8.mk"
}

modify_uboot_makefile() {
    info "===== 4. 修改uboot-rockchip Makefile ====="
    local uboot_makefile="${SOURCE_ROOT_DIR}/package/boot/uboot-rockchip/Makefile"

    \# 添加U-Boot定义
    local uboot_def="U-Boot/${DEVICE_NAME}-${SOC}"  \# 官方格式：设备名-soc
    if ! grep -q "$uboot_def" "$uboot_makefile"; then
        cat >> "$uboot_makefile" << EOF

\# Added for Xiguapi V3 (rk3568)
define ${uboot_def}
  \$(U-Boot/rk3568/Default)  \# 继承RK3568默认依赖/ATF/TPL配置
  NAME:=Xiguapi V3
  BUILD_DEVICES:= \          \# 对齐官方格式：单行也保留反斜杠
    ${DEVICE_DEF}            \# 对应armv8.mk中的DEVICE_DEF
endef
EOF
        info "已添加 ${uboot_def} 定义（继承RK3568默认配置）"
    else
        warn "${uboot_def} 已存在，跳过"
    fi

    \# 添加到UBOOT_TARGETS
    if ! grep -q "${DEVICE_NAME}-${SOC}" "$uboot_makefile"; then
        \# 步骤1：找到UBOOT_TARGETS行，在末尾添加自定义设备（官方格式）
        sed -i "/^UBOOT_TARGETS :=/ s/\$/ \\/" "$uboot_makefile"
        \# 步骤2：在UBOOT_TARGETS行下插入自定义设备（缩进+反斜杠）
        sed -i "/^UBOOT_TARGETS :=/a\  ${DEVICE_NAME}-${SOC} \\" "$uboot_makefile"
        \# 步骤3：清理最后一行的多余反斜杠（避免Makefile语法错误）
        sed -i '/^UBOOT_TARGETS :/,/^$/ { /[^\\]$/! s/\\$// }' "$uboot_makefile"
        
        info "已添加 ${DEVICE_NAME}-${SOC} 到 UBOOT_TARGETS"
    else
        warn "${DEVICE_NAME}-${SOC} 已在UBOOT_TARGETS中，跳过"
    fi
}

modify_device_configs() {
    info "===== 5. 修改设备配置文件 ====="
    
    \# 修复01_leds配置（核心修复部分）
    local leds_file="${SOURCE_ROOT_DIR}/target/linux/rockchip/armv8/base-files/etc/board.d/01_leds"
    ensure_dir "$(dirname "$leds_file")"
    [ ! -f "$leds_file" ] && touch "$leds_file" && info "创建空文件: $leds_file"

    \# 转义BOARD_FULL_NAME中的逗号（避免sed匹配错误）
    local escaped_board_name="${BOARD_FULL_NAME//,/\\,}"
    
    if ! grep -q "${escaped_board_name}" "$leds_file"; then
        \# 适配原有01_leds文件结构（包含board_config_update/flush）
        local leds_config="${BOARD_FULL_NAME})
	ucidef_set_led_default \"power\" \"POWER\" \"blue:power\" \"1\"
	ucidef_set_led_netdev \"status\" \"STATUS\" \"blue:status\" \"eth0\"
	ucidef_set_led_netdev \"network\" \"NETWORK\" \"blue:network\" \"eth1\"
	;;"
        
        \# 找到case分支中最后一个非*的分支（radxa,e54c)），在其后面插入
        \# 匹配模式：radxa,e54c) 结尾的行（适配原有文件结构）
        local match_pattern="radxa,e54c\))"
        
        # 使用安全插入函数，避免sed语法错误
        safe_sed_insert "${leds_file}" "${match_pattern}" "${leds_config}" || error "修改LED配置失败"
        info "已添加 ${DEVICE_NAME} LED配置"
        
        # 调试：输出插入结果
        info "DEBUG: 01_leds 插入后关键内容："
        grep -A8 -B1 "${escaped_board_name}" "${leds_file}" || true
    else
        warn "${DEVICE_NAME} LED配置已存在，跳过"
    fi

    # 修改02_network配置
    local network_file="${SOURCE_ROOT_DIR}/target/linux/rockchip/armv8/base-files/etc/board.d/02_network"
    ensure_dir "$(dirname "$network_file")"
    [ ! -f "$network_file" ] && touch "$network_file" && info "创建空文件: $network_file"

    if ! grep -q "${escaped_board_name}" "$network_file"; then
        # 接口配置（使用安全插入函数）
        local network_iface_config="${BOARD_FULL_NAME})
	ucidef_set_interfaces_lan_wan \"eth0\" \"eth1\"
	;;"
        
        # 找到rockchip_setup_interfaces函数中的*)前插入
        safe_sed_insert "${network_file}" "rockchip_setup_interfaces\(\).*\n.*case" "${network_iface_config}" || error "修改网络接口配置失败"
        
        # MAC地址配置
        local network_mac_config="${BOARD_FULL_NAME})
	wan_mac=\$(generate_mac_from_boot_mmc)
	lan_mac=\$(macaddr_add \"\$wan_mac\" 1)
	;;"
        
        # 找到rockchip_setup_macs函数中的*)前插入
        safe_sed_insert "${network_file}" "rockchip_setup_macs\(\).*\n.*case" "${network_mac_config}" || error "修改MAC配置失败"
        info "已添加 ${DEVICE_NAME} 网络配置"
    else
        warn "${DEVICE_NAME} 网络配置已存在，跳过"
    fi

    # 修改init.sh配置
    local init_file="${SOURCE_ROOT_DIR}/target/linux/rockchip/armv8/base-files/lib/board/init.sh"
    ensure_dir "$(dirname "$init_file")"
    [ ! -f "$init_file" ] && touch "$init_file" && info "创建空文件: $init_file"

    if ! grep -q "${escaped_board_name}" "$init_file"; then
        # 接口修复
        local init_iface_config="${BOARD_FULL_NAME})
	# No interface renaming needed
	;;"
        
        safe_sed_insert "${init_file}" "board_fixup_iface_name\(\).*\n.*case" "${init_iface_config}" || error "修改接口修复配置失败"
        
        # SMP亲和性
        local init_smp_config="${BOARD_FULL_NAME})
	set_iface_cpumask 2 eth0
	set_iface_cpumask 4 eth1
	;;"
        
        safe_sed_insert "${init_file}" "board_set_iface_smp_affinity\(\).*\n.*case" "${init_smp_config}" || error "修改SMP亲和性配置失败"
        info "已添加 ${DEVICE_NAME} 初始化配置"
    else
        warn "${DEVICE_NAME} 初始化配置已存在，跳过"
    fi
}

verify_changes() {
    info "===== 6. 验证修改结果 ====="
    local error_count=0
    local dts_file="${SOURCE_ROOT_DIR}/target/linux/rockchip/dts/rk3568/${UBOOT_CONFIG}.dts"
    local uboot_makefile="${SOURCE_ROOT_DIR}/package/boot/uboot-rockchip/Makefile"
    local uboot_def="U-Boot/${DEVICE_NAME}-${SOC}"
    local escaped_board_name="${BOARD_FULL_NAME//,/\\,}"

    # 验证设备定义
    if ! grep -q "define Device/${DEVICE_DEF}" "${SOURCE_ROOT_DIR}/target/linux/rockchip/image/armv8.mk"; then
        warn "armv8.mk 中未找到 ${DEVICE_DEF} 设备定义"
        error_count=$((error_count+1))
    else
        info "✓ armv8.mk 设备定义验证通过"
    fi

    # U-Boot 深度编译验证
    info "===== 验证U-Boot编译配置 ====="
    # 1. 验证U-Boot定义是否存在且语法正确
    if ! grep -q "$uboot_def" "$uboot_makefile"; then
        warn "uboot Makefile 中未找到 ${uboot_def} 定义"
        error_count=$((error_count+1))
    else
        # 验证继承关系
        if ! grep -A3 "$uboot_def" "$uboot_makefile" | grep -q "\$(U-Boot/rk3568/Default)"; then
            warn "U-Boot定义错误：${uboot_def} 未继承 U-Boot/rk3568/Default"
            error_count=$((error_count+1))
        else
            info "✓ U-Boot 继承关系验证通过"
        fi

        # 验证BUILD_DEVICES语法
        if ! grep -A5 "$uboot_def" "$uboot_makefile" | grep -q "BUILD_DEVICES:= \\\s*${DEVICE_DEF}"; then
            warn "U-Boot BUILD_DEVICES 语法错误：需包含反斜杠+缩进，且指向 ${DEVICE_DEF}"
            error_count=$((error_count+1))
        else
            info "✓ U-Boot BUILD_DEVICES 语法验证通过"
        fi
        info "✓ uboot Makefile 定义验证通过"
    fi

    # 2. 验证UBOOT_TARGETS添加
    if ! grep -q "${DEVICE_NAME}-${SOC}" "$uboot_makefile" | grep -q "UBOOT_TARGETS"; then
        warn "UBOOT_TARGETS 中未找到 ${DEVICE_NAME}-${SOC}"
        error_count=$((error_count+1))
    else
        # 验证UBOOT_TARGETS语法
        local uboot_targets_last_line=$(grep -A 20 "UBOOT_TARGETS :=" "$uboot_makefile" | grep -v "^$" | tail -1)
        if echo "$uboot_targets_last_line" | grep -q "\\\\$" && [ -z "$(echo "$uboot_targets_last_line" | sed 's/\\$//' | sed 's/ //g')"; then
            warn "UBOOT_TARGETS 最后一行存在多余反斜杠，会导致编译错误"
            error_count=$((error_count+1))
        else
            info "✓ UBOOT_TARGETS 语法验证通过"
        fi
        info "✓ UBOOT_TARGETS 设备添加验证通过"
    fi

    # 3. 验证U-Boot编译文件完整性
    local defconfig_dest="${SOURCE_ROOT_DIR}/package/boot/uboot-rockchip/src/configs/${UBOOT_CONFIG}_defconfig"
    local dtsi_dest="${SOURCE_ROOT_DIR}/package/boot/uboot-rockchip/src/arch/arm/dts/rk3568-xiguapi-v3-u-boot.dtsi"
    if [ ! -f "$defconfig_dest" ] || [ ! -s "$defconfig_dest" ]; then
        warn "U-Boot defconfig 文件缺失/为空: $defconfig_dest"
        error_count=$((error_count+1))
    else
        info "✓ U-Boot defconfig 文件验证通过"
    fi
    if [ ! -f "$dtsi_dest" ] || [ ! -s "$dtsi_dest" ]; then
        warn "U-Boot dtsi 文件缺失/为空: $dtsi_dest"
        error_count=$((error_count+1))
    else
        info "✓ U-Boot dtsi 文件验证通过"
    fi

    # 4. 验证U-Boot与设备树关联
    if ! grep -q "uboot" "$dts_file" && [ -f "$dts_file" ]; then
        warn "设备树文件未关联U-Boot：$dts_file 中未找到 uboot 关键字（可能影响引导）"
    fi

    # 验证DTS文件
    if [ ! -f "$dts_file" ]; then
        warn "DTS文件不存在: $dts_file"
        error_count=$((error_count+1))
    else
        if grep -q "xiguapi-v3" "$dts_file"; then
            info "✓ DTS文件存在且包含设备标识"
        else
            warn "DTS文件存在但不包含设备标识"
            error_count=$((error_count+1))
        fi
    fi

    # 验证LED/网络/init配置
    local check_files=(
        "${SOURCE_ROOT_DIR}/target/linux/rockchip/armv8/base-files/etc/board.d/01_leds"
        "${SOURCE_ROOT_DIR}/target/linux/rockchip/armv8/base-files/etc/board.d/02_network"
        "${SOURCE_ROOT_DIR}/target/linux/rockchip/armv8/base-files/lib/board/init.sh"
    )
    for file in "${check_files[@]}"; do
        if [ ! -f "$file" ]; then
            warn "配置文件不存在: $file"
            error_count=$((error_count+1))
        elif ! grep -q "${escaped_board_name}" "$file"; then
            warn "$file 中未找到 ${BOARD_FULL_NAME} 配置"
            error_count=$((error_count+1))
        else
            info "✓ $file 配置验证通过"
        fi
    done

    # 检查U-Boot编译依赖工具
    if ! command -v mkimage &>/dev/null; then
        warn "U-Boot编译依赖缺失：mkimage 未安装（编译时可能失败）"
    else
        info "✓ U-Boot 编译工具 mkimage 已安装"
    fi

    # 最后统一判断是否退出
    if [ $error_count -gt 0 ]; then
        error "共发现 ${error_count} 个验证错误，适配失败"
    else
        info "✓ 所有修改验证通过！U-Boot编译配置无异常"
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
