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
-- @param pkg Package name
-- @return Table with all variables and metadata fields
local function get_pkg_variables(pkg)
    local f = io.popen(([[
pkg="%s"
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
]]):format(pkg))

    local res = {}
    if not f then
        return res
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

local function pkg_exists(pkg)
    local cmd = "pkg-config --exists " .. pkg
    local res = os.execute(cmd)
    return res == true or res == 0
end

--- Suggest similar package names
-- @param pkg Package name to search for
-- @return Array of suggested package names
local function suggest_packages(pkg)
    local f = io.popen(
                  ("pkg-config --list-package-names 2>/dev/null | grep -i %s"):format(
                      pkg))
    if not f then
        return {}
    end

    local suggestions = {}
    for line in f:lines() do
        local name = line:match("^%s*(%S+)%s*$")
        if name then
            suggestions[#suggestions + 1] = name
        end
    end
    f:close()
    return suggestions
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

        if not pkg_exists(name) then
            local suggestions = suggest_packages(name)
            util.printout(("    %s is not registered in pkg-config."):format(
                              name))
            if #suggestions > 0 then
                util.printout(("    Did you mean: %s?"):format(concat(
                                                                   suggestions,
                                                                   ", ")))
            end
        else
            -- Identify and back up all existing variables with the prefix <NAME>_
            local prefix = name:upper() .. "_"
            local old_vars = extract_variables(rockspec.variables, prefix)
            -- Fetch all pkg-config data
            local pkg_data = get_pkg_variables(name)
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
end

return resolve_pkgconfig
