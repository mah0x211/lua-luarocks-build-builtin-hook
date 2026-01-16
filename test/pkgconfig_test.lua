require("luacov")

-- Mock framework
local function mock(name, table)
    package.loaded[name] = table
end

-- Mock dependencies
local mock_util = {
    printout = function(...)
    end,
}
mock("luarocks.util", mock_util)

-- Shell script template for pkg-config queries
local SHELL_SCRIPT = [=[pkg="%s"
pcfile=$(pkg-config --path "$pkg" 2>/dev/null)
if [ -n "$pcfile" ]; then
    # Extract variable definitions
    for v in $(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$pcfile" | sed 's/=.*$//' || true); do
        printf '%%s=%%s\n' "$v" "$(pkg-config --variable="$v" "$pkg" 2>/dev/null)"
    done
    #Extract metadata fields
    grep -E '^(Name|Description|Version):\s*' "$pcfile" | sed 's/:\s*/=/' || true
fi
# Get computed values
printf 'Libs=%%s\n' "$(pkg-config --libs "$pkg" 2>/dev/null || true)"
printf 'Cflags=%%s\n' "$(pkg-config --cflags "$pkg" 2>/dev/null || true)"
printf 'Modversion=%%s\n' "$(pkg-config --modversion "$pkg" 2>/dev/null || true)"
]=]

-- Global Mock for io.popen
local mock_popen_results = {}
function _G.io.popen(cmd)
    local result = mock_popen_results[cmd]
    if result == nil then
        return nil
    end
    -- Return a file-like object that reads line by line
    local lines = {}
    for line in result:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end
    local idx = 0
    return {
        lines = function()
            local i = 0
            return function()
                i = i + 1
                return lines[i]
            end
        end,
        read = function(_, mode)
            if mode == "*l" or mode == "*L" then
                idx = idx + 1
                return lines[idx]
            elseif mode == "*a" then
                return result
            end
            return result
        end,
        close = function()
        end,
    }
end

-- Mock os.execute for pkg-config --exists
local mock_os_execute_results = {}
local _os_execute = os.execute
function _G.os.execute(cmd)
    if cmd:match("^pkg%-config %-%-exists") then
        local result = mock_os_execute_results[cmd]
        if result == nil then
            return 0 -- Default: package exists
        end
        return result
    end
    return _os_execute(cmd)
end

-- Load module under test
local resolve_pkgconfig = require("luarocks.build.builtin-hook.pkgconfig")

-- Test Helper
local function run_test(name, func)
    io.write("Running " .. name .. "... ")
    mock_popen_results = {}
    mock_os_execute_results = {}
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
                  tostring(actual))
    end
end

-- Helper function to create mock pkg-config responses
local function mock_pkg_config(pkg, data)
    mock_popen_results[SHELL_SCRIPT:format(pkg)] = data
end

-- Helper function to create a basic rockspec with external_dependencies
local function create_rockspec(pkg, variables)
    return {
        external_dependencies = {
            [pkg:lower()] = {},
        },
        variables = variables or {},
    }
end

-- Tests

run_test("No external_dependencies", function()
    local rockspec = {
        variables = {},
    }
    resolve_pkgconfig(rockspec)
    assert_equal(nil, next(rockspec.variables))
end)

run_test("Basic Resolution Success", function()
    local rockspec = create_rockspec("libfoo")
    mock_pkg_config("libfoo",
                    "prefix=/usr\nincludedir=/usr/include\nlibdir=/usr/lib\nName=libfoo\nDescription=Foo Library\nVersion=1.2.3\nLibs=-lfoo\nCflags=-I/usr/include\nModversion=1.2.3")

    resolve_pkgconfig(rockspec)

    assert_equal("/usr/include", rockspec.variables.LIBFOO_INCDIR)
    assert_equal("/usr/lib", rockspec.variables.LIBFOO_LIBDIR)
    assert_equal("/usr", rockspec.variables.LIBFOO_DIR)
    assert_equal("1.2.3", rockspec.variables.LIBFOO_VERSION)
    assert_equal("1.2.3", rockspec.variables.LIBFOO_MODVERSION)
    assert_equal("-lfoo", rockspec.variables.LIBFOO_LIBS)
    assert_equal("-I/usr/include", rockspec.variables.LIBFOO_CFLAGS)
end)

run_test("Package not found", function()
    local rockspec = create_rockspec("nonexistent")
    mock_os_execute_results["pkg-config --exists nonexistent"] = 1

    resolve_pkgconfig(rockspec)

    assert_equal(nil, rockspec.variables.NONEXISTENT_INCDIR)
    assert_equal(nil, rockspec.variables.NONEXISTENT_LIBDIR)
end)

run_test("Version and Modversion with different values", function()
    local rockspec = create_rockspec("libbar")
    mock_pkg_config("libbar",
                    "prefix=/usr\nincludedir=/usr/include\nlibdir=/usr/lib\nName=libbar\nDescription=Bar Library\nVersion=1.2.3-dev\nLibs=-lbar\nCflags=-I/usr/include\nModversion=1.2.3")

    resolve_pkgconfig(rockspec)

    assert_equal("1.2.3-dev", rockspec.variables.LIBBAR_VERSION)
    assert_equal("1.2.3", rockspec.variables.LIBBAR_MODVERSION)
end)

