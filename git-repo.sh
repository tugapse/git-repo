#!/bin/bash

# This script automates the setup and removal of Python projects from Git repositories.
#
# Usage Modes:
#   1. Setup Mode (default):
#      - Clones a Git repository.
#      - Creates a virtual environment.
#      - Runs 'build.sh' (if present) or installs 'requirements.txt'.
#      - Handles 'run.sh': If found in the project, it's made executable and symlinked.
#        If not found, a default Python execution script is created directly in TOOLS_BIN_DIR,
#        pointing to the project's 'main.py'.
#      Usage: script_name <repository_name> <github_url>
#      Example: script_name my-web-app https://github.com/myuser/my-web-app.git
#
#   2. Removal Mode:
#      - Deletes the symbolic link and the entire project directory after user confirmation.
#      Usage: script_name --remove <repository_name>
#      Example: script_name --remove my-web-app
#
#   3. Build Python Run Script Mode (Legacy from previous versions):
#      - This mode now primarily ensures the setup process completes; the behavior of
#        generating 'run.sh' (if not found in the project) is now standard for all
#        setup operations, creating the wrapper directly in TOOLS_BIN_DIR.
#      - Does NOT automatically execute the 'run.sh' script; it finishes the setup process.
#      Usage: script_name --build-python-run <repository_name> <github_url>
#      Example: script_name --build-python-run my-web-app https://github.com/myuser/my-web-app.git
#
#   4. Force Create Run Script Mode:
#      - Behaves like Setup Mode, but *always* generates the default Python wrapper script
#        directly in TOOLS_BIN_DIR, even if a 'run.sh' already exists in the project.
#      Usage: script_name --force-create-run <repository_name> <github_url>
#      Example: script_name --force-create-run my-web-app https://github.com/myuser/my-web-app.git
#
#   5. Update Mode:
#      - Cleans up '__pycache__' directories within the project.
#      - Checks for staged and unstaged changes, stashes them.
#      - Performs a 'git pull' to update the repository.
#      - Pops the stashed changes back.
#      Usage: script_name --update <repository_name>
#      Example: script_name --update my-web-app
#
#   6. Help Mode:
#      - Displays this help message.
#      Usage: script_name --help
#      Example: script_name --help

SCRIPT_VERSION="1.9.0" # Updated version

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

