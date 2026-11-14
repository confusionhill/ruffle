#ifndef CLUA_SHIM_H
#define CLUA_SHIM_H

#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"

static inline const char *clua_tostring(lua_State *L, int idx) {
    return lua_tostring(L, idx);
}

static inline void clua_pop(lua_State *L, int n) {
    lua_pop(L, n);
}

static inline int clua_pcall(lua_State *L, int nargs, int nresults, int errfunc) {
    return lua_pcall(L, nargs, nresults, errfunc);
}

static inline int clua_yield(lua_State *L, int nresults) {
    return lua_yield(L, nresults);
}

static inline int clua_upvalueindex(int i) {
    return lua_upvalueindex(i);
}

static inline void clua_newtable(lua_State *L) {
    lua_newtable(L);
}

static inline int clua_isnil(lua_State *L, int idx) {
    return lua_isnil(L, idx);
}

static inline int clua_isboolean(lua_State *L, int idx) {
    return lua_isboolean(L, idx);
}

static inline int clua_istable(lua_State *L, int idx) {
    return lua_istable(L, idx);
}

static inline int clua_isfunction(lua_State *L, int idx) {
    return lua_isfunction(L, idx);
}

static inline int clua_dostring(lua_State *L, const char *str) {
    return luaL_dostring(L, str);
}

static inline lua_Integer clua_len(lua_State *L, int idx) {
    return luaL_len(L, idx);
}

static inline int clua_registry_index(void) {
    return LUA_REGISTRYINDEX;
}

static inline int clua_error(lua_State *L, const char *msg) {
    lua_pushstring(L, msg);
    return lua_error(L);
}

#endif /* CLUA_SHIM_H */
