require("luacov")

-- Load module under test
local append_extra_vars = require("luarocks.build.hooks.extra-vars")

-- Mock os.getenv for testing
local mock_env = {}
local function setenv(k, v)
    mock_env[k] = v
end

local getenv = os.getenv
-- Mock os.getenv to use mock_env table
os.getenv = function(k) -- luacheck: ignore
    return mock_env[k] or getenv(k)
end

-- Test Helper
local function run_test(name, func)
    io.write("Running " .. name .. "... ")
    mock_env = {} -- Reset env vars
    local status, err = xpcall(func, debug.traceback)
    if status then
        print("OK")
    else
        print("FAIL")
        print(err)
        os.exit(1)
    end
end

local function assert_equal(expected, actual, msg)
    if expected ~= actual then
        error((msg or "") .. " Expected " .. tostring(expected) .. ", got " ..
                  tostring(actual), 2)
    end
end

local function assert_not_nil(val, msg)
    if val == nil then
        error((msg or "") .. " Expected non-nil value", 2)
    end
end

local function assert_match(pattern, str, msg)
    if not str:match(pattern) then
        error((msg or "") .. " Expected " .. tostring(str) .. " to match " ..
                  tostring(pattern), 2)
    end
end

-- Helper function to create a basic rockspec
local function create_rockspec(variables, extra_variables, conditional_variables)
    return {
        variables = variables or {},
        build = {
            extra_variables = extra_variables,
            conditional_variables = conditional_variables,
        },
    }
end

-- Tests

run_test("No extra_variables field", function()
    local rockspec = {
        variables = {
            CFLAGS = "-O2",
        },
        build = {
            -- extra_variables field is not set
        },
    }
    append_extra_vars(rockspec)
    assert_equal("-O2", rockspec.variables.CFLAGS)
end)

run_test("No extra_variables", function()
    local rockspec = create_rockspec({
        CFLAGS = "-O2",
    }, nil)
    append_extra_vars(rockspec)
    assert_equal("-O2", rockspec.variables.CFLAGS)
end)

run_test("String value append", function()
    local rockspec = create_rockspec({
        CFLAGS = "-O2",
    }, {
        CFLAGS = "-Wall",
    })
    append_extra_vars(rockspec)
    assert_match("^%-O2 %-Wall$", rockspec.variables.CFLAGS)
end)

run_test("Array of strings value", function()
    local rockspec = create_rockspec({
        CFLAGS = "-O2",
    }, {
        CFLAGS = {
            "-Wall",
            "-Wextra",
        },
    })
    append_extra_vars(rockspec)
    assert_match("^%-O2 %-Wall %-Wextra$", rockspec.variables.CFLAGS)
end)

run_test("Whitespace trimming (string)", function()
    local rockspec = create_rockspec({
        CFLAGS = "  -O2  ",
    }, {
        CFLAGS = "  -Wall  ",
    })
    append_extra_vars(rockspec)
    assert_equal("-O2 -Wall", rockspec.variables.CFLAGS)
end)

run_test("Whitespace trimming (array)", function()
    local rockspec = create_rockspec({
        CFLAGS = "  -O2  ",
    }, {
        CFLAGS = {
            "  -Wall  ",
            "  -Wextra  ",
        },
    })
    append_extra_vars(rockspec)
    assert_equal("-O2 -Wall -Wextra", rockspec.variables.CFLAGS)
end)

run_test("Empty strings in array are filtered", function()
    local rockspec = create_rockspec({
        CFLAGS = "-O2",
    }, {
        CFLAGS = {
            "-Wall",
            "",
            "  ",
            "-Wextra",
        },
    })
    append_extra_vars(rockspec)
    assert_equal("-O2 -Wall -Wextra", rockspec.variables.CFLAGS)
end)

run_test("Skip non-existing variable", function()
    local rockspec = create_rockspec({
        CFLAGS = "-O2",
    }, {
        NONEXISTENT = "--should-not-append",
    })
    append_extra_vars(rockspec)
    assert_equal("-O2", rockspec.variables.CFLAGS)
end)

run_test("Skip empty variable", function()
    local rockspec = create_rockspec({
        CFLAGS = "",
    }, {
        CFLAGS = "-Wall",
    })
    append_extra_vars(rockspec)
    -- Empty variable should remain unchanged (cannot append to empty)
    assert_equal("", rockspec.variables.CFLAGS)
end)

