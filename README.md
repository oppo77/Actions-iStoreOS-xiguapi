## 适用于 **西瓜皮V3** 设备的定制iStoreOS固件。

#### 西瓜皮官方🐧群318407767
> 此项目未半成品未适配完成。🈶bug或者需要新增功能欢迎提交

[![iStore 使用文档](https://img.shields.io/badge/使用文档-iStore%20OS-brightgreen?style=flat-square)](https://doc.linkease.com/zh/guide/istoreos)
[![最新固件下载](https://img.shields.io/github/v/release/xiaomeng9597/Actions-iStoreOS-RK35XX?style=flat-square&label=最新固件下载)](../../releases/latest)


---

## 🖥️ 设备配置

| 项目 | 规格 |
|------|------|
| **厂商** | nlnet |
| **型号** | xiguapi-v3（新版本） |
| **CPU** | 瑞芯微 RK3568 四核64位Cortex-A55 Mail-G52 |
| **电源** | RK817-5（兼容rk808h）DC 12V 1.5A |
| **ROM** | 32GB eMMC（闪迪 SanDisk SDINBDA4-32G） |
| **RAM** | 4GB LPDDR4X（长鑫 CXMT CXDB5CCBM-MK-A） |
| **网络**  | 2个 RTL8211F 千兆网口 |
| **扩展**  | 2个 MINIPCIE 接口（带5V电源PA供电）<br>1个 M.2 B Key接口（5G模块）<br>1个 M.2 E Key接口（WiFi网卡）<br>1个 USB3.0 A口（OTG接口）<br>1个 TF卡槽<br>1个 SIM卡槽 |
| **视频口**  | 1个 HDMI2.0 接口 |
|**其他接口**| 1个 FPC SPI/I2C 显示屏接口<br>1个 5V风扇接口（MX1.25 4pin PWM调速）<br>1个 DC 5521电源插头（5V-18V 1-3A） |
| **指示灯** | 3个 LED指示灯（状态、网络、电源） |
| **按钮** | 刷机键、重启键、恢复键 |

---


### ⚙️ 固件配置

|  **编译周期**  | `北京时间每日 `0:00` 自动编译` |
|------|------|
| **版本** | `istoreos24.10.2` |
| **管理地址** | `http://192.168.100.1` 或 `http://iStoreOS.lan/` |
| **账户** | `root` |
| **密码** | `password` |



### 🌐 网络接口说明

- 一个网口默认作为 **WAN** 口，其余均为 **LAN** 口
- 如需修改 LAN 口 IP：
  - Web 首页 → "内网设置"
  - 或使用 `quickstart` 命令

---

## 📊 适配状态

### ✅ 已完成
- 制作设备树
- 基础适配

### 🚀 计划中
- 添加wifi启动脚本
- 精简配置
- 小屏幕适配

---

### ⚠️ 添加自定义插件（重要）

将自定义插件配置项添加到 **`configfiles/config_data.txt`** 文件中。

> **说明**："Sync Files" 工作流会自动获取官方t68m的config，然后将 `configfiles/config_data.txt` 与 `config` 相结合，在 armv8/ 路径生成 `.config`。


---

## 支持一杯☕
> 零代码小白第一次制作固件，花了很多时间精力，觉得不错可以支持一下后续维护更卖力🥺🥺
<div align="center">
  <img src="https://raw.githubusercontent.com/oppo77/Actions-iStoreOS-xiguapi/main/other/skm.png" 
       alt="vx" 
       title="可选的标题，鼠标悬停时显示" 
       width="800" /> <!-- 宽度可按需修改，如 700/900 或 90% -->
</div>

## ‼️免责声明 

### **使用本固件即表示您已阅读、理解并同意以下条款：**

1.  **责任豁免**
 * 对于任何因**刷入或使用本固件**而导致的设备故障、硬件损坏、数据丢失或任何其他直接或间接损失，**项目作者及贡献者不承担任何责任**。
 * 因**使用者配置不当、操作失误**或对本固件功能的误解而产生的网络安全隐患、服务中断或数据泄露等风险，**由使用者自行承担全部后果**。
 * 本固件依赖的第三方开源项目（包括但不限于istoreos主线、各类软件包）在更新后可能引发兼容性问题或安全漏洞。**此等风险不由本项目控制，亦不在本项目的责任范围之内。**

2.  **使用者责任**
 * 您有义务在刷机前**自行备份所有重要数据和原厂固件**。
 * 您应确保在遵守所在地法律法规的前提下使用本固件及其功能。
 * 您有责任**自行评估使用本固件的风险**，并具备相应的技术能力进行故障排查。

3.  **无担保声明** 

 * 本固件按“**现状**”提供，**不提供任何形式的明示或默示担保**，包括但不限于对**适销性、特定用途适用性及不侵犯第三方权利**的担保。。


## 🙏 鸣谢

本项目的实现离不开以下优秀项目与服务的支持：

- [iStoreOS](https://github.com/istoreos/istoreos) - 固件基础
- [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt) - 自动化编译框架
- [OpenWrt](https://github.com/openwrt/openwrt) / [Lean's OpenWrt](https://github.com/coolsnowwolf/lede) - 开源系统
- [GitHub Actions](https://github.com/features/actions) - 自动化平台
- [Microsoft Azure](https://azure.microsoft.com) - 提供云资源
- [draco-china/istoreos-actions](https://github.com/draco-china/istoreos-actions) - 项目参考
- [xiaomeng9597/Actions-iStoreOS-RK35XX-24.10/](https://github.com/xiaomeng9597) 
- 以及所有相关工具与服务的开发者们


