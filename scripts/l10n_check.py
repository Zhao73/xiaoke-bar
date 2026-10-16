#!/usr/bin/env python3
"""找出源码里 L("...") 用到、但翻译表还没有的简体中文文案，以及翻译不全、占位符对不上的行。
两张表：L10nTable.swift（繁中 / English / 日本語 / 한국어）
        L10nTableEU.swift（Deutsch / Français / Español / Italiano / Português）
用法：python3 scripts/l10n_check.py            列出缺的
      python3 scripts/l10n_check.py --json     以 JSON 数组输出缺的（方便批量翻译）
有问题时退出码为 1，可以串在构建前面。"""
import re, sys, json, pathlib
repo = pathlib.Path(__file__).resolve().parent.parent
root = repo / "Sources" / "XiaokeBar"
# App Store 版（iPhone / Mac 同步）的代码也用同一张翻译表
apple = repo / "Apple"
TABLES = ("L10nTable.swift", "L10nTableEU.swift", "L10nPrivateTable.swift", "L10nPrivateTableEU.swift")
def swift_files():
    yield from root.rglob("*.swift")
    yield from (f for f in apple.rglob("*.swift") if "/build/" not in str(f))
pat = re.compile(r'\bL\(\s*"((?:[^"\\]|\\.)*)"')
used = set()
for f in swift_files():
    if f.name in TABLES:
        continue
    for m in pat.finditer(f.read_text()):
        used.add(m.group(1))

S = r'"((?:[^"\\]|\\.)*)"'
row_pat = re.compile(r'^\s*' + S + r'\s*:\s*\((.*)\),\s*$')
# printf 占位符：数量和种类必须和源文一致，否则 String(format:) 会崩
ph_pat = re.compile(r'%(?:\d+\$)?[-+ 0#]*\d*(?:\.\d+)?[@dfsilu%]')
def placeholders(s):
    return sorted(re.sub(r'^%\d+\$', '%', p) for p in ph_pat.findall(s))

def check_table(name, langs, extra=None):
    """返回 (表里的源文集合, 问题列表[(源文, 说明)])"""
    path = root / "Core" / name
    if not path.exists():
        return set(), [("(整张表)", f"{name} 不存在")]
    # 不公开部分的文案在 Private/L10nPrivate*.swift（公开仓库里没有这个文件夹）
    private = root / "Private" / name.replace("L10nTable", "L10nPrivateTable")
    text = path.read_text() + ("\n" + private.read_text() if private.exists() else "")
    have, problems = set(), []
    for line in text.splitlines():
        m = row_pat.match(line)
        if not m:
            continue
        key = m.group(1)
        have.add(key)
        cols = re.findall(S, m.group(2))
        lacks = [langs[i] for i in range(len(langs)) if i >= len(cols) or not cols[i].strip()]
        if len(cols) > len(langs):
            lacks.append(f"多出 {len(cols) - len(langs)} 列")
        want = placeholders(key)
        bad_ph = [langs[i] for i, c in enumerate(cols[:len(langs)]) if c.strip() and placeholders(c) != want]
        if bad_ph:
            lacks.append("占位符不对：" + "、".join(bad_ph))
        if extra:
            lacks += extra(cols)
        if lacks:
            problems.append((key, "、".join(lacks)))
    return have, problems

def ko_hanzi(cols):  # 韩文列里出现汉字，多半是忘了翻、直接抄了中文
    return ["한국어（含汉字）"] if len(cols) >= 4 and re.search(r'[一-鿿]', cols[3]) else []
def eu_hanzi(cols):
    return ["含汉字（没翻）"] if any(re.search(r'[一-鿿]', c) for c in cols) else []

have, problems = check_table("L10nTable.swift", ("繁中", "English", "日本語", "한국어"), ko_hanzi)
have_eu, problems_eu = check_table("L10nTableEU.swift", ("Deutsch", "Français", "Español", "Italiano", "Português"), eu_hanzi)
missing = sorted(used - have)
missing_eu = sorted(have - have_eu)          # 主表有、欧洲表没有：欧洲语言会退回英文
stale_eu = sorted(have_eu - have)            # 欧洲表多出来的：主表已经删了

# 界面文字直接写中文、没包 L() 的（换语言后还是中文）
raw_pat = re.compile(r'(?:\bText\(|\btitle: |\bname: )"[^"]*[一-鿿]')
# 额度名在数据层就是中文，显示时经 quotaTitle() 翻译，所以这些构造处允许写中文
allowed = (".init(id:", "QuotaWindow(", "MoneyQuota(", "SyncWindow(", "SyncMoney(")
raw = []
for f in swift_files():
    if f.name in TABLES or f.name == "SelfTest.swift":
        continue
    for n, line in enumerate(f.read_text().splitlines(), 1):
        if raw_pat.search(line) and not any(k in line for k in allowed):
            raw.append(f"{f.relative_to(repo)}:{n}: {line.strip()[:90]}")

if "--json" in sys.argv:
    print(json.dumps(missing, ensure_ascii=False, indent=1))
    if problems or missing_eu:
        print(json.dumps([k for k, _ in problems] + missing_eu, ensure_ascii=False, indent=1), file=sys.stderr)
else:
    print(f"用到 {len(used)} 条，表里有 {len(have & used)} 条，缺 {len(missing)} 条")
    for s in missing:
        print("  " + s)
    if problems:
        print(f"主表翻译有问题的 {len(problems)} 条：")
        for k, why in problems:
            print(f"  {k}  → {why}")
    print(f"欧洲语言表 {len(have_eu)} 条，缺 {len(missing_eu)} 条（缺的会显示英文），多余 {len(stale_eu)} 条")
    for s in missing_eu:
        print("  缺：" + s)
    for s in stale_eu:
        print("  多余：" + s)
    for k, why in problems_eu:
        print(f"  {k}  → {why}")
    if raw:
        print(f"没包 L() 的中文界面文字 {len(raw)} 处：")
        for r in raw:
            print("  " + r)
sys.exit(1 if (missing or problems or missing_eu or stale_eu or problems_eu or raw) else 0)
