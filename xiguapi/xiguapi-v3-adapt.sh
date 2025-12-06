#!/bin/bash
set -euo pipefail
# Xiguapi V3 设备适配脚本（简化版：直接读取仓库依赖文件，无需复制）

# 1. 自动设置/检查 OPENWRT_ROOT 路径（优先读取环境变量，适配 GitHub Actions）
OPENWRT_ROOT=${OPENWRT_ROOT:-$(pwd)/openwrt}
if [ ! -d "${OPENWRT_ROOT}" ]; then
    echo -e "\n❌ 错误：OPENWRT_ROOT=${OPENWRT_ROOT} 目录不存在！"
    echo -e "💡 提示：在 GitHub Actions 中已自动设置，本地执行请执行：export OPENWRT_ROOT=你的openwrt源码路径"
    exit 1
fi

# 2. 定义路径常量（核心修改：SRC_DIR 为脚本自身所在目录，即仓库的 xiguapi/ 目录）
# 无论脚本在哪里执行，都能正确找到仓库中的依赖文件
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo -e "✅ 自动识别依赖文件目录：SRC_DIR=${SRC_DIR}"

# OpenWRT 源码内的目标路径（无需修改）
UBOOT_MK="${OPENWRT_ROOT}/package/boot/uboot-rockchip/Makefile"
ARMv8_MK="${OPENWRT_ROOT}/target/linux/rockchip/image/armv8.mk"
DTS_DEST="${OPENWRT_ROOT}/target/linux/rockchip/dts/rk3568/rk3568-xiguapi-v3.dts"
DEFCONFIG_DEST="${OPENWRT_ROOT}/package/boot/uboot-rockchip/src/configs/rk3568-xiguapi-v3_defconfig"
UBOOT_DTSI_DEST="${OPENWRT_ROOT}/package/boot/uboot-rockchip/src/arch/arm/dts/rk3568-xiguapi-v3-u-boot.dtsi"
UBOOT_UPSTREAM_DTS_DEST="${OPENWRT_ROOT}/package/boot/uboot-rockchip/src/dts/upstream/src/arm64/rockchip/rk3568-xiguapi-v3.dts"

# 3. 辅助函数（不变）
check_file() {
    local file_path="$1"
    local desc="$2"
    if [ ! -f "$file_path" ]; then
        echo -e "\n❌ 错误：${desc} 文件不存在 -> ${file_path}"
        echo -e "💡 提示：请确保 ${desc} 文件已放在 ${SRC_DIR} 目录下（仓库的 xiguapi/ 目录）"
        exit 1
    fi
}

safe_grep() {
    local pattern="$1"
    local file="$2"
    fgrep -q -F "${pattern}" "${file}" 2>/dev/null
}

# 4. 彻底清理错误内容（不变）
echo -e "\n【1/7】清理错误插入的内容..."
if safe_grep "U-Boot/nlnet_xiguapi-v3" "${UBOOT_MK}" || safe_grep "U-Boot/xiguapi-v3-rk3568" "${UBOOT_MK}"; then
    sed -i '/define U-Boot\/nlnet_xiguapi-v3/,/endef/ d' "${UBOOT_MK}"
    sed -i '/define U-Boot\/xiguapi-v3-rk3568/,/endef/ d' "${UBOOT_MK}"
    sed -i '/rk3568-xiguapi-v3 \\/d' "${UBOOT_MK}"
    sed -i '/xiguapi-v3-rk3568 \\/d' "${UBOOT_MK}"
    sed -i -e '/endef/ {n; /^$/ {n; /^$/ d;}; }' "${UBOOT_MK}"
    sed -i -e '/^# RK3588 boards$/ {N; /^\n$/ d;}' "${UBOOT_MK}"
    echo -e "✅ 已清理错误内容并恢复原始格式"
else
    echo -e "⚠️ 无错误内容，跳过清理"
fi

# 5. 检查核心文件（提示指向仓库的 xiguapi/ 目录）
echo -e "\n【2/7】检查核心文件..."
required_files=(
    "rk3568-xiguapi-v3.dts:Xiguapi V3 设备树"
    "rk3568-xiguapi-v3_defconfig:U-Boot 配置"
    "rk3568-xiguapi-v3-u-boot.dtsi:U-Boot 设备树片段"
)
for file_info in "${required_files[@]}"; do
    file_name=$(echo "$file_info" | cut -d: -f1)
    file_desc=$(echo "$file_info" | cut -d: -f2)
    file_path="${SRC_DIR}/${file_name}"  # 直接读取仓库 xiguapi/ 目录下的文件
    check_file "${file_path}" "${file_desc}"
done
check_file "${UBOOT_MK}" "uboot-rockchip Makefile"
check_file "${ARMv8_MK}" "rockchip armv8.mk"
echo -e "✅ 核心文件检查通过"

# 6. 修改 uboot-rockchip/Makefile（不变）
echo -e "\n【3/7】修改 ${UBOOT_MK}..."
if ! safe_grep "U-Boot/xiguapi-v3-rk3568" "${UBOOT_MK}"; then
    TMP_FILE=$(mktemp)
    cat > "${TMP_FILE}" << 'EOF'
define U-Boot/xiguapi-v3-rk3568
  $(U-Boot/rk3568/Default)
  NAME:=Xiguapi V3
  UBOOT_CONFIG:=rk3568-xiguapi-v3
  BUILD_DEVICES:= \
    nlnet_xiguapi-v3
endef
  

