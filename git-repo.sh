#!/bin/bash

# This script automates the setup and removal of Python projects from Git repositories.
#
# Usage Modes:
#   1. Setup Mode (default):
#      - Clones a Git repository.
#      - Creates a virtual environment.
#      - Runs 'build.sh' (if present) or installs 'requirements.txt'.
#      - Creates a symbolic link to the 'run.sh' script in TOOLS_BIN_DIR.
#      Usage: script_name <repository_name> <github_url>
#      Example: script_name my-web-app https://github.com/myuser/my-web-app.git
#
#   2. Removal Mode:
#      - Deletes the symbolic link and the entire project directory after user confirmation.
#      Usage: script_name --remove <repository_name>
#      Example: script_name --remove my-web-app
#
#   3. Build Python Run Script Mode:
#      - Performs all Setup Mode steps.
#      - If 'run.sh' does not exist, it will be automatically created with a default Python execution logic.
#      - Creates a symbolic link to this (potentially newly created) 'run.sh' in TOOLS_BIN_DIR.
#      - Does NOT automatically execute the 'run.sh' script; it finishes the setup process.
#      Usage: script_name --build-python-run <repository_name> <github_url>
#      Example: script_name --build-python-run my-web-app https://github.com/myuser/my-web-app.git

SCRIPT_VERSION="1.6.8"

TOOLS_BASE_DIR="${TOOLS_BASE_DIR:-/usr/local/tools}"
TOOLS_BIN_DIR="${TOOLS_BIN_DIR:-/usr/local/bin}"

RESET="\033[0m"
INFO_COLOR="\033[0;32m"
WARN_COLOR="\033[0;33m"
ERROR_COLOR="\033[0;31m"

log_info() {
    echo -e "${INFO_COLOR}[INFO] $(date +'%Y-%m-%d %H:%M:%S') $1${RESET}"
}

log_warn() {
    echo -e "${WARN_COLOR}[WARN] $(date +'%Y-%m-%d %H:%M:%S') $1${RESET}" >&2
}

log_error() {
    echo -e "${ERROR_COLOR}[ERROR] $(date +'%Y-%m-%d %H:%M:%S') $1${RESET}" >&2
    exit 1
}

clean_path() {
    echo "$1" | sed 's/\/\//\//g'
}

check_system_dependencies() {
    log_info "Checking for required system tools..."
    local missing_tools=()

    local tools=("git" "python3" "find" "chmod" "ln" "rm" "pwd")
    if ! command -v readlink &> /dev/null; then
        log_warn "Command 'readlink' not found. The script will rely on 'pwd -P' for symlink resolution in generated 'run.sh' scripts, which is generally more robust anyway."
    fi

    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done

    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "The following required system tools are not installed or not in PATH: ${missing_tools[*]}. Please install them and try again. For 'python3 -m venv' functionality, ensure your Python 3 installation includes the 'venv' module (e.g., on Debian/Ubuntu: 'sudo apt install python3-venv')."
    fi
    log_info "All required system tools found."
}

