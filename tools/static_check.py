#!/usr/bin/env python3
"""师生作业打卡 App 简易版 — C 组静态自查脚本。

检查四项：
  1) 所有 lib/*.dart 的 import 目标文件存在；
  2) CONTRACT.md 点名的类名/方法名在对应文件里出现；
  3) 大括号基本配平（先剥掉字符串与注释再数）；
  4) 不含真实 supabase.co URL / 真实 key / TODO 空函数。

用法：python3 tools/static_check.py
退出码：0 = 全部通过；1 = 有 FAIL。

注意：本脚本只做静态文本检查，不代替 flutter analyze / dart format。
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# ---- CONTRACT.md 点名的类名/方法名（文件 -> 必须出现的符号）----
# 只检查 C 组负责的文件；A/B 组文件不存在时跳过（不算 FAIL）。
CONTRACT_SYMBOLS = {
    "lib/services/import_service.dart": [
        "class ImportService",
        "parseFile",
    ],
    "lib/services/parsers/question_parser.dart": [
        "parseFormattedText",
        "parseCsv",
        "parseJson",
    ],
    "lib/services/parsers/excel_parser.dart": [
        "parseExcelBytes",
    ],
    "lib/services/parsers/word_parser.dart": [
        "parseDocxBytes",
        "docxText",
    ],
    "lib/services/parsers/pdf_text_parser.dart": [
        "parsePdfBytes",
        "hasExtractableText",
        "extractTextViaEdgeFunction",
    ],
}

# 疑似真实 Supabase 地址：https://<一串字母数字>.supabase.co
# 占位写法 https://<项目>.supabase.co 不算（尖括号里的不是真实值）。
REAL_SUPABASE_URL = re.compile(r"https://[a-z0-9][a-z0-9-]*\.supabase\.co")
# 占位写法（不是真实地址）：<...>、xxxx、xxx 等。
PLACEHOLDER_HOST = re.compile(r"https://(?:<[^>]*>|x{3,})\.supabase\.co")
PLACEHOLDER_URL = re.compile(r"https://<[^>]*>\.supabase\.co")
# 疑似真实 key：supabase  anon/service key 均为长 base64（eyJ 开头的 JWT）。
REAL_KEY = re.compile(r"eyJ[A-Za-z0-9_-]{20,}")
# 空函数 / 未实现：TODO、FIXME、UnimplementedError、throw 待实现。
EMPTY_IMPL = re.compile(r"TODO|FIXME|UnimplementedError|throw\s+UnimplementedError")

IMPORT_RE = re.compile(r"""^\s*import\s+['"]([^'"]+)['"]""", re.MULTILINE)


def strip_strings_and_comments(text: str) -> str:
    """剥掉 Dart 字符串与注释，剩下的再数大括号。"""
    out = []
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        # 行注释 //...
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                i += 1
            continue
        # 块注释 /* ... */
        if c == "/" and i + 1 < n and text[i + 1] == "*":
            i += 2
            while i + 1 < n and not (text[i] == "*" and text[i + 1] == "/"):
                i += 1
            i += 2
            continue
        # 字符串 '...' "..." '''...''' """..."""
        if c in ("'", '"'):
            quote = c
            triple = text[i:i + 3] == quote * 3
            i += 3 if triple else 1
            while i < n:
                if text[i] == "\\":
                    i += 2
                    continue
                if triple and text[i:i + 3] == quote * 3:
                    i += 3
                    break
                if not triple and text[i] == quote:
                    i += 1
                    break
                if not triple and text[i] == "\n":
                    break
                i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


def resolve_import(from_file: Path, target: str) -> Path | None:
    """把 Dart import 解析成磁盘路径；dart: 与 package: 由包名映射处理。"""
    if target.startswith("dart:"):
        return None  # SDK 库，不检查
    if target.startswith("package:"):
        # package:excel/excel.dart -> 无法在仓库内验证，记为外部依赖，跳过。
        return None
    # 相对路径：相对 import 所在文件。
    return (from_file.parent / target).resolve()


def check_file(path: Path, results: list) -> None:
    rel = str(path.relative_to(ROOT))
    text = path.read_text(encoding="utf-8")

    # 1) import 目标存在（只检查相对路径 import）。
    missing = []
    for m in IMPORT_RE.finditer(text):
        target = m.group(1)
        resolved = resolve_import(path, target)
        if resolved is not None and not resolved.exists():
            missing.append(target)
    if missing:
        results.append((False, f"{rel}: import 目标不存在：{', '.join(missing)}"))
    else:
        results.append((True, f"{rel}: import 目标全部存在"))

    # 2) CONTRACT 点名符号。
    for symbol in CONTRACT_SYMBOLS.get(rel, []):
        if symbol in text:
            results.append((True, f"{rel}: 含 {symbol}"))
        else:
            results.append((False, f"{rel}: 缺少 {symbol}"))

    # 3) 大括号配平。
    stripped = strip_strings_and_comments(text)
    opens = stripped.count("{")
    closes = stripped.count("}")
    if opens == closes:
        results.append((True, f"{rel}: 大括号配平（{opens} 对）"))
    else:
        results.append((False, f"{rel}: 大括号不配平（{{ {opens} 个，}} {closes} 个）"))

    # 4) 真实 URL / key / TODO 空函数。
    bad = []
    for line in text.splitlines():
        if PLACEHOLDER_URL.search(line) or PLACEHOLDER_HOST.search(line):
            continue
        if REAL_SUPABASE_URL.search(line):
            bad.append(f"疑似真实 supabase.co 地址：{line.strip()[:80]}")
        if REAL_KEY.search(line):
            bad.append(f"疑似真实 key（JWT）：{line.strip()[:60]}...")
        if EMPTY_IMPL.search(line):
            bad.append(f"TODO/未实现：{line.strip()[:80]}")
    if bad:
        for b in bad:
            results.append((False, f"{rel}: {b}"))
    else:
        results.append((True, f"{rel}: 无真实 URL/key/TODO 空函数"))


def main() -> int:
    dart_files = sorted((ROOT / "lib").rglob("*.dart"))
    if not dart_files:
        print("FAIL: lib 下没有 .dart 文件")
        return 1

    results = []
    for path in dart_files:
        # 只检查 C 组文件在 CONTRACT_SYMBOLS 里点名的符号；
        # A/B 组文件只做 1/3/4 三项通用检查（符号检查跳过）。
        check_file(path, results)

    # 额外：SQL 与 Edge Function 也过一遍第 4 项（真实 URL/key/TODO）。
    for extra in [
        "supabase/schema.sql",
        "supabase/seed_test_data.sql",
        "supabase/functions/pdf-extract/index.ts",
    ]:
        p = ROOT / extra
        if not p.exists():
            results.append((False, f"{extra}: 文件不存在"))
            continue
        text = p.read_text(encoding="utf-8")
        bad = [
            line.strip()[:80]
            for line in text.splitlines()
            if (REAL_SUPABASE_URL.search(line) and not PLACEHOLDER_URL.search(line) and not PLACEHOLDER_HOST.search(line))
            or REAL_KEY.search(line)
            or EMPTY_IMPL.search(line)
        ]
        if bad:
            for b in bad:
                results.append((False, f"{extra}: {b}"))
        else:
            results.append((True, f"{extra}: 无真实 URL/key/TODO 空函数"))

    passed = sum(1 for ok, _ in results if ok)
    failed = [msg for ok, msg in results if not ok]
    for ok, msg in results:
        print(f"{'PASS' if ok else 'FAIL'}: {msg}")
    print(f"\n共 {len(results)} 项，通过 {passed} 项，失败 {len(failed)} 项")
    if failed:
        print("结果：FAIL")
        return 1
    print("结果：PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
