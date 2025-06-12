# git-repo-py (Project Setup Script) Changelog

This document provides a detailed history of changes and new features introduced to the `git-repo-py` script during our development process.

## Overview

The `git-repo-py` script is designed to streamline the setup and management of Python projects, handling tasks like repository cloning, virtual environment creation, dependency installation, and script execution. This changelog reflects the evolution of its functionality.

## Version History

### Version 1.9.0

* **New Feature:** Added `--help` (and short alias `-h`) option.  This option displays a comprehensive usage message for the script.

### Version 1.8.1

* **Enhancement:** The `--update` mode (and `-u` alias) now includes a step to clean up `__pycache__` directories within the project before performing Git operations. This helps prevent conflicts with cached files.

### Version 1.8.0

* **New Feature:** Introduced `--update` (and short alias `-u`) mode. This mode performs the following actions:
    1. Checks for staged and unstaged local changes.
    2. Stashes any detected local changes.
    3. Performs a `git pull` to update the repository with the latest remote changes.
    4. Pops the stashed changes back onto the working directory.

### Version 1.7.2

* **Enhancement:** Added a short alias `-bpr` for the `--build-python-run` option, making commands more concise.

### Version 1.7.1

* **Bug Fix:** Corrected a syntax error (originally "Floc al to fi") in the `build.sh` execution block that was causing script failures.

### Version 1.7.0

* **New Feature:** Implemented `--force-create-run` (and short alias `-fcr`) mode. When used, this option will always generate the default Python wrapper script directly in the `TOOLS_BIN_DIR`, even if a `run.sh` script already exists in the cloned project's directory.

### Version 1.6.9

* **Refactor/Enhancement:** Modified the handling logic for `run.sh`:
    * If a `run.sh` exists in the cloned project, it's made executable (`chmod +x`) and a symbolic link is created from `TOOLS_BIN_DIR/<repo_name>` to it.
    * If `run.sh` is not found in the project, a default Python execution wrapper script is now created directly in `TOOLS_BIN_DIR/<repo_name>`. This wrapper activates the virtual environment and runs `main.py` from the project's folder.
    * This change largely supersedes the original `build-python-run` mode's `run.sh` generation logic.

### Version 1.6.8 (Initial State)

* **Core Functionality:** Supported setup (clone repo, create venv, install deps via `build.sh` or `requirements.txt`, symlink `run.sh`) and removal of Python projects.
* **Modes:** Included default setup, removal (`--remove`), and a `build-python-run` (`--build-python-run`) mode that would create `run.sh` inside the project folder if it didn't exist.

---

This changelog provides a clear history of how the script has evolved with your input!
