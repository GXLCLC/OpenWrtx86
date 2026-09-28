#!/bin/bash
# ============================================================================
# diy-part2.sh —— feeds 安装后的自定义修改(按需拉取第三方插件)
#
# 执行时机: feeds update && feeds install 完成后、make defconfig 之前(工作流步骤10)
# 核心规则: 仅当 LEDE 源码(package/)与已安装 feeds(feeds/)中不存在对应
#           软件包时, 才从第三方仓库拉取; 拉取时通过 git sparse-checkout
#           只克隆所需的插件目录, 不完整拉取整个仓库, 节省编译耗时
# 默认工作目录: 仓库根目录(LEDE 源码位于其下的 openwrt/ 目录)
# ============================================================================

# 任何命令出错立即终止脚本(与工作流"错误即终止"策略一致)
set -e

# LEDE 源码目录与第三方插件存放目录
OPENWRT_DIR="${OPENWRT_DIR:-openwrt}"
THIRD_PARTY_DIR="$OPENWRT_DIR/package/thirdparty"

# ----------------------------------------------------------------------------
# 第三方插件定义表
# 格式: "软件包名|插件仓库地址|仓库内插件目录(相对仓库根)"
# 处理逻辑: 逐项检查软件包是否已存在于 LEDE 源码/feeds 中,
#           存在则跳过(使用 LEDE 自带版本), 不存在才从第三方仓库拉取
# ----------------------------------------------------------------------------
THIRD_PARTY_PACKAGES=(
    # ---- EasyTier 内网穿透 ----
    # 说明: LEDE luci feed 中仅有 luci-app-easytier-next(第三方移植版),
    #       本仓库按需求使用 EasyTier 官方的 luci-app-easytier
    "luci-app-easytier|https://github.com/EasyTier/luci-app-easytier|luci-app-easytier"

    # ---- DDNSTO 远程控制(LEDE 不存在, 依赖以下两个仓库) ----
    # luci-app-ddnsto(LuCI 界面)来自 nas-packages-luci 仓库
    "luci-app-ddnsto|https://github.com/linkease/nas-packages-luci|luci/luci-app-ddnsto"
    # ddnsto(后端服务)来自 nas-packages 仓库
    "ddnsto|https://github.com/linkease/nas-packages|network/services/ddnsto"

    # ---- OFA(OpenAppFilter 应用过滤) ----
    # 说明: LEDE luci feed 自带 OFA 的 LuCI 界面(luci-app-appfilter),
    #       但其依赖的用户态后端(appfilter)与内核模块(oaf)在 LEDE 源码及
    #       feeds 中均不存在, 需从 OFA 官方仓库只拉取这两个插件目录补齐
    "appfilter|https://github.com/destan19/OpenAppFilter|open-app-filter"
    "oaf|https://github.com/destan19/OpenAppFilter|oaf"

    # ---- 备用源(当前不会触发拉取) ----
    # 以下插件当前均由 LEDE feeds 自带, 表中仅作备用:
    # 若未来 LEDE 移除对应软件包, 脚本将自动从 kenzok8 仓库按需补齐
    "smartdns|https://github.com/kenzok8/openwrt-packages|smartdns"                    # SmartDNS 后端
    "luci-app-smartdns|https://github.com/kenzok8/openwrt-packages|luci-app-smartdns"  # SmartDNS 界面
    "adguardhome|https://github.com/kenzok8/openwrt-packages|adguardhome"              # AdGuardHome 后端
    "luci-app-adguardhome|https://github.com/kenzok8/openwrt-packages|luci-app-adguardhome"  # AdGuardHome 界面
    "luci-theme-argon|https://github.com/kenzok8/openwrt-packages|luci-theme-argon"    # Argon 主题
    "luci-app-argon-config|https://github.com/kenzok8/openwrt-packages|luci-app-argon-config"  # Argon 主题设置
)

