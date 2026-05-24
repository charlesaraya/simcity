# Slow Grid — dev tasks
# busted is installed in a project-local tree (lua_modules/) bound to LuaJIT,
# matching LÖVE's runtime. The bin/busted wrapper already execs luajit with the
# right package paths, so just call it directly.

BUSTED := ./lua_modules/bin/busted

.PHONY: test run deps
test:
	$(BUSTED)

run:
	love .

# One-time: install busted into lua_modules/, bound to LuaJIT (matches LÖVE).
deps:
	luarocks install busted --lua-version=5.1 --lua-dir=$$(brew --prefix luajit) --tree=lua_modules
