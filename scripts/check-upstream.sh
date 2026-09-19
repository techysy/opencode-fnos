#!/usr/bin/env bash
# 上游版本检查器：比对本地 VERSION 与 OpenCode 官方最新 release。
#
# 用法：
#   bash scripts/check-upstream.sh            # 仅报告
#   bash scripts/check-upstream.sh --apply    # 有新版本时写入 VERSION 并同步 manifest
#   bash scripts/check-upstream.sh --tag      # 有新版本时额外创建本地 git tag（不推送）
#
# 依赖：curl、python3（仅用标准库）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="${UPSTREAM_REPO:-anomalyco/opencode}"

LOCAL="$(tr -d '[:space:]' < "$ROOT/VERSION" 2>/dev/null || echo "")"

echo "== 上游版本检查 =="
echo "  仓库：$REPO"
echo "  本地：${LOCAL:-（无 VERSION）}"

# 取最新 release（follow redirects：该仓库有过改名）
JSON="$(curl -fsSL --retry 3 --max-time 30 "https://api.github.com/repos/$REPO/releases/latest")" || {
    echo "ERROR: 无法访问 GitHub API（网络或限流）" >&2
    exit 1
}

LATEST="$(printf '%s' "$JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tag_name","").lstrip("v"))')"

if [ -z "$LATEST" ]; then
    echo "ERROR: 未能解析上游版本号" >&2
    exit 1
fi
echo "  上游：$LATEST"

if [ "$LOCAL" = "$LATEST" ]; then
    echo "✅ 已是最新（$LOCAL）"
    exit 0
fi

echo "🔔 发现新版本：$LOCAL → $LATEST"

APPLY=0; TAG=0
for a in "$@"; do
    [ "$a" = "--apply" ] && APPLY=1
    [ "$a" = "--tag" ] && TAG=1
done

if [ "$APPLY" = "1" ]; then
    bash "$ROOT/scripts/sync-version.sh" "$LATEST"
    echo "✓ 已更新 VERSION 与 manifest 到 $LATEST"
    echo "  下一步：提交并打 tag 触发 CI —— git commit -am \"chore: bump upstream to v$LATEST\" && git tag v$LATEST"
    if [ "$TAG" = "1" ]; then
        if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
            git -C "$ROOT" tag -f "v$LATEST" >/dev/null
            echo "✓ 已创建本地 tag v$LATEST（未推送）"
        else
            echo "WARN: 非 git 仓库，跳过打 tag" >&2
        fi
    fi
else
    echo "  提示：加 --apply 可自动更新 VERSION/manifest"
fi
