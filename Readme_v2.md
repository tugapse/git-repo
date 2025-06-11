**Test Case 1: Setup Mode - Valid Inputs**

- **ID:** TC_SETUP_001  
- **Description:** Validate cloning, venv setup, dependency installation, and symlink creation for a valid repository.  
- **Preconditions:**  
  - Git installed and authenticated.  
  - Public test repo URL (e.g., https://github.com/your-org/test-repo.git).  
  - Environment variables `TOOLS_BASE_DIR` and `TOOLS_BIN_DIR` unset or correctly set.  
  - Writable directory at the target clone path (~/.repos/my-project).  
- **Test Steps:**  
  1. Run: `./setup_project.sh my-project https://github.com/your-org/test-repo.git`  
  2. Verify cloning to `/path/to/repos/my-project`.  
  3. Check venv creation in the project directory.  
  4. Confirm dependencies are installed from `requirements.txt` (if present).  
  5. Validate symlink creation in `~/bin` or `TOOLS_BIN_DIR/test-repo`.  
- **Expected Results:**  
  - Repository cloned successfully.  
  - Virtual environment created and activated for dependency installation.  
  - Dependencies listed in a lock file installed without errors.  
  - Symlink points to an executable `run.sh` (if generated).  

---

**Test Case 2: Non-Existent Git URL**

- **ID:** TC_SETUP_002  
- **Description:** Handle invalid repository URLs gracefully.  
- **Preconditions:** No network access or non-existent repo (`https://github.com/nonexistent/repo.git`).  
- **Test Steps:** Run `./setup_project.sh my-project https://github.com/nonexistent/repo.git`.  
- **Expected Results:** Script exits with an error message indicating cloning failure (e.g., "Could not clone repository").

---

**Test Case 3: Missing main.py in Repository**

- **ID:** TC_BUILD_001  
- **Description:** Verify behavior when `main.py` is absent during build-python-run mode.  
- **Preconditions:** Clone a repo without `main.py`.  
- **Test Steps:** Run `./setup_project.sh --build-python-run my-project https://github.com/your-org/non-mainpy-repo.git`.  
- **Expected Results:** run.sh script generates and links to `/path/to/repos/my-project/run.sh` with the correct command (`python /path/to/repos/my-project/bin/main.py`) ensuring execution.

---

**Test Case 4: Interactive Removal Mode**

- **ID:** TC_REMOVAL_001  
- **Description:** Confirm removal mode prompts user for deletion confirmation.  
- **Preconditions:** `~/.repos/my-project` exists with a symlink in `~/bin`.  
- **Test Steps:** Run `./setup_project.sh --remove my-project`.  
- **Expected Results:** Prompt "Are you sure? [y/N]" appears; upon 'y' input, the project directory and symlink are removed.

---

**Test Case 5: Missing TOOLS_BIN_DIR Variable**

- **ID:** TC_CONFIG_001  
- **Description:** Ensure default `TOOLS_BIN_DIR` is used when not set.  
- **Preconditions:** Unset or misconfigured `TOOLS_BIN_DIR`.  
- **Test Steps:** Run setup mode normally (`./setup_project.sh my-project https://github.com/your-org/default-bin-repo.git`).  
- **Expected Results:** Symlink created in `/usr/local/bin` (default) with name matching the repository.

---

**Test Case 6: Permission Denied for TOOLS_BASE_DIR**

- **ID:** TC_PERM_001  
- **Description:** Handle insufficient permissions to access `TOOLS_BASE_DIR`.  
- **Preconditions:** Restrict write access to `/path/to/repos` (e.g., via chmod).  
- **Test Steps:** Run `./setup_project.sh my-project https://github.com/your-org/test-repo.git`.  
- **Expected Results:** Script exits with "permission denied" error when attempting to clone.

---

**Test Case 7: Duplicate Repository Name**

- **ID:** TC_SETUP_003  
- **Description:** Check behavior when cloning a repository that already exists.  
- **Preconditions:** Create an empty directory named `my-project` in the target base directory.  
- **Test Steps:** Run `./setup_project.sh my-project https://github.com/your-org/test-repo.git`.  
- **Expected Results:** Warn "Directory already exists" and proceed without overwriting.

---

**Test Case 8: Removal Mode Without Confirmation**

- **ID:** TC_REMOVAL_002  
- **Description:** Test removal mode when confirmation is not provided (if the script has a `force` option).  
- **Preconditions:** Non-interactive environment (e.g., CI pipeline) with no user input.  
- **Test Steps:** Run `./setup_project.sh --remove my-project`.  
- **Expected Results:** Project and symlink are removed without prompting, if `--force` is implemented.

---

**Test Case 9: Build Script Overrides Requirements**

- **ID:** TC_BUILD_002  
- **Description:** Ensure build script execution takes precedence over requirements.txt.  
- **Preconditions:** Clone a repo with both `build.sh` and `requirements.txt`.  
- **Test Steps:** Run setup mode normally.  
- **Expected Results:** `build.sh` is executed for dependency installation, ignoring `requirements.txt`.

---

**Test Case 10: Symlink Creation Fails**

- **ID:** TC_SYMLINK_001  
- **Description:** Handle failure to create symlink (e.g., due to permission issues in TOOLS_BIN_DIR).  
- **Preconditions:** Restrict write access to `~/bin`.  
- **Test Steps:** Run setup mode normally.  
- **Expected Results:** Script exits with error message indicating "unable to create symbolic link".

---

**Test Case 11: Environment Variables Set Post-Script Installation**

- **ID:** TC_CONFIG_002  
- **Description:** Verify that unset environment variables during initial run take effect on subsequent executions.  
- **Preconditions:** Initial setup without setting `TOOLS_BASE_DIR` or `TOOLS_BIN_DIR`.  
- **Test Steps:** Run setup mode, then export and re-run with new env vars:  
  ```[93mbash
  ./setup_project.sh my-project https://github.com/your-org/test-repo.git
  export TOOLS_BASE_DIR="/new/path/repos"
  export TOOLS_BIN_DIR="/usr/local/bin/newbin"
  ./setup_project.sh --build-python-run test-repo-new "${TOOLS_BASE_DIR}" "${TOOLS_BIN_DIR}"
  ```[0m  
- **Expected Results:** Subsequent execution uses `/new/path/repos` for cloning and `/usr/local/bin/newbin` for symlinks.