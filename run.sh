#!/bin/bash

# git-repo-py: Automates setup, update, and removal of Python projects from Git repositories.
#
# Key Features:
# - Clones repositories and sets up Python virtual environments.
# - Manages project dependencies via 'requirements.txt' or custom 'build.sh'.
# - Creates executable wrappers/symlinks in a designated bin directory for easy access.
# - Supports updating existing projects with Git pull and stash management.
# - Allows easy removal of projects and their associated executables.
# - Lists all managed projects.
# - Allows specifying a Python version for virtual environment creation.
# - Provides a 'reinstall' option to cleanly remove and re-setup a project.
# - Configurable base and binary directories, defaulting to user's local directories.
# - Notifies user if the binary directory isn't in their PATH.
#
# Usage:
#   To see all options: ./git-repo-py --help
#
#   1. Setup (default):
#      ./git-repo-py <repository_name> <github_url> [-b | -branch <branch_name>] [-pv | --python-version <python_executable>]
#      Example: ./git-repo-py my-web-app https://github.com/myuser/my-web-app.git -b develop -pv python3.9
#
#   2. Remove:
#      ./git-repo-py --remove <repository_name>
#      Example: ./git-repo-py --remove my-web-app
#
#   3. Update:
#      ./git-repo-py --update <repository_name>
#      Example: ./git-repo-py --update my-web-app
#
#   4. Reinstall:
#      ./git-repo-py --reinstall <repository_name> <github_url> [-b | -branch <branch_name>] [-pv | --python-version <python_executable>]
#      Example: ./git-repo-py --reinstall my-web-app https://github.com/myuser/my-web-app.git -pv python3.10
#
#   5. Force Create Run Script:
#      (Always generates a default Python wrapper, even if project has 'run.sh')
#      ./git-repo-py --force-create-run <repo_name> <url> [-b | -branch <branch_name>] [-pv | --python-version <python_executable>]
#      Example: ./git-repo-py --force-create-run my-app https://github.com/user/my-app.git -pv python3.10
#
#   6. List Projects:
#      ./git-repo-py --list
#      Example: ./git-repo-py --list
#
# Configurable Paths:
#   TOOLS_BASE_DIR: Default for project clones (default: $HOME/.local/share/tools)
#   TOOLS_BIN_DIR: Default for executables (default: $HOME/.local/bin)
#   Override via environment variables:
#   Example: TOOLS_BASE_DIR="/opt/my_projects" ./git-repo-py my-app ...

# Enable strict mode:
# -e: Exit immediately if a command exits with a non-zero status.
# -u: Treat unset variables as an error when substituting.
# -o pipefail: The return value of a pipeline is the status of the last command to exit with a non-zero status,
#              or zero if all commands in the pipeline exit successfully.
set -euo pipefail

SCRIPT_VERSION="1.18.0"

# Default paths: Use environment variable if set, otherwise default to user's local directories.
TOOLS_BASE_DIR="${TOOLS_BASE_DIR:-$HOME/.local/share/tools}"
TOOLS_BIN_DIR="${TOOLS_BIN_DIR:-$HOME/.local/bin}"

# --- Logging Functions ---
log_info() {
    echo "[INFO] $(date +'%Y-%m-%d %H:%M:%S') $1"
}

log_warn() {
    echo "[WARN] $(date +'%Y-%m-%d %H:%M:%S') $1" >&2
}

log_error() {
    echo "[ERROR] $(date +'%Y-%m-%d %H:%M:%S') $1" >&2
    exit 1
}

# --- Utility Functions ---

# Cleans paths by resolving double slashes.
clean_path() {
    echo "$1" | sed 's/\/\//\//g'
}

