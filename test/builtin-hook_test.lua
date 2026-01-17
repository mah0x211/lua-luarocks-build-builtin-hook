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
}
mock_fs.reset = function(self)
    self.exists_result = true
end
mock_fs.exists = function(path)
    return mock_fs.exists_result
end
mock_fs.Q = function(s)
    return "'" .. s .. "'"
end
mock_fs.execute = function(cmd)
    table.insert(mock_fs.executed_cmds, cmd or "")
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

-- Global Mock for loadfile and setfenv (after loading module)
local mock_chunk_func = nil
local mock_env_captured = nil

local original_loadfile = _G.loadfile
function _G.loadfile(filename, mode, env)
    if not filename:match("^lua/") then
        if env then
            mock_env_captured = env
        end
        return function(...)
            if mock_chunk_func then
                return mock_chunk_func(...)
            end
        end
    end
    return original_loadfile(filename, mode, env)
end

if _G.setfenv then
    local original_setfenv = _G.setfenv
    _G.setfenv = function(f, env)
        mock_env_captured = env
        return original_setfenv(f, env)
    end
end

-- Test Helper
local function run_test(name, func)
    io.write("Running " .. name .. "... ")
    mock_builtin:reset()
    mock_fs:reset()
    mock_chunk_func = nil
    mock_env_captured = nil
    local status, err = xpcall(func, debug.traceback)
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
        variables = {
            TARGET = "original",
        },
    }
    -- Verify rockspec is passed as argument (...)
    -- and that modifications are visible to builtin.run
    mock_chunk_func = function(rs)
        rs.variables.TARGET = "modified"
    end

    local original_builtin_run = mock_builtin.run
    local captured_rs_at_run = nil
    mock_builtin.run = function(rs, no_install)
        captured_rs_at_run = rs
        return original_builtin_run(rs, no_install)
    end

    local ok, _ = builtin_hook.run(rockspec)
    mock_builtin.run = original_builtin_run -- restore

    assert_true(ok)
    assert_equal("modified", rockspec.variables.TARGET,
                 "Rockspec should be modified by hook")
    assert_equal("modified", captured_rs_at_run.variables.TARGET,
                 "Builtin should see modifications")
    assert_true(mock_env_captured ~= nil, "Should capture environment")
    assert_true(mock_env_captured.type ~= nil, "Environment should contain type")
end)

run_test("Before Hook Fail", function()
    local rockspec = {
        build = {
            before_build = "pre.lua",
        },
    }
    mock_chunk_func = function()
        error("Simulated failure")
    end
    local ok, err = builtin_hook.run(rockspec)
    assert_false(ok, "Should fail")
    assert_true(string.find(err, "Simulated failure"),
                "Should return correct error")
    assert_equal(0, mock_builtin.run_called, "builtin.run should NOT be called")
end)

run_test("After Hook Success", function()
    local rockspec = {
        build = {
            after_build = "post.lua",
        },
    }
    local captured_rs_at_hook = nil
    mock_chunk_func = function(rs)
        captured_rs_at_hook = rs
    end

    local ok, _ = builtin_hook.run(rockspec)
    assert_true(ok)
    assert_equal(rockspec, captured_rs_at_hook,
                 "Should receive rockspec as argument")
    assert_true(mock_env_captured ~= nil, "Should capture environment")
    assert_equal(1, mock_builtin.run_called, "builtin.run should be called")
end)

