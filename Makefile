NVIM_EXEC ?= nvim

all: test doc

# Use `make test` to run tests for all modules
test:
	for nvim_exec in $(NVIM_EXEC); do \
		printf "\n======\n\n" ; \
		$$nvim_exec --version | head -n 1 && echo '' ; \
		$$nvim_exec --headless --noplugin -u ./scripts/minimal_init.lua \
			-c "lua require('mini.test').setup()" \
			-c "lua MiniTest.run()" ; \
	done

# Use `make test_xxx` to run tests for module 'mini.xxx'
TEST_MODULES = $(basename $(notdir $(wildcard tests/test_*.lua)))

$(TEST_MODULES):
	for nvim_exec in $(NVIM_EXEC); do \
		printf "\n======\n\n" ; \
		$$nvim_exec --version | head -n 1 && echo '' ; \
		$$nvim_exec --headless --noplugin -u ./scripts/minimal_init.lua \
			-c "lua require('mini.test').setup()" \
			-c "lua MiniTest.run_file('tests/$@.lua')" ; \
	done

doc:
	$(NVIM_EXEC) --headless --noplugin -u ./scripts/minimal_init.lua -c "lua require('mini.doc').generate()" -c "qa!"

lintdoc:
	$(NVIM_EXEC) --headless --noplugin --cmd "let &rtp.=','.getcwd()" -u ./scripts/lintdoc.lua

lintcommit-ci:
	export LINTCOMMIT_STRICT=true && chmod u+x scripts/lintcommit-ci.sh && scripts/lintcommit-ci.sh

lint-filename-length-ci:
	chmod u+x scripts/lint-filename-length.sh && scripts/lint-filename-length.sh

dual_sync:
	chmod u+x scripts/dual_sync.sh && scripts/dual_sync.sh

dual_log:
	chmod u+x scripts/dual_log.sh && scripts/dual_log.sh

dual_push:
	chmod u+x scripts/dual_push.sh && scripts/dual_push.sh
	printf "\n\033[1mAdjusting `sync` branch\033[0m\n"
	git branch --force sync
	git push origin sync
	printf "\n\033[1mRemoving local patches\033[0m\n"
	rm -r dual/patches

dual_release:
	chmod u+x scripts/dual_release.sh && scripts/dual_release.sh "$(TAG_NAME)" "$(TAG_MESSAGE)"
