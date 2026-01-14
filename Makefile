lua_fmt:
	echo "===> Formatting"
	stylua lua/ --config-path=.stylua.toml

lua_fmt_check:
	echo "===> Checking format"
	stylua lua/ --config-path=.stylua.toml --check

lua_lint:
	echo "===> Linting"
	luacheck lua/ --globals vim

check: lua_lint lua_fmt_check
