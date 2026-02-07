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

--- Validate and normalize variable values
--- @param value any variable value
--- @return string? normalized variable value or nil if invalid
--- @return any err message if invalid
local function validate_value(value)
    if type(value) == "string" then
        -- remove leading and trailing whitespace if it's a string
        value = value:match("^%s*(.-)%s*$")
        return value
    end

    if type(value) == "table" then
        local arr = {}
        local nvalues = #value
        local count = 0
        -- confirm it's an array of strings
        for k, v in pairs(value) do
            count = count + 1
            if count > nvalues or type(v) ~= "string" then
                return nil, ("variable-value#%s must be a string"):format(
                           tostring(k))
            end
            -- remove leading and trailing whitespace
            v = v:match("^%s*(.-)%s*$")
            if #v > 0 then
                -- only add non-empty strings
                arr[#arr + 1] = v
            end
        end
        -- concatenate array elements with spaces
        return concat(arr, ' ')
    end

    -- invalid value type
    return nil, "variable-value must be a string or an array of strings"
end

--- Get existing variable value
--- @param variables table variables table
--- @param name string name
--- @return string? var existing value or nil if not found
local function get_variables(variables, name)
    local var = variables[name] or ''
    if type(var) ~= "string" then
        -- not a string
        return
    end

    -- remove leading and trailing whitespace
    var = var:match("^%s*(.-)%s*$")
    if #var > 0 then
        return var
    end
end

--- Append extra-variables to variables
--- @param variables table variables table
--- @param extvars table extra-variables table
--- @param target string extra-variables table name
local function append_vars(variables, extvars, target)
    for name, value in pairs(extvars) do
        -- validate name
        if type(name) ~= "string" then
            error(("  %s[%q] variable-name must be a string"):format(target,
                                                                     tostring(
                                                                         name)))
        end

        -- validate value
        local err
        value, err = validate_value(value)
        if err then
            error(("  %s[%q] " .. err):format(target, tostring(name)))
        end

        -- get existing variable
        local var = get_variables(variables, name)
        if not var then
            util.printout(
                ("  skipping %s: %s.%s is not a string or empty"):format(name,
                                                                         target,
                                                                         name))
        elseif #value == 0 then
            -- skip empty value
            util.printout(("  skipping %s: extra value is empty"):format(name))
        else
            -- append extra variables
            util.printout(("  append %s values %q to existing value %q"):format(
                              name, value, var))
            var = var .. ' ' .. value
            variables[name] = var
        end
    end
end

-- Values considered as enabled for conditional_variables
local ENABLED_VALUES = {
    ['1'] = true,
    ['true'] = true,
}

--- Append extra variables to rockspec.variables
--- @param rockspec table rockspec table
local function append_extra_vars(rockspec)
    -- 1. Process extra_variables
    local extra_vars = rockspec.build.extra_variables
    if extra_vars then
        if type(extra_vars) ~= "table" then
            error("hooks.extra-vars: build.extra_variables should be a table.")
        end
        util.printout("hooks.extra-vars: adding extra_variables...")
        append_vars(rockspec.variables, extra_vars, "build.extra_variables")
    end

    -- 2. Process conditional_variables
    local cond_vars = rockspec.build.conditional_variables
    if not cond_vars then
        return
    elseif type(cond_vars) ~= "table" then
        error("hooks.extra-vars: build.conditional_variables should be a table.")
    end
    util.printout("hooks.extra-vars: processing conditional_variables...")

    -- Iterate over conditional_variables
    for flag, variables in pairs(cond_vars) do
        if type(flag) ~= "string" then
            error(
                "hooks.extra-vars: conditional_variables flag name must be a string")
        elseif type(variables) ~= "table" then
            error(
                ("hooks.extra-vars: conditional_variables[%q] must be a table"):format(
                    flag))
        end

        -- Check if the flag is enabled in rockspec.variables
        if ENABLED_VALUES[os.getenv(flag)] then
            util.printout(
                ("  [%s] enabled: appending variables..."):format(flag))
            append_vars(rockspec.variables, variables,
                        ("build.conditional_variables[%q]"):format(flag))
        end
    end
end

return append_extra_vars
