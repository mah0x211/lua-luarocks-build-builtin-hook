# luarocks-build-builtin-hook

[![test](https://github.com/mah0x211/luarocks-build-builtin-hook/actions/workflows/test.yml/badge.svg)](https://github.com/mah0x211/luarocks-build-builtin-hook/actions/workflows/test.yml)
[![codecov](https://codecov.io/gh/mah0x211/luarocks-build-builtin-hook/branch/master/graph/badge.svg)](https://codecov.io/gh/mah0x211/luarocks-build-builtin-hook)


A custom build backend for LuaRocks that extends the standard `builtin` backend with support for executing Lua scripts before and after the build process.


## Requirements

- Lua 5.1 or later
- LuaRocks 3.0 or later (recommended for `build_dependencies` support)


## Installation

```bash
luarocks install luarocks-build-builtin-hook
```


## Usage

Utilize `build_dependencies` to ensure this backend is available during the build process, and specify `build.type = "builtin-hook"` in your rockspec.


### Example Rockspec

```lua
rockspec_format = "3.0"
package = "my-package"
version = "1.0-1"

-- Add this module to build_dependencies
build_dependencies = {
   "luarocks-build-builtin-hook"
}

build = {
   type = "builtin-hook",

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
   type = "builtin-hook",

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
   type = "builtin-hook",

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

- `build.type`: Must be set to `"builtin-hook"`.
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
    type = "builtin-hook",
    before_build = "$(hook_name)",
    -- or
    after_build = "$(hook_name)",
}
```


### `$(pkgconfig)` Built-in Hooks

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
    -- Package name as used by pkg-config
    LIBFOO = {}  
}

build = {
    type = "builtin-hook",
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
- The package name in `external_dependencies` must match the `pkg-config` package name exactly
- Variable names are automatically uppercased (e.g., `libfoo` → `LIBFOO_*`)
- If a package is not found, the hook will suggest similar package names based on `pkg-config --list-package-names`
- All variables from the `.pc` file are made available, not just the standard ones


## License

MIT/X11
