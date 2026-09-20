#!/bin/bash
# 共用的路径推导逻辑（不写死卷路径，兼容不同 fnOS 部署布局）
#
# 用法：source "$(dirname "$0")/_lib.sh"
# 导出：APP_NAME APP_DIR DATA_DIR LOG

# --- 数据目录推导 ---
# 优先 TRIM_PKGVAR（fnOS 注入）；否则从 home 软链或 APP_DIR 推导卷，不写死 /vol4
opencode_resolve_paths() {
    APP_NAME="${TRIM_APPNAME:-oc}"
    APP_DIR="${TRIM_APPDEST:-/var/apps/${APP_NAME}}"

    if [ -n "${TRIM_PKGVAR:-}" ]; then
        DATA_DIR="${TRIM_PKGVAR}"
    else
        local app_home="" app_vol=""
        if [ -L "${APP_DIR}/home" ]; then
            app_home="$(readlink -f "${APP_DIR}/home" 2>/dev/null || true)"
            app_vol="$(printf '%s' "${app_home}" | sed -n 's#^\(/vol[^/]*\)/.*#\1#p')"
        fi
        if [ -z "${app_vol}" ]; then
            app_vol="$(printf '%s' "${APP_DIR}" | sed -n 's#^\(/vol[^/]*\)/.*#\1#p')"
        fi
        if [ -n "${app_vol}" ]; then
            DATA_DIR="${app_vol}/@appdata/${APP_NAME}"
        else
            DATA_DIR="${APP_DIR}/var"
        fi
    fi

    LOG="${DATA_DIR}/oc.log"
    export APP_NAME APP_DIR DATA_DIR LOG
}

# --- 兼容两种部署布局 ---
#   fnOS 传 TRIM_APPDEST=/vol4/@appcenter/oc → bin 直接在 ${APP_DIR}/bin
#   旧版/部分版本 TRIM_APPDEST=/var/apps/oc    → bin 在 ${APP_DIR}/target/bin
opencode_resolve_appdir() {
    if [ -d "${APP_DIR}/bin" ]; then
        REAL_APP_DIR="${APP_DIR}"
    elif [ -d "${APP_DIR}/target/bin" ]; then
        REAL_APP_DIR="${APP_DIR}/target"
    else
        REAL_APP_DIR="${APP_DIR}"
    fi
    export REAL_APP_DIR
}

# --- XDG 目录隔离 ---
# OpenCode 默认写入 $HOME/.local/share/opencode，在 NAS 上往往不可写
# （应用以独立用户运行、家目录受限）。这里显式指向应用数据目录。
opencode_resolve_xdg() {
    export OPENCODE_HOME="${DATA_DIR}"
    export XDG_DATA_HOME="${DATA_DIR}/share"
    export XDG_CONFIG_HOME="${DATA_DIR}/config"
    export XDG_CACHE_HOME="${DATA_DIR}/cache"
    export XDG_STATE_HOME="${DATA_DIR}/state"
    mkdir -p "${XDG_DATA_HOME}" "${XDG_CONFIG_HOME}" "${XDG_CACHE_HOME}" "${XDG_STATE_HOME}" 2>/dev/null || true
}
