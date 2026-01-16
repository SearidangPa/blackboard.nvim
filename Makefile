lua_fmt:
	echo "===> Formatting"
	stylua lua/ --config-path=.stylua.toml

lua_fmt_check:
	echo "===> Checking format"
	stylua lua/ --config-path=.stylua.toml --check

lua_lint:
	echo "===> Linting"
	luacheck lua/ --globals vim

test:
	nvim --headless --noplugin -u scripts/tests/minimal.vim \
		-c "PlenaryBustedDirectory tests/ { minimal_init = 'scripts/tests/minimal.vim' }" \
		-c q

check: lua_lint lua_fmt_check

pr_ready: check test
