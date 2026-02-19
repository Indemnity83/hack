SRC = src/header.zsh \
      src/utils.zsh \
      src/git-helpers.zsh \
      src/branch.zsh \
      src/changelog.zsh \
      src/openai.zsh \
      src/output.zsh \
      src/commands/idea.zsh \
      src/commands/issue.zsh \
      src/commands/commit.zsh \
      src/commands/propose.zsh \
      src/commands/port.zsh \
      src/commands/done.zsh \
      src/commands/prune.zsh \
      src/main.zsh

hack: $(SRC)
	cat $(SRC) > hack
	chmod +x hack

check:
	@for f in $(SRC); do zsh -n $$f && echo "ok: $$f"; done

test:
	@failed=0; \
	for f in tests/test_*.zsh; do \
	  echo "--- $$f ---"; \
	  zsh $$f || failed=$$((failed+1)); \
	done; \
	echo ""; \
	[ $$failed -eq 0 ] && echo "All tests passed." || { echo "$$failed test file(s) had failures."; exit 1; }

install-hooks:
	git config core.hooksPath .githooks
	@echo "Git hooks installed (core.hooksPath = .githooks)."

.PHONY: check test install-hooks
