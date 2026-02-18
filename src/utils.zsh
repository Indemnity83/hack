# ---- UTIL ----
die() { print -r -- "❌ $*" >&2; exit 1; }
info() { print -r -- "ℹ️  $*" >&2; }
ok() { print -r -- "✅ $*" >&2; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"
}

in_git_repo() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1
}

repo_root() {
  git rev-parse --show-toplevel
}

current_branch() {
  git branch --show-current
}

has_changes() {
  [[ -n "$(git status --porcelain)" ]]
}

has_staged_changes() {
  [[ -n "$(git diff --cached --name-only)" ]]
}

truncate_str() {
  # usage: truncate_str "$string" $maxchars
  local s="$1"
  local max="$2"

  if (( ${#s} > max )); then
    # zsh strings are 1-indexed for [start,end] slices
    print -r -- "${s[1,$max]}\n\n[...TRUNCATED...]\n"
  else
    print -r -- "$s"
  fi
}

prompt_choice() {
  # usage: prompt_choice "Question?" "default"
  local q="$1"
  local def="${2:-}"
  local ans=""
  if [[ -n "$def" ]]; then
    vared -p "$q [$def] " ans
    [[ -z "$ans" ]] && ans="$def"
  else
    vared -p "$q " ans
  fi
  print -r -- "$ans"
}

confirm() {
  # usage: confirm "Proceed?" ["y"|"n"]
  local ans
  local default="${2:-y}"
  ans="$(prompt_choice "$1 (y/n)" "$default")"
  [[ "$ans" == "y" || "$ans" == "Y" ]]
}

sanitize_branch_name() {
  # Convert to a safe kebab-case-ish branch name, keep it readable.
  # - lowercase
  # - replace illegal chars with '-'
  # - collapse repeats
  # - trim
  # - cap length
  local s="$1"
  s="${s:l}"
  s="${s//[^a-z0-9\/._-]/-}"
  s="$(print -r -- "$s" | tr -s '-')"
  s="$(print -r -- "$s" | sed -E 's/^-+//; s/-+$//; s/--+/-/g; s@//@/@g')"
  if (( ${#s} > 60 )); then
    s="${s:0:60}"
    s="$(print -r -- "$s" | sed -E 's/-+$//')"
  fi
  print -r -- "$s"
}