undo_project_setup() {
    local repo_name="$1"
    local project_dir="$(clean_path "$TOOLS_BASE_DIR/$repo_name")"
    local symlink_dest="$(clean_path "$TOOLS_BIN_DIR/$repo_name")"

    log_info "Initiating removal process for repository '$repo_name'..."

    echo -e "${WARN_COLOR}WARNING: This will permanently delete the symbolic link at '$symlink_dest' and the entire directory '$project_dir'.${RESET}"
    read -p "Are you absolutely sure you want to proceed? (type 'yes' to confirm): " confirmation
    if [[ ! "$confirmation" =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Removal cancelled by user."
        exit 0
    fi

    if [ -L "$symlink_dest" ]; then
        log_info "Removing symbolic link: '$symlink_dest'..."
        rm "$symlink_dest"
        if [ $? -ne 0 ]; then
            log_warn "Failed to remove symbolic link '$symlink_dest'. Manual removal may be required. Please check permissions."
        else
            log_info "Symbolic link '$symlink_dest' removed."
        fi
    else
        log_warn "Symbolic link '$symlink_dest' does not exist or is not a symlink. Skipping symlink removal."
    fi

    if [ -d "$project_dir" ]; then
        log_info "Removing project directory: '$project_dir'..."
        if [ -n "$project_dir" ] && [ "$project_dir" != "/" ] && [[ "$project_dir" == "$(clean_path "$TOOLS_BASE_DIR")"* ]]; then
            rm -rf "$project_dir"
            if [ $? -ne 0 ]; then
                log_error "Failed to remove project directory '$project_dir'. Manual removal may be required. Please check permissions. Exiting."
            else
                log_info "Project directory '$project_dir' removed successfully."
            fi
        else
            log_error "Attempted to remove an invalid or potentially dangerous path: '$project_dir'. Refusing to proceed. Exiting."
        fi
    else
        log_warn "Project directory '$project_dir' does not exist. Skipping directory removal."
    fi

    log_info "Removal process for '$repo_name' completed."
    exit 0
}

setup_python_project() {
    local repo_name=""
    local github_url=""
    local REMOVE_MODE=false
    local GENERATE_RUN_SCRIPT_MODE=false

    while (( "$#" )); do
        case "$1" in
            --remove|-r)
                REMOVE_MODE=true
                shift
                repo_name="$1"
                shift
                ;;
            --build-python-run)
                GENERATE_RUN_SCRIPT_MODE=true
                shift
                repo_name="$1"
                shift
                github_url="$1"
                shift
                set --
                ;;
            -*)
                log_warn "Unknown option: $1. Ignoring."
                shift
                ;;
            *)
                if [ -z "$repo_name" ]; then
                    repo_name="$1"
                elif [ -z "$github_url" ]; then
                    github_url="$1"
                else
                    log_warn "Unexpected argument: $1. Ignoring."
                fi
                shift
                ;;
        esac
    done

    if "$REMOVE_MODE"; then
        if [ -z "$repo_name" ]; then
            log_error "Usage for removal: $(basename "$0") --remove <repository_name>\nExample: $(basename "$0") --remove my-web-app"
        fi
        undo_project_setup "$repo_name"
    elif "$GENERATE_RUN_SCRIPT_MODE"; then
        if [ -z "$repo_name" ] || [ -z "$github_url" ]; then
            log_error "Usage for build-python-run: $(basename "$0") --build-python-run <repository_name> <github_url>\nExample: $(basename "$0") --build-python-run my-web-app https://github.com/myuser/my-web-app.git"
        fi
    else
        if [ -z "$repo_name" ] || [ -z "$github_url" ]; then
            log_error "Usage for setup: $(basename "$0") <repository_name> <github_url>\nExample: $(basename "$0") my-web-app https://github.com/myuser/my-web-app.git"
        fi
    fi

    log_info "Starting project setup/removal script (Version: $SCRIPT_VERSION)..."

    check_system_dependencies

    local project_dir="$(clean_path "$TOOLS_BASE_DIR/$repo_name")"
    local venv_dir="$(clean_path "$project_dir/.venv")"
    local main_script_source="$(clean_path "$project_dir/run.sh")"
    local requirements_file="$(clean_path "$project_dir/requirements.txt")"
    local build_script="$(clean_path "$project_dir/build.sh")"

    log_info "Ensuring base directory '$TOOLS_BASE_DIR' exists..."
    if [ ! -d "$TOOLS_BASE_DIR" ]; then
        mkdir -p "$TOOLS_BASE_DIR"
        if [ $? -ne 0 ]; then
            log_error "Failed to create base directory '$TOOLS_BASE_DIR'. Please check permissions. Exiting."
        fi
        log_info "Base directory '$TOOLS_BASE_DIR' created."
    else
        log_info "Base directory '$TOOLS_BASE_DIR' already exists."
    fi

    log_info "Checking repository '$repo_name' at '$project_dir'..."
    if [ -d "$project_dir" ]; then
        log_warn "Repository '$repo_name' already exists at '$project_dir'. Skipping cloning."
    else
        log_info "Cloning '$github_url' to '$project_dir'..."
        unset GITHUB_TOKEN
        unset GIT_SSH_COMMAND
        env -i HOME="/tmp" GIT_ASKPASS="" GIT_TERMINAL_PROMPT=0 git clone "$github_url" "$project_dir"
        if [ $? -ne 0 ]; then
            log_error "Failed to clone repository '$github_url'. Check network access and URL. Exiting."
        fi
        log_info "Repository '$repo_name' cloned successfully."
    fi

    log_info "Setting up virtual environment for '$repo_name' at '$venv_dir'..."
    if [ -d "$venv_dir" ]; then
        log_warn "Virtual environment for '$repo_name' already exists at '$venv_dir'. Skipping creation."
    else
        python3 -m venv "$venv_dir"
        if [ $? -ne 0 ]; then
            log_error "Failed to create virtual environment for '$repo_name'. Ensure 'python3-venv' or similar package is installed. Exiting."
        fi
        log_info "Virtual environment for '$repo_name' created."
    fi

    if [ -d "$venv_dir/bin" ]; then
        log_info "Making virtual environment executables in '$venv_dir/bin' group-executable..."
        find "$venv_dir/bin" -type f -exec chmod g+x {} +
        if [ $? -ne 0 ]; then
            log_warn "Failed to set executable permissions for some venv binaries in '$venv_dir/bin'. This might cause issues later."
        fi
    fi

    if [ -f "$build_script" ]; then
        log_info "Found '$build_script' for '$repo_name'. Running build script instead of installing from requirements.txt..."
        chmod +x "$build_script"
        if [ $? -ne 0 ]; then
            log_error "Failed to make '$build_script' executable. Exiting."
        fi

        (
            cd "$project_dir" || log_error "Failed to change directory to '$project_dir' before running build script. Exiting."
            log_info "Executing '$build_script' in '$project_dir'..."
            "$build_script"
            if [ $? -ne 0 ]; then
                log_error "Build script '$build_script' failed for '$repo_name'. Check its output for details. Exiting."
            fi
            log_info "Build script '$build_script' executed successfully."
        )
    elif [ -f "$requirements_file" ]; then
        log_info "No 'build.sh' found. Installing dependencies for '$repo_name' from '$requirements_file'..."
        local venv_activate_script="$(clean_path "$venv_dir/bin/activate")"
        if [ -f "$venv_activate_script" ]; then
            source "$venv_activate_script"
            pip install -r "$requirements_file" --no-input --disable-pip-version-check
            local pip_status=$?
            deactivate
            if [ $pip_status -ne 0 ]; then
                log_error "Failed to install dependencies for '$repo_name'. Check '$requirements_file' and log for detailed pip errors. Exiting."
            fi
            log_info "Dependencies for '$repo_name' installed."
        else
            log_error "Virtual environment activation script not found at '$venv_activate_script'. Cannot install dependencies. Exiting."
        fi
    else
        log_warn "Neither 'build.sh' nor 'requirements.txt' found for '$repo_name'. Skipping dependency/build step."
    fi

    if "$GENERATE_RUN_SCRIPT_MODE"; then
        if [ ! -f "$main_script_source" ]; then
            log_info "'run.sh' not found for '$repo_name'. Generating default 'run.sh'..."
            cat <<EOF > "$main_script_source"
