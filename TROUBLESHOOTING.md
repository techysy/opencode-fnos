# 故障排查

> 当前版本：**v2.0.12**
> 端口默认 **19282**，数据目录默认 **/vol4/@appdata/oc/**。
> 应用名 `oc`，短地址 <http://oc.techysy.fnos.net/>

---

## 快速自检

```bash
# 1. 服务状态
/var/apps/oc/cmd/main status

# 2. 看日志（最重要的排查入口）
tail -n 80 /vol4/@appdata/oc/oc.log

# 3. 本机是否响应（401 = 服务正常但需鉴权，是**预期**结果）
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:19282/

# 4. 用 iframe 同款 URL 访问（应 200）
curl -s -o /dev/null -w '%{http_code}\n' \
  "http://127.0.0.1:19282/?auth_token=b3BlbmNvZGU6b2MtZm5vcw=="

# 5. 重启
/var/apps/oc/cmd/main restart
```

---

## 桌面图标点开是空白 / 401

v2 默认强制鉴权。飞牛桌面用 iframe 嵌入，**无法发送 Basic 认证头**，
必须靠 URL 里的 `?auth_token=` 通过。若两处不一致就会白屏：

| 位置 | 内容 |
| :--- | :--- |
| `/var/apps/oc/ui/config` | `url` 里的 `?auth_token=...` |
| `/var/apps/oc/cmd/main` | `PASSWORD="\${OPENCODE_PASSWORD:-\${OPENCODE_SERVER_PASSWORD:-oc-fnos}}"` |

**排查**：

```bash
# 查看当前 token 解出来是什么
python3 - <<'EOF'
import base64, json, re
cfg = json.load(open("/var/apps/oc/ui/config"))
url = cfg[".url"]["oc.Application"]["url"]
tok = re.search(r"auth_token=([A-Za-z0-9+/=]+)", url).group(1)
print("token    :", tok)
print("decoded  :", base64.b64decode(tok).decode())
EOF

# 查看 cmd/main 内置密码
grep -o 'OPENCODE_SERVER_PASSWORD:-[^}]*' /var/apps/oc/cmd/main
```

两者必须一致（格式为 `opencode:密码`）。构建脚本与 CI 都会强制校验，
若你手工改过其中一个，请同步另一个。

> **临时绕过**：设置固定密码后重启，并手工拼 token
> ```bash
> sudo -u oc OPENCODE_PASSWORD=mysecret /var/apps/oc/cmd/main restart
> printf 'opencode:mysecret' | base64    # 用这个值替换 ui/config 的 auth_token
> ```

---

## 点击图标能打开但内容不显示 / 白屏

1. **确认 CSP**（iframe 能否嵌入的关键）：
   ```bash
   curl -s -D- -o /dev/null "http://127.0.0.1:19282/?auth_token=b3BlbmNvZGU6b2MtZm5vcw==" \
     | grep -i content-security
   ```
   应包含 `frame-ancestors *`。若没有，说明补丁未生效（见下方「重新构建」）。

2. **确认浏览器控制台**（F12）有无报错——通常是 `Refused to display ... in a frame`。

---

## 端口被占用

```bash
ss -tlnp | grep 19282
```

本应用端口为 19282，与 `mimocode-tui`(19281)、`mimocode`(19280) 互不冲突。

---

## 引擎写入 HOME 报 EACCES

引擎默认写 `$HOME/.local/share/opencode`。本项目已在 `cmd/main` 中
把 XDG 目录全部指向应用数据目录，正常不会出现。

若要手工运行引擎调试，记得带上：

```bash
export XDG_DATA_HOME=/vol4/@appdata/oc/share
export XDG_CONFIG_HOME=/vol4/@appdata/oc/config
export XDG_CACHE_HOME=/vol4/@appdata/oc/cache
export XDG_STATE_HOME=/vol4/@appdata/oc/state
```

---

## 工作目录

默认 `/vol4/@appdata/oc/workspace`（引擎拒绝把 `/` 当项目目录）。

```bash
sudo -u oc OPENCODE_WORKSPACE=/vol1/1000/my-project \
  /var/apps/oc/cmd/main restart
```

---

## 终端 / PTY 相关

v2 的交互终端走 `/api/pty/<id>/connect`（WebSocket）。该端点用**一次性 ticket**
鉴权（上游为「浏览器无法在 WebSocket 升级时发头」专门设计），前端会自动申请。

若终端打不开：

```bash
# 确认 PTY 接口本身可用
curl -s -u opencode:oc-fnos http://127.0.0.1:19282/api/pty

# 确认宿主机有 pty 设备
ls /dev/pts/
```

> 若 `/dev/pts` 为空或容器未挂载，PTY 无法创建。这是**环境问题**，非应用缺陷。

---

## 事件流 / 实时刷新不工作

v2 用 **SSE**（`/api/event`）而非 WebSocket。若经过反向代理，
需关闭缓冲：

```nginx
location / {
    proxy_pass http://127.0.0.1:19282;
    proxy_http_version 1.1;

    # SSE 必须关闭缓冲，否则事件会被攒着不发
    proxy_buffering off;
    proxy_cache off;
    proxy_set_header Connection "";

    # WebSocket（PTY 终端）
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $connection_upgrade;
    proxy_read_timeout 3600s;
}
```

---

## 重新构建

需要 **bun 1.4.2+** 与 **fnpack 1.2.4+**：

```bash
cd /path/to/opencode-fnos
bash scripts/build.sh --from-source      # 全量：拉源码 + 打补丁 + 编译 + 打包
ARCH=arm bash scripts/build.sh --from-source   # arm64
```

构建时若报 `AccessDenied accessing temporary directory`，设置：

```bash
export BUN_TMPDIR=/tmp/bun-tmp
export BUN_INSTALL_CACHE_DIR=/tmp/bun-cache
```

若报 `fatal: not a git repository`，是构建脚本需要分支信息——现代码已内置
`git init`，若仍出现请确认 `git` 可用。

---

## 升级 / 卸载

```bash
# 停止
/var/apps/oc/cmd/main stop

# 卸载后数据目录仍保留，如需彻底清理：
rm -rf /vol4/@appdata/oc
```

---

## 从 v1 升级到 v2（重要）

v1（1.18.x）与 v2（2.0.x）是**不同的实现**：

| | v1 | v2 |
| :--- | :--- | :--- |
| 界面 | TUI + ttyd 网页终端 | 官方原生 Web UI |
| ttyd | 需要 | **不需要** |
| 引擎大小 | 193 MB | 214 MB |
| 包大小 | ~63 MB | ~106 MB |

升级方式：**应用中心卸载旧版 → 安装新版**。
应用标识 `oc` 与端口 19282 保持不变，数据目录 `/vol4/@appdata/oc/` 不会被删除。