run_test("Skip non-string variable", function()
    local rockspec = create_rockspec({
        CFLAGS = 123,
    }, {
        CFLAGS = "-Wall",
    })
    append_extra_vars(rockspec)
    assert_equal(123, rockspec.variables.CFLAGS)
end)

run_test("Multiple variables", function()
    local rockspec = create_rockspec({
        CFLAGS = "-O2",
        LIBFLAG = "-shared",
    }, {
        CFLAGS = "-Wall",
        LIBFLAG = "-fPIC",
    })
    append_extra_vars(rockspec)
    assert_match("^%-O2 %-Wall$", rockspec.variables.CFLAGS)
    assert_match("^%-shared %-fPIC$", rockspec.variables.LIBFLAG)
end)

run_test("Invalid value type (number)", function()
    local rockspec = create_rockspec({
        CFLAGS = "-O2",
    }, {
        CFLAGS = 123,
    })
    local ok, err = pcall(append_extra_vars, rockspec)
    assert_equal(false, ok)
    assert_not_nil(err:match("variable%-value must be a string"))
end)

run_test("Invalid value in array (number)", function()
    local rockspec = create_rockspec({
        CFLAGS = "-O2",
    }, {
        CFLAGS = {
            "-Wall",
            123,
            "-Wextra",
        },
    })
    local ok, err = pcall(append_extra_vars, rockspec)
    assert_equal(false, ok)
    assert_not_nil(err:match("variable%-value#%d+ must be a string"))
end)

run_test("Non-array table (hash keys)", function()
    local rockspec = create_rockspec({
        CFLAGS = "-O2",
    }, {
        CFLAGS = {
            key = "value",
        },
    })
    local ok, err = pcall(append_extra_vars, rockspec)
    assert_equal(false, ok)
    assert_not_nil(err:match("variable%-value#%S+ must be a string"))
end)

run_test("Invalid extra_variables type", function()
    local rockspec = {
        variables = {
            CFLAGS = "-O2",
        },
        build = {
            extra_variables = "invalid",
        },
    }
    local ok, err = pcall(append_extra_vars, rockspec)
    assert_equal(false, ok)
    assert_not_nil(err:match("build%.extra_variables should be a table"))
end)

run_test("Invalid variable name type", function()
    local rockspec = {
        variables = {
            CFLAGS = "-O2",
        },
        build = {
            extra_variables = {
                [123] = "-Wall",
            },
        },
    }
    local ok, err = pcall(append_extra_vars, rockspec)
    assert_equal(false, ok)
    assert_not_nil(err:match("variable%-name must be a string"))
end)

run_test("Empty string value", function()
    local rockspec = create_rockspec({
        CFLAGS = "-O2",
    }, {
        CFLAGS = "",
    })
    append_extra_vars(rockspec)
    assert_equal("-O2", rockspec.variables.CFLAGS)
end)

run_test("Empty array value", function()
    local rockspec = create_rockspec({
        CFLAGS = "-O2",
    }, {
        CFLAGS = {},
    })
    append_extra_vars(rockspec)
    assert_equal("-O2", rockspec.variables.CFLAGS)
end)

run_test("Array with only empty strings", function()
    local rockspec = create_rockspec({
        CFLAGS = "-O2",
    }, {
        CFLAGS = {
            "",
            "  ",
            "",
        },
    })
    append_extra_vars(rockspec)
    assert_equal("-O2", rockspec.variables.CFLAGS)
end)

run_test("Conditional variables (Enabled: '1')", function()
    local rockspec = create_rockspec({
        CFLAGS = "-O2",
        LIBFLAG = "-shared",
    }, nil, {
        ENABLE_COVERAGE = {
            CFLAGS = "--coverage",
            LIBFLAG = "--coverage",
        },
    })
    setenv("ENABLE_COVERAGE", "1")
    append_extra_vars(rockspec)
    assert_match("^%-O2 %-%-coverage$", rockspec.variables.CFLAGS)
    assert_match("^%-shared %-%-coverage$", rockspec.variables.LIBFLAG)
end)

