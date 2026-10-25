# dev_machine_setup

This repo contains scripts which have one and only one goal: copy all my dev setup from an old machine to a new one. The reason was very simple, as I switch laptops frequently because of many reasons. Although there are some ready-to-use tools for similar use cases, I decided to do it on my own to have full control over what is copied where. Another reason was to learn something about scripting, bash, Docker, GitHub and AI development.

## Disclaimer

 Written using AI tools as I always forget this strange bash language constructs.

# Running `setup_machine.bash` in a Docker Container

This guide explains how to run the `setup_machine.bash` script in a safe and isolated Docker environment.

## Prerequisites

- Docker installed on your system.

## Steps to Run

1. **Build the Docker Image**

   Open a terminal in the directory containing the `Dockerfile` and `setup_machine.bash` script, then run:

   ```bash
   docker build --build-arg LOCAL_USER=yourUserName -t setup-machine .
   ```

   Replace `yourUserName` with the desired username for the non-root user inside the container. This will create a Docker image named `setup-machine`.

2. **Run the Docker Container**

   Start a container from the image:

   ```bash
   docker run -it --rm setup-machine
   ```

   This will launch an interactive terminal session inside the container.

3. **Run the Script**

   Inside the container, execute the `setup_machine.bash` script:

   ```bash
   ./setup_machine.bash
   ```

   The script will run in the isolated environment of the container.

4. **Verify the Script**

   Check the output of the script to ensure it runs without errors. Since the container is isolated, any changes made by the script will not affect your host system.

5. **Exit the Container**

   To exit the container, type:

   ```bash
   exit
   ```

   The container will be automatically removed because of the `--rm` flag used in the `docker run` command.

## Notes

- The Docker container uses an Ubuntu 26.04 base image.
- The script is run as a non-root user for safety.
- The container is ephemeral; any changes made inside it will be lost when it is stopped.

## Proof of Concept: `tmux_monitoring_setup.sh`

The `tmux_monitoring_setup.sh` script is a Proof of Concept (PoC) designed to set up a `tmux` session for system monitoring. It creates multiple panes within a `tmux` session, each running a different monitoring tool.

### Features

- **System Monitoring**: Includes tools like `htop`, `iotop`, and `iftop` for monitoring system performance, disk I/O, and network traffic, respectively.
- **Passwordless `sudo`**: To ensure smooth execution of commands requiring elevated privileges, the script includes instructions for setting up passwordless `sudo` for specific commands.

### Usage

1. **Run the Script**:

   ```bash
   ./tmux_monitoring_setup.sh
   ```

   This will launch a `tmux` session with pre-configured panes for monitoring.

2. **Exit the Session**:

   To exit the `tmux` session, type:

   ```bash
   exit
   ```

   or press `Ctrl-b` followed by `d` to detach the session.

### Notes

- This script is a PoC and may require additional customization for specific use cases.
- Ensure that the required monitoring tools (`htop`, `iotop`, `iftop`) are installed on your system before running the script.

## Configuration Management Scripts

### `dump_config.bash`

The `dump_config.bash` script is used to extract user configurations from the system and create a compressed archive for backup purposes. This script ensures that important configuration files are preserved and can be restored later.

#### Features

- Copies configurations for tools like VIM, XFCE, Visual Studio Code, Zsh,
  Powerlevel10k, Terminator and Midnight Commander.
- Creates destination directories as needed.
- Sanitises the Zsh history before adding it to the dump (see below).
- Generates a compressed archive containing the extracted configurations and the `install_config.bash` script.

#### Dump layout

Everything that belongs in `$HOME` is stored under `home/` inside the dump,
keeping its original relative path, and every stored path is listed in
`MANIFEST`:

```
config_dump/
├── RESTORE_MANIFEST         # paths relative to $HOME, one per line
├── manifest.txt             # machine the dump was taken from
├── info/                    # reference lists (not restored automatically)
├── install_config.bash      # restore script (not restored into $HOME)
├── config_backup_<date>.tar.gz
├── config_backup_<date>.tar.gz.sha256
└── home/
    ├── .zshrc
    ├── .p10k.zsh
    ├── .zsh_history         # sanitised, mode 600
    ├── .vimrc
    ├── .vim/
    ├── .oh-my-zsh/custom/   # only the user-owned part of Oh-My-Zsh
    └── .config/
        ├── terminator/
        ├── mc/
        ├── xfce4/panel/
        └── Code/User/{settings.json,keybindings.json,snippets/}
```

