#!/usr/bin/env bash

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
DRY_RUN="${DRY_RUN:-false}"

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)
        DRY_RUN="true"
        ;;
      *)
        echo "[setup] Unknown option: $1" >&2
        exit 1
        ;;
    esac
    shift
  done
}

log() { printf "[setup] %s\n" "$*"; }
info() { printf "[info] %s\n" "$*"; }

stow_target_for() {
  local pkg="$1" target
  if [[ -f "$pkg/.stowtarget" ]]; then
    target="$(<"$pkg/.stowtarget")"
    # expand leading ~ to $HOME
    target="${target/#\~/$HOME}"
  else
    target="$HOME"
  fi
  printf '%s\n' "$target"
}

run_command() {
  local cmd="$1" desc="$2"
  if [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY RUN] Would: $desc -> $cmd"
  else
    log "$desc"
    eval "$cmd"
  fi
}

require_macos_arm64() {
  local os_name arch_name
  os_name=$(uname -s)
  if [[ "$os_name" != "Darwin" ]]; then
    echo "[setup] This script is intended for macOS. Detected: $os_name" >&2
    exit 1
  fi
  arch_name=$(uname -m)
  if [[ "$arch_name" != "arm64" ]]; then
    echo "[setup] This script currently supports Apple Silicon (arm64) Macs only. Detected: $arch_name" >&2
    exit 1
  fi
  log "macOS on Apple Silicon detected. Continuing..."
}

install_homebrew_if_missing() {
  if command -v brew >/dev/null 2>&1; then
    log "Homebrew already installed."
    return
  fi

  log "Homebrew not found. Installing via pkg (latest GitHub release)..."
  local pkg_url
  pkg_url=$(/usr/bin/curl -fs https://api.github.com/repos/Homebrew/brew/releases/latest | \
    /usr/bin/awk -F '"' '/browser_download_url/ && /pkg/ {print $4; exit}')
  if [[ -z "${pkg_url:-}" ]]; then
    echo "[setup] Could not find pkg URL from Homebrew releases. Aborting." >&2
    exit 1
  fi
  local tmp_pkg=/tmp/homebrew-latest.pkg
  log "Downloading $pkg_url ..."
  /usr/bin/curl -L "$pkg_url" -o "$tmp_pkg"
  log "Running installer (may prompt for admin password)..."
  sudo /usr/sbin/installer -pkg "$tmp_pkg" -target /
  # Add Homebrew to PATH for Apple Silicon default prefix
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
}

ensure_stow() {
  if command -v stow >/dev/null 2>&1; then
    log "stow already installed."
    return
  fi
  log "Installing stow via Homebrew..."
  brew install stow
}

ensure_default_shell() {
  local target_shell="/opt/homebrew/bin/bash"
  if [[ ! -x "$target_shell" ]]; then
    info "Homebrew bash not found at $target_shell; skipping default shell change."
    return
  fi

  local current_shell
  current_shell=$(dscl . -read ~/ UserShell 2>/dev/null | awk '{print $2}')
  if [[ "$current_shell" == "$target_shell" ]]; then
    log "Default shell already set to $target_shell"
    return
  fi

  if ! grep -q "^$target_shell$" /etc/shells 2>/dev/null; then
    if [[ "$DRY_RUN" == "true" ]]; then
      info "[DRY RUN] Would add $target_shell to /etc/shells"
    else
      run_command "echo \"$target_shell\" | sudo tee -a /etc/shells >/dev/null" "Add Homebrew bash to /etc/shells"
    fi
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY RUN] Would run: chsh -s $target_shell"
  else
    run_command "chsh -s $target_shell" "Set default shell to Homebrew bash"
  fi
}

setup_hostname() {
  log "Setting HostName..."

  local computer_name local_host_name host_name
  computer_name=$(scutil --get ComputerName)
  local_host_name=$(scutil --get LocalHostName)

  if [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY RUN] Would set HostName to: $local_host_name"
    info "[DRY RUN] Would update NetBIOSName in SMB server config"
  else
    run_command "sudo scutil --set HostName '${local_host_name}'" "Set system hostname"
    host_name=$(scutil --get HostName)
    run_command "sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.smb.server.plist NetBIOSName -string '${host_name}'" "Update SMB server NetBIOS name"
  fi

  printf "ComputerName:  ==> [%s]\n" "$computer_name"
  printf "LocalHostName: ==> [%s]\n" "$local_host_name"
  if [[ "$DRY_RUN" == "false" ]]; then
    printf "HostName:      ==> [%s]\n" "$(scutil --get HostName)"
  fi
}