display_help() {
    check_system_dependencies # Ensure necessary tools are present even for help
    cat <<EOF
${INFO_COLOR}Usage: $(basename "$0") [OPTIONS] <repository_name> [github_url]${RESET}

This script automates the setup, removal, and updating of Python projects from Git repositories.

${WARN_COLOR}Options:${RESET}
  -r, --remove <repository_name>          : Deletes the symbolic link and the entire project directory.
                                            Example: $(basename "$0") --remove my-web-app

  -bpr, --build-python-run <repo_name> <url> : Clones, sets up venv, installs dependencies.
                                            If 'run.sh' not found in project, generates a default
                                            Python run script in ${TOOLS_BIN_DIR}.
                                            Example: $(basename "$0") --build-python-run my-app https://github.com/user/my-app.git

  -fcr, --force-create-run <repo_name> <url> : Similar to default setup, but always generates
                                            the default Python run script directly in ${TOOLS_BIN_DIR},
                                            overriding any existing 'run.sh' in the project.
                                            Example: $(basename "$0") --force-create-run my-app https://github.com/user/my-app.git

  -u, --update <repository_name>          : Cleans __pycache__, stashes local changes, pulls latest
                                            from remote, and pops stashed changes.
                                            Example: $(basename "$0") --update my-web-app

  -h, --help                            : Displays this help message and exits.

${INFO_COLOR}Default Setup Mode (no specific option):${RESET}
  $(basename "$0") <repository_name> <github_url>
  Clones the repository, creates a virtual environment, installs dependencies.
  If 'run.sh' exists in project, symlinks it. If not, generates a default
  Python run script in ${TOOLS_BIN_DIR}.
  Example: $(basename "$0") my-web-app https://github.com/myuser/my-web-app.git

${INFO_COLOR}Version:${RESET} $SCRIPT_VERSION

EOF
    exit 0
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

    if [ -L "$symlink_dest" ] || [ -f "$symlink_dest" ]; then # Also check if it's a regular file (generated script)
        log_info "Removing executable/symbolic link: '$symlink_dest'..."
        rm -f "$symlink_dest" # Use -f for force removal, especially if it's a file
        if [ $? -ne 0 ]; then
            log_warn "Failed to remove executable/symbolic link '$symlink_dest'. Manual removal may be required. Please check permissions."
        else
            log_info "Executable/symbolic link '$symlink_dest' removed."
        fi
    else
        log_warn "Executable/symbolic link '$symlink_dest' does not exist or is not a symlink/file. Skipping removal."
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

update_project() {
    local repo_name="$1"
    local project_dir="$(clean_path "$TOOLS_BASE_DIR/$repo_name")"
    local stash_pushed=false

    log_info "Initiating update process for repository '$repo_name'..."

    if [ ! -d "$project_dir" ]; then
        log_error "Project directory '$project_dir' does not exist. Cannot update."
    fi

    if [ ! -d "$project_dir/.git" ]; then
        log_error "Project directory '$project_dir' is not a Git repository. Cannot update."
    fi

    # Execute operations within the project directory
    (
        cd "$project_dir" || log_error "Failed to change directory to '$project_dir' for update. Exiting."

        log_info "Cleaning up '__pycache__' directories in '$project_dir'..."
        find "$project_dir" -type d -name "__pycache__" -exec rm -rf {} +
        if [ $? -ne 0 ]; then
            log_warn "Failed to remove some '__pycache__' directories. This might indicate permission issues or active processes."
        else
            log_info "'__pycache__' directories cleaned."
        fi

        log_info "Checking for local changes in '$project_dir'..."
        # Check for modified (staged/unstaged) or untracked files
        if ! git diff --quiet --exit-code || ! git diff --cached --quiet --exit-code || test -n "$(git ls-files --others --exclude-standard)"; then
            log_info "Local changes detected. Stashing them before pull."
            git stash push -u -m "git-repo-py update: temporary stash for $repo_name"
            if [ $? -ne 0 ]; then
                log_warn "Failed to stash local changes. Attempting pull without stashing, but this may lead to merge issues if there are conflicts. Please check manually."
            else
                stash_pushed=true
                log_info "Local changes stashed."
            fi
        else
            log_info "No local changes detected. Skipping stash."
        fi

        log_info "Pulling latest changes for '$repo_name'..."
        git pull
        local pull_status=$?
        if [ $pull_status -ne 0 ]; then
            log_warn "Git pull failed for '$repo_name'. You may have merge conflicts or other issues that require manual resolution. (Exit status: $pull_status)"
            # Do not exit here, attempt to pop stash if it was pushed
        else
            log_info "Git pull completed successfully."
        fi

        if "$stash_pushed"; then
            log_info "Attempting to pop stashed changes..."
            git stash pop
            if [ $? -ne 0 ]; then
                log_warn "Failed to pop stashed changes for '$repo_name'. This might be due to merge conflicts. You may need to resolve conflicts and run 'git stash pop' manually."
            else
                log_info "Stashed changes popped successfully."
            fi
        fi
    ) # End of subshell

    log_info "Update process for '$repo_name' completed."
    exit 0 # Exit after update is complete
}


setup_python_project() {
    local repo_name=""
    local github_url=""
    local REMOVE_MODE=false
    local BUILD_RUN_SCRIPT_MODE=false
    local FORCE_CREATE_RUN_MODE=false
    local UPDATE_MODE=false
    local HELP_MODE=false # New flag

    while (( "$#" )); do
        case "$1" in
            --remove|-r)
                REMOVE_MODE=true
                shift
                repo_name="$1"
                shift
                ;;
            --build-python-run|-bpr)
                BUILD_RUN_SCRIPT_MODE=true
                shift
                repo_name="$1"
                shift
                github_url="$1"
                shift
                set -- # Clear remaining arguments
                ;;
            --force-create-run|-fcr)
                FORCE_CREATE_RUN_MODE=true
                shift
                repo_name="$1"
                shift
                github_url="$1"
                shift
                set -- # Clear remaining arguments
                ;;
            --update|-u)
                UPDATE_MODE=true
                shift
                repo_name="$1"
                shift
                set -- # Clear remaining arguments
                ;;
            --help|-h) # New help option
                HELP_MODE=true
                shift
                set -- # Clear remaining arguments
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

    if "$HELP_MODE"; then # Check for help mode first
        display_help
    elif "$REMOVE_MODE"; then
        if [ -z "$repo_name" ]; then
            log_error "Usage for removal: $(basename "$0") --remove <repository_name>\nExample: $(basename "$0") --remove my-web-app"
        fi
        undo_project_setup "$repo_name"
    elif "$UPDATE_MODE"; then
        if [ -z "$repo_name" ]; then
            log_error "Usage for update: $(basename "$0") --update <repository_name>\nExample: $(basename "$0") --update my-web-app"
        fi
        update_project "$repo_name"
    elif "$BUILD_RUN_SCRIPT_MODE" || "$FORCE_CREATE_RUN_MODE"; then
        if [ -z "$repo_name" ] || [ -z "$github_url" ]; then
            log_error "Usage for setup modes (--build-python-run/-bpr, --force-create-run/-fcr): $(basename "$0") <option> <repository_name> <github_url>\nExample: $(basename "$0") --force-create-run my-web-app https://github.com/myuser/my-web-app.git"
        fi
    else # Default setup mode
        if [ -z "$repo_name" ] || [ -z "$github_url" ]; then
            log_error "Usage for default setup: $(basename "$0") <repository_name> <github_url>\nExample: $(basename "$0") my-web-app https://github.com/myuser/my-web-app.git"
        fi
    fi

    log_info "Starting project setup/removal script (Version: $SCRIPT_VERSION)..."

    check_system_dependencies

    local project_dir="$(clean_path "$TOOLS_BASE_DIR/$repo_name")"
    local venv_dir="$(clean_path "$project_dir/.venv")"
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
        unset GITHUB_TOKEN # Ensure no token is passed from environment unless explicitly desired
        unset GIT_SSH_COMMAND # Clear SSH command if set
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
        # Apply permissions to executable files only
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

    # --- Start of run.sh handling logic ---
    local target_bin_executable="$(clean_path "$TOOLS_BIN_DIR/$repo_name")"
    local project_run_script_path="$(clean_path "$project_dir/run.sh")"
    local project_main_py_path="$(clean_path "$project_dir/main.py")" # Path to main.py within the cloned project

    log_info "Ensuring target bin directory '$TOOLS_BIN_DIR' exists..."
    if [ ! -d "$TOOLS_BIN_DIR" ]; then
        mkdir -p "$TOOLS_BIN_DIR" || log_error "Failed to create target bin directory '$TOOLS_BIN_DIR'. Please check permissions."
        log_info "Target bin directory '$TOOLS_BIN_DIR' created."
    else
        log_info "Target bin directory '$TOOLS_BIN_DIR' already exists."
    fi

    # Remove any existing executable/symlink at the target bin path to prevent conflicts
    if [ -f "$target_bin_executable" ] || [ -L "$target_bin_executable" ]; then
        log_warn "Existing file or symlink found at '$target_bin_executable'. Removing it before creating a new one."
        rm -f "$target_bin_executable" || log_error "Failed to remove existing file/symlink at '$target_bin_executable'. Please check permissions."
    fi

    # Determine whether to symlink an existing run.sh or generate a new wrapper
    if [ -f "$project_run_script_path" ] && [ "$FORCE_CREATE_RUN_MODE" != true ]; then
        # Scenario 1: project_dir/run.sh found AND --force-create-run is NOT active
        log_info "'run.sh' found in project directory ('$project_run_script_path'). Making it executable and creating a symbolic link."
        chmod +x "$project_run_script_path" || log_error "Failed to make '$project_run_script_path' executable. Exiting."

        log_info "Creating symlink from '$project_run_script_path' to '$target_bin_executable'..."
        ln -s "$project_run_script_path" "$target_bin_executable"
        if [ $? -ne 0 ]; then
            log_error "Failed to create symbolic link for '$repo_name' at '$target_bin_executable'. This might require sudo privileges. Exiting."
        fi
        log_info "Symbolic link for '$repo_name' created successfully at '$target_bin_executable' pointing to '$project_run_script_path'."
    else
        # Scenario 2: project_dir/run.sh NOT found OR --force-create-run IS active
        if [ "$FORCE_CREATE_RUN_MODE" = true ]; then
            log_info "Force-creating default Python wrapper script at '$target_bin_executable' (ignoring existing project 'run.sh' if any)."
        else
            log_warn "No 'run.sh' found in project directory ('$project_run_script_path'). Generating default Python wrapper script directly at '$target_bin_executable'."
        fi

        # Generate the wrapper script content. Only error messages are included.
        cat <<EOF > "$target_bin_executable"