# ----------------------------------------------------------------------------
# 函数: 检查软件包是否已存在于 LEDE 源码或已安装的 feeds 中
# 参数: $1 = 软件包名(与包目录名一致, 精确匹配)
# 返回: 0 = 存在(无需第三方拉取), 1 = 不存在(需要第三方拉取)
# 判定规则:
#   1. 排除第三方插件目录(thirdparty), 避免已拉取的包干扰判定;
#   2. 匹配到的目录必须包含 Makefile 才是真正的软件包目录,
#      避免误匹配插件包内部的同名子目录(如 luasrc/view/<包名>)
# ----------------------------------------------------------------------------
package_exists_in_lede() {
    local dir
    while IFS= read -r dir; do
        [ -f "$dir/Makefile" ] && return 0
    done < <(find "$OPENWRT_DIR/package" "$OPENWRT_DIR/feeds" \
             -maxdepth 5 -type d -name "$1" -not -path "*thirdparty*" -print 2>/dev/null)
    return 1
}

# ----------------------------------------------------------------------------
# 函数: 从第三方仓库只克隆指定插件目录(sparse-checkout 局部克隆)
# 参数: $1 = 软件包名, $2 = 仓库地址, $3 = 仓库内插件目录
# 说明: 使用 --depth 1(浅克隆) + --sparse(稀疏检出) + sparse-checkout set,
#       仅下载该插件目录的文件内容, 避免完整拉取整个仓库
# ----------------------------------------------------------------------------
fetch_thirdparty_package() {
    local pkg="$1" repo="$2" dir="$3"
    local dest="$THIRD_PARTY_DIR/$pkg"

    # 已拉取过则直接跳过(支持缓存恢复后的重复执行)
    if [ -d "$dest" ]; then
        echo "  [跳过] $pkg 已存在于 $dest"
        return 0
    fi

    local tmp
    tmp="$(mktemp -d)"
    echo "  [拉取] $pkg <- $repo (仅克隆插件目录: $dir)"

    # 浅克隆 + 稀疏检出(此时仅检出仓库根目录, 不下载多余文件)
    if ! git clone --depth 1 --filter=blob:none --sparse "$repo" "$tmp" > /dev/null 2>&1; then
        echo "  [错误] 克隆仓库失败: $repo"
        rm -rf "$tmp"
        return 1
    fi
    # 设置稀疏检出目录: 只检出目标插件目录
    if ! (cd "$tmp" && git sparse-checkout set "$dir" --cone) > /dev/null 2>&1; then
        echo "  [错误] 设置稀疏检出目录失败: $dir"
        rm -rf "$tmp"
        return 1
    fi
    # 校验插件目录已成功检出
    if [ ! -d "$tmp/$dir" ]; then
        echo "  [错误] 仓库中不存在插件目录: $repo -> $dir"
        rm -rf "$tmp"
        return 1
    fi

    # 复制插件目录到源码树的第三方插件目录
    mkdir -p "$THIRD_PARTY_DIR"
    cp -r "$tmp/$dir" "$dest"
    rm -rf "$tmp"
    echo "  [完成] $pkg -> $dest"
}

# ----------------------------------------------------------------------------
# 主流程: 逐项检查并按需拉取第三方插件
# ----------------------------------------------------------------------------
mkdir -p "$THIRD_PARTY_DIR"
echo "[diy-part2] 开始按需拉取第三方插件(仅补齐 LEDE 缺失的软件包)..."

for entry in "${THIRD_PARTY_PACKAGES[@]}"; do
    # 解析定义表字段: 包名|仓库地址|插件目录
    pkg="${entry%%|*}"
    rest="${entry#*|}"
    repo="${rest%%|*}"
    dir="${rest#*|}"

    if package_exists_in_lede "$pkg"; then
        echo "  [LEDE自带] $pkg 无需从第三方拉取"
    else
        fetch_thirdparty_package "$pkg" "$repo" "$dir"
    fi
done

echo "[diy-part2] 第三方插件准备完成, 当前第三方插件目录内容:"
ls -1 "$THIRD_PARTY_DIR" 2>/dev/null || echo "  (无第三方插件)"
