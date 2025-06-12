# git-repo: Python Project Automation Script

git-repo is a versatile bash script designed to streamline the setup, management, and removal of Python projects from Git repositories on your system. It automates common tasks like cloning, virtual environment creation, dependency installation, and creating convenient executable links.

## Table of Contents

* [Features](#features)
* [Installation](#installation)
* [Usage](#usage)
    * [Default Setup Mode](#default-setup-mode)
    * [Removal Mode](#removal-mode)
    * [Build Python Run Script Mode (Legacy)](#build-python-run-script-mode-legacy)
    * [Force Create Run Script Mode](#force-create-run-script-mode)
    * [Update Mode](#update-mode)
    * [Help Mode](#help-mode)
* [Configuration](#configuration)
* [System Dependencies](#system-dependencies)
* [Contributing](#contributing)
* [License](#license)

## Features

This script provides robust automation for Python project workflows, including:

* **Automated Cloning:** Clones Git repositories into a designated `TOOLS_BASE_DIR`.
* **Virtual Environment Management:** Automatically creates and manages Python virtual environments for each project.
* **Dependency Installation:** Installs project dependencies via `requirements.txt` or executes a `build.sh` script if present.
* **Intelligent Run Script Handling:**
    * If a `run.sh` script exists in the project, it's made executable and a symbolic link is created to it in `TOOLS_BIN_DIR`.
    * If no `run.sh` is found, a default Python execution wrapper script is generated directly in `TOOLS_BIN_DIR`, pointing to the project's `main.py`.
* **Force Run Script Creation:** Option to force the creation of the default Python wrapper script in `TOOLS_BIN_DIR`, even if a `run.sh` exists in the cloned project's directory. This overrides any existing project-specific `run.sh` behavior.
* **Project Removal:** Safely removes symbolic links and project directories after user confirmation.
* **Project Update:** Cleans up `__pycache__` directories, stashes local changes (staged and unstaged), performs a git pull to update the repository from its remote, and then pops the stashed changes back.
* **Comprehensive Help:** Built-in `--help` option for quick reference.

## Installation

1.  Download the script:

    ```bash
    curl -o /usr/local/bin/git-repo https://raw.githubusercontent.com/tugapse/git-repo/refs/heads/master/git-repo.sh
    ```

    (Note: You might need `sudo` for `/usr/local/bin`)

2.  Make it executable:

    ```bash
    chmod +x /usr/local/bin/git-repo
    ```

3.  Ensure `git`, `python3` (with venv module), `find`, `chmod`, `ln`, `rm`, `pwd` are installed and in your system's PATH.  The script will check for these. For Debian/Ubuntu, you might need `sudo apt install python3-venv`.

## Usage

Replace `script_name` with the actual name of your script (e.g., `git-repo`).

### Default Setup Mode

Clones a Git repository, creates a virtual environment, installs dependencies, and sets up a runnable symbolic link.

```bash
script_name <repository_name> <github_url>
```

Example:

```bash
git-repo my-web-app https://github.com/myuser/my-web-app.git
```

### Removal Mode

Deletes the symbolic link in `TOOLS_BIN_DIR` and the entire project directory after user confirmation.

```bash
script_name --remove <repository_name>
```

or

```bash
script_name -r <repository_name>
```

Example:

```bash
git-repo --remove my-web-app
```

### Build Python Run Script Mode (Legacy)

Performs all default setup steps. If `run.sh` is not found in the project, it will ensure a default Python execution script is generated directly in `TOOLS_BIN_DIR`. This flag mostly ensures the setup process completes; the behavior of generating a `run.sh` (if not found in the project) is now standard for all setup operations.

```bash
script_name --build-python-run <repository_name> <github_url>
```

or

```bash
script_name -bpr <repository_name> <github_url>
```

Example:

```bash
git-repo --build-python-run my-web-app https://github.com/myuser/my-web-app.git
```

### Force Create Run Script Mode

Behaves like the Default Setup Mode, but always generates the default Python wrapper script directly in `TOOLS_BIN_DIR`, even if a `run.sh` already exists in the cloned project's directory. This overrides any existing project-specific `run.sh` behavior.

```bash
script_name --force-create-run <repository_name> <github_url>
```

or

```bash
script_name -fcr <repository_name> <github_url>
```

Example:

```bash
git-repo --force-create-run my-web-app https://github.com/myuser/my-web-app.git
```

### Update Mode

Cleans up `__pycache__` directories, stashes local changes (staged and unstaged), performs a git pull to update the repository from its remote, and then pops the stashed changes back.

```bash
script_name --update <repository_name>
```

or

```bash
script_name -u <repository_name>
```

Example:

```bash
git-repo --update my-web-app
```

### Help Mode

Displays a comprehensive help message with all usage instructions and options.

```bash
script_name --help
```

or

```bash
script_name -h
```

Example:

```bash
git-repo --help
```

## Configuration

You can customize the base directories by setting environment variables before running the script:

*   `TOOLS_BASE_DIR`: The parent directory where all repositories will be cloned. Default: `/usr/local/tools` Example: `export TOOLS_BASE_DIR="/opt/my-repos"`
*   `TOOLS_BIN_DIR`: The directory where symbolic links to the project's run scripts (or generated wrappers) will be placed. This directory should typically be in your system's PATH. Default: `/usr/local/bin` Example: `export TOOLS_BIN_DIR="/home/youruser/bin"`

## System Dependencies

The script requires the following system tools to be installed and available in your PATH:

*   `git`
*   `python3` (with the venv module, e.g., `python3-venv` on Debian/Ubuntu)
*   `find`
*   `chmod`
*   `ln`
*   `rm`
*   `pwd`

The script will perform a check for these dependencies and exit with an error if any are missing.

## Contributing

Contributions are welcome! If you have suggestions for improvements or bug fixes, please open an issue or submit a pull request.

## License

This project is open-sourced under the MIT License. See the `LICENSE` file for more details.