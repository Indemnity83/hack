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

.PHONY: check
