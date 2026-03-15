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
local util = require("luarocks.util")

--- Get all pkg-config variables and metadata for a given package
--- @param pkg string name
--- @return table? vars all variables and metadata fields
local function get_pkg_variables(pkg)
    local f, err = io.popen(([[
pkg="%s"
# Locate .pc file for the package
pcdir=$(pkg-config --variable=pcfiledir "$pkg" 2>/dev/null)
if [ -n "$pcdir" ]; then
    # Construct full path to .pc file
    pcfile="$pcdir/$pkg.pc"

    # Extract variable definitions
    for v in $(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$pcfile" | sed 's/=.*$//' || true); do
        printf '%%s=%%s\n' "$v" "$(pkg-config --variable="$v" "$pkg" 2>/dev/null)"
    done

    # Extract metadata fields
    grep -E '^(Name|Description|Version):\s*' "$pcfile" | sed 's/:\s*/=/' || true

    # Get computed values
    printf 'Libs=%%s\n' "$(pkg-config --libs "$pkg" 2>/dev/null || true)"
    printf 'Cflags=%%s\n' "$(pkg-config --cflags "$pkg" 2>/dev/null || true)"
    printf 'Modversion=%%s\n' "$(pkg-config --modversion "$pkg" 2>/dev/null || true)"
fi
]]):format(pkg))

    local res = {}
    if not f then
        return nil, err
    end

    -- Parse all key=value pairs
    for line in f:lines() do
        local key, val = line:match("^([^=]+)=(.*)$")
        if key and val ~= "" then
            -- Trim leading and trailing whitespace from value
            res[key] = val:match("^%s*(.-)%s*$")
        end
    end
    f:close()

    -- Display package information
    if res.Name or res.Description then
        local info = res.Name or pkg
        if res.Description then
            info = info .. " - " .. res.Description
        end
        util.printout(("    %s"):format(info))
    end
    if res.Modversion then
        util.printout(("    Version: %s"):format(res.Modversion))
    end

    return res
end

--- Normalize a string to a valid LuaRocks variable name.
--- LuaRocks variable substitution $(NAME) only recognizes names starting with
--- a letter and containing only letters, digits, and underscores. This function
--- replaces any other character with an underscore.
--- @param s string
--- @return string
local function normalize_varname(s)
    return s:gsub("[^%a%d_]", "_")
end

local function extract_variables(variables, prefix)
    local extracted = {}
    for k, v in pairs(variables) do
        if k:find(prefix, 1, true) == 1 then
            extracted[k] = v
            variables[k] = nil
        end
    end
    return extracted
end

local function update_variables(variables, new_vars, old_vars)
    -- Log added and updated variables
    for k, v in pairs(new_vars) do
        local newk = normalize_varname(k)
        local old_val = old_vars[k]
        local msg = ("    kept %s = %s"):format(newk, v)
        if not old_val then
            msg = ("    added %s = %s"):format(newk, v)
        elseif old_val ~= v then
            msg = ("    updated %s = %s (replaced %s)"):format(newk, v, old_val)
        end
        util.printout(msg)
        old_vars[k] = nil
        variables[newk] = v
    end

    -- Log old variables that were removed
    for k, v in pairs(old_vars) do
        util.printout(("    removed %s = %s"):format(k, v))
    end
end

--- Find package with case-insensitive exact match and get suggestions
--- @param pkg string name to search for
--- @return string? package name if found (case-insensitive), nil otherwise
--- @return string[]? suggested package names (partial matches)
local function find_package(pkg)
    -- Use grep to filter packages, then awk to extract package names only
    local f = io.popen(concat({
        'pkg-config --list-all 2>/dev/null |',
        ('grep -i %s |'):format(pkg),
        "awk '{print $1}'",
    }, ' '))
    if not f then
        return
    end

    local suggestions = {}
    for line in f:lines() do
        local name = line:match("^%s*(%S+)%s*$")
        if name then
            -- Exact case-sensitive match - return immediately
            if name == pkg then
                return name
            end

            -- Collect for suggestions (as array)
            suggestions[#suggestions + 1] = name

            -- Build namelist for case-insensitive lookup (handle multiple packages with same lowercase name)
            local lname = name:lower()
            local namelist = suggestions[lname]
            if not namelist then
                namelist = {}
                suggestions[lname] = namelist
            end
            namelist[#namelist + 1] = name

        end
    end
    f:close()

    local namelist = suggestions[pkg:lower()]
    return namelist and namelist[1] or nil, suggestions
end

local VAR_MAP = {
    includedir = "INCDIR",
    libdir = "LIBDIR",
    prefix = "DIR",
    bindir = "BINDIR",
}

--- Process a libraries array, expanding any standalone $(VAR_NAME) entries into
--- individual library names. Raises an error if the reference is embedded within
--- a larger string. Returns the original table if no expansion was needed.
--- @param libs string[] The libraries array to process
--- @param lib_names string[] Library names to expand into
--- @param var_name string The normalized *_LIB variable name (e.g. "OPENSSL_LIB")
--- @return string[] The processed libraries array (new table if expanded)
local function expand_libraries(libs, lib_names, var_name)
    local var_pat = '%$%(' .. var_name .. '%)'
    local var_ref = ('$(%s)'):format(var_name)
    local new_libs = {}
    local changed = false
    for _, entry in ipairs(libs) do
        if entry:find(var_pat) then
            local remainder = entry:gsub(var_pat, "")
            if remainder:match('%S') then
                error(("%s resolves to multiple libraries and cannot " ..
                          "be embedded in a library entry: %q"):format(var_ref,
                                                                       entry))
            end
            changed = true
        else
            new_libs[#new_libs + 1] = entry
        end
    end

    -- No entries contained the variable reference, so no expansion needed.
    if not changed then
        return libs
    end

    -- Expand the variable reference into individual library names.
    for _, lib in ipairs(lib_names) do
        new_libs[#new_libs + 1] = lib
    end
    return new_libs
end

--- Expand multi-lib $(VAR_LIB) entries in rockspec.build.modules.*.libraries.
--- Only expands when lib_names contains more than one library name.
--- Single-lib entries are left as-is for LuaRocks to substitute natively.
--- Raises an error if the variable reference is embedded within a larger string,
--- since a multi-lib variable cannot be meaningfully embedded.
--- @param rockspec table The rockspec table
--- @param var_name string The normalized *_LIB variable name (e.g. "OPENSSL_LIB")
--- @param lib_names string[] Library names extracted from Libs (empty = no-op)
local function expand_lib_vars(rockspec, var_name, lib_names)
    if #lib_names < 2 then
        return
    end

    local modules = rockspec.build and rockspec.build.modules
    if type(modules) ~= 'table' then
        return
    end

    for _, mod in pairs(modules) do
        if type(mod) == 'table' then
            local libs = mod.libraries
            if type(libs) == 'string' then
                -- Single string entry - convert to table for uniform processing.
                libs = {
                    libs,
                }
            end

            if type(libs) == 'table' then
                local result = expand_libraries(libs, lib_names, var_name)
                if result ~= libs then
                    mod.libraries = result
                end
            end
        end
    end
end

--- Resolve a single external dependency using pkg-config
--- @param rockspec table The rockspec table
--- @param name string The dependency name from external_dependencies
local function resolve_one(rockspec, name)
    -- First, try to find exact case-insensitive match for better UX
    local pkgname, suggestions = find_package(name)
    if not pkgname then
        util.printout(("    %s is not registered in pkg-config."):format(name))
        if suggestions and #suggestions > 0 then
            util.printout(("    Did you mean: %s?"):format(concat(suggestions,
                                                                  ', ')))
        end
        return
    end

    -- Log resolved package name if different
    if pkgname ~= name then
        util.printout(("    resolved to %s"):format(pkgname))
    end
    name = pkgname

    -- Fetch all pkg-config data before modifying rockspec.variables so that
    -- existing variables are preserved if the fetch fails
    local pkg_data, err = get_pkg_variables(name)
    if not pkg_data then
        util.printout(("    failed to get pkg-config data: %s"):format(err or
                                                                           "unknown error"))
        return
    end

    -- Back up and remove all existing variables with the prefix <NAME>_.
    -- Normalize the prefix so it matches the stored variable keys:
    -- Normalize the prefix so it matches the stored variable keys.
    -- LuaRocks only allows [%a%d_] in $(NAME), so any other character (hyphens,
    -- dots, etc.) in the package name is replaced with underscores.
    local prefix = normalize_varname(name:upper() .. "_")
    local old_vars = extract_variables(rockspec.variables, prefix)
    -- Normalize variable names
    local new_vars = {}
    for varname, val in pairs(pkg_data) do
        local suffix = VAR_MAP[varname] or varname:upper()
        new_vars[prefix .. suffix] = val
    end

    -- Synthesize *_LIB: all library names from Libs, space-separated (no -l prefix).
    -- This enables libraries = { "$(PREFIX_LIB)" } in rockspecs.
    local lib_names = {}
    if pkg_data.Libs then
        for lib in pkg_data.Libs:gmatch('%-l(%S+)') do
            lib_names[#lib_names + 1] = lib
        end
        if #lib_names > 0 then
            new_vars[prefix .. "LIB"] = concat(lib_names, ' ')
        end
    end
    -- Update variables and log changes
    update_variables(rockspec.variables, new_vars, old_vars)

    -- prefix is already normalized; just append "LIB".
    local lib_key = prefix .. "LIB"
    expand_lib_vars(rockspec, lib_key, lib_names)
end

--- Resolve dependencies using pkg-config
--- @param rockspec table The rockspec table
local function resolve_pkgconfig(rockspec)
    local ext_deps = rockspec.external_dependencies
    if not ext_deps then
        return
    end

    util.printout("hooks.pkgconfig: resolving external dependencies...")
    for name, _ in pairs(ext_deps) do
        util.printout(("  checking %s ..."):format(name))
        resolve_one(rockspec, name)
    end
end

return resolve_pkgconfig
