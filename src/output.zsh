# ---- OUTPUT HELPERS ----
split_title_body() {
  # usage: split_title_body "$text"
  # echoes title then NUL then body (for safe parsing)
  local text="$1"
  local title body
  title="$(print -r -- "$text" | head -n 1 | tr -d '\r')"
  body="$(
    print -r -- "$text" \
    | tail -n +2 \
    | sed -E 's/\r$//' \
    | sed -E '1{/^[[:space:]]*$/d;}' \
    | sed -E '1{/^[[:space:]]*$/d;}'
  )"
  title="$(print -r -- "$title" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  print -rn -- "$title"
  print -rn -- $'\0'
  print -r -- "$body"
}
