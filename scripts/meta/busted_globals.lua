---@meta

-- Under plenary.nvim's Busted runner, the global `assert` is replaced with a
-- Luassert instance. The `Luassert` class is defined in
-- `.dev/lua/plenary/lua/plenary/_meta/_luassert.lua`; this stub retypes the
-- global so LuaLS resolves `assert.equals`, `assert.truthy`, etc. in spec
-- files that do not locally `require("luassert")`.
--
-- Only consumed by LuaLS via `workspace.library` in `.luarc.json`.

---@type Luassert
assert = nil
