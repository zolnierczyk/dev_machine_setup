# Repository Guidelines

## Build, test, and lint

- `bash test_config_scripts.sh` runs the config dump/restore sanity suite, including syntax, CLI argument, fake-`HOME` dump/restore, and checksum checks.
- There is no test-name selector. To run one of the suite's focused checks, use its underlying command, e.g. `bash -n dump_config.bash` for the syntax check or `bash dump_config.bash --help` for the help-output check.
- `./test_setup_machine.sh` builds and runs the setup script in Docker. It performs a full package and tool installation inside the container, so use Docker rather than running `setup_machine.bash` directly on a host.
- CI runs `bash test_config_scripts.sh` and `./test_setup_machine.sh` on pushes and pull requests to `main`; see `.github/workflows/test_pipeline.yml`.
- No standalone build or configured lint target exists. Useful local checks are `shellcheck dump_config.bash install_config.bash setup_machine.bash tmux_monitoring_setup.sh test_config_scripts.sh test_setup_machine.sh` and `python3 -m py_compile zsh_history_sanitize.py zsh_stats.py`.

## Architecture

- This repository automates two related workflows: preparing an Ubuntu 26.x development machine (`setup_machine.bash`) and migrating selected home-directory configuration between machines (`dump_config.bash` and `install_config.bash`). The setup script installs system packages/tools; it deliberately no longer copies dotfiles.
- The dump/restore scripts share a dump layout contract. `dump_config.bash` stores selected `$HOME` paths under `home/`, records their relative paths in `RESTORE_MANIFEST`, includes machine metadata and informational package/tool lists, then creates a compressed archive and SHA-256 file. Users verify and extract the archive, then run its bundled `install_config.bash` without an archive argument. The installer reads data beside itself regardless of the working directory, restores only manifest-listed paths to their original locations, backs up existing destinations, and keeps package lists informational; VS Code extensions are installed only when explicitly requested.
- Zsh history is handled separately by `zsh_history_sanitize.py`, which `dump_config.bash` invokes by default. Sanitization fails closed if Python or the sanitizer is unavailable; `--no-sanitize` is an explicit unsafe override. Custom secret words belong in a local file, not in the repository. `zsh_stats.py` is a standard-library-only analyzer for extended Zsh history.
- `tmux_monitoring_setup.sh` is a separate monitoring-session proof of concept. Docker-based setup validation is defined by `Dockerfile` and `test_setup_machine.sh`; CI orchestration is in `.github/workflows/test_pipeline.yml`.

## Repository-specific conventions

- Shell scripts generally use `set -euo pipefail`; scripts that call sibling files derive their location from `BASH_SOURCE` rather than relying on the caller's working directory.
- Keep dump and restore behavior aligned: add or change home paths through the dump's manifest-aware copy flow, and ensure restore continues to honor each path verbatim. Do not replace this with a top-level glob, which skips dotfiles and loses nested paths.
- Treat dump reference lists as guidance, not an install plan. Do not make package installation automatic during restore; preserve the explicit opt-in for VS Code extensions.
- Preserve the history privacy guarantees: sanitize by default, keep history and sensitive reports mode `600`, and never commit personal secret-word lists or redaction reports.
- `setup_machine.bash` is intentionally Ubuntu 26.x-specific and makes system-level changes. Validate edits in its Docker workflow rather than on the host.
- Python utilities use only the standard library and are command-line scripts; Zsh history inputs use extended-history format.