`install_config.bash` walks `RESTORE_MANIFEST` and restores each entry to `$HOME/<path>`.
This is what makes dotfiles work: the previous version globbed the extracted
folder with `"$temp_dir"/*`, and a shell glob skips every name starting with a
dot, so `.zshrc`, `.vimrc` and `.vim` were dumped but never restored, while the
remaining files were flattened into `$HOME` under their dump names
(`vscode_settings.json` instead of `.config/Code/User/settings.json`).

Only `.oh-my-zsh/custom` is dumped - the framework itself is reinstalled by
`setup_machine.bash`, and skipping its checkout shrinks the archive from about
11 MB to 1.3 MB.

Archives created before the `RESTORE_MANIFEST` format are rejected by
`install_config.bash` with a message to recreate them.

#### Machine manifest and checksum

`manifest.txt` records the machine the dump came from and is stored inside the
archive, so the target machine can be compared against the source:

- `[dump]` - creation time, whether the history was sanitised, entry count.
- `[machine]` - hostname, user, OS, kernel, architecture, CPU, memory, locale,
  timezone, desktop, login shell and the dev-relevant local groups
  (`docker`, `vboxusers`, ...), which have to be recreated on the new machine.
- `[tools]` - versions of `zsh`, `git`, `python3`, `docker`, `code`, `gh` and
  friends.

The environment is deliberately **not** recorded, because it routinely holds
tokens, and the full group list is filtered down to local groups only.

`config_backup_<date>.tar.gz.sha256` sits next to the archive and stores only
the base name, so it can be checked directly:

```bash
cd config_dump && sha256sum -c config_backup_<date>.tar.gz.sha256
```

`install_config.bash` verifies this automatically when the file is present and
aborts on a mismatch; if it is absent it warns and continues. After extracting,
it prints a short summary of the source machine.

#### Reference lists (`info/`)

| File | Contents |
| --- | --- |
| `vscode_extensions.txt` | `code --list-extensions` output, one ID per line. |
| `apt_manual_packages.txt` | `apt-mark showmanual` - packages you asked for, without pulled-in dependencies. |
| `snap_packages.txt` | `snap list`, when snap is present. |
| `pip_user_packages.txt` | `pip3 list --user --format=freeze`. |
| `npm_global_packages.txt` | `npm ls -g --depth=0`. |

These lists are **informational**. `install_config.bash` copies them to
`~/config_dump_info/` on the target machine and installs nothing from them, with
one opt-in exception:

```bash
./install_config.bash --install-vscode-extensions config_backup_<date>.tar.gz
```

That runs `code --install-extension --force` for every ID in
`vscode_extensions.txt`, reports per-extension success or failure, and keeps
going when a single extension fails. Without the flag it only prints a hint.
It aborts if the `code` CLI is unavailable.

The package lists are intentionally never replayed: the new machine's
distribution and `setup_machine.bash` already provide most of them. Install what
you actually need after reviewing:

```bash
grep -v '^#' ~/config_dump_info/apt_manual_packages.txt | xargs sudo apt install -y
```

#### Usage

1. **Run the Script**:

   ```bash
   ./dump_config.bash
   ```

   This will create a compressed archive in the `configs/` directory.

2. **Verify the Archive**:

   Ensure that the archive file (e.g., `config_backup_<date>.tar.gz`) is created successfully in the `configs/` directory.

#### Sanitising the dumped Zsh history

By default `dump_config.bash` runs `zsh_history_sanitize.py` on `~/.zsh_history`
before adding it to the dump, so the archive carries no passwords or tokens.

```bash
./dump_config.bash ~/config_dump                      # history is sanitised
./dump_config.bash --no-sanitize ~/config_dump        # verbatim history (unsafe)
./dump_config.bash --report ~/redactions.txt ~/config_dump
./dump_config.bash --secret-words-file ~/words.txt ~/config_dump
```

