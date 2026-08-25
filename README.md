# PMAN — Project Manager

A lightweight Windows command-line project manager built entirely with **Batch (`.bat`)**.

PMAN provides a single terminal interface for common project-management tasks such as dependency installation, development, building, testing, linting, formatting, Git operations, cleanup, diagnostics, dependency management, project exploration, and more.

> **Platform:** Windows  
> **Interface:** CMD / PowerShell  
> **Main command:** `pman`  
> **Technology:** Windows Batch + built-in Windows utilities  
> **Primary focus:** Node.js, JavaScript/TypeScript, and general development projects

---

## What is PMAN?

PMAN is designed to reduce repetitive terminal work.

Instead of manually typing commands such as:

```bat
npm install
npm run dev
npm run build
npm test
git status
```

you can open a project directory and run:

```bat
pman
```

PMAN detects the project, detects the available package manager, and gives you a numbered menu for common operations.

---

# Installation

The recommended way to install PMAN is with the included installer.

The ZIP contains:

```text
pman.zip
├── pman.bat
├── install.bat
├── uninstall.bat
└── README.md
```

## 1. Install PMAN

Extract the ZIP file.

Then double-click:

```text
install.bat
```

The installer copies PMAN to:

```text
%LOCALAPPDATA%\PMAN
```

and adds that directory to your **User PATH**.

No administrator privileges are normally required.

---

## 2. Restart your terminal

After installation, **close the current CMD/PowerShell window and open a new one**.

This is important because the newly added PATH is loaded by new terminal processes.

---

## 3. Run PMAN

Open CMD or PowerShell in any project directory and type:

```bat
pman
```

For example:

```bat
cd C:\Projects\MyApp
pman
```

PMAN will operate on:

```text
C:\Projects\MyApp
```

The PMAN installation directory and the project directory are separate, so PMAN can be used from anywhere.

---

# Uninstallation

To remove PMAN, run:

```text
uninstall.bat
```

The uninstaller:

- Removes PMAN from `%LOCALAPPDATA%\PMAN`
- Removes the PMAN directory from the user's PATH
- Does not delete your projects
- Does not delete project files
- Does not remove Node.js, Git, Python, or other development tools

After uninstalling, close and reopen CMD/PowerShell.

---

# Direct Usage Without Installation

You can also run PMAN directly without installing it.

From the folder containing `pman.bat`:

```bat
pman.bat
```

This is useful for testing or portable usage.

However, the installer is recommended if you want to use:

```bat
pman
```

from any project directory.

---

# Main Menu

PMAN currently provides:

1. Install Dependencies
2. Run Project
3. Development Server
4. Build Project
5. Run Custom Script
6. Clean Project
7. Test
8. Lint
9. Format
10. Type Check
11. Project Status
12. Package Scripts
13. Package Updates
14. Environment Info
15. Project Diagnostics
16. Port Checker
17. Process Manager
18. Git Status
19. Git Manager
20. Dependency Manager
21. Auto Repair
22. Recent Projects
23. Project Explorer
24. Open Terminal
25. Open in VS Code
26. Project Configuration
27. Command History
28. Workspace Information
29. Deep Clean
30. Exit

---

# Project Detection

PMAN checks the current working directory and attempts to identify the project type.

Supported project types include:

- Node.js
- TypeScript
- Vite
- Next.js
- Nuxt
- Electron
- Python
- C/C++
- HTML/CSS/JavaScript

Examples:

### Node.js

Detected from:

```text
package.json
```

### TypeScript

Detected from:

```text
tsconfig.json
```

### Vite

Detected from:

```text
vite.config.js
vite.config.ts
vite.config.mjs
```

### Next.js

Detected from:

```text
next.config.js
next.config.mjs
next.config.ts
```

### Nuxt

Detected from:

```text
nuxt.config.js
nuxt.config.ts
```

### Electron

Detected from:

```text
electron-builder.yml
electron-builder.json
electron-builder.json5
```

### Python

Detected from:

```text
requirements.txt
pyproject.toml
setup.py
```

### C/C++

Detected from:

```text
CMakeLists.txt
```

### HTML/CSS/JavaScript

Detected when these files are present:

```text
index.html
style.css
script.js
```

---

# Package Manager Detection

For Node.js projects, PMAN detects the available package manager.

Supported package managers:

- npm
- pnpm
- yarn
- bun

Detection is based on project lock files and installed commands.

Examples:

```text
package-lock.json  → npm
pnpm-lock.yaml     → pnpm
yarn.lock          → yarn
bun.lock           → bun
bun.lockb          → bun
```

If no lock file identifies a package manager, PMAN falls back to npm when npm is available.

---

# Using PMAN

Open a project:

```bat
cd C:\Path\To\Project
```

Run:

```bat
pman
```

The main menu shows information such as:

```text
Project Type: Node.js
Package Manager: npm
Project Path: C:\Projects\MyApp
```

Then select an option from `1` to `30`.

---

# Important Behavior

PMAN uses the **current terminal directory as the project directory**.

For example:

```bat
cd C:\Projects\Website
pman
```

PMAN works with:

```text
C:\Projects\Website
```

If you run:

```bat
cd C:\Projects\AnotherApp
pman
```

PMAN automatically works with:

```text
C:\Projects\AnotherApp
```

This means you do not need to reinstall PMAN for every project.

---

# Features

## Install Dependencies

