#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
TMP="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/dream-skin-menubar-upgrade.XXXXXX")"
trap '/bin/rm -rf "$TMP"' EXIT

MENU_SHELL_FILES=(
  pause-dream-skin-macos.sh
  status-dream-skin-macos.sh
  apply-from-menubar-macos.sh
  switch-theme-macos.sh
  load-image-theme-macos.sh
  install-menubar-macos.sh
)
MENU_HELPER_FILES=(
  check-image-dimensions.mjs
  image-metadata.mjs
  write-theme.mjs
)

copy_menu_source() {
  local destination="$1" name
  /bin/mkdir -p "$destination/scripts" "$destination/menubar"
  /bin/cp "$ROOT/scripts/common-macos.sh" "$destination/scripts/common-macos.sh"
  /bin/cp "$ROOT/menubar/codex_dream_skin.10s.sh" \
    "$destination/menubar/codex_dream_skin.10s.sh"
  for name in "${MENU_SHELL_FILES[@]}" "${MENU_HELPER_FILES[@]}"; do
    /bin/cp "$ROOT/scripts/$name" "$destination/scripts/$name"
  done
  /bin/chmod 755 "$destination/scripts/"*.sh
}

prepare_old_install() {
  local test_home="$1" live state name
  live="$test_home/.codex/codex-dream-skin-studio"
  state="$test_home/Library/Application Support/CodexDreamSkinStudio"
  /bin/mkdir -p "$live/scripts" "$live/menubar" "$state/menubar" \
    "$test_home/Applications/SwiftBar.app"
  /usr/bin/printf '%s\n' 'keep-existing-engine-content' > "$live/engine-sentinel.txt"
  /usr/bin/printf '%s\n' '#!/bin/bash' 'exit 0' > \
    "$live/menubar/codex_dream_skin.10s.sh"
  for name in "${MENU_SHELL_FILES[@]}"; do
    /usr/bin/printf '%s\n' '#!/bin/bash' 'exit 0' > "$live/scripts/$name"
  done
  # v1.5.13 did not carry check-image-dimensions.mjs. Keep the other helpers
  # old to prove that the complete coupled bundle appears in one transaction.
  /usr/bin/printf '%s\n' '// old helper' > "$live/scripts/image-metadata.mjs"
  /usr/bin/printf '%s\n' '// old helper' > "$live/scripts/write-theme.mjs"
  /usr/bin/printf '%s\n' '#!/bin/bash' 'echo old plugin' > \
    "$state/menubar/codex_dream_skin.10s.sh"
  /bin/chmod 755 "$state/menubar/codex_dream_skin.10s.sh"
}

assert_no_transaction_debris() {
  local test_home="$1"
  [ -z "$(/usr/bin/find "$test_home/.codex" -maxdepth 1 \
    \( -name 'codex-dream-skin-studio.menubar-installing.*' \
    -o -name 'codex-dream-skin-studio.menubar-installing.*.previous' \
    -o -name 'codex-dream-skin-studio.menubar-installing.*.broken' \) \
    -print -quit)" ]
}

SOURCE="$TMP/source"
HOME_OK="$TMP/home-success"
copy_menu_source "$SOURCE"
prepare_old_install "$HOME_OK"

CODEX_DREAM_SKIN_TEST_SKIP_SWIFTBAR_ACTIVATION=true HOME="$HOME_OK" \
  "$SOURCE/scripts/install-menubar-macos.sh" --no-brew >/dev/null

LIVE_OK="$HOME_OK/.codex/codex-dream-skin-studio"
STATE_OK="$HOME_OK/Library/Application Support/CodexDreamSkinStudio"
[ "$(/bin/cat "$LIVE_OK/engine-sentinel.txt")" = 'keep-existing-engine-content' ]
/usr/bin/cmp -s "$SOURCE/menubar/codex_dream_skin.10s.sh" \
  "$LIVE_OK/menubar/codex_dream_skin.10s.sh"
for name in "${MENU_SHELL_FILES[@]}"; do
  /usr/bin/cmp -s "$SOURCE/scripts/$name" "$LIVE_OK/scripts/$name"
  [ "$(/usr/bin/stat -f '%Lp' "$LIVE_OK/scripts/$name")" = '755' ]
done
for name in "${MENU_HELPER_FILES[@]}"; do
  /usr/bin/cmp -s "$SOURCE/scripts/$name" "$LIVE_OK/scripts/$name"
  [ "$(/usr/bin/stat -f '%Lp' "$LIVE_OK/scripts/$name")" = '644' ]
done
/usr/bin/grep -F -q "export CODEX_DREAM_SKIN_ENGINE=$LIVE_OK" \
  "$STATE_OK/menubar/codex_dream_skin.10s.sh"
[ "$(/usr/bin/stat -f '%Lp' "$STATE_OK/menubar/codex_dream_skin.10s.sh")" = '755' ]
assert_no_transaction_debris "$HOME_OK"

BROKEN_SOURCE="$TMP/source-missing-helper"
HOME_FAIL="$TMP/home-failure"
/usr/bin/rsync -a "$SOURCE/" "$BROKEN_SOURCE/"
/bin/rm -f "$BROKEN_SOURCE/scripts/image-metadata.mjs"
prepare_old_install "$HOME_FAIL"
LIVE_FAIL="$HOME_FAIL/.codex/codex-dream-skin-studio"
STATE_FAIL="$HOME_FAIL/Library/Application Support/CodexDreamSkinStudio"
BEFORE_HASHES="$(/usr/bin/find "$LIVE_FAIL" -type f -print0 | /usr/bin/xargs -0 /usr/bin/shasum -a 256)"
if CODEX_DREAM_SKIN_TEST_SKIP_SWIFTBAR_ACTIVATION=true HOME="$HOME_FAIL" \
   "$BROKEN_SOURCE/scripts/install-menubar-macos.sh" --no-brew \
   >"$TMP/missing-helper.out" 2>&1; then
  printf 'Menu upgrade unexpectedly accepted a missing helper.\n' >&2
  exit 1
fi
/usr/bin/grep -F -q 'image-metadata.mjs' "$TMP/missing-helper.out"
AFTER_HASHES="$(/usr/bin/find "$LIVE_FAIL" -type f -print0 | /usr/bin/xargs -0 /usr/bin/shasum -a 256)"
[ "$BEFORE_HASHES" = "$AFTER_HASHES" ]
[ "$(/bin/cat "$STATE_FAIL/menubar/codex_dream_skin.10s.sh")" = $'#!/bin/bash\necho old plugin' ]
[ ! -e "$LIVE_FAIL/scripts/check-image-dimensions.mjs" ]
assert_no_transaction_debris "$HOME_FAIL"

printf 'PASS: standalone menu upgrade stages, verifies, swaps, and fails before live mutation.\n'
