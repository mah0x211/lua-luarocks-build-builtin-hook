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
        local old_val = old_vars[k]
        local msg = ""
        if not old_val then
            msg = ("    added %s = %s"):format(k, v)
        elseif old_val ~= v then
            msg = ("    updated %s = %s (replaced %s)"):format(k, v, old_val)
        else
            msg = ("    kept %s = %s"):format(k, v)
        end
        util.printout(msg)
        old_vars[k] = nil
        variables[k] = v
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

--- Resolve dependencies using pkg-config
-- @param rockspec The rockspec table
local function resolve_pkgconfig(rockspec)
    local ext_deps = rockspec.external_dependencies
    if not ext_deps then
        return
    end

    util.printout("builtin-hook.pkgconfig: resolving external dependencies...")

    for name, _ in pairs(ext_deps) do
        util.printout(("  checking %s ..."):format(name))

        -- First, try to find exact case-insensitive match for better UX
        local pkgname, suggestions = find_package(name)
        if not pkgname then
            util.printout(("    %s is not registered in pkg-config."):format(
                              name))
            if suggestions and #suggestions > 0 then
                util.printout(("    Did you mean: %s?"):format(concat(
                                                                   suggestions,
                                                                   ', ')))
            end
            return
        end

        -- Log resolved package name if different
        if pkgname ~= name then
            util.printout(("    resolved to %s"):format(pkgname))
        end
        name = pkgname

        -- Identify and back up all existing variables with the prefix <NAME>_
        local prefix = name:upper() .. "_"
        local old_vars = extract_variables(rockspec.variables, prefix)
        -- Fetch all pkg-config data
        local pkg_data, err = get_pkg_variables(name)
        if not pkg_data then
            util.printout(("    failed to get pkg-config data: %s"):format(
                              err or "unknown error"))
            return
        end
        -- Normalize variable names
        local new_vars = {}
        for varname, val in pairs(pkg_data) do
            local suffix = VAR_MAP[varname] or varname:upper()
            new_vars[prefix .. suffix] = val
        end
        -- Update variables and log changes
        update_variables(rockspec.variables, new_vars, old_vars)
    end
end

return resolve_pkgconfig