Installs dependencies using the detected package manager.

Examples:

```bat
npm install
pnpm install
yarn install
bun install
```

---

## Run Project

Looks for the project's `start` script and runs it with the detected package manager.

---

## Development Server

Looks for a `dev` script and launches it.

Examples:

```bat
npm run dev
pnpm dev
yarn dev
bun run dev
```

---

## Build

Runs the project's `build` script when available.

For TypeScript projects, PMAN can also fall back to:

```bat
npx tsc
```

when an appropriate build script is not available.

---

## Custom Scripts

PMAN can display package scripts and let you run a selected script.

Script names are validated before being used.

---

## Clean / Deep Clean

PMAN provides normal and deep project-cleaning operations.

Destructive directory deletion is handled through protected routines rather than unrestricted deletion.

---

## Testing / Linting / Formatting / Type Checking

PMAN provides dedicated actions for common development workflows:

```text
Test
Lint
Format
Type Check
```

---

## Git

PMAN detects whether the current directory is a Git repository and provides:

- Git Status
- Git Manager

---

## Dependency Management

PMAN provides dependency-related utilities for supported package-manager projects.

---

## Diagnostics

PMAN includes environment and project diagnostics to help identify common development problems.

---

## Port Checker

Useful for finding processes using development ports.

For example, when a development server reports:

```text
Port already in use
```

PMAN can help identify the process associated with the port.

---

## Process Manager

Provides process-related utilities directly from the PMAN menu.

---

## Project Explorer

Provides project exploration/navigation functionality without manually opening another tool.

---

## VS Code Integration

Option `25` can open the current project in Visual Studio Code when VS Code is installed and available from the command line.

---

## Recent Projects

PMAN keeps a limited list of recently used project directories.

This prevents the list from growing indefinitely.

---

## Command History

Commands executed through PMAN are recorded in the project's:

```text
.project-manager
```

directory.

---

# Logging

PMAN uses:

```text
.project-manager
```

inside the project directory.

Typical files include:

```text
.project-manager/
├── manager.log
├── command-history.log
└── recent-projects.log
```

### `manager.log`

Stores PMAN command/activity information.

### `command-history.log`

Stores commands executed through PMAN.

### `recent-projects.log`

Stores recently used project paths.

---

# Log Rotation

PMAN limits log growth.

The configured maximum log size is:

```text
1 MB
```

When the configured limit is exceeded, the log is rotated/truncated instead of growing indefinitely.

---

# Command Execution

PMAN uses a centralized command execution system.

Executed commands are:

1. Displayed in the terminal.
2. Written to the log.
3. Added to command history.
4. Executed.
5. Checked for an exit code.
6. Reported as successful or failed.

Example:

```text
[COMMAND] npm install
----------------------------------------------

[OK] Command completed successfully.
```

On failure:

```text
[ERROR] Command failed with exit code 1.
```

---

# Safety

PMAN includes several safeguards around command execution.

Input used in command lines is validated where appropriate.

This includes values such as:

- Script names
- Process names
- PIDs
- Ports
- Other command-related input

Unsafe shell metacharacters are rejected where the input is expected to be a restricted token.

---

# Protected Deletion

Cleanup operations use a protected directory-deletion routine.

The routine checks that the target:

- Exists
- Is not empty
- Is not the current directory
- Is not the parent directory
- Is not a drive root
- Resolves inside the current project directory

This is especially important for operations involving directories such as:

```text
node_modules
```

---

# Requirements

PMAN is designed for **Windows**.

Depending on the selected feature, PMAN may use tools installed on the system, including:

- Command Prompt
- PowerShell
- Node.js
- npm
- pnpm
- yarn
- bun
- Git
- Python
- TypeScript
- Visual Studio Code

You do not need every tool installed. PMAN detects and uses the tools relevant to the current project.

---

# Project Structure

After installation:

```text
%LOCALAPPDATA%\PMAN\
├── pman.bat
└── pman.cmd
```

`pman.cmd` is the command launcher registered through PATH.

When you type:

```bat
pman
```

Windows resolves the command to the PMAN installation directory and launches:

```text
pman.bat
```

The project working directory is preserved, so PMAN still operates on the folder from which you ran `pman`.

---

# Troubleshooting

## `pman` is not recognized

If you see:

```text
'pman' is not recognized as an internal or external command
```

first close CMD/PowerShell and open a new terminal.

Then try:

```bat
pman
```

If it still does not work, run:

```bat
where pman
```

You should see the PMAN command launcher.

You can also run the installer again:

```text
install.bat
```

---

## PMAN opens but detects the wrong project

Make sure you started PMAN from the correct project directory:

```bat
cd C:\Path\To\Project
pman
```

PMAN detects the project based on the current working directory.

---

## Node.js commands do not work

Check that Node.js and npm are installed:

```bat
node --version
npm --version
```

If either command is unavailable, install the required development tools before using the related PMAN features.

---

# License

Add your preferred license here before publishing the project publicly.

For example:

```text
MIT License
```

---

# Author

**Yasin**

PMAN is a lightweight personal developer utility designed to make everyday Windows project management faster and simpler.

---

# Summary

PMAN turns a collection of repetitive Windows development commands into one command-driven project manager.

Install once:

```bat
install.bat
```

Then use it anywhere:

```bat
pman
```

No separate installation is required for each project.

---

**PMAN — One command. One menu. Your project workflow.**
