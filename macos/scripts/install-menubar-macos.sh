#!/bin/bash

# Install the SwiftBar plugin and optionally install SwiftBar itself.

set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd -P)/common-macos.sh"

INSTALL_SWIFTBAR="true"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --no-brew) INSTALL_SWIFTBAR="false"; shift ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

PLUGIN_SRC="$PROJECT_ROOT/menubar/codex_dream_skin.10s.sh"
[ -f "$PLUGIN_SRC" ] && [ ! -L "$PLUGIN_SRC" ] && [ -s "$PLUGIN_SRC" ] \
  || fail "Plugin source is missing, empty, or a symbolic link: $PLUGIN_SRC"

MENU_SHELL_FILES=(
  localization-macos.sh
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
MENU_UPGRADE_STAGE=""
MENU_UPGRADE_PREVIOUS=""
MENU_UPGRADE_BROKEN=""
MENU_UPGRADE_STATE="idle"
PLUGIN_STAGE=""
PLUGIN_BACKUP=""
PLUGIN_HAD_PREVIOUS="false"
PLUGIN_PUBLISH_STATE="idle"

cleanup_menu_upgrade() {
  local status="${1:-1}"
  local plugin_rollback_ok="true"
  local engine_detached="false"
  local engine_restored="false"
  trap - EXIT HUP INT TERM
  set +e
  if { [ "$PLUGIN_PUBLISH_STATE" = "publishing" ] || [ "$PLUGIN_PUBLISH_STATE" = "published" ]; } &&
     [ -n "${PLUGIN_DST:-}" ]; then
    if [ "$PLUGIN_HAD_PREVIOUS" = "true" ] && [ -n "$PLUGIN_BACKUP" ] && [ -f "$PLUGIN_BACKUP" ]; then
      /bin/mv -f "$PLUGIN_BACKUP" "$PLUGIN_DST" 2>/dev/null || plugin_rollback_ok="false"
    else
      /bin/rm -f "$PLUGIN_DST" 2>/dev/null || plugin_rollback_ok="false"
    fi
  fi
  if [ "$plugin_rollback_ok" = "true" ] &&
     { [ "$MENU_UPGRADE_STATE" = "publishing" ] || [ "$MENU_UPGRADE_STATE" = "published" ]; } &&
     [ -n "$MENU_UPGRADE_PREVIOUS" ] && [ -e "$MENU_UPGRADE_PREVIOUS" ]; then
    if [ -e "$INSTALL_ROOT" ]; then
      if /bin/mv "$INSTALL_ROOT" "$MENU_UPGRADE_BROKEN" 2>/dev/null; then
        engine_detached="true"
      fi
    else
      engine_detached="true"
    fi
    if [ "$engine_detached" = "true" ] &&
       /bin/mv "$MENU_UPGRADE_PREVIOUS" "$INSTALL_ROOT" 2>/dev/null; then
      engine_restored="true"
    fi
    if [ "$engine_detached" = "true" ] && [ "$engine_restored" != "true" ] &&
       [ -e "$MENU_UPGRADE_BROKEN" ]; then
      /bin/mv "$MENU_UPGRADE_BROKEN" "$INSTALL_ROOT" 2>/dev/null
    elif [ "$engine_restored" = "true" ] && [ -e "$MENU_UPGRADE_BROKEN" ]; then
      /bin/rm -rf "$MENU_UPGRADE_BROKEN" 2>/dev/null
    fi
  fi
  [ -n "$MENU_UPGRADE_STAGE" ] && /bin/rm -rf "$MENU_UPGRADE_STAGE" 2>/dev/null
  [ -n "$PLUGIN_STAGE" ] && /bin/rm -f "$PLUGIN_STAGE" 2>/dev/null
  [ -n "$PLUGIN_BACKUP" ] && /bin/rm -f "$PLUGIN_BACKUP" 2>/dev/null
  exit "$status"
}

preflight_menu_bundle() {
  local name source
  [ ! -L "$PROJECT_ROOT/scripts" ] && [ ! -L "$PROJECT_ROOT/menubar" ] \
    || fail "Menu upgrade source directories must not be symbolic links."
  /bin/bash -n "$PLUGIN_SRC" || fail "Menu plugin source has invalid shell syntax."
  for name in "${MENU_SHELL_FILES[@]}"; do
    source="$PROJECT_ROOT/scripts/$name"
    [ -f "$source" ] && [ ! -L "$source" ] && [ -s "$source" ] \
      || fail "Menu upgrade script is missing, empty, or a symbolic link: $name"
    /bin/bash -n "$source" || fail "Menu upgrade script has invalid shell syntax: $name"
  done
  for name in "${MENU_HELPER_FILES[@]}"; do
    source="$PROJECT_ROOT/scripts/$name"
    [ -f "$source" ] && [ ! -L "$source" ] && [ -s "$source" ] \
      || fail "Menu upgrade helper is missing, empty, or a symbolic link: $name"
  done
}

stage_menu_engine_upgrade() {
  local name source target
  [ -d "$INSTALL_ROOT" ] && [ ! -L "$INSTALL_ROOT" ] \
    || fail "Installed engine root is missing or is a symbolic link: $INSTALL_ROOT"
  for target in "$INSTALL_ROOT/scripts" "$INSTALL_ROOT/menubar"; do
    [ ! -L "$target" ] || fail "Installed engine contains a symbolic-link bundle directory: $target"
  done

  /bin/mkdir -p "$(/usr/bin/dirname "$INSTALL_ROOT")"
  MENU_UPGRADE_STAGE="$(/usr/bin/mktemp -d "$INSTALL_ROOT.menubar-installing.XXXXXX")" \
    || fail "Could not create a private menu upgrade staging directory."
  MENU_UPGRADE_PREVIOUS="$MENU_UPGRADE_STAGE.previous"
  MENU_UPGRADE_BROKEN="$MENU_UPGRADE_STAGE.broken"
  [ ! -e "$MENU_UPGRADE_PREVIOUS" ] && [ ! -L "$MENU_UPGRADE_PREVIOUS" ] &&
    [ ! -e "$MENU_UPGRADE_BROKEN" ] && [ ! -L "$MENU_UPGRADE_BROKEN" ] \
    || fail "Menu upgrade transaction paths already exist."
  /usr/bin/rsync -a "$INSTALL_ROOT/" "$MENU_UPGRADE_STAGE/" \
    || fail "Could not stage the installed engine for the menu upgrade."
  [ ! -L "$MENU_UPGRADE_STAGE/scripts" ] && [ ! -L "$MENU_UPGRADE_STAGE/menubar" ] \
    || fail "Staged engine contains a symbolic-link bundle directory."
  /bin/mkdir -p "$MENU_UPGRADE_STAGE/scripts" "$MENU_UPGRADE_STAGE/menubar"

  target="$MENU_UPGRADE_STAGE/menubar/codex_dream_skin.10s.sh"
  [ ! -L "$target" ] || fail "Staged menu plugin target is a symbolic link."
  /bin/cp -f "$PLUGIN_SRC" "$target"
  /bin/chmod 755 "$target"
  /usr/bin/cmp -s "$PLUGIN_SRC" "$target" || fail "Staged menu plugin did not verify."

  for name in "${MENU_SHELL_FILES[@]}"; do
    source="$PROJECT_ROOT/scripts/$name"
    target="$MENU_UPGRADE_STAGE/scripts/$name"
    [ ! -L "$target" ] || fail "Staged menu script target is a symbolic link: $name"
    /bin/cp -f "$source" "$target"
    /bin/chmod 755 "$target"
    /usr/bin/cmp -s "$source" "$target" || fail "Staged menu script did not verify: $name"
  done
  for name in "${MENU_HELPER_FILES[@]}"; do
    source="$PROJECT_ROOT/scripts/$name"
    target="$MENU_UPGRADE_STAGE/scripts/$name"
    [ ! -L "$target" ] || fail "Staged menu helper target is a symbolic link: $name"
    /bin/cp -f "$source" "$target"
    /bin/chmod 644 "$target"
    /usr/bin/cmp -s "$source" "$target" || fail "Staged menu helper did not verify: $name"
  done
  MENU_UPGRADE_STATE="staged"
}

publish_menu_engine_upgrade() {
  MENU_UPGRADE_STATE="publishing"
  /bin/mv "$INSTALL_ROOT" "$MENU_UPGRADE_PREVIOUS" \
    || fail "Could not move the previous engine aside for the menu upgrade."
  if ! /bin/mv "$MENU_UPGRADE_STAGE" "$INSTALL_ROOT"; then
    /bin/mv "$MENU_UPGRADE_PREVIOUS" "$INSTALL_ROOT" \
      || fail "Menu upgrade failed and the previous engine could not be restored."
    MENU_UPGRADE_STATE="idle"
    fail "Could not publish the staged menu engine upgrade."
  fi
  MENU_UPGRADE_STATE="published"
}

commit_menu_engine_upgrade() {
  [ "$MENU_UPGRADE_STATE" = "published" ] || return 0
  MENU_UPGRADE_STATE="committed"
  /bin/rm -rf "$MENU_UPGRADE_PREVIOUS" 2>/dev/null || true
}

trap 'cleanup_menu_upgrade $?' EXIT
trap 'cleanup_menu_upgrade 129' HUP
trap 'cleanup_menu_upgrade 130' INT
trap 'cleanup_menu_upgrade 143' TERM

preflight_menu_bundle

# Prefer installed engine when this tree is the repo and engine already exists.
ENGINE_ROOT="$PROJECT_ROOT"
if [ -d "$INSTALL_ROOT/scripts" ]; then
  ENGINE_ROOT="$INSTALL_ROOT"
fi

/bin/chmod 755 \
  "$PROJECT_ROOT/scripts/pause-dream-skin-macos.sh" \
  "$PROJECT_ROOT/scripts/status-dream-skin-macos.sh" \
  "$PROJECT_ROOT/scripts/apply-from-menubar-macos.sh" \
  "$PROJECT_ROOT/scripts/switch-theme-macos.sh" \
  "$PROJECT_ROOT/scripts/load-image-theme-macos.sh" \
  "$PROJECT_ROOT/scripts/install-menubar-macos.sh" \
  "$PROJECT_ROOT/Install Menu Bar.command" 2>/dev/null || true

SWIFTBAR_APP=""
for candidate in "/Applications/SwiftBar.app" "$HOME/Applications/SwiftBar.app"; do
  if [ -d "$candidate" ]; then SWIFTBAR_APP="$candidate"; break; fi
done

if [ -z "$SWIFTBAR_APP" ] && [ "$INSTALL_SWIFTBAR" = "true" ]; then
  if command -v brew >/dev/null 2>&1; then
    printf 'Installing SwiftBar via Homebrew…\n'
    brew install --cask swiftbar || fail "brew install --cask swiftbar failed. Install SwiftBar manually, then rerun with --no-brew."
  else
    fail "SwiftBar is not installed and Homebrew was not found. Install SwiftBar from https://github.com/swiftbar/SwiftBar/releases then rerun with --no-brew."
  fi
  for candidate in "/Applications/SwiftBar.app" "$HOME/Applications/SwiftBar.app"; do
    if [ -d "$candidate" ]; then SWIFTBAR_APP="$candidate"; break; fi
  done
fi

[ -n "$SWIFTBAR_APP" ] || fail "SwiftBar.app not found. Install it, then rerun this script."

PLUGIN_DIR="$STATE_ROOT/menubar"
[ ! -L "$STATE_ROOT" ] || fail "Dream Skin state root is a symbolic link: $STATE_ROOT"
ensure_state_root
[ ! -L "$PLUGIN_DIR" ] || fail "Menu plugin directory is a symbolic link: $PLUGIN_DIR"
/bin/mkdir -p "$PLUGIN_DIR"

PLUGIN_DST="$PLUGIN_DIR/codex_dream_skin.10s.sh"
[ ! -L "$PLUGIN_DST" ] || fail "Installed menu plugin is a symbolic link: $PLUGIN_DST"
if [ -e "$PLUGIN_DST" ] && [ ! -f "$PLUGIN_DST" ]; then
  fail "Installed menu plugin is not a regular file: $PLUGIN_DST"
fi
PLUGIN_STAGE="$(/usr/bin/mktemp "$PLUGIN_DIR/.codex_dream_skin.10s.sh.installing.XXXXXX")" \
  || fail "Could not create a private menu plugin staging file."
[ -f "$PLUGIN_STAGE" ] && [ ! -L "$PLUGIN_STAGE" ] \
  || fail "Menu plugin staging path is not a regular file."
{
  printf '%s\n' '#!/bin/bash'
  printf 'export CODEX_DREAM_SKIN_ENGINE=%q\n' "$ENGINE_ROOT"
  # Skip the original shebang line from the template.
  /usr/bin/tail -n +2 "$PLUGIN_SRC"
} > "$PLUGIN_STAGE"
/bin/chmod 755 "$PLUGIN_STAGE"
/bin/bash -n "$PLUGIN_STAGE" || fail "Generated menu plugin has invalid shell syntax."

# Publish the coupled loader/helper bundle as one engine-root transaction. The
# active plugin is replaced only after the complete staged engine is live.
if [ -d "$INSTALL_ROOT" ] && [ "$PROJECT_ROOT" != "$INSTALL_ROOT" ]; then
  stage_menu_engine_upgrade
  publish_menu_engine_upgrade
fi
if [ -e "$PLUGIN_DST" ]; then
  PLUGIN_BACKUP="$(/usr/bin/mktemp "$PLUGIN_DIR/.codex_dream_skin.10s.sh.previous.XXXXXX")" \
    || fail "Could not create a private menu plugin rollback file."
  /bin/cp -p "$PLUGIN_DST" "$PLUGIN_BACKUP" \
    || fail "Could not stage the previous menu plugin for rollback."
  PLUGIN_HAD_PREVIOUS="true"
fi
PLUGIN_PUBLISH_STATE="publishing"
/bin/mv -f "$PLUGIN_STAGE" "$PLUGIN_DST" || fail "Could not publish the menu plugin atomically."
PLUGIN_STAGE=""
PLUGIN_PUBLISH_STATE="published"
commit_menu_engine_upgrade
MENU_UPGRADE_STATE="committed"
PLUGIN_PUBLISH_STATE="committed"
[ -n "$PLUGIN_BACKUP" ] && /bin/rm -f "$PLUGIN_BACKUP" 2>/dev/null || true
PLUGIN_BACKUP=""
trap - EXIT HUP INT TERM

if [ "${CODEX_DREAM_SKIN_TEST_SKIP_SWIFTBAR_ACTIVATION:-false}" != "true" ]; then
  /usr/bin/defaults write com.ameba.SwiftBar PluginDirectory -string "$PLUGIN_DIR" 2>/dev/null || true
  /usr/bin/open -a "$SWIFTBAR_APP" || true
  /bin/sleep 1
  /usr/bin/open "swiftbar://refreshall" 2>/dev/null || true
fi

printf '\n'
printf 'Menu bar plugin installed.\n'
printf '  Plugin folder: %s\n' "$PLUGIN_DIR"
printf '  Engine:        %s\n' "$ENGINE_ROOT"
printf '  SwiftBar:      %s\n' "$SWIFTBAR_APP"
printf '\n'
printf 'Look at the top-right menu bar for 🎨 Skin.\n'
printf 'If missing: SwiftBar → Preferences → Plugin Folder → %s\n' "$PLUGIN_DIR"
