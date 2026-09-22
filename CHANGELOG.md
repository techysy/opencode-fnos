# CHANGELOG / 更新日志

本项目版本号**跟随上游 OpenCode 官方版本**。

---

## v2.0.12 (2026-09-21)

对应官方 OpenCode **v2.0.12**。**架构重构：改用官方原生 Web UI，不再需要 ttyd。**

### 💥 破坏性变更

- **界面方案重写**：从「TUI + ttyd 网页终端」改为**官方原生 Web UI**
  - 引擎新增的 `opencode serve` 直接提供 Solid.js SPA（含 PWA）
  - **移除 ttyd 依赖**（可选二进制与手写的 748 KB 页面一并删除）
  - 界面由上游构建产出，**跟随上游自动升级**，本项目不再维护页面
- **对上游的补丁从 3 处减到 1 处**：
  - ❌ 移除「放宽 bun 版本约束」（v2 直接用 bun 1.4.2）
  - ❌ 移除「静态资源免鉴权」（改用上游自带的 `?auth_token=`）
  - ✅ 仅保留「CSP 增加 `frame-ancestors *`」（跨源 iframe 必需）
- **鉴权模型变化**：v2 默认强制鉴权（未设密码也会随机生成）
  - 密码在**安装向导**中填写（用户名固定 `opencode`，引擎硬编码；留空自动生成）
  - 存于 `/vol4/@appdata/opencode/credentials`，由 `cmd/install_callback` 自动同步到
    `app/ui/config` 的 `?auth_token=`，桌面图标点开即自动登录
  - 构建脚本与 CI 强制校验整条凭据链路完整
  - **会话 Cookie**：首次带 `?auth_token=` 访问时下发 HttpOnly Cookie。
    因为页面加载后会把 token 从地址栏抹掉，iframe 内刷新/跳转会丢鉴权，
    表现为「登录不进去」。现在后续请求凭 Cookie 自动认证。
  - **密码二次确认**：安装向导新增「确认密码」，两次不一致会中止安装。

### ✨ 功能

- 🖥️ **官方原生 Web UI**：Solid.js SPA，非重制界面
- 🖱️ **飞牛桌面集成**：桌面图标一键打开，`appname=opencode`
- 🌐 **短地址访问**：<http://opencode.techysy.fnos.net/> 直达
- 📡 **实时通道用 SSE**：事件流为 Server-Sent Events（带心跳、`X-Accel-Buffering: no`），
  对 iframe 与反向代理比 WebSocket 更友好
- 🔒 **数据隔离**：独立系统用户 `opencode`，数据存于 `/vol4/@appdata/opencode/`
- 🗂️ **XDG 目录隔离**：config/data/cache/state 全部指向应用数据目录
- 🤝 **可与其他版本共存**：端口 **19282**，与 mimocode(19280/19281) 互不冲突
- 📜 **安装协议授权向导**：首次安装需勾选同意 7 项条款
- 🎨 **品牌化**：OpenCode 图标（64/128/256 三档）
- 🧭 **不写死卷路径**：`cmd/_lib.sh` 自动推导，兼容不同 fnOS 部署布局

### 🔧 其他

- **构建链路更新**：构建入口从 `packages/opencode` 移到 `packages/cli`；
  bun 要求 1.3.14 → **1.4.2**；产物 `dist/cli-linux-x64/bin/opencode`（214 MB）
- **CI 更新**：bun 固定 1.4.2；新增凭据链路完整性校验；
  移除 ttyd 与页面语法校验；新增「不应包含 bin/ttyd」的负向校验
- **`check-upstream.sh` 修复**：v2 上游**只打 tag、不建 release**，
  旧脚本查 releases API 会漏检；现同时查询 releases 与 tags

### 📋 实测记录

| 项目 | 结果 |
| :--- | :--- |
| 构建 | ✅ `packages/cli` 构建通过，产物 214 MB |
| 启动 | ✅ `cmd/main start/stop/status/restart` 全通过 |
| 鉴权 | ✅ 无凭据 401 / 正确凭据 200 / 错误凭据 401 |
| iframe | ✅ `?auth_token=` 返回 200，`<title>OpenCode</title>` |
| SSE | ✅ 收到 `server.connected` 与心跳 |
| CSP | ✅ 响应头含 `frame-ancestors *` |
| 包内容 | ✅ 仅 `bin/opencode`（无 ttyd）、无 v1 遗留 `web/` |

> 详见 [`docs/v2-migration-feasibility.md`](docs/v2-migration-feasibility.md)

### 🐛 修复：fpk 文件名必须等于 appname

原先文件名保持 `opencode-tui-*` 而 `appname = opencode`，导致 fnOS 应用中心
报 **「不符合系统要求」** 拒绝安装（与架构、代码均无关）。

fnOS 硬性要求 **fpk 文件名前缀 = manifest 的 appname**，因此文件名改回
以 appname 开头：`opencode-2.0.12-x86.fpk` / `opencode-2.0.12-arm.fpk`。

- 构建脚本与 CI 均改为从 `appname` 派生文件名
- CI 新增校验：文件名前缀必须与 appname 一致（不一致直接失败）
- `deliver-fpk.sh` 同步适配

> 短地址 <http://opencode.techysy.fnos.net/> 不受影响（由 appname 决定）。

### ⚠️ 升级说明

v1 与 v2 实现不同，需**卸载重装**：

1. 应用中心卸载旧版（1.18.x）
2. 安装 `opencode-2.0.12-*.fpk`
3. 应用标识 `oc` 与端口 19282 不变，数据目录 `/vol4/@appdata/opencode/` 保留

---

## v1.18.31 (2026-09-14) — 已废弃

> ⚠️ **此版本已废弃**。v2 起改用官方原生 Web UI，v1 的「TUI + ttyd」方案不再维护。

首个飞牛（fnOS）发布版，对应官方 OpenCode **v1.18.31**。

### ✨ 功能

- 🖥️ **官方原版 TUI**：直接使用官方 `opencode` 二进制的 TUI（终端界面）
- 🌐 **网页终端接入**：通过 ttyd 1.7.7 把 TUI 包装为网页终端
- 🖱️ **飞牛桌面集成**：桌面图标一键打开，`appname=oc`
- 🔒 **数据隔离**：独立系统用户 `oc`，数据存于 `/vol4/@appdata/opencode/`
- 🗂️ **XDG 目录隔离**
- 🤝 **可与其他版本共存**：端口 **19282**
- 📜 **安装协议授权向导**
- 📋 **iframe 剪贴板修复**：三级降级 + 右键复制
- 🎨 **品牌化**：OpenCode 图标 + 固定页面标题
- 🧭 **不写死卷路径**

### 🔧 对上游的适配（3 处）

见 [`docs/patches/fnos-adaptation.patch`](docs/patches/fnos-adaptation.patch)
（v2 已精简为 1 处）。
