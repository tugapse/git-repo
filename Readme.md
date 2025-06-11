
---

### **Overview**
This script automates Python project setup, virtual environment management, dependency installation, and project removal. It streamlines workflows for developers by handling repetitive tasks like cloning repositories, creating virtual environments, and generating executable scripts.

---

### **Key Features**
1. **Repository Cloning**  
   - Clones Git repositories into a user-defined base directory (default: `/usr/local/tools`).

2. **Virtual Environment Management**  
   - Automatically creates and manages Python virtual environments using `python3 venv`.

3. **Dependency Installation**  
   - Installs dependencies from `requirements.txt` or via a `build.sh` script (if present).

4. **Auto-Generated `run.sh`**  
   - Generates a shell script (`run.sh`) for Python projects, which activates the virtual environment and runs `main.py`.  
   - Creates symlinks in the user's `bin` directory (default: `$HOME/bin` or `/usr/local/bin`) for direct execution.

5. **Project Removal**  
   - Safely deletes project directories and symlinks after user confirmation.

---

### **Requirements**
- Ensure the following tools are installed and in your `PATH`:  
  `git`, `python3` (with `venv`), `find`, `chmod`, `ln`, `rm`, `pwd`.

---

### **Installation Steps**
1. **Clone the Script Repository**  
   ```bash
   git clone https://github.com/your-organization/your-project-setup-repo.git
   cd your-project-setup-repo
   ```
2. **Make the Script Executable**  
   ```bash
   chmod +x your_script_name.sh
   ```
3. **Optional: Add to PATH**  
   Place the script in a directory within your `PATH` or create a symlink for easy access.

---

### **Configuration**
- **Customize Directories** (via environment variables):  
  - `TOOLS_BASE_DIR`: Repository clone directory (default: `/usr/local/tools`).  
  - `TOOLS_BIN_DIR`: Symlink directory for executables (default: `/usr/local/bin` or `$HOME/bin`).

---

### **Usage Modes**
#### **1. Setup Mode (Default)**  
Clones the repo, sets up the environment, installs dependencies, and creates symlinks.  
**Syntax**:  
```bash
./your_script_name.sh <repository_name> <github_url>
```
**Example**:  
```bash
./your_script_name.sh my-project https://github.com/your-organization/my-project.git
```

#### **2. Build Python Run Script Mode**  
Generates a `run.sh` script for Python projects (activates venv and runs `main.py`).  
**Syntax**:  
```bash
./your_script_name.sh --build-python-run <repository_name> <github_url>
```
**Example**:  
```bash
./your_script_name.sh --build-python-run my-project https://github.com/your-organization/my-project.git
```

#### **3. Removal Mode**  
Deletes project directories and symlinks after confirmation.  
**Syntax**:  
```bash
./your_script_name.sh --remove <repository_name>
```
**Example**:  
```bash
./your_script_name.sh --remove my-project
```

---

### **Notes**
- **Symlink Path**: Ensure `$HOME/bin` is in your `PATH` for symlinks to work.  
- **Dependencies**: Projects must include `requirements.txt` or `build.sh` for dependency installation.  
- **Safety**: Removal mode requires user confirmation to prevent accidental deletion.  
- **Customization**: Adjust `TOOLS_BASE_DIR` and `TOOLS_BIN_DIR` via environment variables if needed.

---

### **Contributing**
- The script is open-source under the **MIT License**.  
- Contributions for improvements or bug fixes are welcome. Check the `LICENSE` file for details.

---

### **Example Workflow**
1. Clone the script repo and make it executable.  
2. Run the setup mode to initialize a project:  
   ```bash
   ./your_script_name.sh my-project https://github.com/your-organization/my-project.git
   ```  
3. Use the generated `run.sh` via the symlink (e.g., `my-project` command).  
4. Remove the project later with:  
   ```bash
   ./your_script_name.sh --remove my-project
   ```

---

This script is ideal for developers who want to standardize their Python project workflows while minimizing manual configuration.