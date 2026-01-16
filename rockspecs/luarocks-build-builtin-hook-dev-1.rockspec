rockspec_format = "3.0"
package = "luarocks-build-builtin-hook"
version = "dev-1"
source = {
	url = "git+https://github.com/mah0x211/luarocks-build-builtin-hook.git",
}
description = {
	summary = "A build backend for LuaRocks that runs hooks before/after builtin build",
	homepage = "https://github.com/mah0x211/luarocks-build-builtin-hook",
	license = "MIT/X11",
}
dependencies = {
   "lua >= 5.1"
}
build = {
   type = "builtin",
   modules = {
      ["luarocks.build.builtin-hook"] = "lua/builtin-hook.lua"
   }
}
