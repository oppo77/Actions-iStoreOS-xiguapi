#!/bin/sh
# /usr/local/bin/setup_wifi_universal.sh
# 基于已知硬件路径的预设WiFi配置脚本（针对 xiguapi-v3 + MT7916）
# 此版本放弃复杂的动态探测，采用已验证的稳定配置。

LOG_FILE="/tmp/wifi_preset_setup.log"
exec > "$LOG_FILE" 2>&1
set -x

echo "=== $(date) 开始应用预设WiFi配置 ==="

# ========== 预设配置参数 (可根据需要修改) ==========
SSID="zzXGP"
ENCRYPTION="psk2+ccmp"
WIFI_KEY="xgpxgpxgp"
COUNTRY="CN"        # 国家码，CN为中国
CHAN_2G="6"         # 2.4GHz推荐信道：1, 6, 11
CHAN_5G="40"        # 5GHz信道（CN允许：36,40,44,48,149,153,157,161,165）
# =================================================

# ========== 核心：硬件路径 (来自你当前运行的系统，已验证可用) ==========
# 这些路径直接从你设备的 `uci show wireless` 输出中提取
RADIO0_PATH="3c0400000.pcie/pci0001:10/0001:10:00.0/0001:11:00.0"
RADIO1_PATH="3c0400000.pcie/pci0001:10/0001:10:00.0/0001:11:00.0+1"
# ======================================================================

echo "使用预设路径:"
echo "  radio0.path = $RADIO0_PATH"
echo "  radio1.path = $RADIO1_PATH"

# 1. 清理旧的动态配置（与之前逻辑一致，安全删除）
for radio_section in $(uci show wireless 2>/dev/null | grep -o "wireless\.radio[0-9]*" | sort -u); do
    if uci get "${radio_section}.type" 2>/dev/null | grep -q "mac80211"; then
        uci delete "$radio_section"
        echo "已删除旧配置节: $radio_section"
    fi
done
# 清理默认接口节
while uci delete wireless.@wifi-iface[0] 2>/dev/null; do :; done

# 2. 应用预设配置：2.4GHz (radio0)
echo "正在配置 radio0 (2.4GHz)..."
uci set wireless.radio0=wifi-device
uci set wireless.radio0.type='mac80211'
uci set wireless.radio0.path="$RADIO0_PATH"
uci set wireless.radio0.band='2g'
uci set wireless.radio0.channel="$CHAN_2G"
uci set wireless.radio0.htmode='HE20'      # MT7916 2.4GHz支持HE模式
uci set wireless.radio0.country="$COUNTRY"
uci set wireless.radio0.disabled='0'
uci set wireless.radio0.cell_density='0'   # 可选，改善兼容性

uci set wireless.default_radio0=wifi-iface
uci set wireless.default_radio0.device='radio0'
uci set wireless.default_radio0.mode='ap'
uci set wireless.default_radio0.network='lan'
uci set wireless.default_radio0.ssid="$SSID"
uci set wireless.default_radio0.encryption="$ENCRYPTION"
uci set wireless.default_radio0.key="$WIFI_KEY"
uci set wireless.default_radio0.disabled='0'

# 3. 应用预设配置：5GHz (radio1)
echo "正在配置 radio1 (5GHz)..."
uci set wireless.radio1=wifi-device
uci set wireless.radio1.type='mac80211'
uci set wireless.radio1.path="$RADIO1_PATH"
uci set wireless.radio1.band='5g'
uci set wireless.radio1.channel="$CHAN_5G"
uci set wireless.radio1.htmode='HE80'      # MT7916 5GHz支持HE80
uci set wireless.radio1.country="$COUNTRY"
uci set wireless.radio1.disabled='0'

uci set wireless.default_radio1=wifi-iface
uci set wireless.default_radio1.device='radio1'
uci set wireless.default_radio1.mode='ap'
uci set wireless.default_radio1.network='lan'
uci set wireless.default_radio1.ssid="$SSID" # 相同SSID实现双频漫游
uci set wireless.default_radio1.encryption="$ENCRYPTION"
uci set wireless.default_radio1.key="$WIFI_KEY"
uci set wireless.default_radio1.disabled='0'

# 4. 提交配置
echo "提交UCI配置..."
if uci commit wireless; then
    echo "UCI配置提交成功"
else
    echo "错误：提交UCI配置失败"
    exit 1
fi

# 5. 重启无线服务
echo "重启无线服务..."
wifi down >/dev/null 2>&1
sleep 2
wifi up >/dev/null 2>&1
sleep 2 # 给无线接口启动留点时间

# 6. 简易验证
echo "配置完成，检查接口状态:"
if ip link show wlan0 >/dev/null 2>&1 && ip link show wlan1 >/dev/null 2>&1; then
    echo "成功: wlan0 和 wlan1 接口已启动。"
    echo "热点 SSID: $SSID"
    echo "国家码: $COUNTRY"
    echo "信道: 2.4GHz-$CHAN_2G, 5GHz-$CHAN_5G"
    exit 0
else
    echo "警告: 部分无线接口可能未启动，请检查日志。"
    # 不返回错误，因为配置可能部分生效
    exit 0
fi
