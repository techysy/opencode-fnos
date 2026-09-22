#!/usr/bin/env python3
"""把 OpenCode Console 的 OAuth 凭据写入引擎数据库。

TUI 版 auth login 把凭据塞进 SQLite（credential 表），且 stdout 被缓冲、
管道里读不到设备码。这里绕开 TUI：直接申请设备码 -> 轮询 -> 写库。

用法:
  oc-login.py --start                  输出 {"user_code":...} 并保持轮询由调用方驱动
  oc-login.py --login                  完整流程（交互，自己出码+轮询+写库）
  oc-login.py --status                 查看当前凭据
  oc-login.py --logout                 删除凭据
  oc-login.py --write-json <file>      从 curl 拿到的 token JSON 写库（调试用）
"""
import json, os, sqlite3, sys, time, uuid, urllib.error, urllib.request
from urllib.parse import quote

SERVER = "https://opencode.ai/console"
CLIENT = "opencode-cli"
INTEGRATION = "opencode"
METHOD = "device"


def db_path():
    root = os.environ.get("XDG_DATA_HOME") or os.path.join(os.path.expanduser("~"), ".local", "share")
    d = os.path.join(root, "opencode")
    # v2 主库名形如 opencode-master.db / opencode-local.db
    for name in sorted(os.listdir(d)) if os.path.isdir(d) else []:
        if name.startswith("opencode-") and name.endswith(".db") and "-shm" not in name and "-wal" not in name:
            return os.path.join(d, name)
    return os.path.join(d, "opencode-master.db")


def http(path, body, ua="opencode-cli"):
    req = urllib.request.Request(
        SERVER + path, data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "User-Agent": ua}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", "replace")
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"_raw": raw[:200]}
    except Exception as e:
        return 0, {"_error": str(e)}


