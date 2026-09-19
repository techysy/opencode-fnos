# 问题排查 / Troubleshooting

端口默认 **19282**，数据目录默认 **/vol4/@appdata/opencode-tui/**。
以下命令按需替换端口/目录。

## 安装相关

### 安装时提示「必须同意以上全部条款才能继续安装」

这是预期行为。本应用使用飞牛安装向导的 `checkbox` 必选类型（`required: true`），
需勾选协议才能继续。协议内容见 [`wizard/install`](wizard/install)。

### 安装后桌面图标点不开 / 页面空白

1. 检查服务是否在运行：
   ```bash
   ps -ef | grep ttyd | grep 19282
   ```
2. 检查端口是否响应：
   ```bash
   curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:19282/
   # 期望 200
   ```
3. 查看日志：
   ```bash
   tail -n 50 /vol4/@appdata/opencode-tui/opencode-tui.log
   ```
4. 手动拉起：
   ```bash
   /var/apps/opencode-tui/cmd/main restart
   ```

### 端口 19282 被占用

```bash
# 查看占用者
netstat -tlnp | grep 19282
# 或
ss -tlnp | grep 19282
```

确认无冲突后重启应用；若确实冲突，可在 `manifest` 中改 `service_port`
并重装（`cmd/main` 会自动读取 `TRIM_SERVICE_PORT`）。

### 日志里出现 `EACCES ... \.local/share/opencode`

引擎默认写入 `$HOME/.local/share/opencode`，在 NAS 上常不可写。

**正常安装不会出现此问题**：`cmd/_lib.sh` 的 `opencode_resolve_xdg()` 已把
`XDG_DATA_HOME` 等指向应用数据目录。

若你是手动直接运行引擎而报此错，请自行指定：

```bash
export XDG_DATA_HOME=/vol4/@appdata/opencode-tui/share
export XDG_CONFIG_HOME=/vol4/@appdata/opencode-tui/config
export XDG_CACHE_HOME=/vol4/@appdata/opencode-tui/cache
export XDG_STATE_HOME=/vol4/@appdata/opencode-tui/state
```

## 使用相关

### 页面能打开，但终端里没有内容 / 一直空白

ttyd 是**懒启动**：只有客户端连上来才会 fork 引擎子进程。

1. 确认 WebSocket 可用（期望 101）：
   ```bash
   curl -s -o /dev/null -w "%{http_code}\n" \
     -H "Connection: Upgrade" -H "Upgrade: websocket" \
     -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
     http://127.0.0.1:19282/ws
   ```
2. 若走反向代理，**必须**转发 WebSocket（Nginx 示例）：
   ```nginx
   location / {
       proxy_pass http://127.0.0.1:19282;
       proxy_http_version 1.1;
       proxy_set_header Upgrade $http_upgrade;
       proxy_set_header Connection "upgrade";
       proxy_read_timeout 3600s;
   }
   ```

### 复制粘贴不工作

- **HTTPS 环境**体验最佳（`navigator.clipboard` 可用）
- **HTTP 环境**浏览器可能禁用剪贴板 API，本应用已内置
  `execCommand('copy')` 兜底；若仍失败，请用鼠标选中后手动复制
- 有选区时按 `Ctrl/Cmd+C` 才会复制；**无选区**时保留 `Ctrl+C` 作为中断信号
- 右键：有选区时会直接复制

### 如何把工作目录指向我的代码仓库

```bash
sudo -u opencode-tui OPENCODE_WORKSPACE=/vol1/1000/my-project \
  /var/apps/opencode-tui/cmd/main restart
```

或编辑 `/var/apps/opencode-tui/cmd/main`，修改 `WORKSPACE` 默认值。

> 引擎拒绝把 `/` 当作项目目录，请务必指向一个具体目录。

### 数据/配置存在哪里

| 项 | 路径 |
| :--- | :--- |
| 应用数据根 | `/vol4/@appdata/opencode-tui/` |
| 工作目录 | `/vol4/@appdata/opencode-tui/workspace` |
| 配置 | `/vol4/@appdata/opencode-tui/config` |
| 数据 | `/vol4/@appdata/opencode-tui/share` |
| 缓存 | `/vol4/@appdata/opencode-tui/cache` |
| 状态 | `/vol4/@appdata/opencode-tui/state` |
| 日志 | `/vol4/@appdata/opencode-tui/opencode-tui.log` |

## 构建相关

### `bun install` 报 `AccessDenied accessing temporary directory`

bun 的临时目录不可写。指定一个可写目录：

```bash
export BUN_TMPDIR=/tmp/bun-tmp
mkdir -p "$BUN_TMPDIR"
``

### 构建时报 `fatal: not a git repository`

上游构建脚本会执行 `git branch --show-current` 取渠道名。
用 tarball（而非 `git clone`）获取源码时没有 `.git`，需补一个：

```bash
cd <源码目录> && git init -q .
```

或直接设置 `OPENCODE_CHANNEL=local OPENCODE_VERSION=local` 跳过自动探测
（`scripts/build.sh` 与 CI 均已如此处理）。

### 构建后 smoke test 报 `EACCES ... \.local/share/opencode`

是上游构建脚本自带的 `--version` 冒烟测试，因 `$HOME` 不可写而失败。
**不影响产物**——二进制已生成。可忽略，或：

```bash
export HOME=/tmp/oc-home XDG_DATA_HOME=/tmp/oc-home/.local/share
```

### 页面白屏，但 HTTP / WebSocket 都正常

多半是 `app/web/index.html` 里的内联 JS 被改坏了（该文件由 ttyd 官方页面
字符串替换而来，压缩 JS 一旦损坏浏览器会整页 SyntaxError）。

```bash
node scripts/check-web-syntax.js app/web/index.html
```

构建脚本与 CI 都会强制跑这一检查。

## 卸载

飞牛 → 应用中心 → OpenCode TUI → 卸载。

数据目录 `/vol4/@appdata/opencode-tui/` 默认保留，如需彻底清理：

```bash
rm -rf /vol4/@appdata/opencode-tui/
```