setup_directories() {
  # Use DOTFILES env override or default to ~/.dotfiles
  if [[ -z "${DOTFILES:-}" ]]; then
    export DOTFILES="${HOME}/.dotfiles"
  fi

  info "Using DOTFILES directory: ${DOTFILES}"

  if [[ ! -d "${DOTFILES}" ]]; then
    echo "[setup] DOTFILES directory not found: ${DOTFILES}" >&2
    exit 1
  fi

  # Ensure XDG_CONFIG_HOME (~/.config) exists
  if [[ -z "${XDG_CONFIG_HOME:-}" ]]; then
    log "Setting up ~/.config directory..."
    if [[ ! -d "${HOME}/.config" ]]; then
      if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would create directory: ${HOME}/.config"
      else
        run_command "mkdir '${HOME}/.config'" "Create XDG config directory"
      fi
    fi
    export XDG_CONFIG_HOME="${HOME}/.config"
  fi

  # Ensure ~/.local/bin exists
  if [[ ! -d "${HOME}/.local/bin" ]]; then
    log "Setting up ~/.local/bin directory..."
    if [[ "$DRY_RUN" == "true" ]]; then
      info "[DRY RUN] Would create directory: ${HOME}/.local/bin"
    else
      run_command "mkdir -pv '${HOME}/.local/bin'" "Create local bin directory"
    fi
  fi

  # Record Homebrew prefix (Apple Silicon only supported here)
  HOMEBREW_PREFIX="/opt/homebrew"
  export HOMEBREW_PREFIX
  info "Using HOMEBREW_PREFIX=${HOMEBREW_PREFIX}"
}

build_stow_ignore_pattern() {
  local ignore_file="$DOTFILES_DIR/.stow-global-ignore" patterns=()
  if [[ -f "$ignore_file" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
      patterns+=("$line")
    done < "$ignore_file"
  fi

  ((${#patterns[@]})) || return 1
  (IFS='|'; printf '%s' "${patterns[*]}")
}

setup_symlinks() {
  log "Setting up symlinks with GNU Stow..."

  if [[ "$DRY_RUN" == "false" ]] && [[ "$PWD" != "$DOTFILES" ]]; then
    if ! cd "$DOTFILES/"; then
      echo "[setup] Failed to change to DOTFILES directory: $DOTFILES" >&2
      exit 1
    fi
  fi

  local stow_packages=0 stow_ignore="" stow_ignore_flag=""
  if stow_ignore="$(build_stow_ignore_pattern)"; then
    stow_ignore_flag="--ignore '${stow_ignore}'"
  fi
  for item in *; do
    # Skip non-directories and known non-stow folders
    if [[ ! -d "$item" ]]; then
      continue
    fi
    case "$item" in
      .git|brew)
        continue
        ;;
    esac

    local target
    target="$(stow_target_for "$item")"

    # Ensure target dir exists
    if [[ "$DRY_RUN" == "true" ]]; then
      info "[DRY RUN] Would ensure directory: $target"
    else
      run_command "mkdir -p \"$target\"" "Ensure target directory $target"
    fi

    stow_packages=$((stow_packages + 1))
    if [[ "$DRY_RUN" == "true" ]]; then
      if [[ -n "$stow_ignore_flag" ]]; then
        info "[DRY RUN] Would stow package: $item -> $target (ignoring ${stow_ignore})"
      else
        info "[DRY RUN] Would stow package: $item -> $target"
      fi
    else
      run_command "stow -R ${stow_ignore_flag} -t \"$target\" \"$item\"" "Stow package: $item to $target"
    fi
  done

  info "Processed ${stow_packages} stow packages"
}

brew_bundle() {
  local brewfile="$DOTFILES_DIR/brew/Brewfile"
  if [[ -f "$brewfile" ]]; then
    log "Installing packages from Brewfile..."
    brew bundle --file "$brewfile"
  else
    echo "[setup] Brewfile not found at $brewfile. Skipping bundle." >&2
  fi
}

install_nvm_latest() {
  if command -v nvm >/dev/null 2>&1; then
    log "nvm already installed ($(nvm --version 2>/dev/null || true))"
    return
  fi

  local latest_tag install_url
  latest_tag=$(/usr/bin/curl -fs https://api.github.com/repos/nvm-sh/nvm/releases/latest | \
    /usr/bin/awk -F '"' '/"tag_name":/ {print $4; exit}')
  if [[ -z "${latest_tag:-}" ]]; then
    echo "[setup] Could not determine latest nvm release tag." >&2
    return
  fi
  install_url="https://raw.githubusercontent.com/nvm-sh/nvm/${latest_tag}/install.sh"

  log "Installing nvm (${latest_tag}) from ${install_url}..."
  if [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY RUN] Would run: PROFILE=/dev/null NVM_DIR=\"$HOME/.nvm\" curl -fsSL ${install_url} | bash"
    return
  fi

  PROFILE=/dev/null NVM_DIR="$HOME/.nvm" /usr/bin/curl -fsSL "${install_url}" | bash
}

run_package_hooks() {
  log "Running package setup hooks (if any)..."
  if [[ "$PWD" != "$DOTFILES_DIR" ]]; then
    cd "$DOTFILES_DIR"
  fi
  for item in *; do
    if [[ -d "$item" ]]; then
      local hook="$item/.hook.sh"
      local hook_path="$DOTFILES_DIR/$hook"
      if [[ -x "$hook_path" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
          info "[DRY RUN] Would run hook: $hook"
        else
          log "Running hook: $hook"
          (cd "$DOTFILES_DIR/$item" && "./.hook.sh")
        fi
      fi
    fi
  done
}

main() {
  parse_args "$@"
  require_macos_arm64
  install_homebrew_if_missing
  ensure_stow
  # setup_hostname
  setup_directories
  setup_symlinks
  brew_bundle
  ensure_default_shell
  install_nvm_latest
  run_package_hooks
}

main "$@"