| Option | Effect |
| --- | --- |
| `--no-sanitize` | Copy the history verbatim. The dump will contain secrets. |
| `--secret-words-file FILE` | Custom secret substrings. Defaults to `$HOME/.config/zsh-sanitize/secret-words.txt` (or `$ZSH_SANITIZE_WORDS`), skipped when absent. |
| `--report FILE` | Write the before/after redaction report to `FILE`. |
| `-h`, `--help` | Show usage. |

Safety behaviour:

- **Fail closed** - if `zsh_history_sanitize.py` or `python3` is missing, the
  script aborts instead of dumping an unsanitised history. `--no-sanitize` is
  the only way to get a verbatim copy.
- `--report` is rejected when it points inside the destination folder, because
  the report holds the *original* secrets and would be archived with the dump.
- The dumped history and the resulting archive are created with mode `600`.

### `install_config.bash`

The `install_config.bash` script is used to restore configurations from the archive created by `dump_config.bash`. It ensures that existing files are backed up before being replaced.

#### Features

- Extracts the archive into a temporary directory.
- Reads `MANIFEST` and restores every entry to its original path under `$HOME`,
  including dotfiles and nested paths such as `.config/terminator`.
- Creates backups of existing files before overwriting them.
- Re-applies mode `600` to the restored `.zsh_history`.
- Aborts on archives that contain no `MANIFEST`.

#### Usage

1. **Run the Script**:

   ```bash
   ./install_config.bash <config_archive.tar.gz>
   ```

   Replace `<config_archive.tar.gz>` with the path to the archive file.

2. **Verify Restoration**:

   Check that the configuration files have been restored to their original locations and that backups of existing files have been created.

### Notes

- Ensure that the `dump_config.bash` script is run before using `install_config.bash` to create a valid archive.
- Both scripts are designed to work seamlessly together for configuration management.

## Shell Usage Analytics: `zsh_stats.py`

The `zsh_stats.py` script analyses a Zsh *extended* history file and prints a text
report describing how the shell is actually being used. It is useful for finding
alias/script candidates, spotting abandoned tooling and understanding working
patterns.

### Requirements

- Python 3 (standard library only, no external dependencies).
- A history file in Zsh extended format, i.e. lines like
  `: <epoch>:<duration>;<command>`. This requires `setopt EXTENDED_HISTORY`
  in `.zshrc`.

### Usage

```bash
./zsh_stats.py                      # analyses ~/.zsh_history
./zsh_stats.py /path/to/.zsh_history
TOP=40 ./zsh_stats.py               # widen the top-N tables (default 25)
./zsh_stats.py > report.txt         # save the full report
```

### Report sections

- **Overview** – number of entries, unique command lines, distinct programs,
  time span, active days, commands per day, average command length, share of
  pipes and `sudo`, detected shell sessions (gap > 2 h), median think-time
  between commands and the immediate-repeat (retry) rate.
- **Command transitions** – most frequent `A -> B` pairs, showing typical
  workflows.
- **Top programs** – most frequently invoked executables.
- **Coverage / concentration** – how many programs make up 50/80/90/95/99 % of
  all invocations, plus the size of the one-off "long tail".
- **Top full command lines** – verbatim repeats, i.e. direct alias candidates.
- **Sub-command breakdown** – for multi-tool CLIs such as `git`, `docker`,
  `apt`, `pip` or `gh`.
- **Top flags** and **top directories** referenced in arguments.
- **Activity by hour / weekday / month** and **busiest days** – ASCII histograms.
- **Tool lifecycle** – tools adopted in the last 90 days versus tools dropped
  more than 180 days ago.
- **Alias / script suggestions** – repeated long command lines ranked by the
  number of keystrokes they would save.
- **Typo / failure signals** – rare very short tokens that are likely typos or
  aborted command lines.

### Implementation notes

- Pipelines are split on `|`, `||`, `&&` and `;`, so every stage is counted.
- Wrappers (`sudo`, `time`, `env`, `nohup`, `xargs`, `watch`, ...) and leading
  `VAR=value` assignments are skipped when determining the actual program.