# Checks for essential system commands.
# Now checks for a specific Python version if provided.
check_system_dependencies() {
    log_info "Checking for required system tools..."
    local missing_tools=()
    local tools=("git" "find" "chmod" "ln" "rm" "pwd") # Removed python3 from here, checked separately

    # Check for the specific Python executable if provided, otherwise default to python3
    local python_exec_to_check="${PYTHON_VERSION:-python3}"
    if ! command -v "$python_exec_to_check" &> /dev/null; then
        missing_tools+=("$python_exec_to_check")
    else
        log_info "Using Python executable: $(command -v "$python_exec_to_check")"
    fi

    # Warn if 'readlink' is missing, but it's not critical.
    if ! command -v readlink &> /dev/null; then
        log_warn "Command 'readlink' not found. Script will rely on 'pwd -P' for symlink resolution in generated wrappers."
    fi

    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done

    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "Missing required system tools: ${missing_tools[*]}. Please install them (e.g., 'python3-venv' for venv on Debian/Ubuntu, or ensure '$python_exec_to_check' is in PATH)."
    fi
    log_info "All required system tools found."
}

# Informs the user if TOOLS_BIN_DIR is not in their PATH and provides instructions.
add_tools_bin_to_path_if_needed() {
    local bin_dir_to_check="$(clean_path "$TOOLS_BIN_DIR")"
    log_info "Checking if '$bin_dir_to_check' is in your system PATH..."

    if [[ ":$PATH:" == *":$bin_dir_to_check:"* ]]; then
        log_info "'$bin_dir_to_check' is already in your PATH."
    else
        log_warn "'$bin_dir_to_check' is NOT currently in your PATH."
        echo "-----------------------------------------------------------------------"
        echo "  To run the project's executable (e.g., '$REPO_NAME') from any location,"
        echo "  you need to add '$bin_dir_to_check' to your system's PATH."
        echo "  Temporarily for this session:"
        echo "    export PATH=\"\$PATH:$bin_dir_to_check\""
        echo ""
        echo "  Permanently (add to ~/.bashrc, ~/.zshrc, or ~/.profile):"
        echo "    export PATH=\"\$PATH:$bin_dir_to_check\""
        echo "  Then, source the file (e.g., 'source ~/.bashrc') or open a new terminal."
        echo "-----------------------------------------------------------------------"
    fi
}

# --- Main Operation Functions ---

# Displays the script's help message.
display_help() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] <repository_name> [github_url]

This script automates the setup, removal, and updating of Python projects from Git repositories.

Options:
  -r, --remove <repository_name>          : Deletes the symbolic link and the project directory.
                                            Example: $(basename "$0") --remove my-web-app

  -u, --update <repository_name>          : Cleans cache, stashes changes, pulls latest, pops stash.
                                            Example: $(basename "$0") --update my-web-app

  -re, --reinstall <repo_name> <url> [-b <branch>] [-pv <python_executable>]
                                          : Removes and then re-sets up the project.
                                            Requires repository name and GitHub URL.
                                            Example: $(basename "$0") --reinstall my-app https://github.com/user/my-app.git -pv python3.10

  -b, --branch <branch_name>              : Specifies the Git branch to clone (used with setup/reinstall modes).
                                            Example: ... <github_url> -b develop

  -pv, --python-version <python_executable> : Specifies the Python executable to use for the virtual environment.
                                            Example: -pv python3.9 or -pv /usr/bin/python3.10
                                            Defaults to 'python3' if not specified.

  -fcr, --force-create-run <repo_name> <url> : Always generates the default Python wrapper in \${TOOLS_BIN_DIR},
                                            overriding project's 'run.sh'.
                                            Example: $(basename "$0") --force-create-run my-app https://github.com/user/my-app.git

  -l, --list                              : Lists all projects managed by git-repo-py.
                                            Example: $(basename "$0") --list

  -h, --help                            : Displays this help message and exits.

Default Setup Mode (no specific option):
  $(basename "$0") <repository_name> <github_url> [-b <branch>] [-pv <python_executable>]
  Clones repo, creates venv, installs dependencies. Symlinks project's 'run.sh' or generates
  a default Python wrapper in \${TOOLS_BIN_DIR}.
  Example: $(basename "$0") my-web-app https://github.com/myuser/my-web-app.git -pv python3.9

Configurable Paths:
  Project Base Directory: '\${TOOLS_BASE_DIR}' (default: $HOME/.local/share/tools)
  Executable Bin Directory: '\${TOOLS_BIN_DIR}' (default: $HOME/.local/bin)
  Override by setting environment variables TOOLS_BASE_DIR or TOOLS_BIN_DIR before running.

