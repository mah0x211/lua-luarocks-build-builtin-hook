# luarocks-build-hooks

[![test](https://github.com/mah0x211/luarocks-build-hooks/actions/workflows/test.yml/badge.svg)](https://github.com/mah0x211/luarocks-build-hooks/actions/workflows/test.yml)
[![codecov](https://codecov.io/gh/mah0x211/luarocks-build-hooks/branch/master/graph/badge.svg)](https://codecov.io/gh/mah0x211/luarocks-build-hooks)


A custom build backend for LuaRocks that extends the standard `builtin` backend with support for executing Lua scripts before and after the build process.


## Requirements

- Lua 5.1 or later
- LuaRocks 3.0 or later (recommended for `build_dependencies` support)


## Installation

```bash
luarocks install luarocks-build-hooks
```


## Usage

Utilize `build_dependencies` to ensure this backend is available during the build process, and specify `build.type = "hooks"` in your rockspec.


### Example Rockspec

```lua
rockspec_format = "3.0"
package = "my-package"
version = "1.0-1"

-- Add this module to build_dependencies
build_dependencies = {
   "luarocks-build-hooks"
}

build = {
   type = "hooks",
   -- Standard builtin modules definition
   modules = {
      ["my.module"] = "src/my/module.lua"
   },

   -- Hook configuration
   -- before_build: Runs before the builtin build process starts
   before_build = "scripts/preprocess.lua",

   -- after_build: Runs after the builtin build process finishes
   after_build = "scripts/cleanup.lua"
}
```

### Multiple Hooks

You can specify multiple hooks as an array. They will be executed in order.

```lua
build = {
   type = "hooks",

   -- Multiple hooks executed in order
   before_build = {
      "scripts/generate_headers.lua",
      "scripts/prepare_assets.lua",
      "$(pkgconfig)",  -- Built-in hooks can also be used in arrays
   },

   after_build = {
      "scripts/cleanup_temp.lua",
      "scripts/postprocess.lua",
   },
}
```


### Hooks with Arguments

You can pass arguments to hook scripts by adding them after the script path.

```lua
build = {
   type = "hooks",

   -- Hook with arguments
   before_build = "scripts/generate.lua --verbose --output=dist",

   -- Built-in hook with arguments
   after_build = "$(my-custom-hook) arg1 arg2",
}
```

The hook script receives the `rockspec` as the first argument, followed by any additional arguments:

```lua
-- scripts/generate.lua
local rockspec, verbose, output_option = ...

if verbose == "--verbose" then
   print("Verbose mode enabled")
end

-- Process arguments...
```


## Configuration Fields

- `build.type`: Must be set to `"hooks"`.
- `build.before_build` (optional): Path to a Lua script to execute before the build, or an array of hook strings.
- `build.after_build` (optional): Path to a Lua script to execute after the build, or an array of hook strings.

**Hook String Format:**

- `"<path>"` - Execute script at `<path>`
- `"<path> <arg1> <arg2> ..."` - Execute script with arguments
- `"$(hook_name)"` - Execute built-in hook
- `"$(hook_name) <arg1> <arg2> ..."` - Execute built-in hook with arguments


## Hook Scripts

Hooks must be Lua scripts. They are executed in a sandboxed environment within the same Lua VM.

The `rockspec` table is passed as the first argument to the script, followed by any additional arguments specified in the hook string.

**Example `scripts/preprocess.lua`**:

```lua
local rockspec = ...

print("Running pre-processing...")
-- You can modify the rockspec table
rockspec.variables.MY_CUSTOM_VAR = "some_value"

local f = io.open("src/generated_code.lua", "w")
f:write("return { generated = true }")
f:close()
```


## Built-in Hooks

Built-in hooks are predefined hooks that can be invoked using the `$(hook_name)` syntax in your `before_build` or `after_build` fields. These hooks provide common functionality without requiring you to write custom scripts.

**Syntax to use a built-in hook:**

```lua
build = {
    type = "hooks",
    before_build = "$(hook_name)",
    -- or
    after_build = "$(hook_name)",
}
```


## `$(pkgconfig)` Built-in Hooks

The `pkgconfig` hook automatically resolves external dependencies using `pkg-config` and populates LuaRocks variables with the correct paths. This eliminates the need to manually specify include and library directories for external dependencies.

**How it works:**

1. Reads package information from the `.pc` files via `pkg-config`
2. Extracts all defined variables (e.g., `includedir`, `libdir`, `prefix`, etc.)
3. Maps them to LuaRocks variables with the package name as a prefix
4. Replaces any existing guessed values to ensure consistency

**Variable Mapping:**

The hook maps `pkg-config` variables and metadata to LuaRocks variables as follows:
- `includedir` → `<PACKAGE>_INCDIR`
- `libdir` → `<PACKAGE>_LIBDIR`
- `prefix` → `<PACKAGE>_DIR`
- `bindir` → `<PACKAGE>_BINDIR`
- Other variables → `<PACKAGE>_<VARNAME>` (uppercase)
- Version (from `Version:` field) → `<PACKAGE>_VERSION`
- Modversion (from `--modversion`) → `<PACKAGE>_MODVERSION`
- Libs (from `--libs`) → `<PACKAGE>_LIBS`
- Cflags (from `--cflags`) → `<PACKAGE>_CFLAGS`

For example, if you have `libfoo` in your `external_dependencies`, the hook will create variables like:

- `LIBFOO_INCDIR`
- `LIBFOO_LIBDIR`
- `LIBFOO_DIR`
- `LIBFOO_VERSION` (from Version: field in .pc file)
- `LIBFOO_MODVERSION` (from --modversion)
- `LIBFOO_LIBS` (e.g., `-lfoo`)
- `LIBFOO_CFLAGS` (e.g., `-I/path/to/include`)
- `LIBFOO_EXEC_PREFIX`
- etc.

**Usage Example:**

```lua
external_dependencies = {
    -- Package name as used by pkg-config (case-insensitive)
    LIBFOO = {}
}

build = {
    type = "hooks",
    before_build = "$(pkgconfig)",
    modules = {
        mymodule = {
            sources = {
                "src/mymodule.c",
            },
            libraries = {
                "foo",
            },
            incdirs = {
                "$(LIBFOO_INCDIR)",  -- Automatically populated by pkgconfig hook
            },
            libdirs = {
                "$(LIBFOO_LIBDIR)",  -- Automatically populated by pkgconfig hook
            },
        },
    }
}
```

**Notes:**

- The package name in `external_dependencies` should match the `pkg-config` package name (case-insensitive)
- Variable names are automatically uppercased (e.g., `libfoo` → `LIBFOO_*`)
- If a package is not found, the hook will suggest similar package names based on `pkg-config --list-all`
- All variables from the `.pc` file are made available, not just the standard ones


## `$(extra-vars)` Built-in Hook

The `extra-vars` hook allows you to append additional values to existing `rockspec.variables`. This is useful when you want to extend build variables (such as `CFLAGS`, `LIBFLAG`, etc.) with custom values without completely replacing them.

**How it works:**

1. Reads `build.extra_variables` from your rockspec
2. For each entry, validates the value (string or array of strings)
3. Appends the value to the corresponding variable in `rockspec.variables` if it exists and is a non-empty string
4. Skips variables that don't exist, are not strings, or are empty

**Usage Example:**

```lua
build = {
    type = "hooks",
    before_build = "$(extra-vars)",

    -- Define variables that will receive extra values
    variables = {
        CFLAGS = "-O2",
        LIBFLAG = "-shared",
    },

    -- Extra values to append to existing variables
    extra_variables = {
        -- Append a single string
        CFLAGS = "-Wall -Wextra",

        -- Append an array of strings (joined with spaces)
        LIBFLAG = {"-fPIC", "-static"},
    },
}
```

After the hook runs:

- `rockspec.variables.CFLAGS` becomes `-O2 -Wall -Wextra`
- `rockspec.variables.LIBFLAG` becomes `-shared -fPIC -static`

**Value Types:**

You can specify extra values as:

- **String:** `CFLAGS = "-Wall"` → appends `-Wall`
- **Array of strings:** `CFLAGS = {"-Wall", "-Wextra"}` → appends `-Wall -Wextra`

**Behavior:**

- Whitespace is automatically trimmed from values
- Empty strings in arrays are filtered out
- Only appends to existing **non-empty string** variables in `rockspec.variables`
- Skips variables that:
  - Don't exist in `rockspec.variables`
  - Are not strings (e.g., numbers, tables)
  - Are empty strings

**Example with mixed results:**

```lua
variables = {
    CFLAGS = "-O2",           -- Will be extended
    LIBFLAG = "",             -- Empty: will be skipped
    LDFLAGS = 123,            -- Not a string: will be skipped
    -- NONEXISTENT is not defined: will be skipped
}
build = {
    type = "hooks",
    before_build = "$(extra-vars)",
    extra_variables = {
        CFLAGS = "-Wall",         -- Appended: CFLAGS becomes "-O2 -Wall"
        LIBFLAG = "-static",      -- Skipped (LIBFLAG is empty)
        LDFLAGS = "-Wl,--as-needed",  -- Skipped (LDFLAGS is not a string)
        NONEXISTENT = "--unused", -- Skipped (variable doesn't exist)
    }
    ...
}
```

**Error Handling:**

The hook will raise an error if:
- `build.extra_variables` is not a table
- A variable name in `extra_variables` is not a string
- A value is neither a string nor an array of strings


### Conditional Variables

The `extra-vars` hook also supports `conditional_variables`, which allows you to append variables only when a specific flag is enabled. This is useful for feature toggles, debug builds, or platform-specific configurations.

**Configuration:**

You can define `conditional_variables` in the `build` table. The keys are the flag names (variables in `rockspec.variables`), and the values are tables of variables to append if the flag is enabled.

```lua
build = {
    type = "hooks",
    before_build = "$(extra-vars)",
    conditional_variables = {
        -- Appends -DDEBUG -g to CFLAGS only if ENABLE_DEBUG environment variable is defined as considered enabled
        ENABLE_DEBUG = {
            CFLAGS = "-DDEBUG -g",
        },
        -- Appends --coverage to CFLAGS and LIBFLAG only if ENABLE_COVERAGE environment variable is defined as considered enabled
        ENABLE_COVERAGE = {
            CFLAGS = "--coverage",
            LIBFLAG = "--coverage",
        }
    }
}
```

**Boolean Logic:**

A flag is considered **enabled** if the value of the corresponding **environment variable** matches one of the following:

- `1`
- `true` (Boolean type)

A flag is considered **disabled** if its value is any other string or value.

**Execution Order:**

1. `extra_variables` are processed first (Unconditional).
2. `conditional_variables` are processed second (Conditional).

This means conditional values are appended *after* any unconditional extra values.

**Usage with LuaRocks:**

You can facilitate these flags from the command line by setting environment variables:

```bash
# Enable debug mode
ENABLE_DEBUG=1 luarocks make

# Disable debug mode
ENABLE_DEBUG=0 luarocks make

# Empty string is disabled
ENABLE_FEATURE= luarocks make
```


## License

MIT/X11