- Multi-line history entries and Zsh's escaped-newline artefacts are normalised.
- Output is pipe-safe, so `./zsh_stats.py | head` works without a traceback.

### Getting richer data

The duration field in the history file is normally `0`. To capture command
duration, exit status and the working directory, additional `preexec`/`precmd`
hooks have to be added to `.zshrc`; the script currently reports only what the
standard extended history provides.

## History Sanitisation: `zsh_history_sanitize.py`

The `zsh_history_sanitize.py` script strips secrets from a Zsh *extended* history
file so it can safely be migrated to another machine. Timestamps, ordering and
command structure are preserved; only secret values are replaced with
`<REDACTED>`.

### Requirements

- Python 3.8+, no third-party dependencies.
- A history file in extended format (`: <timestamp>:<elapsed>;<command>`).
  Multi-line entries and Zsh's escaped-newline artefacts are handled.

### Usage

```bash
./zsh_history_sanitize.py ~/.zsh_history -o ~/.zsh_history.clean \
    --report redactions.txt --review review.txt
```

Copy the resulting `.clean` file to the new machine as `~/.zsh_history`
(mode `600`) after reviewing the report.

### Options

| Option | Effect |
| --- | --- |
| `-o`, `--output` | Destination for the sanitised history (required). |
| `--report FILE` | Before/after line for every modified entry. |
| `--review FILE` | Entries that merit a manual look but contain no secret. |
| `--secret-words-file FILE` | Custom secret substrings, one per line. |
| `--entropy` | Also redact standalone high-entropy blobs (may over-redact). |
| `--entropy-threshold` | Shannon-entropy cut-off for the above (default `3.5`). |
| `--mask-ips` | Replace public IP addresses with `<IP>`. |
| `--drop-unsafe` | Delete entries that cannot be safely redacted. |

### What gets redacted

- Credentials embedded in URLs: `https://user:<REDACTED>@host`.
- Vendor token shapes: GitHub (`ghp_`, `github_pat_`), GitLab, Slack, AWS keys,
  Google API keys, OpenAI/Anthropic `sk-` keys, JWTs, PEM private-key headers.
- Secret-bearing flags: `--pw`, `--password`, `--token`, `--api-key`,
  `--secret`, `--passphrase` and friends, in both `--flag X` and `--flag=X` form.
- `sshpass -p`, database passwords glued to `-p`, `curl -u user:pass`,
  `Authorization` / `X-Api-Key` headers, `.netrc`-style `password` lines.
- Environment assignments whose name looks secret (`*_TOKEN`, `*_SECRET`, ...).

### Custom secret substrings

Personal password fragments are supplied through a file rather than a command
line argument, because an argument would itself be written into the history
being sanitised:

```bash
mkdir -p ~/.config/zsh-sanitize
printf '%s\n' 'MyPasswordFragment' > ~/.config/zsh-sanitize/secret-words.txt
chmod 600 ~/.config/zsh-sanitize/secret-words.txt

./zsh_history_sanitize.py ~/.zsh_history -o ~/.zsh_history.clean \
    --secret-words-file ~/.config/zsh-sanitize/secret-words.txt
```

Matching is case-insensitive and the **whole token** containing the fragment is
removed, so `MyPasswordFragment2024!` disappears in full. Lines starting with
`re:` are treated as regular expressions, `#` marks a comment.

**Keep this file local - never copy it to the target machine, and never commit
it to this repository.**

### Implementation notes

- Rules run in order: structural rules (URLs, flags, headers) fire before the
  custom-wordlist rule, so useful context such as `git clone https://user:<REDACTED>@...`
  survives instead of the whole argument being erased.
- Narrow rules carry a required command context, which prevents false positives
  such as `docker run --user 1000:1000` being mistaken for `user:password`.
- Empty values (`--pw ""`) are preserved: they carry meaning and are not secrets.
- Names containing `PATH` are never treated as secrets, so `PYTHONPATH` and
  `LD_LIBRARY_PATH` survive a naive `PAT` match.
- Verify the result loads before migrating: `zsh -f -c 'fc -p ~/.zsh_history.clean'`.
