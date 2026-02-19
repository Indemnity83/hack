# MAIN
main() {
  need_cmd git
  need_cmd curl
  need_cmd jq

  local cmd="${1:-}"
  [[ $# -gt 0 ]] && shift

  case "$cmd" in
    done)    in_git_repo || die "Run this inside a git repository."; cmd_done "$@" ;;
    port)    in_git_repo || die "Run this inside a git repository."; cmd_port "$@" ;;
    idea)    in_git_repo || die "Run this inside a git repository."; cmd_idea "$@" ;;
    issue)   in_git_repo || die "Run this inside a git repository."; cmd_issue "$@" ;;
    commit)  in_git_repo || die "Run this inside a git repository."; cmd_commit "$@" ;;
    propose) in_git_repo || die "Run this inside a git repository."; cmd_propose "$@" ;;
    prune)   in_git_repo || die "Run this inside a git repository."; cmd_prune "$@" ;;

    -h|--help|"")
      cat <<'HELP'
hack — git helper (zsh)

Commands:
  hack idea ["my idea"]          Create a new feature branch
  hack issue <number>            Create a branch from a GitHub issue
  hack commit                    Generate and create a commit
  hack propose [remote]          Create/update a GitHub PR (default remote: origin)
  hack port [sha] [branch]       Cherry-pick commit (defaults to current branch)
  hack port --continue           Continue after resolving conflicts
  hack done                      Clean up merged branch
  hack prune                     Delete all merged branches (bulk cleanup)

Config:
  OPENAI_API_KEY (required):
    Option 1: Environment variable (add to ~/.zshrc or ~/.bashrc)
      export OPENAI_API_KEY='sk-proj-...'

    Option 2: Config file at ~/.config/hack/config
      echo 'OPENAI_API_KEY="sk-proj-..."' > ~/.config/hack/config
      chmod 600 ~/.config/hack/config

  OPENAI_MODEL (optional, default: gpt-5.2)

Dependencies:
  git, curl, jq
  propose/done/prune: gh (GitHub CLI)
  optional: fzf (improved selection UI), git town

Install fzf for better experience: brew install fzf

HELP
      ;;
    *)
      die "Unknown command: $cmd (try: hack --help)"
      ;;
  esac
}

main "$@"
