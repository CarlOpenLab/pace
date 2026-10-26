#!/usr/bin/env python3
"""字号必须跟系统走：写死的字号与 minimumScaleFactor 都必须是 0 处；
界面上不许出现机器话（全大写带下划线的错误码）。

后一条是今晚踩出来的：恢复预览把 IMPORT_MALFORMED_JSON 直接印在了屏幕上。

Colo 第十五版 §5 的两条，Ato 试出来的四种漏网写法都在这儿补齐：

  .font(.system(size: 15))          抓到
  .font(.system(size:15))           抓到（无空格）
  Font.system(size: 15)             抓到（赋给变量再传）
  .font(Font.system(size: 15))      抓到
  .font(.custom("Pace", size: 15))  抓到（自定义字体这条路）
  UIFont.systemFont(ofSize: 15)     抓到（万一以后有人用 UIKit）
  .minimumScaleFactor(0.8)          抓到（把用户选的字号压回去）
  .font(.system(size: scaledSize))  放过（白名单：变量名不带数字）
  .font(.system(size: displaySize)) 放过
  Text("IMPORT_MALFORMED_JSON")     抓到（界面上的机器话）
  let IMPORT_MALFORMED_JSON = 1     放过（标识符不是界面文字）

用法：
  python3 scripts/check-type-scale.py            # 查整个 iosApp/
  python3 scripts/check-type-scale.py 某个.swift   # 只查一个文件（给自检用）

自检也是硬要求：每次运行先拿一份故意违规的样本跑一遍，抓不到就说明这个检查坏了，
直接判红——一个永远说干净的检查比没有检查更坏（今天已经出过一次）。
"""

from __future__ import annotations

import pathlib
import re
import sys

RULES = [
    ("写死的字号", re.compile(r"\.system\(\s*size:\s*[0-9]")),
    ("写死的字号", re.compile(r"\.custom\([^)]*size:\s*[0-9]")),
    ("写死的字号", re.compile(r"UIFont[^)]*ofSize:\s*[0-9]")),
    ("minimumScaleFactor", re.compile(r"minimumScaleFactor")),
]

# 机器话：字符串里出现「全大写 + 至少一个下划线」，五个字符以上。
# 抓不到所有机器话，但能抓住错误码这一类——以后谁把码写进文案，CI 会先说话。
MACHINE_TOKEN = re.compile(r"\b[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+\b")
STRING_LITERAL = re.compile(r'"(?:[^"\\]|\\.)*"')

# 样本里应当被抓到的行数；改样本时一起改。
FIXTURE_EXPECTED = 7


def code_part(line: str) -> str:
    """去掉行尾注释，但不把网址里的 // 当注释（https://… 之后写的仍然是代码）。"""
    m = re.search(r"(?<!:)//", line)
    return line[: m.start()] if m else line


def scan(text: str, machine: bool = False):
    hits = []
    for no, line in enumerate(text.splitlines(), 1):
        code = code_part(line)
        if not code.strip():
            continue
        for why, rx in RULES:
            if rx.search(code):
                hits.append((no, why, line.strip()))
        if machine:
            for literal in STRING_LITERAL.findall(code):
                token = MACHINE_TOKEN.search(literal)
                if token and len(token.group(0)) >= 5:
                    hits.append((no, "界面上的机器话", line.strip()))
                    break
    return hits


def self_test() -> bool:
    fixture = "\n".join(
        [
            ".font(.system(size: 15))",
            ".font(.system(size:15))",
            "Font.system(size: 15)",
            ".font(Font.system(size: 15))",
            '.font(.custom("Pace", size: 15))',
            "UIFont.systemFont(ofSize: 15)",
            ".minimumScaleFactor(0.8)",
            ".font(.system(size: scaledSize))",
            ".font(.system(size: displaySize))",
            "// 注释里提到 .font(.system(size: 15)) 不算",
            'let url = "https://example.com"; Text("x").font(.system(size: 15))',
        ]
    )
    caught = scan(fixture)
    # 最后一行是「同一行里先有个网址，后面又写了违规字号」：网址里的 // 不能被当注释，
    # 否则从网址处截断，后面的违规就漏了。所以这一行也要抓到。
    expected = FIXTURE_EXPECTED + 1
    if len(caught) != expected:
        print(f"::error::自检没过：样本应当抓到 {expected} 处，实际抓到 {len(caught)} 处。"
              "检查本身坏了，别再信它的「干净」。")
        for c in caught:
            print("   抓到:", c)
        return False
    # 机器话这条只查 Copy.swift：别处字符串里出现错误码是分支判断，不是界面文字。
    if scan('Text("IMPORT_MALFORMED_JSON")', machine=True).__len__() != 1:
        print("::error::自检没过：Copy 里的错误码应当被抓到，实际没抓到。")
        return False
    if scan('let IMPORT_MALFORMED_JSON = 1', machine=True):
        print("::error::自检没过：标识符里的全大写不该被判红。")
        return False
    print(f"自检通过：样本 {expected} 处违反写法全部抓到，变量写法 0 误报，注释里的写法 0 误报，"
          "标识符里的全大写 0 误报。")
    return True


def main(argv: list[str]) -> int:
    if not self_test():
        return 1

    if len(argv) > 1:
        targets = [pathlib.Path(p) for p in argv[1:]]
    else:
        targets = sorted(pathlib.Path("iosApp").rglob("*.swift"))

    bad = []
    for path in targets:
        # 机器话只查文案文件：别处的全大写字符串是分支判断，不是界面文字。
        check_machine = path.name == "Copy.swift"
        for no, why, text in scan(path.read_text(encoding="utf-8"), machine=check_machine):
            bad.append((path, no, why, text))

    for path, no, why, text in bad:
        print(f"::error file={path},line={no}::{why}：{text}")

    if bad:
        print(f"\n共 {len(bad)} 处。")
        if any(why == "界面上的机器话" for _, _, why, _ in bad):
            print("界面上不许出现机器话：Copy 里的字是给人读的，错误码请留在日志里。")
        if any(why != "界面上的机器话" for _, _, why, _ in bad):
            print("字号请走 paceFont(base, …) 这类基准缩放；放不下就改布局，不许缩字。")
        return 1
    print("写死的字号 0 处，minimumScaleFactor 0 处，界面上的机器话 0 处。")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
