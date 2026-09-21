# v2 迁移可行性报告（实测）

> 基于 **v2.0.12**（2026-09-21）本地实测，非推测。
> 结论：**v1 废弃，仓库直接改为 v2。**

## 一、最终方案：serve 模式，彻底去掉 ttyd

```
fnOS 桌面
  └─ iframe  http://127.0.0.1:19282/?auth_token=<base64(user:pass)>
                  │
                  └─ opencode serve   ← v2 原生 Web UI（Solid.js SPA）
```

---

## 二、构建可行性 ✅

| 项目 | v1.18.31 | v2.0.12 |
| :--- | :--- | :--- |
| 构建入口 | `script/build.ts` | `packages/cli/script/build.ts` |
| 产物路径 | `packages/opencode/dist/opencode-linux-x64/bin/opencode` | `packages/cli/dist/cli-linux-x64/bin/opencode` |
| 产物大小 | 193 MB | **214 MB** |
| bun 要求 | 1.3.14 | **1.4.2** |
| 依赖安装 | 4631 包 / 198s | 2420 包 / **30s** |
| 构建命令 | `--single --skip-install` | **相同** |
| 实测结果 | ✅ | ✅ exit 0 |

```bash
cd packages/cli
OPENCODE_CHANNEL=local OPENCODE_VERSION=local \
  bun run script/build.ts --single --skip-install
# → dist/cli-linux-x64/bin/opencode  (214 MB, ELF x86-64)
```

实测 `--version` → `opencode vlocal`，`--help` 正常。

---

## 三、v2 自带原生 Web UI（不再需要 ttyd）🎉

| 检查项 | 实测结果 |
| :--- | :--- |
| `/`（带凭据） | **HTTP 200**，`<title>OpenCode</title>` |
| Web UI 类型 | Solid.js SPA + PWA（`sw.js`，913 预缓存条目） |
| 页面大小 | 6145 字节（v1 是手工 748 KB 页面） |

**可以让出的维护负担**：

- ❌ `ttyd` 二进制（省 1.3 MB）
- ❌ 手写 `app/web/index.html`（748 KB）
- ❌ `check-web-syntax.js` 白屏防护
- ❌ 页面品牌化改动

界面由上游产出，**跟随上游自动升级**。

---

## 四、鉴权（实测）

v2 **默认强制鉴权**（`server-process.ts`）：密码未配置时也会 `randomBytes(32)` 随机生成。

### iframe 问题的解法（已实测）✅

飞牛桌面 iframe 无法发 Basic 头。v2 自带 `?auth_token=` 查询参数
（`packages/server/src/middleware/authorization.ts`，`AUTH_TOKEN_QUERY = "auth_token"`）：

```bash
?auth_token=b3BlbmNvZGU6c2VjcmV0MTIz    # base64("opencode:secret123")
实测 → HTTP 200 ✅
```

**所以不需要「静态资源免鉴权」补丁。**

---

## 五、接口实测

| 端点 | 方式 | 结果 |
| :--- | :--- | :--- |
| `/` | GET | ✅ 200 |
| `/api/event` | GET (SSE) | ✅ 200，收到 `server.connected` + `: heartbeat` |
| `/api/pty` | GET | ✅ 200 |
| `/api/session` | GET | ✅ 200 |
| `/api/model` | GET | ✅ 200 |
| `/api/config` | GET | ✅ 200 |

### 实时通道 = SSE，不是 WebSocket ✅

`packages/server/src/handlers/event.ts`：`contentType: "text/event-stream"`，
带 15 秒心跳，并设了 `X-Accel-Buffering: no`（明确为反向代理设计）。

**SSE 比 WebSocket 对 iframe/反代友好得多**，这是比 v1 更稳妥的地方。

### PTY 的 WebSocket 走 ticket（上游已为浏览器设计）✅

```
POST /api/pty/:id/connect-token   (带凭据)  → 短期一次性 ticket
GET  /api/pty/:id/connect?connect_token=... (WebSocket 升级)
```

中间件显式跳过对 PTY ticket 的凭据检查，注释说明：
> *Browsers cannot set headers on WebSocket upgrades, so a ticketed PTY connect skips credential checks*

---

## 六、⚠️ 沙箱无法验证的部分

**PTY 实际创建在沙箱内会 500**，原因已定位为环境限制而非 v2 缺陷：

```
$ python3 -c "import pty; pty.fork()"
out of pty devices
$ ls /dev/pts/     → 空
```

沙箱没有分配 PTY 设备（v1 时同样无法交互式测 TUI）。
**真机 fnOS 上应有 `/dev/pts`，需装机后实测确认。**

---

## 七、补丁对照：v1 三处 → v2 仅一处

| v1 补丁 | v1 位置 | v2 情况 | 还需要？ |
| :--- | :--- | :--- | :--- |
| bun 版本放宽 | `packages/script/src/index.ts` | 文件仍在 | ❌ 不需要（直接用 bun 1.4.2） |
| CSP `frame-ancestors` | `server/shared/ui.ts` | → `packages/cli/src/services/web-ui.ts:58` | ✅ **仍需要** |
| 静态资源免鉴权 | `server/shared/public-ui.ts` | 文件消失 | ❌ 不需要（用 `?auth_token=`） |

### v2 的 CSP 实测响应头

```
default-src 'self'; script-src 'self' 'wasm-unsafe-eval' 'sha256-...';
style-src 'self' 'unsafe-inline'; img-src 'self' data: https: blob:;
font-src 'self' data:; media-src 'self' data:; connect-src * data: blob:
```

- 缺 `frame-ancestors` → 跨源 iframe 会被拒（**唯一必须的补丁**）
- `connect-src` 已含 `*` → SSE/WS 无需再改 ✅

---

## 八、待办 / 待验证

- [x] 构建可行性
- [x] 原生 Web UI 可用
- [x] `?auth_token=` iframe 方案
- [x] SSE 事件流
- [ ] **真机 PTY 验证**（沙箱无 `/dev/pts`）
- [ ] 长时间运行内存占用
- [ ] arm64 构建
- [ ] `check-upstream.sh` 修：v2 只打 tag 不建 release

---

## 九、环境资产（可复用）

| 路径 | 内容 |
| :--- | :--- |
| `.build/bun/bun-1.4.2` | bun 1.4.2（v2 必需） |
| `.build/src-v2/opencode-2.0.12/` | v2 源码 + node_modules（**已构建**） |
| `.build/src-v2/.../packages/cli/dist/cli-linux-x64/bin/opencode` | 产物（214 MB） |
