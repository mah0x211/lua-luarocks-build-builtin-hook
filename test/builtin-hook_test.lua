require("luacov")

-- Mock framework
local function mock(name, table)
    package.loaded[name] = table
end

-- Mock dependencies
local mock_builtin = {
    run_called = 0,
    run_result = true,
    run_error = nil,
}
mock_builtin.reset = function(self)
    self.run_called = 0
    self.run_result = true
    self.run_error = nil
end
mock_builtin.run = function(rockspec, no_install)
    mock_builtin.run_called = mock_builtin.run_called + 1
    return mock_builtin.run_result, mock_builtin.run_error
end
mock("luarocks.build.builtin", mock_builtin)

local mock_fs = {
    exists_result = true,
    execute_result = true,
    executed_cmds = {},
}
mock_fs.reset = function(self)
    self.exists_result = true
    self.execute_result = true
    self.executed_cmds = {}
end
mock_fs.exists = function(path)
    return mock_fs.exists_result
end
mock_fs.Q = function(s)
    return "'" .. s .. "'"
end
mock_fs.execute = function(cmd)
    table.insert(mock_fs.executed_cmds, cmd)
    return mock_fs.execute_result
end
mock("luarocks.fs", mock_fs)

local mock_cfg = {
    variables = {
        LUA = "lua",
    },
}
mock("luarocks.core.cfg", mock_cfg)

local mock_util = {
    printout = function(...)
    end,
}
mock("luarocks.util", mock_util)

-- Load module under test
local builtin_hook = require("luarocks.build.builtin-hook")

-- Test Helper
local function run_test(name, func)
    io.write("Running " .. name .. "... ")
    mock_builtin:reset()
    mock_fs:reset()
    local status, err = pcall(func)
    if status then
        print("OK")
    else
        print("FAIL")
        print(err)
        os.exit(1)
    end
end

local function assert_true(val, msg)
    if not val then
        error((msg or "Expected true") .. ", got " .. tostring(val))
    end
end

local function assert_false(val, msg)
    if val then
        error((msg or "Expected false") .. ", got " .. tostring(val))
    end
end

local function assert_equal(expected, actual, msg)
    if expected ~= actual then
        error((msg or "") .. " Expected " .. tostring(expected) .. ", got " ..
                  tostring(actual))
    end
end

-- Tests

run_test("No Hooks", function()
    local rockspec = {
        build = {},
    }
    local ok, _ = builtin_hook.run(rockspec)
    assert_true(ok)
    assert_equal(1, mock_builtin.run_called, "builtin.run should be called once")
end)

run_test("Before Hook Success", function()
    local rockspec = {
        build = {
            before_build = "pre.lua",
        },
    }
    local ok, _ = builtin_hook.run(rockspec)
    assert_true(ok)
    assert_equal(1, #mock_fs.executed_cmds, "Should execute 1 hook")
    assert_true(mock_fs.executed_cmds[1]:find("pre.lua"),
                "Command should be pre.lua")
    assert_equal(1, mock_builtin.run_called, "builtin.run should be called")
end)

run_test("Before Hook Fail", function()
    local rockspec = {
        build = {
            before_build = "pre.lua",
        },
    }
    mock_fs.execute_result = false
    local ok, err = builtin_hook.run(rockspec)
    assert_false(ok, "Should fail")
    assert_true(string.find(err, "Failed to run before_build"),
                "Should return correct error")
    assert_equal(0, mock_builtin.run_called, "builtin.run should NOT be called")
end)

run_test("After Hook Success", function()
    local rockspec = {
        build = {
            after_build = "post.lua",
        },
    }
    local ok, _ = builtin_hook.run(rockspec)
    assert_true(ok)
    assert_equal(1, #mock_fs.executed_cmds, "Should execute 1 hook")
    assert_true(mock_fs.executed_cmds[1]:find("post.lua"),
                "Command should be post.lua")
    assert_equal(1, mock_builtin.run_called, "builtin.run should be called")
end)

run_test("After Hook Fail", function()
    local rockspec = {
        build = {
            after_build = "post.lua",
        },
    }
    mock_fs.execute_result = false -- Setting execute to fail
    -- Note: verify reset works
    mock_builtin.run_result = true

    local ok, err = builtin_hook.run(rockspec)
    assert_false(ok, "Should fail")
    assert_true(string.find(err, "Failed to run after_build"),
                "Should return correct error")
    assert_equal(1, mock_builtin.run_called,
                 "builtin.run SHOULD be called before after_build fails")
end)

run_test("Builtin Fail", function()
    local rockspec = {
        build = {
            after_build = "post.lua",
        },
    }
    mock_builtin.run_result = nil
    mock_builtin.run_error = "Builtin error"

    local ok, err = builtin_hook.run(rockspec)
    assert_false(ok)
    assert_equal("Builtin error", err)
    assert_equal(0, #mock_fs.executed_cmds,
                 "After hook should NOT run if builtin fails")
end)

run_test("Hook File Not Found", function()
    local rockspec = {
        build = {
            before_build = "missing.lua",
        },
    }
    mock_fs.exists_result = false

    local ok, err = builtin_hook.run(rockspec)
    assert_false(ok)
    assert_true(string.find(err, "Hook script not found"),
                "Should report missing file")
end)

print("All tests passed!")
