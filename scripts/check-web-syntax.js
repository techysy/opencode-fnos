#!/usr/bin/env node
/**
 * 校验 app/web/index.html 内联 <script> 的 JS 语法。
 *
 * 背景：该页面是在 ttyd 官方页面（压缩过的单文件）上做字符串替换得到的
 * （品牌化 + 剪贴板修复）。一旦替换破坏了压缩 JS，浏览器会抛出
 * 「Uncaught SyntaxError」并放弃执行整段 bundle —— 表现就是**完全白屏**，
 * 而 HTTP 200、页面体积、WebSocket 数据、引擎进程全都正常，极难排查。
 *
 * 因此在构建与 CI 阶段都强制做一次静态语法校验。
 *
 * 用法：node scripts/check-web-syntax.js <index.html 路径>
 * 退出码：0 全部合法；1 存在语法错误或参数缺失。
 */
"use strict";

const fs = require("fs");
const vm = require("vm");

const file = process.argv[2];
if (!file) {
  console.error("用法: node scripts/check-web-syntax.js <index.html>");
  process.exit(1);
}

let html;
try {
  html = fs.readFileSync(file, "utf8");
} catch (err) {
  console.error(`::error::无法读取 ${file}: ${err.message}`);
  process.exit(1);
}

// 提取所有内联 <script>（忽略带 src 的外链脚本）
const blocks = [];
const re = /<script\b([^>]*)>([\s\S]*?)<\/script>/gi;
let m;
while ((m = re.exec(html)) !== null) {
  const attrs = m[1] || "";
  if (/\bsrc\s*=/i.test(attrs)) continue;
  const type = (attrs.match(/\btype\s*=\s*["']?([^"'\s>]+)/i) || [])[1] || "";
  // 只校验 JS（跳过 application/json、text/template 等数据块）
  if (type && !/^(text\/javascript|application\/javascript|module)$/i.test(type)) {
    console.log(`  script(type=${type}) 跳过（非 JS）`);
    continue;
  }
  blocks.push(m[2]);
}

if (blocks.length === 0) {
  console.error("::error::页面中未找到任何内联 <script> 块");
  process.exit(1);
}

let bad = 0;
blocks.forEach((body, i) => {
  try {
    // 仅做语法解析，不执行
    new vm.Script(body, { filename: `inline-script-${i}.js` });
    console.log(`  ✅ script#${i} 语法正常（${body.length} 字节）`);
  } catch (err) {
    bad++;
    console.error(`::error::script#${i} 语法错误 —— 浏览器将整页白屏`);
    console.error(`  ${err.message}`);
    // 给出出错行附近片段，便于定位
    const lm = /inline-script-\d+\.js:(\d+)/.exec(err.stack || "");
    if (lm) {
      const line = Number(lm[1]);
      const lines = body.split("\n");
      const from = Math.max(0, line - 1);
      lines.slice(from, from + 1).forEach((l, k) => {
        console.error(`  行 ${from + k + 1}: ${l.slice(0, 200)}`);
      });
    }
  }
});

if (bad) {
  console.error(`\n❌ 页面脚本语法校验失败（${bad} 处）`);
  process.exit(1);
}
console.log("✓ 页面脚本语法校验通过");