#!/bin/bash
# This script was automatically generated by the project setup script (Version: $SCRIPT_VERSION).
# It acts as a wrapper to run the main Python application within its virtual environment.

# The actual project directory where the repository was cloned
PROJECT_ROOT="${project_dir}"
VENV_DIR="\${PROJECT_ROOT}/.venv"
MAIN_PYTHON_SCRIPT="\${PROJECT_ROOT}/main.py"
ACTIVATE_SCRIPT="\${VENV_DIR}/bin/activate"

# Basic checks
if [ ! -d "\$PROJECT_ROOT" ]; then
    echo "ERROR: Project directory '\$PROJECT_ROOT' not found or accessible." >&2
    exit 1
fi

if [ ! -f "\$MAIN_PYTHON_SCRIPT" ]; then
    echo "ERROR: Main Python script '\$MAIN_PYTHON_SCRIPT' not found in project directory." >&2
    echo "Please ensure 'main.py' exists in '\$PROJECT_ROOT' or adjust the generated script." >&2
    exit 1
fi

if [ ! -f "\$ACTIVATE_SCRIPT" ]; then
    echo "ERROR: Virtual environment activation script not found at '\$ACTIVATE_SCRIPT'." >&2
    echo "Please ensure the virtual environment is correctly set up in '\$VENV_DIR'." >&2
    exit 1
fi

# Activate the virtual environment
source "\$ACTIVATE_SCRIPT"
if [ \$? -ne 0 ]; then
    echo "ERROR: Failed to activate virtual environment at '\$ACTIVATE_SCRIPT'." >&2
    exit 1
fi

# Execute the main Python script with all passed arguments
python "\$MAIN_PYTHON_SCRIPT" "\$@"
RUN_STATUS=\$?

# Deactivate the virtual environment if the function exists
if declare -f deactivate &>/dev/null; then
    deactivate
fi

exit \$RUN_STATUS
EOF
        if [ $? -ne 0 ]; then
            log_error "Failed to create wrapper script at '$target_bin_executable'. Please check permissions. Exiting."
        fi

        chmod +x "$target_bin_executable"
        if [ $? -ne 0 ]; then
            log_error "Failed to make wrapper script '$target_bin_executable' executable. Exiting."
        fi
        log_info "Wrapper script for '$repo_name' created successfully at '$target_bin_executable'."
    fi
    # --- End of run.sh handling logic ---

    log_info "Project setup for '$repo_name' completed successfully!"
}

setup_python_project "$@"