Version: $SCRIPT_VERSION
EOF
    exit 0
}

# Internal function to clean up project files and symlinks.
# Does NOT exit the script.
_cleanup_project_files() {
    local repo_name="$1"
    local project_dir="$(clean_path "$TOOLS_BASE_DIR/$repo_name")"
    local symlink_dest="$(clean_path "$TOOLS_BIN_DIR/$repo_name")"

    log_info "Attempting to clean up files for '$repo_name'..."

    # Remove the symlink or generated executable.
    if [ -L "$symlink_dest" ] || [ -f "$symlink_dest" ]; then
        log_info "Removing executable/symlink: '$symlink_dest'..."
        rm -f "$symlink_dest" || log_warn "Failed to remove '$symlink_dest'. Manual removal may be required."
    else
        log_warn "Executable/symlink '$symlink_dest' not found. Skipping."
    fi

    # Remove the project directory with safety check.
    if [ -d "$project_dir" ]; then
        log_info "Removing project directory: '$project_dir'..."
        # Prevent accidental deletion of critical system paths.
        if [ -n "$project_dir" ] && [ "$project_dir" != "/" ] && \
           [[ "$project_dir" == "$(clean_path "$TOOLS_BASE_DIR")"* ]]; then
            rm -rf "$project_dir" || log_warn "Failed to remove '$project_dir'. Check permissions. Manual removal may be required."
            log_info "Project directory '$project_dir' removed."
        else
            log_warn "Refusing to remove potentially dangerous path: '$project_dir'. Manual removal may be required."
        fi
    else
        log_warn "Project directory '$project_dir' not found. Skipping."
    fi
}


