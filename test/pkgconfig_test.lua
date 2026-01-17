require("luacov")

-- Load module under test
local resolve_pkgconfig = require("luarocks.build.builtin-hook.pkgconfig")

-- Test Helper
local function run_test(name, func)
    io.write("Running " .. name .. "... ")
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

local function assert_not_nil(val, msg)
    if val == nil then
        error((msg or "") .. " Expected non-nil value")
    end
end

local function assert_not_equal(expected, actual, msg)
    if expected == actual then
        error((msg or "") .. " Expected " .. tostring(actual) .. " to be different from " .. tostring(expected))
    end
end

-- Helper function to create a basic rockspec with external_dependencies
local function create_rockspec(pkg, variables)
    return {
        external_dependencies = {
            [pkg] = {},
        },
        variables = variables or {},
    }
end

-- Check if zlib is available for testing
local function check_zlib_available()
    local f = io.popen("pkg-config --exists zlib 2>/dev/null && echo 1 || echo 0")
    if not f then
        return false
    end
    local result = f:read("*a"):match("%d")
    f:close()
    return result == "1"
end

local zlib_available = check_zlib_available()

-- Tests

run_test("No external_dependencies", function()
    local rockspec = {
        variables = {},
    }
    resolve_pkgconfig(rockspec)
    assert_equal(nil, next(rockspec.variables))
end)

if zlib_available then
    run_test("Basic Resolution Success (zlib)", function()
        local rockspec = create_rockspec("zlib")

        resolve_pkgconfig(rockspec)

        -- Check that ZLIB_ variables are set
        assert_not_nil(rockspec.variables.ZLIB_LIBDIR, "ZLIB_LIBDIR should be set")
        assert_not_nil(rockspec.variables.ZLIB_INCDIR, "ZLIB_INCDIR should be set")
        assert_not_nil(rockspec.variables.ZLIB_DIR, "ZLIB_DIR should be set")
        assert_not_nil(rockspec.variables.ZLIB_MODVERSION, "ZLIB_MODVERSION should be set")

        -- Check that paths are strings
        assert_equal("string", type(rockspec.variables.ZLIB_LIBDIR))
        assert_equal("string", type(rockspec.variables.ZLIB_INCDIR))
        assert_equal("string", type(rockspec.variables.ZLIB_DIR))
        assert_equal("string", type(rockspec.variables.ZLIB_MODVERSION))
    end)

    run_test("Update existing variables (zlib)", function()
        local rockspec = create_rockspec("zlib", {
            ZLIB_INCDIR = "/old/include",
            ZLIB_LIBDIR = "/old/lib",
        })

        resolve_pkgconfig(rockspec)

        -- Check that old values were replaced
        assert_not_equal("/old/include", rockspec.variables.ZLIB_INCDIR)
        assert_not_equal("/old/lib", rockspec.variables.ZLIB_LIBDIR)
    end)

    run_test("Variables with unchanged values (zlib)", function()
        -- First resolve to get actual values
        local rockspec1 = create_rockspec("zlib")
        resolve_pkgconfig(rockspec1)

        local actual_includedir = rockspec1.variables.ZLIB_INCDIR
        local actual_libdir = rockspec1.variables.ZLIB_LIBDIR

        -- Now test with unchanged values
        local rockspec2 = create_rockspec("zlib", {
            ZLIB_INCDIR = actual_includedir,
            ZLIB_LIBDIR = actual_libdir,
        })

        resolve_pkgconfig(rockspec2)

        -- Values should remain the same
        assert_equal(actual_includedir, rockspec2.variables.ZLIB_INCDIR)
        assert_equal(actual_libdir, rockspec2.variables.ZLIB_LIBDIR)
    end)
else
    print("SKIPPED: zlib not available via pkg-config")
end

run_test("Package not found", function()
    local rockspec = create_rockspec("nonexistent-pkg-12345")

    resolve_pkgconfig(rockspec)

    -- No variables should be set for nonexistent package
    assert_equal(nil, rockspec.variables.NONEXISTENT_PKG_12345_INCDIR)
    assert_equal(nil, rockspec.variables.NONEXISTENT_PKG_12345_LIBDIR)
end)

run_test("Keep variables when package not found", function()
    local rockspec = create_rockspec("nonexistent-pkg-67890", {
        NONEXISTENT_PKG_67890_INCDIR = "/old/include",
        NONEXISTENT_PKG_67890_LIBDIR = "/old/lib",
        NONEXISTENT_PKG_67890_CUSTOM_VAR = "custom_value",
    })

    resolve_pkgconfig(rockspec)

    -- Variables should be kept since package doesn't exist (early return)
    assert_equal("/old/include", rockspec.variables.NONEXISTENT_PKG_67890_INCDIR)
    assert_equal("/old/lib", rockspec.variables.NONEXISTENT_PKG_67890_LIBDIR)
    assert_equal("custom_value", rockspec.variables.NONEXISTENT_PKG_67890_CUSTOM_VAR)
end)

