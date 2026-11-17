"""Run with Python + lupa (Lua 5.1); no game or account access required."""
from pathlib import Path
import sys

if len(sys.argv) > 1:
    sys.path.insert(0, sys.argv[1])
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
for path in root.glob("*.lua"):
    lua.execute("assert(loadstring(...))", path.read_text(encoding="utf-8"))
lua.execute((root / "tests/mock.lua").read_text(encoding="utf-8"))
ns = lua.table()
for name in ["Core", "Layouts", "Skin", "Glyphs", "TextSafety", "Inventory", "FocusTracker", "Keyboard", "AuctionFilters", "AuctionData", "AuctionStyle", "AuctionTransactions", "AuctionTradeUI", "AuctionHouse"]:
    lua.execute((root / (name + ".lua")).read_text(encoding="utf-8"), "EnhancedBlizzardGamepad", ns)
lua.globals().ns = ns
lua.execute((root / "tests/regression.lua").read_text(encoding="utf-8"))
print(lua.globals().messages[len(lua.globals().messages)])
lua.execute((root / "tests/transactions.lua").read_text(encoding="utf-8"))
print(lua.globals().messages[len(lua.globals().messages)])
print("Lua 5.1: all addon files parsed; regression checks passed.")