run_test("After Hook Fail", function()
    local rockspec = {
        build = {
            after_build = "post.lua",
        },
    }
    mock_chunk_func = function()
        error("Simulated failure")
    end
    -- Note: verify reset works
    mock_builtin.run_result = true

    local ok, err = builtin_hook.run(rockspec)
    assert_false(ok, "Should fail")
    assert_true(string.find(err, "Simulated failure"),
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

    local hook_called = false
    mock_chunk_func = function()
        hook_called = true
    end

    local ok, err = builtin_hook.run(rockspec)
    assert_false(ok)
    assert_equal("Builtin error", err)
    assert_false(hook_called, "After hook should NOT run if builtin fails")
end)

run_test("Invalid Lua Hook", function()
    local rockspec = {
        build = {
            before_build = "invalid.lua",
        },
    }
    -- Mock loadfile to return nil and an error message (simulating syntax error)
    local original_loadfile_wrapped = _G.loadfile
    _G.loadfile = function()
        return nil, "syntax error: unexpected symbol"
    end

    local ok, err = builtin_hook.run(rockspec)
    _G.loadfile = original_loadfile_wrapped -- restore

    assert_false(ok)
    assert_true(string.find(err, "syntax error: unexpected symbol"),
                "Should report syntax error from loadfile")
end)

run_test("Submodule Success", function()
    local rockspec = {
        build = {
            before_build = "$(mock-sub)",
        },
    }

    local submodule_called = false
    local captured_rs = nil
    local mock_submodule = function(rs)
        submodule_called = true
        captured_rs = rs
    end

    -- Mock require for our submodule
    local original_require = _G.require
    _G.require = function(modname)
        if modname == "luarocks.build.builtin-hook.mock-sub" then
            return mock_submodule
        end
        return original_require(modname)
    end

    local ok, _ = builtin_hook.run(rockspec)
    _G.require = original_require -- restore

    assert_true(ok)
    assert_true(submodule_called, "Submodule should be called")
    assert_equal(rockspec, captured_rs, "Submodule should receive rockspec")
end)

run_test("pkgconfig Success", function()
    local rockspec = {
        external_dependencies = {
            libfoo = {},
        },
        variables = {},
        build = {
            before_build = "$(pkgconfig)",
            modules = {},
        },
    }

    -- Mock implementation of pkgconfig logic for the test
    local function mock_pkgconfig(rs)
        if rs.external_dependencies and rs.external_dependencies.libfoo then
            rs.variables.LIBFOO_INCDIR = "/usr/include"
            rs.variables.LIBFOO_LIBDIR = "/usr/lib"
        end
    end

    -- Mock require for the submodule
    local original_require = _G.require
    _G.require = function(modname)
        if modname == "luarocks.build.builtin-hook.pkgconfig" then
            return mock_pkgconfig
        end
        return original_require(modname)
    end

    local ok, err = builtin_hook.run(rockspec)
    _G.require = original_require -- restore

    assert_true(ok, "Should run successfully: " .. (err or ""))
    assert_equal("/usr/include", rockspec.variables.LIBFOO_INCDIR)
    assert_equal("/usr/lib", rockspec.variables.LIBFOO_LIBDIR)
end)

run_test("Invalid Builtin Hook Syntax", function()
    local cases = {
        ["$(ok)extra"] = "Invalid builtin hook syntax",
        ["$(ok"] = "Invalid builtin hook syntax",
        ["$()"] = "missing name",
    }

    for input, expected_err in pairs(cases) do
        local rockspec = {
            build = {
                before_build = input,
            },
        }
        local ok, err = builtin_hook.run(rockspec)
        assert_false(ok, "Should fail for input: " .. input)
        assert_true(string.find(err, expected_err),
                    "Should report error '" .. expected_err .. "' for input: " ..
                        input .. " got: " .. tostring(err))
    end
end)

run_test("Builtin Hook Load Failure", function()
    local rockspec = {
        build = {
            before_build = "$(fail-load)",
        },
    }

    local original_require = _G.require
    _G.require = function(modname)
        if modname == "luarocks.build.builtin-hook.fail-load" then
            error("module not found")
        end
        return original_require(modname)
    end

    local ok, err = builtin_hook.run(rockspec)
    _G.require = original_require

    assert_false(ok)
    assert_true(string.find(err, "Failed to load builtin-hook", 1, true),
                "Should report load failure: " .. (err or ""))
end)

run_test("Builtin Hook Run Failure", function()
    local rockspec = {
        build = {
            before_build = "$(fail-run)",
        },
    }

    local original_require = _G.require
    _G.require = function(modname)
        if modname == "luarocks.build.builtin-hook.fail-run" then
            return function()
                error("runtime error in builtin-hook")
            end
        end
        return original_require(modname)
    end

    local ok, err = builtin_hook.run(rockspec)
    _G.require = original_require

    assert_false(ok)
    assert_true(string.find(err, "Failed to run", 1, true),
                "Should report run failure: " .. (err or ""))
end)

run_test("Hook Script Not Found", function()
    local rockspec = {
        build = {
            before_build = "non-existent.lua",
        },
    }

    -- Mock mock_fs.exists to return false
    local original_exists = mock_fs.exists
    mock_fs.exists = function()
        return false
    end

    local ok, err = builtin_hook.run(rockspec)
    mock_fs.exists = original_exists

    assert_false(ok)
    assert_true(string.find(err, "hook script not found", 1, true),
                "Should report script not found: " .. (err or ""))
end)

run_test("Multiple Before Hooks Success", function()
    local call_order = {}
    local rockspec = {
        build = {
            before_build = {
                "hook1.lua",
                "hook2.lua",
                "hook3.lua",
            },
        },
    }

    -- Each hook appends its name to call_order
    local call_count = 0
    mock_chunk_func = function(_, _)
        call_count = call_count + 1
        table.insert(call_order, "hook" .. call_count)
    end

    local ok, err = builtin_hook.run(rockspec)
    if not ok then
        print("Error: " .. tostring(err))
    end
    assert_true(ok)
    assert_equal(3, call_count, "All hooks should be called")
    assert_equal("hook1", call_order[1])
    assert_equal("hook2", call_order[2])
    assert_equal("hook3", call_order[3])
end)

run_test("Multiple After Hooks Success", function()
    local call_order = {}
    local rockspec = {
        build = {
            after_build = {
                "post1.lua",
                "post2.lua",
            },
        },
    }

    local call_count = 0
    mock_chunk_func = function(_, _)
        call_count = call_count + 1
        table.insert(call_order, "post" .. call_count)
    end

    local ok, _ = builtin_hook.run(rockspec)
    assert_true(ok)
    assert_equal(2, call_count, "All after hooks should be called")
    assert_equal("post1", call_order[1])
    assert_equal("post2", call_order[2])
end)

run_test("Multiple Hooks With One Failure", function()
    local rockspec = {
        build = {
            before_build = {
                "hook1.lua",
                "hook2.lua",
                "hook3.lua",
            },
        },
    }

    local call_count = 0
    mock_chunk_func = function(_, _)
        call_count = call_count + 1
        if call_count == 2 then
            error("Hook 2 failed")
        end
    end

    local ok, err = builtin_hook.run(rockspec)
    assert_false(ok)
    assert_true(string.find(err, "Hook 2 failed"),
                "Should report hook 2 failure")
    assert_equal(2, call_count, "Should stop at failing hook")
    assert_equal(0, mock_builtin.run_called, "builtin.run should NOT be called")
end)

run_test("Mixed Before And After Hooks", function()
    local before_calls = {}
    local after_calls = {}
    local rockspec = {
        build = {
            before_build = {
                "pre1.lua",
                "pre2.lua",
            },
            after_build = {
                "post1.lua",
                "post2.lua",
            },
        },
    }

    local before_count = 0
    local after_count = 0
    mock_chunk_func = function(_, _)
        if mock_builtin.run_called == 0 then
            before_count = before_count + 1
            table.insert(before_calls, "pre" .. before_count)
        else
            after_count = after_count + 1
            table.insert(after_calls, "post" .. after_count)
        end
    end

    local ok, _ = builtin_hook.run(rockspec)
    assert_true(ok)
    assert_equal(2, #before_calls)
    assert_equal(2, #after_calls)
    assert_equal("pre1", before_calls[1])
    assert_equal("pre2", before_calls[2])
    assert_equal("post1", after_calls[1])
    assert_equal("post2", after_calls[2])
end)

run_test("Invalid Hook Type In Array", function()
    local rockspec = {
        build = {
            before_build = {
                "hook1.lua",
                123,
                "hook2.lua",
            },
        },
    }

    local ok, err = builtin_hook.run(rockspec)
    assert_false(ok)
    assert_true(string.find(err, "must be an array of strings", 1, true),
                "Should report type error: " .. (err or ""))
end)

run_test("Invalid Hook Type Not String Or Table", function()
    local rockspec = {
        build = {
            before_build = 123,
        },
    }

    local ok, err = builtin_hook.run(rockspec)
    assert_false(ok)
    assert_true(string.find(err, "Invalid hook type", 1, true),
                "Should report invalid hook type: " .. (err or ""))
end)

run_test("Hook With Arguments", function()
    local rockspec = {
        build = {
            before_build = {
                "hook1.lua arg1 arg2",
                "hook2.lua",
            },
        },
    }

    local captured_args = {}
    local hook_count = 0
    mock_chunk_func = function(...)
        hook_count = hook_count + 1
        captured_args[hook_count] = {
            ...,
        }
    end

    local ok, err = builtin_hook.run(rockspec)
    if not ok then
        print("Error: " .. tostring(err))
    end
    assert_true(ok)
    assert_equal(2, hook_count)
    assert_equal(3, #captured_args[1],
                 "hook1 should receive 3 args (rockspec + 2 args)")
    assert_equal(rockspec, captured_args[1][1])
    assert_equal("arg1", captured_args[1][2])
    assert_equal("arg2", captured_args[1][3])
    assert_equal(1, #captured_args[2],
                 "hook2 should receive 1 arg (rockspec only)")
    assert_equal(rockspec, captured_args[2][1])
end)

run_test("Builtin Hook With Arguments", function()
    local rockspec = {
        build = {
            before_build = "$(mock-arg) arg1 arg2",
        },
    }

    local captured_args = {}
    local mock_submodule = function(...)
        captured_args = {
            ...,
        }
    end

    local original_require = _G.require
    _G.require = function(modname)
        if modname == "luarocks.build.builtin-hook.mock-arg" then
            return mock_submodule
        end
        return original_require(modname)
    end

    local ok, _ = builtin_hook.run(rockspec)
    _G.require = original_require

    assert_true(ok)
    assert_equal(3, #captured_args,
                 "Builtin hook should receive 3 args (rockspec + 2 args)")
    assert_equal(rockspec, captured_args[1])
    assert_equal("arg1", captured_args[2])
    assert_equal("arg2", captured_args[3])
end)

run_test("Hook With Multiple Arguments", function()
    local rockspec = {
        build = {
            before_build = "hook.lua  --flag1=value1  --flag2=value2  --verbose",
        },
    }

    local captured_args = {}
    mock_chunk_func = function(rs, ...)
        captured_args = {
            rs,
            ...,
        }
    end

    local ok, _ = builtin_hook.run(rockspec)
    assert_true(ok)
    assert_equal(4, #captured_args)
    assert_equal(rockspec, captured_args[1])
    assert_equal("--flag1=value1", captured_args[2])
    assert_equal("--flag2=value2", captured_args[3])
    assert_equal("--verbose", captured_args[4])
end)

run_test("Builtin Hook Not A Function", function()
    local rockspec = {
        build = {
            before_build = "$(not-a-function)",
        },
    }

    local original_require = _G.require
    _G.require = function(modname)
        if modname == "luarocks.build.builtin-hook.not-a-function" then
            return {} -- Return a table instead of a function
        end
        return original_require(modname)
    end

    local ok, err = builtin_hook.run(rockspec)
    _G.require = original_require

    assert_false(ok)
    assert_true(string.find(err, "not a function", 1, true),
                "Should report 'not a function' error: " .. (err or ""))
end)

run_test("Empty Hooks Array", function()
    local rockspec = {
        build = {
            before_build = {},
            after_build = {},
        },
    }

    local ok, _ = builtin_hook.run(rockspec)
    assert_true(ok)
    assert_equal(1, mock_builtin.run_called, "builtin.run should be called once")
end)

run_test("Non-String Element In Hooks Array", function()
    local rockspec = {
        build = {
            before_build = {
                "hook1.lua",
                123,
                "hook2.lua",
            },
        },
    }

    local ok, err = builtin_hook.run(rockspec)
    assert_false(ok)
    -- The pairs loop validates the array and catches non-string elements
    assert_true(string.find(err, "must be an array of strings", 1, true),
                "Should report 'must be an array of strings' error: " ..
                    (err or ""))
end)

run_test("After Build Parse Failure", function()
    local rockspec = {
        build = {
            before_build = "$(mock-sub)", -- Valid builtin hook
            after_build = "non-existent.lua", -- Invalid file hook
        },
    }

    -- Mock require for the valid before_build hook
    local mock_submodule = function(rs)
    end

    local original_require = _G.require
    _G.require = function(modname)
        if modname == "luarocks.build.builtin-hook.mock-sub" then
            return mock_submodule
        end
        return original_require(modname)
    end

    -- Mock fs.exists to return false for non-existent.lua
    local original_exists = mock_fs.exists
    mock_fs.exists = function(path)
        if path:match("non%-existent%.lua$") then
            return false
        end
        return true
    end

    local ok, err = builtin_hook.run(rockspec)
    _G.require = original_require
    mock_fs.exists = original_exists

    assert_false(ok)
    assert_true(string.find(err, "after_build", 1, true),
                "Should report after_build error: " .. (err or ""))
end)

print("All tests passed!")
