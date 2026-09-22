#!/bin/bash
# 共用的路径推导逻辑（不写死卷路径，兼容不同 fnOS 部署布局）
#
# 用法：source "$(dirname "$0")/_lib.sh"
# 导出：APP_NAME APP_DIR DATA_DIR LOG

# --- 数据目录推导 ---
# 优先 TRIM_PKGVAR（fnOS 注入）；否则从 home 软链或 APP_DIR 推导卷，不写死 /vol4
opencode_resolve_paths() {
    APP_NAME="${TRIM_APPNAME:-opencode}"
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
#   fnOS 传 TRIM_APPDEST=/vol4/@appcenter/opencode → bin 直接在 ${APP_DIR}/bin
#   旧版/部分版本 TRIM_APPDEST=/var/apps/opencode    → bin 在 ${APP_DIR}/target/bin
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

# --- 凭据与桌面入口 ---
# v2 默认强制鉴权，而飞牛桌面用 <iframe> 嵌入、发不了 Basic 头，
# 只能靠 app/ui/config 的 url 里带 ?auth_token=<base64(user:pass)>。
# 该 url 在打包时是静态的，因此安装时必须把用户填的账号密码写回 ui/config。
opencode_cred_file() {
    printf '%s' "${DATA_DIR}/credentials"
}

# 生成 base64("user:pass")
opencode_make_token() {
    printf '%s:' "$1" | cat - <(printf '%s' "$2") | base64 | tr -d "\n"
}

# 把 token 写进 app/ui/config（桌面入口），失败不阻断安装
opencode_apply_token() {
    local token="$1" cfg=""
    # 安全约束（2026-09-22 踩坑）：
    #   早期实现用 ${REAL_APP_DIR}/${APP_DIR} 拼路径，当 TRIM_APPDEST 未传、
    #   /var/apps/<app> 又不存在时，路径会退化并可能命中【其它应用】的 ui/config，
    #   把本应用的 token 写进别人的桌面入口（实测污染了 dsh 的 ui/config）。
    #   因此这里要求路径必须解析到本应用自己的目录，且必须能找到 opencode 二进制。
    local cand=""
    for c in "${REAL_APP_DIR}/ui/config" "${APP_DIR}/ui/config" "${APP_DIR}/target/ui/config"; do
        [ -f "$c" ] || continue
        local real; real="$(readlink -f "$c" 2>/dev/null || printf '%s' "$c")"
        local realdir; realdir="$(dirname "$(dirname "$real")")"
        # 该目录必须真的装着本应用的引擎，否则说明路径找错了（可能命中别的应用）
        if [ ! -x "${realdir}/bin/opencode" ]; then
            echo "WARN: 跳过（不是本应用的 ui/config）: $real" >&2
            continue
        fi
        # 且归一化路径必须与本应用目录一致（防止软链把别人的目录指进来）
        local want; want="$(readlink -f "${REAL_APP_DIR}" 2>/dev/null || printf '%s' "${REAL_APP_DIR}")"
        if [ "$realdir" != "$want" ]; then
            echo "WARN: 跳过（app 目录不符，期望 $want 实为 $realdir）" >&2
            continue
        fi
        cfg="$c"
        break
    done
    [ -n "$cfg" ] || { echo "WARN: 未找到本应用的 ui/config，跳过 token 注入" >&2; return 0; }

    if command -v python3 >/dev/null 2>&1; then
        python3 - "$cfg" "$token" <<'PYEOF'
import json, sys
cfg_path, token = sys.argv[1], sys.argv[2]
with open(cfg_path, encoding="utf-8") as f:
    data = json.load(f)
urls = data.get(".url", {})
for key, entry in urls.items():
    # 去掉已有的 auth_token，再拼上新的
    base = entry.get("url", "/").split("?")[0]
    entry["url"] = base + "?auth_token=" + token
with open(cfg_path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write(chr(10))
print("token applied to " + cfg_path)
PYEOF
    else
        # 无 python3 时的兜底：直接替换 url 字段
        sed -i "s#\(\"url\"[[:space:]]*:[[:space:]]*\"\)/\?[^\"]*\"#\1/?auth_token=${token}\"#" "$cfg" 2>/dev/null || true
    fi
}

# 读取用户填的向导变量，落盘为 credentials（首次安装写入；升级时保留旧值）
# 支持传入：opencode_save_credentials <默认用户> <默认密码>
opencode_save_credentials() {
    local def_user="${1:-opencode}" def_pass="${2:-}"
    local cred; cred="$(opencode_cred_file)"
    # 用户名固定为 opencode —— 引擎硬编码（packages/server/src/auth.ts 里 username: "opencode"），
    # 允许用户改会导致 token 与引擎期望不符、整站 401，故此处强制覆盖。
    local user="opencode"
    local pass="${wizard_auth_password:-}"

    # 向导没填：沿用已有凭据；没有则用默认值（密码为空时自动生成）
    if [ -z "$user" ] && [ -f "$cred" ]; then user="$(sed -n "s/^user=//p" "$cred" | head -1)"; fi
    if [ -z "$pass" ] && [ -f "$cred" ]; then pass="$(sed -n "s/^pass=//p" "$cred" | head -1)"; fi
    [ -n "$user" ] || user="$def_user"
    if [ -z "$pass" ]; then
        pass="$(head -c 18 /dev/urandom | base64 | tr -d "=+/" | cut -c1-20)"
        echo "INFO: 未填写密码，已自动生成随机密码" >&2
    fi

    mkdir -p "$(dirname "$cred")" 2>/dev/null || true
    ( umask 077; printf 'user=%s\npass=%s\n' "$user" "$pass" > "$cred" ) 2>/dev/null || true
    printf '%s\n%s\n' "$user" "$pass"
}
# ── 免密模式（no-auth）──────────────────────────────────────────────────────
# 引擎侧由 OPENCODE_DISABLE_AUTH=1 控制：置位后 routes 走 ServerAuth.Config.layer，
# 完全不做鉴权，桌面 iframe 无需任何 token 即可打开。
# 这里用 DATA_DIR 下的标记文件记录用户选择，避免每次都读环境变量。
opencode_noauth_flag() { printf '%s/noauth' "${DATA_DIR}"; }

opencode_noauth_enabled() {
    # 优先级：环境变量 > 标记文件
    case "${OPENCODE_DISABLE_AUTH:-}" in
        1|true|yes|on) return 0 ;;
    esac
    [ -f "$(opencode_noauth_flag)" ]
}

opencode_enable_noauth() {
    mkdir -p "${DATA_DIR}" 2>/dev/null || true
    ( umask 022; : > "$(opencode_noauth_flag)" ) 2>/dev/null || true
}

opencode_disable_noauth() {
    rm -f "$(opencode_noauth_flag)" 2>/dev/null || true
}

# 免密时把桌面入口的 ?auth_token= 去掉，避免带一个无意义的 token
opencode_clear_token() {
    local cfg
    for cfg in "${REAL_APP_DIR}/ui/config" "${APP_DIR}/ui/config" "${APP_DIR}/target/ui/config"; do
        [ -f "$cfg" ] || continue
        local realdir
        realdir="$(dirname "$(dirname "$(readlink -f "$cfg")")")"
        [ -x "${realdir}/bin/opencode" ] || continue
        [ "$realdir" = "$(readlink -f "${REAL_APP_DIR}")" ] || continue
        python3 -c "
import json, sys
p = sys.argv[1]
d = json.load(open(p))
for v in d.get('.url', {}).values():
    if isinstance(v, dict) and 'url' in v:
        v['url'] = '/'
json.dump(d, open(p, 'w'), ensure_ascii=False, indent=2)
" "$cfg" 2>/dev/null && return 0
    done
    return 0
}