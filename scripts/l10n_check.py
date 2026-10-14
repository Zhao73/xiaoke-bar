#!/usr/bin/env python3
"""找出源码里 L("...") 用到、但翻译表 L10nTable.swift 里还没有的简体中文文案。
用法：python3 scripts/l10n_check.py            列出缺的
      python3 scripts/l10n_check.py --json     以 JSON 数组输出缺的（方便批量翻译）"""
import re, sys, json, pathlib
root = pathlib.Path(__file__).resolve().parent.parent / "Sources" / "XiaokeBar"
pat = re.compile(r'\bL\(\s*"((?:[^"\\]|\\.)*)"')
used = set()
for f in root.rglob("*.swift"):
    if f.name == "L10nTable.swift":
        continue
    for m in pat.finditer(f.read_text()):
        used.add(m.group(1))
table = (root / "Core" / "L10nTable.swift").read_text()
have = set(re.findall(r'^\s*"((?:[^"\\]|\\.)*)"\s*:', table, re.M))
missing = sorted(used - have)
# 界面文字直接写中文、没包 L() 的（换语言后还是中文）
raw_pat = re.compile(r'(?:\bText\(|\btitle: |\bname: )"[^"]*[\u4e00-\u9fff]')
raw = []
for f in root.rglob("*.swift"):
    if f.name in ("L10nTable.swift", "SelfTest.swift"):
        continue
    for n, line in enumerate(f.read_text().splitlines(), 1):
        if raw_pat.search(line) and not any(k in line for k in (".init(id:", "QuotaWindow(", "MoneyQuota(")):  # 额度名显示时经 quotaTitle() 翻译
            raw.append(f"{f.relative_to(root)}:{n}: {line.strip()[:90]}")
if "--json" in sys.argv:
    print(json.dumps(missing, ensure_ascii=False, indent=1))
else:
    print(f"用到 {len(used)} 条，表里有 {len(have & used)} 条，缺 {len(missing)} 条")
    for s in missing:
        print("  " + s)
    if raw:
        print(f"没包 L() 的中文界面文字 {len(raw)} 处：")
        for r in raw:
            print("  " + r)
