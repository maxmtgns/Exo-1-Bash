# Exo 1 - bash

My solution to the [Linux bash exercise](https://courses.dallard.tech/linux/bash_exo/):
improve the shell, check Python, and automate the setup of a dev environment
with `env_install.sh`.

## Key concepts

| Concept | In one sentence |
|---|---|
| **Terminal vs shell** | The terminal is the window/app that shows text; the shell (bash, zsh…) is the program running inside it that reads and executes your commands. |
| **Environment variables** | Named values (`PATH`, `HOME`, `SHELL`, `OSTYPE`…) inherited by every program you start; they configure behaviour without changing code. |
| **Scripts** | Text files with a list of shell commands, run by an interpreter given in the shebang (`#!/usr/bin/env bash`). |
| **Package managers** | Tools that install/update/remove software and their dependencies (`apt`, `dnf`, `brew`, `pip`, `pipx`…). |

## Part 1 — Improve the shell

### 1.1 Which shell am I using?

```bash
echo "$0"        # the shell that is running right now (e.g. bash, -zsh)
echo "$SHELL"    # the LOGIN shell assigned to my user (e.g. /bin/bash)
```

`$SHELL` can differ from the running shell: if my login shell is zsh and I
type `bash`, `$SHELL` still says `/bin/zsh` while `$0` says `bash`.

### 1.2 Install Oh My Bash

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh)"
```

Change the theme in `~/.bashrc`, e.g. `OSH_THEME="powerline"`, then reload:

```bash
source ~/.bashrc
```

**What is `source` for?** `source file` (or `. file`) runs the commands of
`file` **in the current shell** instead of in a new child process. That's why
it is used to reload `~/.bashrc`: the new aliases, functions and variables are
applied to the terminal you're in, without having to close and reopen it.
(Running `./file` would execute it in a subshell, and everything it defines
would disappear when it ends.)

### 1.3 Enable the Git plugin

In `~/.bashrc`, add `git` to the plugins list:

```bash
plugins=(
  git
)
```

Then `source ~/.bashrc` and test the aliases:

| Alias | Full command |
|---|---|
| `gst` | `git status` |
| `gl`  | `git pull` |
| `gp`  | `git push` |
| `glog`| `git log --oneline --decorate --graph` |

## Part 2 — Check Python

```bash
python --version    # may be missing or be Python 2 on old systems
python3 --version   # always use python3 explicitly
```

## Part 3 — `env_install.sh`

```bash
chmod +x env_install.sh   # make it executable
./env_install.sh          # run it
```

### Required features

| # | Feature | Where in the script |
|---|---|---|
| 1 | Pretty printing with `printf` + blank lines around messages | `pretty_print` |
| 2 | OS detection with `$OSTYPE` | `detect_os` |
| 3 | Install `python3` if missing (brew / apt / dnf / yum / pacman / zypper / apk / winget / choco), else show its version | `check_python`, `install_python` |
| 4 | Check pip and show its version (installs it with `ensurepip` if missing) | `check_pip` |
| 5 | Install Jupyter Notebook (brew on macOS, pip `--user` on Linux with a `pipx` fallback for PEP 668 distros) | `install_jupyter` |
| 6 | `brew doctor` on macOS only | `macos_health_check` |

### Bonus features

- **Colours:** green = success, yellow = warning, red = error (disabled automatically when the output is not a terminal).
- **Logging:** every action, command, exit status and error output is written with a timestamp to `env_install.log`.
- **Strict mode:** `set -euo pipefail`.
- **Flags:**

  ```text
  -n, --dry-run    Show what would be done without changing anything
  -v, --verbose    Show every command and its full output
  -q, --quiet      Only show warnings and errors
  -u, --uninstall  Remove what this script installed (Jupyter Notebook)
  -h, --help       Show help
  ```

- **Uninstall:** removes Jupyter Notebook (brew, pipx or pip, whichever was used). Python itself is kept on purpose because the OS depends on it.

### Example run (Ubuntu 24.04)

```text
[INFO] Detected operating system: linux (OSTYPE=linux-gnu)

[OK] python3 is installed: Python 3.13.18

[OK] pip is available: pip 24.0 from /usr/lib/python3/dist-packages/pip (python 3.13)

[INFO] Installing Jupyter Notebook...

[OK] Jupyter Notebook is ready.

[INFO] Summary

  Python:    Python 3.13.18
  Pip:       pip 24.0
  Jupyter:   installed (launch with: jupyter notebook)

[OK] All done! Log file: ./env_install.log
```

