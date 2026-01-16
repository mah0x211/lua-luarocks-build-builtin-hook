# luarocks-build-builtin-hook

A custom build backend for LuaRocks that extends the standard `builtin` backend with support for executing Lua scripts before and after the build process.

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

### Hook Scripts

Hooks must be Lua scripts. They are executed in a subprocess using the same Lua interpreter that is running LuaRocks.

**Example `scripts/preprocess.lua`**:
```lua
print("Running pre-processing...")
-- Perform code generation or setup here
local f = io.open("src/generated_code.lua", "w")
f:write("return { generated = true }")
f:close()
```

### Configuration Fields

- `build.type`: Must be set to `"builtin-hook"`.
- `build.before_build` (optional): Path to a Lua script to execute before the build.
- `build.after_build` (optional): Path to a Lua script to execute after the build.

## Requirements

- Lua 5.1 or later
- LuaRocks 3.0 or later (recommended for `build_dependencies` support)

## License

MIT/X11
