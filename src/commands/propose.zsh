# SUBCOMMAND: propose (interactive, uses gh)
cmd_propose() {
  need_cmd gh
  gh auth status >/dev/null 2>&1 || die "GitHub CLI not authenticated. Run: gh auth login"

  local remote="${1:-origin}"
  git remote get-url "$remote" >/dev/null 2>&1 || die "No remote named: $remote"

  local base branch
  branch="$(current_branch)"
  [[ -n "$branch" ]] || die "Detached HEAD; check out a branch first."
  base="$(find_parent_branch "$branch" "$remote")"

  # Ensure we have up-to-date refs for the target remote
  info "Proposing $branch → $remote/$base"
  info "Fetching $remote/$base..."
  git fetch "$remote" "$base" --quiet 2>/dev/null || true

  local last_tag
  last_tag="$(last_release_tag)"

  # gather commit history and diff vs remote base
  local remote_base_ref commits diffstat rawdiff diff_trunc
  remote_base_ref="$remote/$base"
  commits="$(git log --no-decorate --oneline "${remote_base_ref}..HEAD" 2>/dev/null || true)"
  [[ -n "$commits" ]] || die "No commits ahead of '$remote_base_ref'. Nothing to propose."

  # Use merge-base diff to represent "what this branch introduces"
  diffstat="$(git diff --stat "${remote_base_ref}...HEAD" || true)"
  rawdiff="$(git diff "${remote_base_ref}...HEAD" || true)"
  diff_trunc="$(truncate_str "$rawdiff" "$MAX_CHARS_DIFF_PROPOSE")"

  # changelog context
  local cl
  cl="$(changelog_excerpt || true)"

  local instructions input pr_message combined title body

  instructions=$'You are a senior engineer preparing a GitHub Pull Request message.\n\nGenerate a CONVENTIONAL COMMIT message (no scope) that accurately describes what this branch does.\n\nPR BODY STYLE (read like release notes):\n- Write the body like patch notes for users.\n- Focus on WHAT changed and WHY it matters.\n- Prefer short sections with headings like: Summary / Changes / Notes.\n- Use bullet points. Group related items. Keep it scannable.\n- Do NOT include low-level implementation details unless they affect behavior, compatibility, or contributors.\n\nOutput format:\n- Line 1: <type>: <description>\n- Blank line\n- Body: release-notes style (MUST NOT be empty)\n- Optional blank line + footer ONLY if BREAKING CHANGE (e.g. \"BREAKING CHANGE: ...\")\n\nValid types: feat, fix, refactor, perf, test, docs, build, ci, chore, revert\nNo scope in parentheses.\nDo not invent changes that aren\'t in the commits/diff/changelog.\n'
  input="Repo: $(basename "$(repo_root)")\nBranch: $branch\nBase: $remote_base_ref\nLast release tag (best-effort): ${last_tag:-<none>}\n\nCOMMITS (${remote_base_ref}..HEAD):\n$commits\n\nDIFFSTAT (merge-base ${remote_base_ref}...HEAD):\n$diffstat\n\nCHANGELOG EXCERPT (if present):\n${cl:-<no changelog found>}\n\nDIFF (merge-base ${remote_base_ref}...HEAD, may be truncated):\n$diff_trunc"

  pr_message="$(openai_response "$instructions" "$input" | tr -d '\r')"
  combined="$(split_title_body "$pr_message")"
  title="${combined%%$'\0'*}"
  body="${combined#*$'\0'}"

  # One retry if the model returns title-only (common failure mode).
  if [[ -z "${body:-}" ]]; then
    info "Model returned an empty PR body; retrying with stricter instructions..."
    local instructions_retry
    instructions_retry=$'You are a senior engineer preparing a GitHub Pull Request message.\n\nReturn BOTH a conventional-commit title AND a non-empty PR body.\n\nOutput format:\n- Line 1: <type>: <description>\n- Blank line\n- Body with at least:\n  - A \"Summary\" heading (1-2 sentences)\n  - A \"Changes\" heading with 3-8 bullet points\n\nRules:\n- No scope in parentheses.\n- No code blocks.\n- Do not invent changes.\n'
    pr_message="$(openai_response "$instructions_retry" "$input" | tr -d '\r')"
    combined="$(split_title_body "$pr_message")"
    title="${combined%%$'\0'*}"
    body="${combined#*$'\0'}"
  fi

  title="$(print -r -- "$title" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  [[ -n "$title" ]] || die "Model returned empty title."
  [[ -n "${body:-}" ]] || die "Model returned empty body (twice)."

  info "Proposed PR title:"
  print -r -- "  $title" >&2
  print -r -- "" >&2
  info "Proposed PR body (preview):"
  print -r -- "$body" | sed -n '1,40p' >&2
  if [[ "$(print -r -- "$body" | wc -l | tr -d ' ')" -gt 40 ]]; then
    print -r -- "  ... (truncated preview) ..." >&2
  fi

  if ! confirm "Use this title/body for the PR?"; then
    die "Cancelled."
  fi

  # ensure branch is pushed to origin (the fork)
  if ! git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
    info "No upstream set for this branch."
    if confirm "Push branch to origin and set upstream?"; then
      git push -u origin HEAD
    else
      die "Cannot create/update PR without a pushed branch."
    fi
  else
    git push >/dev/null 2>&1 || true
  fi

  # Build gh flags: when targeting a non-origin remote, point gh at that
  # repo and qualify --head as fork-owner:branch so GitHub routes it correctly.
  local gh_repo_args=()
  local gh_head="$branch"
  if [[ "$remote" != "origin" ]]; then
    local upstream_repo fork_owner
    upstream_repo="$(remote_to_gh_repo "$remote")"
    fork_owner="$(remote_to_gh_repo "origin")"
    fork_owner="${fork_owner%%/*}"
    gh_repo_args=(--repo "$upstream_repo")
    gh_head="${fork_owner}:${branch}"
  fi

  if gh pr view "${gh_repo_args[@]}" --json number >/dev/null 2>&1; then
    ok "Existing PR found for this branch. Updating title/body…"
    gh pr edit "${gh_repo_args[@]}" --title "$title" --body "$body"
    ok "PR updated."
  else
    ok "No PR found for this branch. Creating…"
    gh pr create "${gh_repo_args[@]}" --base "$base" --head "$gh_head" --title "$title" --body "$body"
    ok "PR created."
  fi
}
