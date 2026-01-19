/**
 *  Copyright (C) 2026 Masatoshi Fukunaga
 *
 *  Permission is hereby granted, free of charge, to any person obtaining a
 *  copy of this software and associated documentation files (the "Software"),
 *  to deal in the Software without restriction, including without limitation
 *  the rights to use, copy, modify, merge, publish, distribute, sublicense,
 *  and/or sell copies of the Software, and to permit persons to whom the
 *  Software is furnished to do so, subject to the following conditions:
 *
 *  The above copyright notice and this permission notice shall be included in
 *  all copies or substantial portions of the Software.
 *
 *  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 *  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 *  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL
 *  THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 *  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 *  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 *  DEALINGS IN THE SOFTWARE.
 */

#include <errno.h>
#include <limits.h>
#include <string.h>
#include <unistd.h>
// lua
#include <lauxlib.h>
#include <lua.h>

static int chdir_lua(lua_State *L)
{
    const char *pathname      = luaL_checkstring(L, 1);
    // get current working directory
    static char buf[PATH_MAX] = {0};
    char *cwd                 = getcwd(buf, PATH_MAX);

    if (!cwd) {
        // got error
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        lua_pushinteger(L, errno);
        return 3;
    } else if (chdir(pathname) == 0) {
        // return previous working directory
        lua_pushstring(L, cwd);
        return 1;
    }
    // got error
    lua_pushnil(L);
    lua_pushstring(L, strerror(errno));
    lua_pushinteger(L, errno);
    return 3;
}

LUALIB_API int luaopen_luarocks_build_hooks_chdir(lua_State *L)
{
    lua_pushcfunction(L, chdir_lua);
    return 1;
}
