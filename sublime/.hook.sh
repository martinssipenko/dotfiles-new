#!/usr/bin/env bash
set -euo pipefail

log() { printf "[sublime-hook] %s\n" "$*"; }
DRY_RUN=${DRY_RUN:-false}

PKG_DIR="$HOME/Library/Application Support/Sublime Text/Installed Packages"
PKG_FILE="$PKG_DIR/Package Control.sublime-package"
PKG_URL="https://packagecontrol.io/Package%20Control.sublime-package"

quit_sublime() {
  if pgrep -x "Sublime Text" >/dev/null 2>&1; then
    log "Sublime Text running; asking it to quit..."
    if [[ "$DRY_RUN" == "true" ]]; then
      log "[DRY RUN] Would quit Sublime Text"
    else
      osascript -e 'tell application "Sublime Text" to quit'
      sleep 2
    fi
  fi
}

ensure_pkg_control() {
  if [[ -f "$PKG_FILE" ]]; then
    log "Package Control already installed at $PKG_FILE"
    return
  fi

  log "Package Control not found; installing..."
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY RUN] Would create directory: $PKG_DIR"
    log "[DRY RUN] Would download Package Control from $PKG_URL to $PKG_FILE"
    return
  fi

  mkdir -p "$PKG_DIR"
  tmp_file="$PKG_FILE.tmp"
  curl -fL "$PKG_URL" -o "$tmp_file"
  mv "$tmp_file" "$PKG_FILE"
  log "Installed Package Control at $PKG_FILE"
}

quit_sublime
ensure_pkg_control
