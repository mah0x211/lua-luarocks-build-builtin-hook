local builtin = require("luarocks.build.builtin")
local fs = require("luarocks.fs")
local cfg = require("luarocks.core.cfg")
local util = require("luarocks.util")

local function execute_hook(build, name)
    local hook_file = build[name]
    if not hook_file then
        return true
    end

    if not fs.exists(hook_file) then
        return nil, "Hook script not found: " .. hook_file
    end

    util.printout("Running hook: " .. hook_file)

    -- Execute the Lua script using the same Lua interpreter
    -- We use fs.execute to run it as a subprocess to ensure environment isolation
    local cmd = fs.Q(cfg.variables.LUA) .. " " .. fs.Q(hook_file)
    if not fs.execute(cmd) then
        return nil, "Failed to run " .. name
    end
    return true
end

local function run(rockspec, no_install)
    local build = rockspec.build

    -- 1. Run before_build if present
    local ok, err = execute_hook(build, "before_build")
    if not ok then
        return nil, err
    end

    -- 2. Delegate to standard builtin backend
    ok, err = builtin.run(rockspec, no_install)
    if not ok then
        return nil, err
    end

    -- 3. Run after_build if present
    ok, err = execute_hook(build, "after_build")
    if not ok then
        return nil, err
    end

    return true
end

return {
    run = run,
}
