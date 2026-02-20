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
