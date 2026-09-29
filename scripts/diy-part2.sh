#!/bin/bash
# ============================================================================
# diy-part2.sh —— feeds 安装后的自定义修改(按需拉取第三方插件)
#
# 执行时机: feeds update && feeds install 完成后、注入系统配置之前
# 核心规则: 优先使用 ImmortalWrt 源码/feeds 自带软件包;
#           仅当 ImmortalWrt 中不存在对应软件包时, 才从第三方仓库通过
#           git sparse-checkout 浅克隆所需的插件目录(不完整拉取整个仓库),
#           节省编译耗时
# 默认工作目录: 仓库根目录(ImmortalWrt 源码位于其下的 openwrt/ 目录)
# ============================================================================

# 任何命令出错立即终止脚本(与工作流"错误即终止"策略一致)
set -e

# ImmortalWrt 源码目录与第三方插件存放目录
OPENWRT_DIR="${OPENWRT_DIR:-openwrt}"
THIRD_PARTY_DIR="$OPENWRT_DIR/package/thirdparty"

# ----------------------------------------------------------------------------
# 第三方插件定义表
# 格式: "软件包名|插件仓库地址|仓库内插件目录(相对仓库根)|仓库分支"
# 处理逻辑: 逐项检查软件包是否已存在于 ImmortalWrt 源码/feeds 中,
#           存在则跳过(使用自带版本), 不存在才从第三方仓库浅克隆插件目录
# ----------------------------------------------------------------------------
THIRD_PARTY_PACKAGES=(
    # ---- Turbo ACC 网络加速(ImmortalWrt 无此包) ----
    # 说明: TurboAcc 官方上游为 LEDE 的 luci 仓库(openwrt-25.12 分支);
    #       其功能组件按需依赖, x86_64 平台启用"流量分载(Flow Offloading)
    #       + BBR 拥塞控制"方案, 无需 LEDE 专有内核模块, ImmortalWrt 完全兼容
    "luci-app-turboacc|https://github.com/coolsnowwolf/luci|applications/luci-app-turboacc|openwrt-25.12"

    # ---- EasyTier 去中心化内网穿透(ImmortalWrt 无前后端) ----
    # LuCI 前端(界面)与后端(主程序)同来自 EasyTier 官方仓库(main 分支),
    # 两个目录都需要拉取
    "luci-app-easytier|https://github.com/EasyTier/luci-app-easytier|luci-app-easytier|main"
    "easytier|https://github.com/EasyTier/luci-app-easytier|easytier|main"

    # ---- DDNSTO 远程控制(ImmortalWrt 无前后端, 依赖以下两个仓库) ----
    # luci-app-ddnsto(LuCI 前端)来自 nas-packages-luci 仓库(main 分支)
    "luci-app-ddnsto|https://github.com/linkease/nas-packages-luci|luci/luci-app-ddnsto|main"
    # ddnsto(后端服务)来自 nas-packages 仓库(master 分支)
    "ddnsto|https://github.com/linkease/nas-packages|network/services/ddnsto|master"

    # ---- OFA(OpenAppFilter 应用过滤)的 LuCI 前端 ----
    # 说明: 用户指定使用 luci-app-oaf 界面(ImmortalWrt 无此包);
    #       其依赖的用户态后端 appfilter 与内核模块 kmod-oaf 由
    #       ImmortalWrt feeds 自带(open-app-filter 目录, 2026-04 版),
    #       仅需从 OFA 官方仓库拉取前端目录, 不重复拉取后端
    "luci-app-oaf|https://github.com/destan19/OpenAppFilter|luci-app-oaf|master"

    # ---- 备用源(当前不会触发拉取) ----
    # 以下插件当前均由 ImmortalWrt feeds 自带, 表中仅作备用:
    # 若未来 ImmortalWrt 移除对应软件包, 脚本将自动从 kenzok8 仓库按需补齐
    "smartdns|https://github.com/kenzok8/openwrt-packages|smartdns|master"                    # SmartDNS 后端
    "luci-app-smartdns|https://github.com/kenzok8/openwrt-packages|luci-app-smartdns|master"  # SmartDNS 界面
    "adguardhome|https://github.com/kenzok8/openwrt-packages|adguardhome|master"              # AdGuardHome 后端
    "luci-app-adguardhome|https://github.com/kenzok8/openwrt-packages|luci-app-adguardhome|master"  # AdGuardHome 界面
    "luci-theme-argon|https://github.com/kenzok8/openwrt-packages|luci-theme-argon|master"    # Argon 主题
    "luci-app-argon-config|https://github.com/kenzok8/openwrt-packages|luci-app-argon-config|master"  # Argon 主题设置
)

