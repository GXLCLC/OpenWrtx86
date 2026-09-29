#!/bin/bash
# ============================================================================
# system-settings.sh —— 固件系统默认配置(独立脚本)
#
# 用途: 集中管理固件的系统级默认设置(LAN IP、后台登录密码、主机名等),
#       后续想要修改这些信息, 只需修改本文件, 无需改动其他任何代码;
#       工作流编译前会自动拉取并执行本脚本, 将设置注入固件
#       (首次开机时自动生效, 详见脚本下半部分的注入逻辑)。
#
# 注意: Release 发布说明中的 LAN IP / 账号密码 / 主机名信息,
#       也是直接从本脚本读取的, 改这里即可全处同步, 无需二次修改。
# ============================================================================

# ----------------------------------------------------------------------------
# ↓↓↓ 可自行修改的配置项 ↓↓↓
# ----------------------------------------------------------------------------

# LAN 口 IP 地址与子网掩码(浏览器访问该地址进入固件管理后台)
LAN_IP="192.168.1.1"
LAN_NETMASK="255.255.255.0"

# 后台登录账号与密码(LuCI 管理页面与 SSH 登录共用此账号密码)
# 安全提示: 固件刷入后请尽快修改为强密码
LOGIN_USER="root"
LOGIN_PASS="password"

# 主机名(路由器在网络中显示的名称)
HOSTNAME="ImmortalWrt"

# 时区与区域名称
TIMEZONE="CST-8"
ZONENAME="Asia/Shanghai"

# 系统默认 LuCI 主题(ARGON 主题)
# THEME_URLBASE 为主题的静态资源路径, THEME_NAME 为主题显示名称
THEME_URLBASE="/luci-static/argon"
THEME_NAME="Argon"

# ----------------------------------------------------------------------------
# ↑↑↑ 可自行修改的配置项 ↑↑↑
# ----------------------------------------------------------------------------

# ----------------------------------------------------------------------------
# 以下为注入逻辑(无需修改):
# 直接执行本脚本时, 自动在源码树生成 uci-defaults 初始化脚本,
# 固件首次开机时自动应用上述设置, 应用成功后该脚本自删;
# 被 source 引用时(如 gen-release-info.sh), 仅提供上方变量, 不执行注入
# ----------------------------------------------------------------------------
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    # 仅在直接执行时运行注入逻辑
    OPENWRT_DIR="${OPENWRT_DIR:-openwrt}"
    UCI_DEFAULTS_FILE="$OPENWRT_DIR/files/etc/uci-defaults/99-custom-settings"

    mkdir -p "$(dirname "$UCI_DEFAULTS_FILE")"

    # 生成首次开机初始化脚本(uci-defaults 机制: 首次开机执行, 成功后自删)
    cat > "$UCI_DEFAULTS_FILE" <<SETTINGS_EOF
#!/bin/sh
# 本文件由 scripts/system-settings.sh 自动生成, 请勿直接修改;
# 如需调整 LAN IP / 登录密码 / 主机名等, 请修改仓库中的 scripts/system-settings.sh

# 设置 LAN 口 IP 与子网掩码
uci set network.lan.ipaddr='$LAN_IP'
uci set network.lan.netmask='$LAN_NETMASK'
uci commit network

# 设置系统默认主题为 Argon
uci set luci.main.mediaurlbase='$THEME_URLBASE'
uci commit luci

# 设置后台登录账号密码
echo "$LOGIN_USER:$LOGIN_PASS" | chpasswd

# 设置主机名与时区
uci set system.@system[0].hostname='$HOSTNAME'
uci set system.@system[0].timezone='$TIMEZONE'
uci set system.@system[0].zonename='$ZONENAME'
uci commit system

# 正常退出(uci-defaults 要求, 非 0 退出码会导致下次开机重复执行)
exit 0
SETTINGS_EOF

    chmod +x "$UCI_DEFAULTS_FILE"
    echo "[system-settings] 系统默认配置已注入: $UCI_DEFAULTS_FILE"
    echo "[system-settings] LAN_IP=$LAN_IP HOSTNAME=$HOSTNAME 主题=$THEME_NAME"
fi