-- Test for partial match with suggestions
run_test("Package not found with suggestions", function()
    local rockspec = create_rockspec("zli")  -- Partial match for "zlib"

    resolve_pkgconfig(rockspec)

    -- No variables should be set for partial match
    assert_equal(nil, rockspec.variables.ZLI_INCDIR)
    assert_equal(nil, rockspec.variables.ZLI_LIBDIR)
end)

if zlib_available then
    run_test("Case insensitive package name resolution", function()
        local rockspec = create_rockspec("ZLIB")  -- Use uppercase

        resolve_pkgconfig(rockspec)

        -- Variables should still be set with ZLIB_ prefix (original name)
        assert_not_nil(rockspec.variables.ZLIB_INCDIR, "ZLIB_INCDIR should be set")
        assert_not_nil(rockspec.variables.ZLIB_LIBDIR, "ZLIB_LIBDIR should be set")
    end)

    run_test("Remove obsolete variables when package found", function()
        -- First, get the current pkg-config variables
        local rockspec1 = create_rockspec("zlib")
        resolve_pkgconfig(rockspec1)

        -- Get all ZLIB_ variables
        local zlib_vars = {}
        for k, v in pairs(rockspec1.variables) do
            if k:match("^ZLIB_") then
                zlib_vars[k] = v
            end
        end

        -- Create a new rockspec with current variables plus a custom variable
        local rockspec2 = create_rockspec("zlib")
        for k, v in pairs(zlib_vars) do
            rockspec2.variables[k] = v
        end
        -- Add a custom variable that won't be in the new pkg-config output
        rockspec2.variables.ZLIB_CUSTOM_VAR = "custom_value"

        resolve_pkgconfig(rockspec2)

        -- Custom variable should be removed
        assert_equal(nil, rockspec2.variables.ZLIB_CUSTOM_VAR,
                     "ZLIB_CUSTOM_VAR should be removed")

        -- Standard variables should still exist
        assert_not_nil(rockspec2.variables.ZLIB_INCDIR, "ZLIB_INCDIR should be set")
        assert_not_nil(rockspec2.variables.ZLIB_LIBDIR, "ZLIB_LIBDIR should be set")
    end)
end

-- Test cases with io.popen mocking for error paths
if zlib_available then
    run_test("Handle io.popen failure in get_pkg_variables", function()
        local rockspec = create_rockspec("zlib", {
            ZLIB_INCDIR = "/existing/include",
            ZLIB_LIBDIR = "/existing/lib",
            ZLIB_CUSTOM_VAR = "custom_value",
        })

        -- Mock io.popen to fail only for get_pkg_variables (second call)
        -- find_package (first call) should succeed
        local call_count = 0
        local old_popen = _G.io.popen
        _G.io.popen = function(cmd)
            call_count = call_count + 1
            -- First call is find_package, let it succeed
            if call_count == 1 then
                return old_popen(cmd)
            end
            -- Second call is get_pkg_variables, make it fail
            return nil, "simulated io.popen failure"
        end

        resolve_pkgconfig(rockspec)

        -- Restore original io.popen
        _G.io.popen = old_popen

        -- Variables should be removed by extract_variables but not restored
        -- since get_pkg_variables failed
        assert_equal(nil, rockspec.variables.ZLIB_INCDIR)
        assert_equal(nil, rockspec.variables.ZLIB_LIBDIR)
        assert_equal(nil, rockspec.variables.ZLIB_CUSTOM_VAR)
    end)

    run_test("Handle io.popen failure in find_package", function()
        local rockspec = create_rockspec("zlib-nonexist", {
            ZLIB_NONEXIST_INCDIR = "/existing/include",
        })

        -- Mock io.popen to fail only for find_package
        local call_count = 0
        local old_popen = _G.io.popen
        _G.io.popen = function(cmd)
            call_count = call_count + 1
            -- First call is find_package, make it fail
            if call_count == 1 then
                return nil, "simulated io.popen failure"
            end
            -- Subsequent calls use original
            return old_popen(cmd)
        end

        resolve_pkgconfig(rockspec)

        -- Restore original io.popen
        _G.io.popen = old_popen

        -- Variables should remain unchanged since find_package failed
        assert_equal("/existing/include", rockspec.variables.ZLIB_NONEXIST_INCDIR)
    end)
end

print("All pkgconfig tests passed!")
