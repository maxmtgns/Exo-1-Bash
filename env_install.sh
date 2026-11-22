#!/usr/bin/env bash
#
# env_install.sh — set up a minimal Python / Jupyter development environment.
#
# What it does:
#   1. Detects the operating system (via $OSTYPE) to pick the right package manager.
#   2. Installs python3 if it is missing, otherwise prints its version.
#   3. Checks that pip is available and prints its version.
#   4. Installs Jupyter Notebook.
#   5. On macOS, runs `brew doctor` as a health check of Homebrew.
#
# Usage:
#   ./env_install.sh [--dry-run] [--verbose] [--quiet] [--uninstall] [--help]
#
# Every action is recorded with a timestamp in env_install.log (next to the script).

# ---------------------------------------------------------------------------
# Strict mode
#   -e          : exit as soon as a command fails
#   -u          : using an unset variable is an error (catches typos)
#   -o pipefail : a pipeline fails if ANY command in it fails, not only the last
# ---------------------------------------------------------------------------
set -euo pipefail

# ---------------------------------------------------------------------------
# Global settings (can be changed with command-line flags)
# ---------------------------------------------------------------------------
DRY_RUN=false
VERBOSE=false
QUIET=false
UNINSTALL=false

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${LOG_FILE:-$SCRIPT_DIR/env_install.log}"

# ANSI colour codes. Disabled automatically when output is not a terminal
# (e.g. redirected to a file) so the log / pipes don't get filled with escape codes.
if [[ -t 1 ]]; then
    GREEN=$'\033[0;32m'
    YELLOW=$'\033[0;33m'
    RED=$'\033[0;31m'
    BLUE=$'\033[0;34m'
    RESET=$'\033[0m'
else
    GREEN="" YELLOW="" RED="" BLUE="" RESET=""
fi

# ---------------------------------------------------------------------------
# Functions
# ---------------------------------------------------------------------------

# log LEVEL MESSAGE... — append a timestamped line to the log file.
log() {
    local level="$1"
    shift
    printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*" >> "$LOG_FILE"
}

# pretty_print MESSAGE [LEVEL]
#   Prints MESSAGE surrounded by blank lines so it stands out in the output.
#   LEVEL is one of: info (default), success, warning, error.
#   printf is used instead of echo because echo's behaviour (-e, -n, escapes)
#   differs between shells and systems; printf is portable.
pretty_print() {
    local message="$1"
    local level="${2:-info}"
    local color prefix

    case "$level" in
        success) color="$GREEN";  prefix="[OK]"   ;;
        warning) color="$YELLOW"; prefix="[WARN]" ;;
        error)   color="$RED";    prefix="[ERROR]";;
        *)       color="$BLUE";   prefix="[INFO]" ;;
    esac

    log "$(printf '%s' "$level" | tr '[:lower:]' '[:upper:]')" "$message"

    # Quiet mode hides everything except warnings and errors.
    if [[ "$QUIET" == true && "$level" != "warning" && "$level" != "error" ]]; then
        return 0
    fi

    # Errors go to stderr so they can be separated from normal output.
    if [[ "$level" == "error" ]]; then
        printf '\n%s%s %s%s\n\n' "$color" "$prefix" "$message" "$RESET" >&2
    else
        printf '\n%s%s %s%s\n\n' "$color" "$prefix" "$message" "$RESET"
    fi
}

# verbose MESSAGE — only shown with --verbose (always logged).
verbose() {
    log "DEBUG" "$*"
    if [[ "$VERBOSE" == true ]]; then
        printf '%s  > %s%s\n' "$YELLOW" "$*" "$RESET"
    fi
}

# run COMMAND [ARGS...]
#   Runs a command (or only shows it in --dry-run mode) and logs whether it
#   succeeded. Returns the command's exit code so the caller can react.
run() {
    log "CMD" "$*"
    if [[ "$DRY_RUN" == true ]]; then
        printf '%s  [dry-run] %s%s\n' "$YELLOW" "$*" "$RESET"
        return 0
    fi

    verbose "Running: $*"

    local status=0
    # Capture output so it can be logged; show it live only in verbose mode.
    local output
    output="$("$@" 2>&1)" || status=$?

    if [[ -n "$output" ]]; then
        printf '%s\n' "$output" >> "$LOG_FILE"
        if [[ "$VERBOSE" == true ]]; then
            printf '%s\n' "$output"
        fi
    fi

    if [[ "$status" -eq 0 ]]; then
        log "OK" "$* (exit 0)"
    else
        log "FAIL" "$* (exit $status)"
        # Show the tail of the output so the user knows why it failed.
        if [[ "$VERBOSE" != true && -n "$output" ]]; then
            printf '%s\n' "$output" | tail -n 5 >&2
        fi
    fi
    return "$status"
}

# command_exists NAME — true if NAME is an available command.
command_exists() {
    command -v "$1" > /dev/null 2>&1
}

