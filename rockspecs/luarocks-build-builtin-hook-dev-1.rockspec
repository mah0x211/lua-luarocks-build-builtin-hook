rockspec_format = "3.0"
package = "luarocks-build-builtin-hook"
version = "dev-1"
source = {
    url = "git+https://github.com/mah0x211/luarocks-build-builtin-hook.git",
}
description = {
    summary = "A build backend for LuaRocks that runs hooks before/after builtin build",
    detailed = [[
This is a LuaRocks build backend that extends the builtin build process by allowing users to specify hooks to be run before and/or after the standard build steps.
It also includes a hook to resolve external dependencies using pkg-config.
]],
    homepage = "https://github.com/mah0x211/luarocks-build-builtin-hook",
    license = "MIT/X11",
}
dependencies = {
    "lua >= 5.1",
}
build = {
    type = "builtin",
    modules = {
        ["luarocks.build.builtin-hook"] = "lua/builtin-hook.lua",
        ["luarocks.build.builtin-hook.extra-vars"] = "lua/hooks/extra-vars.lua",
        ["luarocks.build.builtin-hook.pkgconfig"] = "lua/hooks/pkgconfig.lua",
    },
}
