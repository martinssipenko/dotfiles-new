# Dotfiles Setup (macOS)

## Quick start on a new Mac

Prereqs: install git first. On a fresh macOS:
```bash
xcode-select --install
```

1) Clone into `~/.dotfiles`:
   ```bash
   git clone git@github.com:martinssipenko/dotfiles.git ~/.dotfiles
   ```
2) Run the setup script:
   ```bash
   ~/.dotfiles/setup.sh
   ```
   - Installs Homebrew if needed
   - Installs packages from `brew/Brewfile`
   - Symlinks configs via stow
   - Installs nvm (latest release) for Node version management

## Rerun after changes
If you edit `Brewfile` or configs, rerun:
```bash
~/.dotfiles/setup.sh
```

## Notes
- Repo is designed to be safe to re-run; it will relink configs idempotently.
- Extra `PATH` entries can be listed in `~/.config/bash/paths` (one path per line, `#` for comments).

## 1Password env refs for Bash
If `op` is installed and `~/.config/1Password/op/env` exists, Bash will load secret
references from that file at startup and export the resolved values into your shell.

File format:
```bash
LINEAR_API_KEY=op://Private/Linear/api_key
export SENTRY_AUTH_TOKEN=op://Private/Sentry/token
```

Notes:
- Keep `~/.config/1Password/op/env` local and untracked.
- Resolved values are cached in `${XDG_CACHE_HOME:-$HOME/.cache}/bash` for `OP_ENV_CACHE_TTL` seconds. The default TTL is `43200` (12 hours).
- After editing the file or signing back into 1Password, run `op_reload_env`.
- Remove the cache manually with `op_clear_env_cache`.
- The same file also works with the existing `opr` helper, which runs commands via `op run --env-file`.