# Use sudo only when we are not already root and sudo exists.
sudo_if_needed() {
    if [[ "$(id -u)" -eq 0 ]] || ! command_exists sudo; then
        "$@"
    else
        sudo "$@"
    fi
}

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Set up python3, pip and Jupyter Notebook for this machine.

Options:
  -n, --dry-run    Show what would be done without changing anything
  -v, --verbose    Show every command and its full output
  -q, --quiet      Only show warnings and errors
  -u, --uninstall  Remove what this script installed (Jupyter Notebook)
  -h, --help       Show this help and exit

The log is written to: $LOG_FILE
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--dry-run)   DRY_RUN=true ;;
            -v|--verbose)   VERBOSE=true ;;
            -q|--quiet)     QUIET=true ;;
            -u|--uninstall) UNINSTALL=true ;;
            -h|--help)      usage; exit 0 ;;
            *)
                printf 'Unknown option: %s\n\n' "$1" >&2
                usage >&2
                exit 2
                ;;
        esac
        shift
    done

    if [[ "$VERBOSE" == true && "$QUIET" == true ]]; then
        printf '%s\n' "--verbose and --quiet cannot be used together." >&2
        exit 2
    fi
}

# Feature 2 — detect the OS from $OSTYPE (set by bash itself).
# Sets the global OS variable to: linux, macos, windows or unknown.
detect_os() {
    # ${OSTYPE:-} avoids an "unbound variable" error under `set -u` in odd shells.
    case "${OSTYPE:-}" in
        linux*)                OS="linux" ;;
        darwin*)               OS="macos" ;;
        msys*|cygwin*|win32*)  OS="windows" ;;
        *)                     OS="unknown" ;;
    esac
    pretty_print "Detected operating system: $OS (OSTYPE=${OSTYPE:-unset})"
}

# On Linux, find which package manager this distribution uses.
detect_linux_package_manager() {
    local pm
    for pm in apt-get dnf yum pacman zypper apk; do
        if command_exists "$pm"; then
            printf '%s' "$pm"
            return 0
        fi
    done
    return 1
}

# Install python3 (and pip) with the package manager of the current OS.
install_python() {
    case "$OS" in
        macos)
            if ! command_exists brew; then
                pretty_print "Homebrew is not installed. Install it from https://brew.sh and run this script again." error
                return 1
            fi
            run brew install python
            ;;
        linux)
            local pm
            if ! pm="$(detect_linux_package_manager)"; then
                pretty_print "No supported package manager found. Please install python3 manually." error
                return 1
            fi
            verbose "Linux package manager: $pm"
            case "$pm" in
                apt-get) run sudo_if_needed apt-get update &&
                         run sudo_if_needed apt-get install -y python3 python3-pip python3-venv ;;
                dnf)     run sudo_if_needed dnf install -y python3 python3-pip ;;
                yum)     run sudo_if_needed yum install -y python3 python3-pip ;;
                pacman)  run sudo_if_needed pacman -Sy --noconfirm python python-pip ;;
                zypper)  run sudo_if_needed zypper install -y python3 python3-pip ;;
                apk)     run sudo_if_needed apk add python3 py3-pip ;;
            esac
            ;;
        windows)
            if command_exists winget; then
                run winget install -e --id Python.Python.3.12
            elif command_exists choco; then
                run choco install -y python
            else
                pretty_print "Install Python from https://www.python.org/downloads/ (no winget/choco found)." error
                return 1
            fi
            ;;
        *)
            pretty_print "Unsupported OS: cannot install python3 automatically." error
            return 1
            ;;
    esac
}

# Feature 3 — make sure python3 is there.
check_python() {
    if command_exists python3; then
        pretty_print "python3 is installed: $(python3 --version 2>&1)" success
        return 0
    fi

    pretty_print "python3 not found — installing it..." warning
    if install_python; then
        if [[ "$DRY_RUN" == true ]]; then
            pretty_print "(dry-run) python3 would now be installed." success
        elif command_exists python3; then
            pretty_print "python3 installed: $(python3 --version 2>&1)" success
        else
            pretty_print "Installation finished but python3 is still not on the PATH. Open a new terminal and retry." error
            return 1
        fi
    else
        pretty_print "Failed to install python3. See $LOG_FILE for details." error
        return 1
    fi
}

# Feature 4 — make sure pip works. `python3 -m pip` is used instead of `pip`
# because it guarantees we talk to the pip of THIS python3, not another one.
check_pip() {
    if [[ "$DRY_RUN" == true ]] && ! command_exists python3; then
        pretty_print "(dry-run) pip would be checked once python3 is installed."
        return 0
    fi

    if python3 -m pip --version > /dev/null 2>&1; then
        pretty_print "pip is available: $(python3 -m pip --version)" success
        return 0
    fi

    pretty_print "pip not found — trying to install it with ensurepip..." warning
    if run python3 -m ensurepip --upgrade && python3 -m pip --version > /dev/null 2>&1; then
        pretty_print "pip installed: $(python3 -m pip --version)" success
    elif [[ "$OS" == "linux" ]] && command_exists apt-get &&
         run sudo_if_needed apt-get install -y python3-pip; then
        pretty_print "pip installed: $(python3 -m pip --version)" success
    else
        pretty_print "Could not install pip. Install it manually (e.g. python3-pip package)." error
        return 1
    fi
}