#!/bin/bash
SCRIPT_DIR="${project_dir}"

if [ -f "\$SCRIPT_DIR/.venv/bin/activate" ]; then
    source "\$SCRIPT_DIR/.venv/bin/activate"
    if [ \$? -ne 0 ]; then
        echo "WARN: Failed to activate virtual environment. Proceeding, but dependencies might not be found." >&2
    fi
else
    echo "ERROR: Virtual environment activation script not found at \$SCRIPT_DIR/.venv/bin/activate. Cannot run main.py." >&2
    exit 1
fi

echo "INFO: Running python \$SCRIPT_DIR/main.py with provided arguments..."
python "\$SCRIPT_DIR"/main.py "\$@"
RUN_STATUS=\$?

if declare -f deactivate &>/dev/null; then
    deactivate
    echo "INFO: Virtual environment deactivated."
fi

exit \$RUN_STATUS
EOF
            if [ $? -ne 0 ]; then
                log_error "Failed to create default 'run.sh' for '$repo_name'. Exiting."
            fi
            chmod +x "$main_script_source"
            if [ $? -ne 0 ]; then
                log_error "Failed to make generated 'run.sh' executable. Exiting."
            fi
            log_info "Default 'run.sh' created and made executable."
        else
            log_info "'run.sh' already exists for '$repo_name'. Skipping generation."
        fi
    fi

    local symlink_dest="$(clean_path "$TOOLS_BIN_DIR/$repo_name")"
    log_info "Attempting to create symbolic link for '$repo_name' in '$TOOLS_BIN_DIR'..."

    if [ -f "$main_script_source" ]; then
        if [ ! -d "$TOOLS_BIN_DIR" ]; then
            log_error "Destination directory for symlink '$TOOLS_BIN_DIR' does not exist. Please create it or set TOOLS_BIN_DIR correctly. Exiting."
        fi

        if [ -f "$symlink_dest" ] || [ -L "$symlink_dest" ]; then
            log_warn "Existing file or symlink found at '$symlink_dest'. Removing it before creating a new one."
            rm "$symlink_dest"
            if [ $? -ne 0 ]; then
                log_error "Failed to remove existing file/symlink at '$symlink_dest'. Please check permissions. Exiting."
            fi
        fi

        log_info "Creating symlink from '$main_script_source' to '$symlink_dest'..."
        ln -s "$main_script_source" "$symlink_dest"
        if [ $? -ne 0 ]; then
            log_error "Failed to create symbolic link for '$repo_name' at '$symlink_dest'. This might require sudo privileges. Exiting."
        fi
        log_info "Symbolic link for '$repo_name' created successfully at '$symlink_dest'."
    else
        log_warn "Source script '$main_script_source' not found. Skipping symbolic link creation."
    fi

    log_info "Project setup for '$repo_name' completed successfully!"
}

setup_python_project "$@"