run_test("Package without Version field", function()
    local rockspec = create_rockspec("oldlib")
    mock_pkg_config("oldlib",
                    "prefix=/usr\nincludedir=/usr/include\nlibdir=/usr/lib\nName=Old Library\nModversion=1.0.0")

    resolve_pkgconfig(rockspec)

    assert_equal(nil, rockspec.variables.OLDLIB_VERSION)
    assert_equal("1.0.0", rockspec.variables.OLDLIB_MODVERSION)
end)

run_test("Package without Modversion", function()
    local rockspec = create_rockspec("brokenlib")
    mock_pkg_config("brokenlib",
                    "prefix=/usr\nincludedir=/usr/include\nlibdir=/usr/lib\nName=Broken Library\nVersion=2.0.0-beta")

    resolve_pkgconfig(rockspec)

    assert_equal("2.0.0-beta", rockspec.variables.BROKENLIB_VERSION)
    assert_equal(nil, rockspec.variables.BROKENLIB_MODVERSION)
end)

run_test("Whitespace trimming in values", function()
    local rockspec = create_rockspec("libtest")
    mock_pkg_config("libtest",
                    "prefix=/usr\nincludedir=/usr/include\nlibdir=/usr/lib\nName=  libtest  \nDescription=  Test Library  \nVersion=  1.0.0  \nLibs=-ltest\nCflags=-I/usr/include\nModversion=1.0.0")

    resolve_pkgconfig(rockspec)

    assert_equal("libtest", rockspec.variables.LIBTEST_NAME)
    assert_equal("Test Library", rockspec.variables.LIBTEST_DESCRIPTION)
    assert_equal("1.0.0", rockspec.variables.LIBTEST_VERSION)
end)

run_test("Update existing variables", function()
    local rockspec = create_rockspec("libupdate", {
        LIBUPDATE_INCDIR = "/old/include",
        LIBUPDATE_LIBDIR = "/old/lib",
        LIBUPDATE_DIR = "/old",
        LIBVERSION_VERSION = "1.0.0",
    })
    mock_pkg_config("libupdate",
                    "prefix=/usr\nincludedir=/usr/include\nlibdir=/usr/lib\nName=libupdate\nDescription=Update Library\nVersion=2.0.0\nLibs=-lupdate\nCflags=-I/usr/include\nModversion=2.0.0")

    resolve_pkgconfig(rockspec)

    assert_equal("/usr/include", rockspec.variables.LIBUPDATE_INCDIR)
    assert_equal("/usr/lib", rockspec.variables.LIBUPDATE_LIBDIR)
    assert_equal("/usr", rockspec.variables.LIBUPDATE_DIR)
    assert_equal("1.0.0", rockspec.variables.LIBVERSION_VERSION)
end)

run_test("Remove obsolete variables", function()
    local rockspec = create_rockspec("libremove", {
        LIBREMOVE_INCDIR = "/old/include",
        LIBREMOVE_LIBDIR = "/old/lib",
        LIBREMOVE_CUSTOM_VAR = "custom_value",
    })
    mock_pkg_config("libremove",
                    "prefix=/usr\nincludedir=/usr/include\nlibdir=/usr/lib\nName=libremove\nDescription=Remove Library\nVersion=1.0.0\nLibs=-lremove\nCflags=-I/usr/include\nModversion=1.0.0")

    resolve_pkgconfig(rockspec)

    assert_equal("/usr/include", rockspec.variables.LIBREMOVE_INCDIR)
    assert_equal("/usr/lib", rockspec.variables.LIBREMOVE_LIBDIR)
    assert_equal(nil, rockspec.variables.LIBREMOVE_CUSTOM_VAR)
end)

run_test("Package with suggestions", function()
    local rockspec = create_rockspec("unknownpkg")
    mock_os_execute_results["pkg-config --exists unknownpkg"] = 1
    mock_popen_results["pkg-config --list-package-names 2>/dev/null | grep -i unknownpkg"] =
        "knownpkg\nsimilarpkg\nunknownpkg2"

    resolve_pkgconfig(rockspec)

    assert_equal(nil, rockspec.variables.UNKNOWNPKG_INCDIR)
end)

run_test("Variables with unchanged values", function()
    local rockspec = create_rockspec("libkeep", {
        LIBKEEP_INCDIR = "/usr/include",
        LIBKEEP_LIBDIR = "/usr/lib",
    })
    mock_pkg_config("libkeep",
                    "prefix=/usr\nincludedir=/usr/include\nlibdir=/usr/lib\nName=libkeep\nDescription=Keep Library\nVersion=1.0.0\nLibs=-lkeep\nCflags=-I/usr/include\nModversion=1.0.0")

    resolve_pkgconfig(rockspec)

    assert_equal("/usr/include", rockspec.variables.LIBKEEP_INCDIR)
    assert_equal("/usr/lib", rockspec.variables.LIBKEEP_LIBDIR)
end)

run_test("io.popen returns nil", function()
    local rockspec = create_rockspec("nilpkg")
    -- Don't set any mock result, so io.popen returns nil

    resolve_pkgconfig(rockspec)

    assert_equal(nil, rockspec.variables.NILPKG_INCDIR)
    assert_equal(nil, rockspec.variables.NILPKG_VERSION)
end)

print("All pkgconfig tests passed!")
