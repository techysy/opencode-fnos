#!/usr/bin/env bash
# 上游版本检查器：比对本地 VERSION 与 OpenCode 官方最新版本。
#
# 注意：上游 v2 起「只打 tag、不建 release」，因此不能只看 releases API。
#       本脚本同时查询 tags，取两者中较高的版本。
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

# 分别取 releases 与 tags，取较高的正式版本号。
# - releases/latest：v1 时代有 release
# - tags：v2 起只打 tag（形如 v2.0.12），且仓库有大量子项目 tag（vscode-* 等），需过滤
API="https://api.github.com/repos/$REPO"

REL_JSON="$(curl -fsSL --retry 3 --max-time 45 "$API/releases/latest" 2>/dev/null || echo '{}')"
TAG_JSON="$(curl -fsSL --retry 3 --max-time 45 "$API/tags?per_page=100" 2>/dev/null || echo '[]')"

LATEST="$(python3 - "$REL_JSON" "$TAG_JSON" <<'PYEOF'
import json, re, sys

def parse(raw, default):
    try:
        return json.loads(raw)
    except Exception:
        return default

rel = parse(sys.argv[1], {})
tags = parse(sys.argv[2], [])

cands = []
# release 的 tag_name
if isinstance(rel, dict) and rel.get("tag_name"):
    cands.append(rel["tag_name"])
# tags 列表：只接受严格的 vX.Y.Z（排除 vscode-v0.0.13 之类）
if isinstance(tags, list):
    for t in tags:
        name = t.get("name", "") if isinstance(t, dict) else ""
        if re.fullmatch(r"v\d+\.\d+\.\d+", name):
            cands.append(name)

if not cands:
    print("")
    sys.exit(0)

def key(v):
    return tuple(int(x) for x in v.lstrip("v").split("."))

best = max((c for c in cands), key=key)
print(best.lstrip("v"))
PYEOF
)"

if [ -z "$LATEST" ]; then
    echo "ERROR: 未能解析上游版本号（网络或限流？）" >&2
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