# ----------------------------------------------------------------------------
# 函数: 检查软件包是否已存在于 ImmortalWrt 源码或已安装的 feeds 中
# 参数: $1 = 软件包名(精确匹配)
# 返回: 0 = 存在(无需第三方拉取), 1 = 不存在(需要第三方拉取)
# 判定规则(双重匹配, 任一命中即视为已存在):
#   1. 目录名匹配: 存在与包名同名的目录且包含 Makefile
#      (排除第三方目录 thirdparty, 并要求目录含 Makefile,
#       避免误匹配插件包内部的同名子目录, 如 luasrc/view/<包名>);
#   2. 包定义匹配: Makefile 中存在该包的定义
#      (define Package/<包名> / define KernelPackage/<包名> /
#       call BuildPackage,<包名> / call KernelPackage,<包名>)
#      用于兜住"目录名与包名不一致"的情况 —— 例如 ImmortalWrt feeds 自带的
#      open-app-filter 目录内同时定义了 appfilter 与 kmod-oaf 两个包,
#      仅按目录名查找会漏判, 导致第三方重复拉取同名包,
#      引发 Kconfig 递归依赖与内核包编译失败
# ----------------------------------------------------------------------------
package_exists_in_lede() {
    local pkg="$1" dir
    # 方式1: 目录名匹配(目录须含 Makefile 才是真正的软件包目录)
    while IFS= read -r dir; do
        [ -f "$dir/Makefile" ] && return 0
    done < <(find "$OPENWRT_DIR/package" "$OPENWRT_DIR/feeds" \
             -maxdepth 5 -type d -name "$pkg" -not -path "*thirdparty*" -print 2>/dev/null)
    # 方式2: Makefile 包定义匹配(排除第三方目录与 feeds 的 .git 目录)
    grep -rqsE \
        "^define (Kernel)?Package/$pkg(/|\$)|\((call (Build|Kernel)Package,$pkg)\)" \
        --include="Makefile" --include="*.mk" \
        --exclude-dir=thirdparty --exclude-dir=.git \
        "$OPENWRT_DIR/package" "$OPENWRT_DIR/feeds" 2>/dev/null && return 0
    return 1
}

# ----------------------------------------------------------------------------
# 函数: 从第三方仓库浅克隆指定插件目录(sparse-checkout 局部克隆)
# 参数: $1 = 软件包名, $2 = 仓库地址, $3 = 仓库内插件目录, $4 = 仓库分支
# 说明: 使用 --depth 1(浅克隆) + --filter=blob:none(按需下载文件) +
#       --sparse(稀疏检出) + sparse-checkout set, 仅下载该插件目录的
#       文件内容, 避免完整拉取整个仓库, 节省编译耗时
# ----------------------------------------------------------------------------
fetch_thirdparty_package() {
    local pkg="$1" repo="$2" dir="$3" branch="$4"
    local dest="$THIRD_PARTY_DIR/$pkg"

    # 已拉取过则直接跳过(支持缓存恢复后的重复执行)
    if [ -d "$dest" ]; then
        echo "  [跳过] $pkg 已存在于 $dest"
        return 0
    fi

    local tmp
    tmp="$(mktemp -d)"
    echo "  [拉取] $pkg <- $repo (分支: $branch, 仅克隆插件目录: $dir)"

    # 浅克隆指定分支 + 稀疏检出(此时仅检出仓库根目录, 不下载多余文件)
    if ! git clone --depth 1 --filter=blob:none --sparse -b "$branch" "$repo" "$tmp" > /dev/null 2>&1; then
        echo "  [错误] 克隆仓库失败: $repo (分支: $branch)"
        rm -rf "$tmp"
        return 1
    fi
    # 设置稀疏检出目录: 只检出目标插件目录
    if ! (cd "$tmp" && git sparse-checkout set "$dir" --cone) > /dev/null 2>&1; then
        echo "  [错误] 设置稀疏检出目录失败: $dir"
        rm -rf "$tmp"
        return 1
    fi
    # 校验插件目录与 Makefile 已成功检出(防止拉到空目录)
    if [ ! -f "$tmp/$dir/Makefile" ]; then
        echo "  [错误] 仓库中不存在插件目录或缺少 Makefile: $repo -> $dir"
        rm -rf "$tmp"
        return 1
    fi

    # 复制插件目录到源码树的第三方插件目录
    mkdir -p "$THIRD_PARTY_DIR"
    cp -r "$tmp/$dir" "$dest"
    rm -rf "$tmp"

    # 适配 Makefile 的 luci.mk 引用路径:
    # 部分 luci feed 仓库的 Makefile 使用相对路径引用 include ../../luci.mk,
    # 拷贝到第三方目录后相对路径断裂, 包定义失效(会被 defconfig 静默丢弃);
    # 统一改写为绝对引用 $(TOPDIR)/feeds/luci/luci.mk(ImmortalWrt feeds 自带)
    if [ -f "$dest/Makefile" ] && grep -q 'include \.\./\.\./luci\.mk' "$dest/Makefile"; then
        sed -i 's|include \.\./\.\./luci\.mk|include $(TOPDIR)/feeds/luci/luci.mk|' "$dest/Makefile"
        echo "  [适配] $pkg: 已将 Makefile 的 luci.mk 引用改为绝对路径"
    fi
    echo "  [完成] $pkg -> $dest"
}

# ----------------------------------------------------------------------------
# 主流程: 逐项检查并按需拉取第三方插件
# ----------------------------------------------------------------------------
mkdir -p "$THIRD_PARTY_DIR"
echo "[diy-part2] 开始按需拉取第三方插件(优先使用 ImmortalWrt 自带软件包)..."

for entry in "${THIRD_PARTY_PACKAGES[@]}"; do
    # 解析定义表字段: 包名|仓库地址|插件目录|分支
    pkg="${entry%%|*}"; rest="${entry#*|}"
    repo="${rest%%|*}"; rest="${rest#*|}"
    dir="${rest%%|*}"
    branch="${rest#*|}"

    if package_exists_in_lede "$pkg"; then
        echo "  [自带] $pkg 无需从第三方拉取(使用 ImmortalWrt 版本)"
    else
        fetch_thirdparty_package "$pkg" "$repo" "$dir" "$branch"
    fi
done

echo "[diy-part2] 第三方插件准备完成, 本次实际拉取的第三方插件:"
ls -1 "$THIRD_PARTY_DIR" 2>/dev/null || echo "  (无)"