jupyter_installed() {
    command_exists jupyter-notebook ||
        { command_exists jupyter && jupyter notebook --version > /dev/null 2>&1; } ||
        python3 -m notebook --version > /dev/null 2>&1
}

# Feature 5 — install Jupyter Notebook, the method depends on the OS.
install_jupyter() {
    if jupyter_installed; then
        pretty_print "Jupyter Notebook is already installed." success
        return 0
    fi

    pretty_print "Installing Jupyter Notebook..."
    case "$OS" in
        macos)
            # Homebrew's jupyterlab formula ships `jupyter notebook` too.
            run brew install jupyterlab
            ;;
        linux)
            # Recent distributions (Debian 12+, Ubuntu 23.04+) block `pip install`
            # into the system Python (PEP 668, "externally-managed-environment").
            # pipx installs apps in their own isolated venv, which is the clean way.
            if command_exists pipx; then
                run pipx install notebook
            elif run python3 -m pip install --user notebook; then
                :
            else
                pretty_print "pip refused to install (PEP 668). Falling back to pipx..." warning
                if command_exists apt-get; then
                    run sudo_if_needed apt-get install -y pipx
                else
                    run python3 -m pip install --user --break-system-packages pipx
                fi
                run python3 -m pipx install notebook
                run python3 -m pipx ensurepath
            fi
            ;;
        windows)
            run python3 -m pip install --user notebook
            ;;
        *)
            run python3 -m pip install --user notebook
            ;;
    esac
}

# Feature 6 — only on macOS: check Homebrew is healthy.
macos_health_check() {
    [[ "$OS" == "macos" ]] || return 0

    if ! command_exists brew; then
        pretty_print "Homebrew not found, skipping brew doctor." warning
        return 0
    fi

    pretty_print "Running brew doctor..."
    # brew doctor exits non-zero on warnings, which are often harmless:
    # report them but don't abort the whole script.
    if run brew doctor; then
        pretty_print "Homebrew is healthy." success
    else
        pretty_print "brew doctor reported issues — run 'brew doctor' to read them." warning
    fi
}

# --uninstall: undo what this script installed. python3 itself is NOT removed
# on purpose: on Linux/macOS the system depends on it.
uninstall() {
    pretty_print "Uninstalling Jupyter Notebook..."
    local removed=false

    if [[ "$OS" == "macos" ]] && command_exists brew && brew list jupyterlab > /dev/null 2>&1; then
        run brew uninstall jupyterlab && removed=true
    fi
    if command_exists pipx && pipx list 2>/dev/null | grep -q "package notebook"; then
        run pipx uninstall notebook && removed=true
    fi
    if command_exists python3 && python3 -m pip show notebook > /dev/null 2>&1; then
        # PEP 668 systems may need --break-system-packages to remove a --user package.
        run python3 -m pip uninstall -y notebook ||
            run python3 -m pip uninstall -y --break-system-packages notebook
        removed=true
    fi

    if [[ "$removed" == true ]]; then
        pretty_print "Jupyter Notebook removed. (python3 is kept, the system needs it.)" success
    else
        pretty_print "Nothing to uninstall: Jupyter Notebook was not found." warning
    fi
}

# Print the final checklist so the user can verify everything at a glance.
summary() {
    [[ "$DRY_RUN" == true ]] && return 0
    pretty_print "Summary"
    local py pip jup
    py="$(python3 --version 2>&1 || echo 'missing')"
    pip="$(python3 -m pip --version 2>/dev/null | cut -d' ' -f1-2 || echo 'missing')"
    if jupyter_installed; then jup="installed (launch with: jupyter notebook)"; else jup="missing"; fi
    if [[ "$QUIET" != true ]]; then
        printf '  %-10s %s\n' "Python:" "$py" "Pip:" "${pip:-missing}" "Jupyter:" "$jup"
    fi
    if ! jupyter_installed; then
        pretty_print "If 'jupyter' isn't found, open a new terminal (or run 'source ~/.bashrc') so the new PATH is loaded." warning
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    parse_args "$@"
    log "INFO" "===== env_install.sh started (args: ${*:-none}) ====="
    [[ "$DRY_RUN" == true ]] && pretty_print "Dry-run mode: nothing will be changed." warning

    detect_os

    if [[ "$UNINSTALL" == true ]]; then
        uninstall
    else
        check_python
        check_pip
        if install_jupyter; then
            [[ "$DRY_RUN" == true ]] || pretty_print "Jupyter Notebook is ready." success
        else
            pretty_print "Jupyter Notebook installation failed. See $LOG_FILE" error
            exit 1
        fi
        macos_health_check
        summary
    fi

    pretty_print "All done! Log file: $LOG_FILE" success
    log "INFO" "===== env_install.sh finished ====="
}

main "$@"
