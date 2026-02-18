# ---- CHANGELOG HELPERS ----
changelog_excerpt() {
  # Returns a useful excerpt from CHANGELOG.md, favoring "Unreleased" if present.
  local root file
  root="$(repo_root)"
  file="$root/CHANGELOG.md"
  [[ -f "$file" ]] || return 0

  local start
  start="$(grep -n -i -m1 '^##\s*\[?\s*unreleased' "$file" 2>/dev/null | cut -d: -f1 || true)"

  if [[ -n "$start" ]]; then
    sed -n "${start},$((start+200))p" "$file"
  else
    sed -n '1,200p' "$file"
  fi
}

last_release_tag() {
  # Best-effort: find the most recent tag reachable. If none, empty.
  git describe --tags --abbrev=0 2>/dev/null || true
}