def get(path, token):
    req = urllib.request.Request(SERVER + path, headers={
        "Accept": "application/json", "Authorization": "Bearer " + token, "User-Agent": "opencode-cli"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read() or b"{}")
    except Exception:
        return None


def start():
    st, d = http("/auth/device/code", {"client_id": CLIENT, "supports_org_scope": True})
    if st != 200 or "device_code" not in d:
        print(json.dumps({"_error": st, "resp": d})); return None
    return d


def poll(dev, interval, deadline):
    while time.time() < deadline:
        time.sleep(interval)
        st, d = http("/auth/device/token", {
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            "device_code": dev, "client_id": CLIENT})
        if isinstance(d, dict) and "access_token" in d:
            return d
        err = (d.get("error") or "") if isinstance(d, dict) else ""
        if err in ("authorization_pending", "slow_down"):
            if err == "slow_down": interval += 5
            sys.stdout.write("."); sys.stdout.flush()
            continue
        return {"_error": err or "unknown", "resp": d}
    return {"_error": "timeout"}


def write_credential(tok):
    access = tok.get("access_token")
    refresh = tok.get("refresh_token") or ""
    expires_in = int(tok.get("expires_in") or 3600)
    org_id = tok.get("org_id")
    if not access:
        raise SystemExit("token 里没有 access_token")

    user = get("/api/user", access) or {}
    orgs = get("/api/orgs", access) or []
    org = None
    if org_id:
        org = next((o for o in orgs if o.get("id") == org_id), None)
    elif isinstance(orgs, list) and orgs:
        org = sorted(orgs, key=lambda o: (o.get("name") or "", o.get("id") or ""))[0]

    metadata = {"server": SERVER}
    if isinstance(user, dict):
        if user.get("id"): metadata["accountID"] = user["id"]
        if user.get("email"): metadata["email"] = user["email"]
    if org:
        metadata["orgID"] = org.get("id")
        metadata["orgName"] = org.get("name")

    value = {
        "type": "oauth",
        "methodID": METHOD,
        "access": access,
        "refresh": refresh,
        "expires": int(time.time() * 1000) + expires_in * 1000,
        "metadata": metadata,
    }

    db = db_path()
    os.makedirs(os.path.dirname(db), exist_ok=True)
    con = sqlite3.connect(db, timeout=30)
    try:
        con.execute("pragma journal_mode=wal")
        now = int(time.time() * 1000)
        old = con.execute("select id, time_created from credential where integration_id=?", (INTEGRATION,)).fetchone()
        if old:
            con.execute("update credential set label=?, value=?, method_id=?, active=1, time_updated=? where id=?",
                        ("OAuth", json.dumps(value), METHOD, now, old[0]))
        else:
            con.execute("insert into credential (id, integration_id, label, value, connector_id, method_id, active, time_created, time_updated) values (?,?,?,?,?,?,?,?,?)",
                        (str(uuid.uuid4()), INTEGRATION, "OAuth", json.dumps(value), None, METHOD, 1, now, now))
        sources = con.execute("select value from kv where key=?", ("wellknown:sources",)).fetchone()
        cur = json.loads(sources[0]) if sources else []
        if INTEGRATION not in cur:
            cur.append(INTEGRATION)
            con.execute("insert into kv (key, value, time_created, time_updated) values (?,?,?,?) "
                        "on conflict(key) do update set value=excluded.value, time_updated=excluded.time_updated",
                        ("wellknown:sources", json.dumps(cur), now, now))
        con.commit()
    finally:
        con.close()
    return db, metadata


def status():
    db = db_path()
    if not os.path.exists(db):
        print("  未登录（数据库不存在）"); return 1
    con = sqlite3.connect("file:" + db + "?mode=ro", uri=True)
    try:
        rows = con.execute("select id, integration_id, label, value from credential").fetchall()
    except Exception as e:
        print("  读取失败:", e); return 1
    finally:
        con.close()
    if not rows:
        print("  未登录（无凭据）"); return 1
    for cid, iid, label, val in rows:
        try:
            v = json.loads(val)
            md = v.get("metadata") or {}
            exp = v.get("expires") or 0
            left = max(0, (exp - int(time.time() * 1000)) // 1000)
            print("  集成 :", iid, "/", label)
            print("  账号 :", md.get("email") or md.get("accountID") or "?")
            print("  组织 :", md.get("orgName") or md.get("orgID") or "-")
            print("  有效期:", str(left) + "s" if exp else "?")
        except Exception:
            print("  ", iid, label, str(val)[:50])
    return 0


def logout():
    db = db_path()
    if not os.path.exists(db):
        print("  无需退出"); return 0
    con = sqlite3.connect(db, timeout=30)
    try:
        n = con.execute("delete from credential where integration_id=?", (INTEGRATION,)).rowcount
        con.commit()
    finally:
        con.close()
    print("  已删除", n, "条凭据"); return 0


def main():
    a = sys.argv[1:]
    if not a or a[0] in ("-h", "--help"):
        print(__doc__); return 0
    if a[0] == "--status":
        return status()
    if a[0] == "--logout":
        return logout()
    if a[0] == "--write-json":
        tok = json.load(open(a[1]))
        db, md = write_credential(tok)
        print("  已写入:", db); return 0
    if a[0] in ("--start", "--login"):
        d = start()
        if not d:
            print("  无法申请设备码"); return 1
        if a[0] == "--start":
            print(json.dumps(d)); return 0
        code = d["user_code"]
        print()
        print("  ┌───────────────────────────────────────────┐")
        print("  │  验证码:  " + code.ljust(32) + "│")
        print("  └───────────────────────────────────────────┘")
        print()
        print("  👉 打开 https://opencode.ai/console/device 输入上面的码并授权")
        print("     有效期 15 分钟。")
        print()
        sys.stdout.write("  等待授权中")
        tok = poll(d["device_code"], int(d.get("interval", 5)), time.time() + 880)
        print()
        if "_error" in tok:
            print("  ❌ 失败:", json.dumps(tok, ensure_ascii=False)); return 1
        db, md = write_credential(tok)
        print("  ✅ 登录成功")
        print("     账号:", md.get("email") or md.get("accountID") or "?")
        print("     组织:", md.get("orgName") or "-")
        print("     已写入:", db)
        return 0
    print("未知参数:", a[0]); return 2


if __name__ == "__main__":
    sys.exit(main())