EOF
    ed -s "${UBOOT_MK}" << EOF
/^# RK3588 boards/
-1r ${TMP_FILE}
w
q
EOF
    rm -f "${TMP_FILE}"
    echo -e "✅ 已插入官方标准定义块"
else
    echo -e "⚠️ 正确定义块已存在，跳过插入"
fi

# 7. 添加 UBOOT_TARGETS 列表项（不变）
echo -e "\n【4/7】添加 UBOOT_TARGETS 列表项..."
target_line="  xiguapi-v3-rk3568 \\"
if safe_grep "rock-3a-rk3568 \\" "${UBOOT_MK}"; then
    sed -i '/rock-3a-rk3568 \\/a \  xiguapi-v3-rk3568 \\' "${UBOOT_MK}"
elif safe_grep "rock-3b-rk3568 \\" "${UBOOT_MK}"; then
    sed -i '/rock-3b-rk3568 \\/a \  xiguapi-v3-rk3568 \\' "${UBOOT_MK}"
else
    sed -i '/^UBOOT_TARGETS :=/ s/$/ \\\n  xiguapi-v3-rk3568/' "${UBOOT_MK}"
fi
echo -e "✅ 已添加 xiguapi-v3-rk3568 到 UBOOT_TARGETS 列表"

# 8. 修改 armv8.mk 插入设备定义（不变）
echo -e "\n【5/7】修改 ${ARMv8_MK}..."
if ! safe_grep "Device/nlnet_xiguapi-v3" "${ARMv8_MK}"; then
    TMP_ARM_FILE=$(mktemp)
    cat > "${TMP_ARM_FILE}" << 'EOF'

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
    ed -s "${ARMv8_MK}" << EOF
/^include legacy.mk/
-1r ${TMP_ARM_FILE}
w
q
EOF
    rm -f "${TMP_ARM_FILE}"
    echo -e "✅ 已添加 Device/nlnet_xiguapi-v3 设备定义"
else
    echo -e "⚠️ 设备定义已存在，跳过"
fi

# 9. 复制设备树/配置文件（直接从仓库 xiguapi/ 目录复制，无需提前复制到 workdir）
echo -e "\n【6/7】部署设备树/UBOOT 文件..."
mkdir -p "$(dirname "${DTS_DEST}")" && cp -f "${SRC_DIR}/rk3568-xiguapi-v3.dts" "${DTS_DEST}" && echo -e "✅ 复制主设备树成功"
mkdir -p "$(dirname "${DEFCONFIG_DEST}")" && cp -f "${SRC_DIR}/rk3568-xiguapi-v3_defconfig" "${DEFCONFIG_DEST}" && echo -e "✅ 复制 U-Boot 配置成功"
mkdir -p "$(dirname "${UBOOT_DTSI_DEST}")" && cp -f "${SRC_DIR}/rk3568-xiguapi-v3-u-boot.dtsi" "${UBOOT_DTSI_DEST}" && echo -e "✅ 复制 U-Boot 设备树片段成功"
mkdir -p "$(dirname "${UBOOT_UPSTREAM_DTS_DEST}")" && cp -f "${SRC_DIR}/rk3568-xiguapi-v3.dts" "${UBOOT_UPSTREAM_DTS_DEST}" && echo -e "✅ 复制 upstream 设备树成功"

# 10. 验证修改结果（不变）
echo -e "\n【7/7】验证修改结果..."
verify_pass=0

if safe_grep "U-Boot/xiguapi-v3-rk3568" "${UBOOT_MK}" && safe_grep "UBOOT_CONFIG:=rk3568-xiguapi-v3" "${UBOOT_MK}"; then
    echo -e "✅ 定义块内容正确（官方标准）"
else
    echo -e "❌ 定义块内容错误"
    verify_pass=1
fi

if grep -B 10 "# RK3588 boards" "${UBOOT_MK}" | grep -q -F "U-Boot/xiguapi-v3-rk3568"; then
    echo -e "✅ 定义块位置正确（RK3588 上方）"
else
    echo -e "❌ 定义块位置错误"
    verify_pass=1
fi

if safe_grep "${target_line}" "${UBOOT_MK}"; then
    echo -e "✅ UBOOT_TARGETS 列表项正确"
else
    echo -e "❌ UBOOT_TARGETS 列表项缺失"
    verify_pass=1
fi

if safe_grep "Device/nlnet_xiguapi-v3" "${ARMv8_MK}"; then
    echo -e "✅ armv8.mk 设备定义正确"
else
    echo -e "❌ armv8.mk 设备定义缺失"
    verify_pass=1
fi

if [ -f "${DTS_DEST}" ] && [ -f "${DEFCONFIG_DEST}" ] && [ -f "${UBOOT_DTSI_DEST}" ] && [ -f "${UBOOT_UPSTREAM_DTS_DEST}" ]; then
    echo -e "✅ 所有设备树/配置文件复制完成"
else
    echo -e "❌ 部分文件复制失败"
    verify_pass=1
fi

if [ ${verify_pass} -eq 0 ]; then
    echo -e "\n🎉 适配100%成功！"
    echo -e "-------------------------------------------------"
    grep -B 5 -A 7 "# RK3588 boards" "${UBOOT_MK}"
    echo -e "-------------------------------------------------"
    echo -e "✅ 所有验证项通过，可开始编译 OpenWRT！"
else
    echo -e "\n❌ 适配失败，请根据以上错误提示排查问题！"
    exit 1
fi

exit 0