# Removes a project and its associated executable.
undo_project_setup() {
    local repo_name="$1"

    log_info "Initiating removal for '$repo_name'..."

    echo "WARNING: This will permanently delete the project files and executable link for '$repo_name'."
    read -p "Are you absolutely sure you want to proceed? (type 'yes' to confirm): " confirmation
    if [[ ! "$confirmation" =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Removal cancelled by user."
        exit 0
    fi

    _cleanup_project_files "$repo_name"
    log_info "Removal for '$repo_name' completed."
    exit 0
}

# Updates an existing project by cleaning cache, stashing changes, pulling, and popping stash.
update_project() {
    local repo_name="$1"
    local project_dir="$(clean_path "$TOOLS_BASE_DIR/$repo_name")"
    local stash_pushed=false

    log_info "Initiating update for '$repo_name'..."

    if [ ! -d "$project_dir" ]; then
        log_error "Project directory '$project_dir' does not exist. Cannot update."
    fi
    if [ ! -d "$project_dir/.git" ]; then
        log_error "Project directory '$project_dir' is not a Git repository. Cannot update."
    fi

    (
        cd "$project_dir" || log_error "Failed to change directory to '$project_dir'."

        log_info "Cleaning '__pycache__' directories..."
        # Using -prune to avoid descending into removed directories.
        find . -type d -name "__pycache__" -prune -exec rm -rf {} + || log_warn "Some '__pycache__' directories could not be removed."; true # 'true' to prevent 'set -e' from exiting on non-zero from find/rm if some files are unremovable

        log_info "Checking for local changes..."
        if ! git diff --quiet --exit-code || ! git diff --cached --quiet --exit-code || test -n "$(git ls-files --others --exclude-standard)"; then
            log_info "Local changes detected. Stashing..."
            git stash push -u -m "git-repo-py update: temporary stash for $repo_name"
            # Check if stash actually created an entry.
            # Using 'grep -q' to suppress output and just check exit status.
            if git stash list | grep -q "git-repo-py update: temporary stash for $repo_name"; then
                stash_pushed=true
            else
                log_warn "Failed to stash changes or no changes to stash. Pull may have issues."
            fi
        else
            log_info "No local changes detected."
        fi

        log_info "Pulling latest changes..."
        git pull || log_error "Git pull failed. Manual resolution may be required."

        if "$stash_pushed"; then
            log_info "Attempting to pop stashed changes..."
            git stash pop || log_warn "Failed to pop stashed changes. Manual resolution may be required."
        fi
    ) # Subshell ends here to contain directory changes.

    log_info "Update for '$repo_name' completed."
    exit 0
}

# Sets up a Python project: clones, creates venv, installs deps, and creates executable.
setup_python_project() {
    local repo_name="$1"
    local github_url="$2"
    local force_create_run_mode="$3" # 'true' or 'false'
    local branch_name="$4"
    local py_version_exec="$5" # The Python executable to use (e.g., python3.9, /usr/bin/python3.8)

    local project_dir="$(clean_path "$TOOLS_BASE_DIR/$repo_name")"
    local venv_dir="$(clean_path "$project_dir/.venv")"
    local requirements_file="$(clean_path "$project_dir/requirements.txt")"
    local build_script="$(clean_path "$project_dir/build.sh")"
    local target_bin_executable="$(clean_path "$TOOLS_BIN_DIR/$repo_name")"
    local project_run_script_path="$(clean_path "$project_dir/run.sh")"
    local project_main_py_path="$(clean_path "$project_dir/main.py")"

    log_info "Ensuring base directory '$TOOLS_BASE_DIR' exists..."
    mkdir -p "$TOOLS_BASE_DIR" || log_error "Failed to create '$TOOLS_BASE_DIR'. Check permissions."
    log_info "Base directory '$TOOLS_BASE_DIR' ensured."

    log_info "Handling repository '$repo_name' at '$project_dir'..."
    if [ -d "$project_dir" ]; then
        log_warn "Repository '$repo_name' already exists. Skipping clone."
    else
        log_info "Cloning '$github_url' to '$project_dir'${branch_name:+ (branch '$branch_name')}"
        
        # Build the git clone command as an array for safer execution
        local git_clone_cmd=("git" "clone")
        if [ -n "$branch_name" ]; then
            git_clone_cmd+=("--branch" "$branch_name")
        fi
        git_clone_cmd+=("$github_url" "$project_dir")

        # Execute git clone with a clean environment, bypassing problematic 'eval'
        # Using 'env -i' to ensure a clean environment for git clone.
        # Preserve HOME to allow git to find user's .ssh directory for authentication.
        env -i HOME="$HOME" GIT_ASKPASS="" GIT_TERMINAL_PROMPT=0 "${git_clone_cmd[@]}" \
            || log_error "Failed to clone repository. Check URL/branch/network."
        log_info "Repository cloned successfully."
    fi

    log_info "Setting up virtual environment for '$repo_name' at '$venv_dir' using '$py_version_exec'..."
    if [ -d "$venv_dir" ]; then
        log_warn "Virtual environment already exists. Skipping creation."
    else
        # Use the specified Python executable for venv creation
        "$py_version_exec" -m venv "$venv_dir" || log_error "Failed to create venv using '$py_version_exec'. Ensure '$py_version_exec' is installed and 'python3-venv' (or equivalent) is available for it."
        log_info "Virtual environment created."
    fi
    # Make venv executables group-executable for broader access if needed.
    # Added 'true' to the end to prevent 'set -e' from exiting if chmod fails on some files.
    find "$venv_dir/bin" -type f -exec chmod g+x {} + || log_warn "Failed to set venv bin permissions."; true

    # Install dependencies or run build script.
    if [ -f "$build_script" ]; then
        log_info "Found '$build_script'. Running build script..."
        chmod +x "$build_script" || log_error "Failed to make '$build_script' executable."
        (cd "$project_dir" && "$build_script") || log_error "Build script '$build_script' failed."
        log_info "Build script executed."
    elif [ -f "$requirements_file" ]; then
        log_info "No 'build.sh' found. Installing dependencies from '$requirements_file'..."
        # Activate venv, install, then deactivate.
        # The 'source' command needs to be in the same shell context, so we use a subshell.
        (
            source "$(clean_path "$venv_dir/bin/activate")" \
                || log_error "Failed to activate venv. Activation script missing?"
            pip install -r "$requirements_file" --no-input --disable-pip-version-check \
                || log_error "Failed to install dependencies. Check '$requirements_file'."
        )
        log_info "Dependencies installed."
    else
        log_warn "Neither 'build.sh' nor 'requirements.txt' found. Skipping dependency step."
    fi

    # Ensure binary directory exists.
    log_info "Ensuring target bin directory '$TOOLS_BIN_DIR' exists..."
    mkdir -p "$TOOLS_BIN_DIR" || log_error "Failed to create '$TOOLS_BIN_DIR'. Check permissions."
    log_info "Target bin directory '$TOOLS_BIN_DIR' ensured."

    # Remove old executable/symlink if it exists to prevent conflicts.
    if [ -f "$target_bin_executable" ] || [ -L "$target_bin_executable" ]; then
        log_warn "Existing executable/symlink at '$target_bin_executable' found. Removing."
        rm -f "$target_bin_executable" || log_error "Failed to remove existing '$target_bin_executable'. Check permissions."
    fi

    # Create the executable wrapper or symlink.
    if [ -f "$project_run_script_path" ] && [ "$force_create_run_mode" != true ]; then
        # Project has its own 'run.sh', and we're not forcing a new one.
        log_info "Found 'run.sh' in project. Creating symlink to '$target_bin_executable'."
        chmod +x "$project_run_script_path" || log_error "Failed to make '$project_run_script_path' executable."
        ln -s "$project_run_script_path" "$target_bin_executable" || log_error "Failed to create symlink. Permissions?"
        log_info "Symlink to '$repo_name' created at '$target_bin_executable'."
    else
        # No project 'run.sh' or force creation is active, generate a wrapper.
        if [ "$force_create_run_mode" = true ]; then
            log_info "Force-creating default Python wrapper at '$target_bin_executable'."
        else
            log_warn "No 'run.sh' found in project. Generating default Python wrapper at '$target_bin_executable'."
        fi

        # Generate the Python wrapper script.
        cat <<EOF > "$target_bin_executable"
#!/bin/bash
# Automatically generated by git-repo-py (Version: $SCRIPT_VERSION).
# Runs the main Python application within its virtual environment.

# Use 'readlink -f' if available, otherwise fall back to 'pwd -P' for robust path resolution.
# This ensures the script can be called from anywhere and correctly locate its project root.
SCRIPT_PATH="\$( cd "\$( dirname "\${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
if command -v readlink &> /dev/null; then
    PROJECT_ROOT="\$(readlink -f "\${SCRIPT_PATH}/../share/tools/$repo_name")"
else
    # Fallback for systems without readlink -f, assumes standard install path
    PROJECT_ROOT="${project_dir}"
fi

VENV_DIR="\${PROJECT_ROOT}/.venv"
MAIN_PYTHON_SCRIPT="\${PROJECT_ROOT}/main.py"
ACTIVATE_SCRIPT="\${VENV_DIR}/bin/activate"

# Verify essential files/directories exist.
if [ ! -d "\$PROJECT_ROOT" ]; then echo "ERROR: Project directory '\$PROJECT_ROOT' not found." >&2; exit 1; fi
if [ ! -f "\$MAIN_PYTHON_SCRIPT" ]; then echo "ERROR: Main Python script '\$MAIN_PYTHON_SCRIPT' not found." >&2; exit 1; fi
if [ ! -f "\$ACTIVATE_SCRIPT" ]; then echo "ERROR: Virtual environment activation script not found." >&2; exit 1; fi

# Activate venv, run main.py, then deactivate.
# The 'source' command needs to be in the same shell context.
(
    source "\$ACTIVATE_SCRIPT" || { echo "ERROR: Failed to activate virtual environment." >&2; exit 1; }
    python "\$MAIN_PYTHON_SCRIPT" "\$@"
    RUN_STATUS=\$?
    exit \$RUN_STATUS # Exit subshell with the status of the python command
)
# The status of the subshell is propagated to the main script.
exit \$?
EOF
        chmod +x "$target_bin_executable" || log_error "Failed to make wrapper script executable."
        log_info "Wrapper script for '$repo_name' created at '$target_bin_executable'."
    fi

    log_info "Project setup for '$repo_name' completed successfully!"
    add_tools_bin_to_path_if_needed # Remind user about PATH.
}

# Reinstalls a project: removes existing installation and then performs a fresh setup.
reinstall_project() {
    local repo_name="$1"
    local github_url="$2"
    local force_create_run_mode="$3" # 'true' or 'false'
    local branch_name="$4"
    local py_version_exec="$5"

    log_info "Initiating reinstall for '$repo_name'..."

    echo "WARNING: This will remove and then re-setup '$repo_name'. All local changes will be lost unless committed to Git."
    read -p "Are you absolutely sure you want to proceed? (type 'yes' to confirm): " confirmation
    if [[ ! "$confirmation" =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Reinstallation cancelled by user."
        exit 0
    fi

    _cleanup_project_files "$repo_name"
    log_info "Previous installation of '$repo_name' cleaned up. Proceeding with fresh setup."

    # Now call the setup function with all necessary arguments
    setup_python_project "$repo_name" "$github_url" "$force_create_run_mode" "$branch_name" "$py_version_exec"
    log_info "Reinstallation for '$repo_name' completed successfully!"
    exit 0
}


# Lists all projects managed by git-repo-py.
list_projects() {
    log_info "Listing projects managed by git-repo-py in '$TOOLS_BASE_DIR'..."
    if [ ! -d "$TOOLS_BASE_DIR" ]; then
        log_warn "Base directory '$TOOLS_BASE_DIR' does not exist. No projects found."
        exit 0
    fi

    local project_count=0
    echo "-----------------------------------------------------------------------"
    echo "Managed Projects:"
    echo "-----------------------------------------------------------------------"
    # Find directories that look like Git repositories
    for project_path in "$TOOLS_BASE_DIR"/*/; do
        # Check if it's a directory and contains a .git folder
        if [ -d "$project_path" ] && [ -d "$project_path/.git" ]; then
            local repo_name="$(basename "$project_path")"
            local venv_status="N/A"
            local symlink_status="N/A"
            local run_script_status="N/A"
            local main_py_status="N/A"

            # Check venv status
            if [ -d "$(clean_path "$project_path/.venv")" ]; then
                venv_status="OK"
            else
                venv_status="MISSING"
            fi

            # Check symlink/executable status
            local target_bin_executable="$(clean_path "$TOOLS_BIN_DIR/$repo_name")"
            if [ -L "$target_bin_executable" ]; then
                symlink_status="SYMLINK -> $(readlink -f "$target_bin_executable" || echo "Broken")"
            elif [ -f "$target_bin_executable" ]; then
                symlink_status="EXECUTABLE"
            else
                symlink_status="MISSING"
            fi

            # Check for project's run.sh
            if [ -f "$(clean_path "$project_path/run.sh")" ]; then
                run_script_status="FOUND"
            else
                run_script_status="NOT FOUND"
            fi

            # Check for project's main.py
            if [ -f "$(clean_path "$project_path/main.py")" ]; then
                main_py_status="FOUND"
            else
                main_py_status="NOT FOUND"
            fi

            echo "  - $repo_name"
            echo "    Path: $project_path"
            echo "    Venv: $venv_status"
            echo "    Executable: $symlink_status"
            echo "    Project run.sh: $run_script_status"
            echo "    Project main.py: $main_py_status"
            echo "-----------------------------------------------------------------------"
            project_count=$((project_count + 1))
        fi
    done

    if [ "$project_count" -eq 0 ]; then
        echo "No managed projects found."
        echo "-----------------------------------------------------------------------"
    else
        echo "Total projects found: $project_count"
        echo "-----------------------------------------------------------------------"
    fi
    exit 0
}

# --- Main Script Execution ---

# Global variables for parsed arguments, initialized empty.
REPO_NAME=""
GITHUB_URL=""
CLONE_BRANCH=""
PYTHON_VERSION="python3" # Default Python version

# Flags for different script modes.
MODE_REMOVE=false
MODE_FORCE_CREATE_RUN=false
MODE_UPDATE=false
MODE_LIST=false
MODE_REINSTALL=false # New mode for reinstalling projects
MODE_HELP=false

# Parse command-line arguments using a more robust loop.
while (( "$#" )); do
    case "$1" in
        --remove|-r)
            MODE_REMOVE=true
            shift
            if [ -z "${1:-}" ]; then log_error "Option '$1' requires a repository name argument."; fi
            REPO_NAME="$1"
            shift
            ;;
        --update|-u)
            MODE_UPDATE=true
            shift
            if [ -z "${1:-}" ]; then log_error "Option '$1' requires a repository name argument."; fi
            REPO_NAME="$1"
            shift
            ;;
        --reinstall|-re) # New argument for reinstalling projects
            MODE_REINSTALL=true
            shift
            if [ -z "${1:-}" ]; then log_error "Option '$1' requires a repository name argument."; fi
            REPO_NAME="$1"
            shift
            if [ -z "${1:-}" ]; then log_error "Option '$1' requires a GitHub URL argument."; fi
            GITHUB_URL="$1"
            shift
            ;;
        --force-create-run|-fcr)
            MODE_FORCE_CREATE_RUN=true
            shift
            if [ -z "${1:-}" ]; then log_error "Option '$1' requires a repository name argument."; fi
            REPO_NAME="$1"
            shift
            if [ -z "${1:-}" ]; then log_error "Option '$1' requires a GitHub URL argument."; fi
            GITHUB_URL="$1"
            shift
            ;;
        --branch|-b)
            shift
            if [ -z "${1:-}" ]; then log_error "Option '$1' requires a branch name argument."; fi
            CLONE_BRANCH="$1"
            shift
            ;;
        --python-version|-pv)
            shift
            if [ -z "${1:-}" ]; then log_error "Option '$1' requires a Python executable argument (e.g., python3.9)."; fi
            PYTHON_VERSION="$1"
            shift
            ;;
        --list|-l)
            MODE_LIST=true
            shift
            ;;
        --help|-h)
            MODE_HELP=true
            shift
            ;;
        -*)
            log_warn "Unknown option: $1. Ignoring."
            shift
            ;;
        *) # Positional arguments for default setup mode
            if [ -z "$REPO_NAME" ]; then
                REPO_NAME="$1"
            elif [ -z "$GITHUB_URL" ]; then
                GITHUB_URL="$1"
            else
                log_warn "Unexpected argument: $1. Ignoring."
            fi
            shift
            ;;
    esac
done

log_info "Starting git-repo-py (Version: $SCRIPT_VERSION)..."

# Perform initial system dependency check before any mode-specific execution.
check_system_dependencies

# Execute the appropriate function based on parsed arguments.
if "$MODE_HELP"; then
    display_help
elif "$MODE_REMOVE"; then
    [ -z "$REPO_NAME" ] && log_error "Usage for removal: $(basename "$0") --remove <repository_name>"
    undo_project_setup "$REPO_NAME"
elif "$MODE_UPDATE"; then
    [ -z "$REPO_NAME" ] && log_error "Usage for update: $(basename "$0") --update <repository_name>"
    update_project "$REPO_NAME"
elif "$MODE_REINSTALL"; then
    [ -z "$REPO_NAME" ] || [ -z "$GITHUB_URL" ] && log_error "Usage for reinstall: $(basename "$0") --reinstall <repository_name> <github_url> [-b <branch>] [-pv <python_executable>]\nSee --help for more details."
    reinstall_project "$REPO_NAME" "$GITHUB_URL" "$MODE_FORCE_CREATE_RUN" "$CLONE_BRANCH" "$PYTHON_VERSION"
elif "$MODE_LIST"; then
    list_projects
else # Default setup or --force-create-run mode.
    # Check for required arguments for setup modes.
    [ -z "$REPO_NAME" ] || [ -z "$GITHUB_URL" ] && log_error "Usage for setup: $(basename "$0") <repository_name> <github_url> [-b <branch>] [-pv <python_executable>]\nSee --help for more details."
    setup_python_project "$REPO_NAME" "$GITHUB_URL" "$MODE_FORCE_CREATE_RUN" "$CLONE_BRANCH" "$PYTHON_VERSION"
fi
