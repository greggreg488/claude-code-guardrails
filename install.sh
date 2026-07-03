#!/usr/bin/env bash
# install.sh — copy the hooks into ~/.claude/hooks and wire them into settings.json.
#
#   ./install.sh            copy hooks + print the settings block to merge by hand
#   ./install.sh --merge    also merge the block into ~/.claude/settings.json (backs it up first; needs jq)
#
# Every hook is independent — delete any line you don't want from settings.example.json
# first. The opt-in guards are inert until configured (see each hook's header).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS_SRC="$REPO_DIR/hooks"
DEST="$HOME/.claude/hooks"
SETTINGS="$HOME/.claude/settings.json"

mkdir -p "$DEST"
count=0
for f in "$HOOKS_SRC"/*.sh; do
  cp "$f" "$DEST/"
  chmod +x "$DEST/$(basename "$f")"
  count=$((count + 1))
done
echo "Copied $count hooks to $DEST"

# Build the settings block with your real home path substituted for <HOME>.
BLOCK="$(sed "s#<HOME>#$HOME#g" "$REPO_DIR/settings.example.json")"

if [ "${1:-}" = "--merge" ]; then
  command -v jq >/dev/null 2>&1 || { echo "jq is required for --merge"; exit 1; }
  [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
  backup="$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
  cp "$SETTINGS" "$backup"
  printf '%s' "$BLOCK" | jq 'del(."//")' > "$REPO_DIR/.block.tmp.json"
  # Append our per-event hook arrays onto whatever already exists.
  if jq -s '
      .[0] as $cur | .[1] as $add
      | $cur
      | .hooks = ( ($cur.hooks // {}) as $h
          | reduce ($add.hooks | keys[]) as $ev ($h;
              .[$ev] = (( .[$ev] // [] ) + $add.hooks[$ev]) ) )
    ' "$SETTINGS" "$REPO_DIR/.block.tmp.json" > "$SETTINGS.new"; then
    mv "$SETTINGS.new" "$SETTINGS"
    rm -f "$REPO_DIR/.block.tmp.json"
    echo "Merged hooks into $SETTINGS (backup: $backup). Review it, then restart Claude Code."
  else
    rm -f "$SETTINGS.new" "$REPO_DIR/.block.tmp.json"
    echo "Merge failed — settings.json left untouched (backup at $backup)."
    exit 1
  fi
else
  echo
  echo "Add these 'hooks' entries to $SETTINGS (merge into any existing 'hooks' object):"
  echo "------------------------------------------------------------------"
  printf '%s\n' "$BLOCK"
  echo "------------------------------------------------------------------"
  echo "Or re-run with --merge to do it automatically (backs up first)."
fi
