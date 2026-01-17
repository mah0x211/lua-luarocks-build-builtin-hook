--
-- Copyright (C) 2026 Masatoshi Fukunaga
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.
--
local concat = table.concat
local unpack = unpack or table.unpack
local builtin = require("luarocks.build.builtin")
local fs = require("luarocks.fs")
local util = require("luarocks.util")

--- Create a shallow copy of a table, recursively copying any nested tables.
local function copy_table(tbl, visited)
    if tbl == nil then
        return nil
    end

    visited = visited or {}
    if visited[tbl] then
        return visited[tbl]
    end

    local t2 = {}
    visited[tbl] = t2
    for k, v in pairs(tbl) do
        if type(v) == "table" then
            v = copy_table(v, visited)
        end
        t2[k] = v
    end
    return t2
end

--- Create an environment table for executing hook scripts.
local function getenv()
    local env = {
        _G = nil, -- placeholder
        _VERSION = _VERSION,

        -- Lua 5.1
        assert = assert,
        collectgarbage = collectgarbage,
        dofile = dofile,
        error = error,
        getfenv = getfenv,
        getmetatable = getmetatable,
        ipairs = ipairs,
        load = load,
        loadfile = loadfile,
        loadstring = loadstring,
        module = module,
        next = next,
        pairs = pairs,
        pcall = pcall,
        print = print,
        rawequal = rawequal,
        rawget = rawget,
        rawset = rawset,
        require = require,
        select = select,
        setfenv = setfenv,
        setmetatable = setmetatable,
        tonumber = tonumber,
        tostring = tostring,
        type = type,
        xpcall = xpcall,

        coroutine = copy_table(coroutine),
        debug = copy_table(debug),
        io = copy_table(io),
        math = copy_table(math),
        os = copy_table(os),
        package = copy_table(package),
        string = copy_table(string),
        table = copy_table(table),

        unpack = unpack or table.unpack, -- table.unpack in Lua 5.2+
        bit32 = copy_table(_G.bit32), -- Lua 5.2+
        warn = _G.warn, -- Lua 5.4+
        utf8 = copy_table(_G.utf8), -- Lua 5.3+
    }
    env._G = env
    return env
end

--- Load a hook file as a chunk.
--- @param pathname string The hook file path.
--- @return function? chunk fn The loaded chunk, or nil on failure.
--- @return any err An error message on failure.
local function load_hook(pathname)
    -- Load as file
    if not fs.exists(pathname) then
        return nil, ("%q hook script not found"):format(pathname)
    end

    local env = getenv()
    local chunk, err
    if _G.setfenv then
        chunk, err = loadfile(pathname)
        if chunk then
            _G.setfenv(chunk, env)
        end
    else
        chunk, err = loadfile(pathname, "bt", env)
    end

    if err then
        return nil, ("Failed to load hook script %q: %s"):format(pathname, err)
    end
    return chunk
end

--- Load a builtin hook module from its name.
--- @param pathname string The hook string to parse.
--- @return function? fn The loaded module, or nil on failure.
--- @return any err An error message on failure.
local function load_builtin_hook(pathname)
    local whole, name = pathname:match("^(%s*%$%(([^)%s]*))")
    if not whole then
        -- Not a builtin hook attempt
        return
    elseif not pathname:find("^%)%s*$", #whole + 1) then
        return nil, "Invalid builtin hook syntax"
    elseif #name == 0 then
        return nil, "Invalid builtin hook syntax: missing name"
    end

    -- Load hook as submodule via require
    local ok, mod = pcall(require, "luarocks.build.builtin-hook." .. name)
    if not ok then
        return nil, ("Failed to load builtin-hook %s: %s"):format(name, mod)
    elseif type(mod) ~= "function" then
        return nil, ("Invalid builtin-hook %s: not a function"):format(name)
    end
    return mod
end

--- @class builtin.hook
--- @field spec_name string The name of the hook in the rockspec.
--- @field value string The original hook string.
--- @field pathname string The hook file path.
--- @field args string[] The arguments to pass to the hook
--- @field func function The loaded hook function.

--- Parse a hook string into its components.
--- @param str string The hook string to parse.
--- @return builtin.hook? hook The parsed hook
--- @return any err An error message on failure.
local function parse_hook(str)
    local hook = {
        args = {},
    }
    for match in str:gmatch('([^%s]+)') do
        hook.args[#hook.args + 1] = match
    end
    -- Reconstruct original hook string
    hook.value = concat(hook.args, " ")
    -- First argument is the hook pathname
    hook.pathname = table.remove(hook.args, 1)

    -- Try to load as builtin hook
    local err
    hook.func, err = load_builtin_hook(hook.pathname)
    if not err and not hook.func then
        -- Load as script file
        hook.func, err = load_hook(hook.pathname)
    end

    if err then
        -- Failed to load as builtin hook
        return nil, err
    end
    return hook
end

local function parse_hooks(rockspec, name)
    local spec_key = 'build.' .. name
    local build = rockspec.build
    local hooks = build[name]
    if not hooks then
        return {} -- no hooks
    end

    local is_array = false
    local hook_type = type(hooks)
    if hook_type == 'string' then
        hooks = {
            build[name],
        }
    elseif hook_type ~= 'table' then
        return nil, "Invalid hook type: " .. hook_type
    elseif #hooks == 0 then
        return {} -- no hooks
    else
        is_array = true
        -- confirm it's an array of strings
        local nhooks = #hooks
        local count = 0
        for _, v in pairs(hooks) do
            count = count + 1
            if count > nhooks or type(v) ~= "string" then
                return nil, ("%s must be an array of strings"):format(spec_key)
            end
        end
    end

    -- parse hooks
    for i, str in ipairs(hooks) do
        local idx = is_array and ("#%d"):format(i) or ""
        local t = type(str)
        if t ~= 'string' then
            return nil, ("%s%s must be a string: %s"):format(spec_key, idx, t)
        end

        -- parse hook string
        local hook, err = parse_hook(str)
        if err then
            return nil, ("%s%s: %s"):format(spec_key, idx, err)
        end
        hook.spec_name = ("%s%s"):format(spec_key, idx)
        hooks[i] = hook
    end

    return hooks
end

local function run_hook(hook, rockspec)
    return xpcall(function()
        hook.func(rockspec, unpack(hook.args))
    end, debug.traceback)
end

local function run(rockspec, no_install)
    local before_hooks, after_hooks, err

    -- Parse before_build hooks
    before_hooks, err = parse_hooks(rockspec, "before_build")
    if not before_hooks then
        return nil, err
    end
    after_hooks, err = parse_hooks(rockspec, "after_build")
    if not after_hooks then
        return nil, err
    end

    -- 1. Run before_build if present
    local ok
    for _, hook in ipairs(before_hooks) do
        util.printout("Running hook: " .. hook.value)
        ok, err = run_hook(hook, rockspec)
        if not ok then
            return false, ("Failed to run %q: %s"):format(hook.spec_name, err)
        end
    end

    -- 2. Delegate to standard builtin backend
    ok, err = builtin.run(rockspec, no_install)
    if not ok then
        return nil, err
    end

    -- 3. Run after_build if present
    for _, hook in ipairs(after_hooks) do
        util.printout("Running hook: " .. hook.value)
        ok, err = run_hook(hook, rockspec)
        if not ok then
            return false, ("Failed to run %q: %s"):format(hook.spec_name, err)
        end
    end

    return true
end

return {
    run = run,
}
