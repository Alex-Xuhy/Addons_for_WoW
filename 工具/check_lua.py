"""对插件目录里的所有 .lua 做语法编译检查（不执行）。

用法：
    python -I check_lua.py <插件目录> [lupa所在的目录]

依赖 lupa（提供 LuaJIT，语法与 Lua 5.1 兼容）：
    python -m pip install --target <某个临时目录> lupa

注意：-I 会忽略 PYTHONPATH，所以 lupa 的目录要从命令行传进来，
      由脚本自己插进 sys.path。
"""
import glob
import io
import os
import sys

if len(sys.argv) > 2:
    sys.path.insert(0, sys.argv[2])

import lupa

lua = lupa.LuaRuntime()

target = sys.argv[1] if len(sys.argv) > 1 else "."
files = sorted(glob.glob(os.path.join(target, "*.lua")))

if not files:
    print("没找到 .lua 文件：%s" % target)
    sys.exit(2)

failed = 0
for path in files:
    with io.open(path, encoding="utf-8") as handle:
        source = handle.read()
    try:
        lua.compile(source)
        print("  OK    %-16s %5d 行" % (os.path.basename(path), source.count("\n") + 1))
    except Exception as exc:  # noqa: BLE001 - 要把任何编译错误都报出来
        failed += 1
        print("  FAIL  %-16s" % os.path.basename(path))
        print("        %s" % exc)

print()
print("共 %d 个文件，失败 %d 个" % (len(files), failed))
sys.exit(1 if failed else 0)