run_test("Conditional variables (Disabled: empty string)", function()
    local rockspec = create_rockspec({
        CFLAGS = "-O2",
        LIBFLAG = "-shared",
    }, nil, {
        ENABLE_COVERAGE = {
            CFLAGS = "--coverage",
            LIBFLAG = "--coverage",
        },
    })
    setenv("ENABLE_COVERAGE", "")
    append_extra_vars(rockspec)
    -- Expect NO coverage flags appended
    assert_equal("-O2", rockspec.variables.CFLAGS)
    assert_equal("-shared", rockspec.variables.LIBFLAG)
end)

run_test("Conditional variables (Enabled: boolean true)", function()
    local rockspec = create_rockspec({
        CFLAGS = "-O2",
        LIBFLAG = "-shared",
    }, nil, {
        ENABLE_COVERAGE = {
            CFLAGS = "--coverage",
            LIBFLAG = "--coverage",
        },
    })
    setenv("ENABLE_COVERAGE", "true")
    append_extra_vars(rockspec)
    assert_match("^%-O2 %-%-coverage$", rockspec.variables.CFLAGS)
    assert_match("^%-shared %-%-coverage$", rockspec.variables.LIBFLAG)
end)

run_test("Conditional variables (Disabled: '0')", function()
    local rockspec = create_rockspec({
        CFLAGS = "-O2",
    }, nil, {
        ENABLE_COVERAGE = {
            CFLAGS = "--coverage",
        },
    })
    setenv("ENABLE_COVERAGE", "0")
    append_extra_vars(rockspec)
    assert_equal("-O2", rockspec.variables.CFLAGS)
end)

run_test("Conditional variables (Disabled: 'false')", function()
    local rockspec = create_rockspec({
        CFLAGS = "-O2",
    }, nil, {
        ENABLE_COVERAGE = {
            CFLAGS = "--coverage",
        },
    })
    setenv("ENABLE_COVERAGE", "false")
    append_extra_vars(rockspec)
    assert_equal("-O2", rockspec.variables.CFLAGS)
end)

run_test("Conditional variables (Disabled: nil)", function()
    local rockspec = create_rockspec({
        CFLAGS = "-O2",
    }, nil, {
        ENABLE_COVERAGE = {
            CFLAGS = "--coverage",
        },
    })
    -- ENABLE_COVERAGE is nil
    append_extra_vars(rockspec)
    assert_equal("-O2", rockspec.variables.CFLAGS)
end)

run_test("Mixed Order: extra_variables first, then conditional", function()
    local rockspec = create_rockspec({
        CFLAGS = "-O2",
    }, {
        CFLAGS = "-Wall",
    }, {
        DEBUG = {
            CFLAGS = "-DDEBUG",
        },
    })
    setenv("DEBUG", "1")
    append_extra_vars(rockspec)
    assert_match("^%-O2 %-Wall %-DDEBUG$", rockspec.variables.CFLAGS)
end)

run_test("Invalid conditional_variables type", function()
    local rockspec = {
        variables = {
            CFLAGS = "-O2",
        },
        build = {
            conditional_variables = "invalid",
        },
    }
    local ok, err = pcall(append_extra_vars, rockspec)
    assert_equal(false, ok)
    assert_not_nil(err:match("build%.conditional_variables should be a table"))
end)

run_test("Invalid conditional flag name type", function()
    local rockspec = {
        variables = {
            CFLAGS = "-O2",
        },
        build = {
            conditional_variables = {
                [123] = {
                    CFLAGS = "-Wall",
                },
            },
        },
    }
    local ok, err = pcall(append_extra_vars, rockspec)
    assert_equal(false, ok)
    assert_not_nil(err:match("conditional_variables flag name must be a string"))
end)

run_test("Invalid conditional variables value type", function()
    local rockspec = {
        variables = {
            CFLAGS = "-O2",
            FLAG = "1",
        },
        build = {
            conditional_variables = {
                FLAG = "not a table",
            },
        },
    }
    local ok, err = pcall(append_extra_vars, rockspec)
    assert_equal(false, ok)
    assert_not_nil(err:match('conditional_variables%["FLAG"%] must be a table'))
end)

-- Restore original getenv
os.getenv = getenv -- luacheck: ignore
print("All extra-vars tests passed!")
