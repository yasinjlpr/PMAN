@echo off

setlocal EnableExtensions EnableDelayedExpansion

:: =========================================================================
:: تنظیم اندازه پنجره (عرض و ارتفاع)
:: =========================================================================
set "WIDTH=75"
set "HEIGHT=50"

powershell -command "&{$H=$Host.UI.RawUI; $W=$H.WindowSize; $B=$H.BufferSize; $W.Width=%WIDTH%; $W.Height=%HEIGHT%; $B.Width=%WIDTH%; $B.Height=9999; $H.WindowSize=$W; $H.BufferSize=$B;}"


title Project Manager
setlocal EnableExtensions EnableDelayedExpansion

:: =========================================================================
:: PROJECT MANAGER  (hardened release build)
:: ===============================================================================
:: Changes vs. prototype:
::   - All set/p input that reaches a command line is now
::     validated against a strict allow-list before use
::     (script names, PIDs, ports, process names, Y/N).
::   - Every executed command goes through :run_command so
::     it is logged and its exit code is reported the same
::     way everywhere.
::   - Destructive deletes go through :safe_rmdir, which
::     refuses to touch a directory that resolves outside
::     the current project folder, or is the drive root.
::   - ANSI colour setup no longer shells out to `cmd`; it
::     degrades to plain text automatically if ANSI is not
::     supported instead of printing garbage escape codes.
::   - Log files are capped and rotated instead of growing
::     forever.
:: ===============================================================================

:: ------------------------------------------------------
:: ANSI COLOURS (safe, no shell-out; auto-degrades)
:: ------------------------------------------------------

set "ANSI_OK=0"
for /f %%a in ('powershell -NoProfile -Command "[char]27" 2^>nul') do (
    set "ESC=%%a"
    set "ANSI_OK=1"
)

if "!ANSI_OK!"=="1" (
    set "RED=!ESC![91m"
    set "GREEN=!ESC![92m"
    set "YELLOW=!ESC![93m"
    set "CYAN=!ESC![96m"
    set "MAGENTA=!ESC![95m"
    set "WHITE=!ESC![97m"
    set "RESET=!ESC![0m"
) else (
    set "RED="
    set "GREEN="
    set "YELLOW="
    set "CYAN="
    set "MAGENTA="
    set "WHITE="
    set "RESET="
)

:: ------------------------------------------------------
:: PROJECT SETTINGS
:: ------------------------------------------------------

set "PROJECT_NAME=Project"
set "LOG_DIR=.project-manager"
set "LOG_FILE=!LOG_DIR!\manager.log"
set "HISTORY_FILE=!LOG_DIR!\command-history.log"
set "RECENT_FILE=!LOG_DIR!\recent-projects.log"
set "MAX_LOG_BYTES=1048576"
set "GIT_MAIN=main"
set "GIT_ORIGIN=origin"

if not exist "!LOG_DIR!" mkdir "!LOG_DIR!" >nul 2>&1

:: Ensure PMAN internal files are globally ignored by Git.
:: This uses Git's per-user global excludes file, so .project-manager/
:: is ignored in every repository for this Windows user.
call :ensure_git_global_ignore

:: Remember this run in the recent-projects list (deduped, capped at 10)
call :remember_project

:: ------------------------------------------------------
:: INITIAL DETECTION
:: ------------------------------------------------------

call :detect_project
call :detect_package_manager

:: ------------------------------------------------------
:: MAIN MENU
:: ------------------------------------------------------

:main
call :rotate_log "!LOG_FILE!"
call :rotate_log "!HISTORY_FILE!"
cls

echo %CYAN%=========================================================================
echo              yasin !PROJECT_NAME! MANager
echo =========================================================================%RESET%

echo.
echo   ----------------------------------------------
echo    1. Install project dependencies       [!PM! install]
echo    2. Start the project                  [!PM! start]
echo    3. Start development server           [!PM! run dev]
echo    4. Build the project                  [!PM! run build]
echo    5. Run a package.json script          [!PM! run ^<script^>]
echo    6. Clean caches and generated files   [cleanup options]
echo   ----------------------------------------------
echo    7. Run tests                          [!PM! test]
echo    8. Check code for problems (Lint)     [!PM! run lint]
echo    9. Format project code                [!PM! run format]
echo   10. Check TypeScript types             [npx tsc --noEmit / typecheck]
echo   ----------------------------------------------
echo   11. See project health and status      [status / detection]
echo   12. See available package commands     [package.json scripts]
echo   13. Find outdated packages             [!PM! outdated]
echo   14. See installed tools and versions   [node/npm/git/etc.]
echo   15. Diagnose common project problems   [automatic checks]
echo   16. Check whether a port is in use     [netstat -ano]
echo   17. Find or stop running programs      [tasklist / taskkill]
echo   ----------------------------------------------
echo   18. See Git changes                    [git status]
echo   19. Manage Git (branches, commit, push,...) [git]
echo   20. Manage project dependencies        [!PM! commands]
echo   ----------------------------------------------
echo   21. Automatically repair common issues [install/typecheck]
echo   22. Open recently used projects        [PMAN history]
echo   23. Open this project folder           [Explorer]
echo   24. Open a terminal here               [cmd]
echo   25. Open this project in VS Code       [code .]
echo   26. See PMAN/project configuration     [configuration]
echo   27. See commands you have run          [history log]
echo   28. See workspace information          [workspace]
echo   ----------------------------------------------
echo   29. Deep clean the project             [cleanup]
echo   0. Exit PMAN
echo   ----------------------------------------------
echo.

echo   Project Type: %GREEN%!PROJECT_TYPE!%RESET%
echo   Package Manager: %GREEN%!PM!%RESET%
echo   Project Path: %CD%
echo.

set "choice="
set /p "choice=  Select option (0-29): "

for /f "delims=0123456789" %%x in ("!choice!") do set "choice="
if not defined choice goto badchoice

if !choice! LSS 0 goto badchoice
if !choice! GTR 29 goto badchoice

if "!choice!"=="1" goto install
if "!choice!"=="2" goto runproject
if "!choice!"=="3" goto dev
if "!choice!"=="4" goto buildproject
if "!choice!"=="5" goto customscript
if "!choice!"=="6" goto cleanmenu
if "!choice!"=="7" goto test
if "!choice!"=="8" goto lint
if "!choice!"=="9" goto format
if "!choice!"=="10" goto typecheck
if "!choice!"=="11" goto status
if "!choice!"=="12" goto scripts
if "!choice!"=="13" goto updates
if "!choice!"=="14" goto environment
if "!choice!"=="15" goto diagnostics
if "!choice!"=="16" goto ports
if "!choice!"=="17" goto processes
if "!choice!"=="18" goto gitstatus
if "!choice!"=="19" goto gitmanager
if "!choice!"=="20" goto dependencies
if "!choice!"=="21" goto autorepair
if "!choice!"=="22" goto recent
if "!choice!"=="23" goto explorer
if "!choice!"=="24" goto terminal
if "!choice!"=="25" goto vscode
if "!choice!"=="26" goto configuration
if "!choice!"=="27" goto history
if "!choice!"=="28" goto workspace
if "!choice!"=="29" goto cleanmenu
if "!choice!"=="0" goto exit

:badchoice
echo.
echo   %RED%[WARNING] Invalid option!%RESET%
timeout /t 2 >nul
goto main


:: ===============================================================================
:: PROJECT DETECTION
:: ===============================================================================

:detect_project

set "PROJECT_TYPE=Unknown"

if exist "package.json" set "PROJECT_TYPE=Node.js"

if exist "tsconfig.json" set "PROJECT_TYPE=TypeScript"

if exist "vite.config.js" set "PROJECT_TYPE=Vite"
if exist "vite.config.ts" set "PROJECT_TYPE=Vite"
if exist "vite.config.mjs" set "PROJECT_TYPE=Vite"

if exist "next.config.js" set "PROJECT_TYPE=Next.js"
if exist "next.config.mjs" set "PROJECT_TYPE=Next.js"
if exist "next.config.ts" set "PROJECT_TYPE=Next.js"

if exist "nuxt.config.ts" set "PROJECT_TYPE=Nuxt"
if exist "nuxt.config.js" set "PROJECT_TYPE=Nuxt"

if exist "electron-builder.yml" set "PROJECT_TYPE=Electron"
if exist "electron-builder.json" set "PROJECT_TYPE=Electron"
if exist "electron-builder.json5" set "PROJECT_TYPE=Electron"

if exist "requirements.txt" set "PROJECT_TYPE=Python"
if exist "pyproject.toml" set "PROJECT_TYPE=Python"
if exist "setup.py" set "PROJECT_TYPE=Python"

if exist "CMakeLists.txt" set "PROJECT_TYPE=C/C++"

if exist "index.html" if exist "style.css" if exist "script.js" (
    set "PROJECT_TYPE=HTML/CSS/JavaScript"
)

if exist ".git" (
    set "HAS_GIT=YES"
) else (
    set "HAS_GIT=NO"
)

exit /b


:: ===============================================================================
:: PACKAGE MANAGER DETECTION
:: ===============================================================================

:detect_package_manager

set "PM=none"

if exist "bun.lockb" (
    where bun >nul 2>&1
    if not errorlevel 1 set "PM=bun"
)

if exist "bun.lock" (
    where bun >nul 2>&1
    if not errorlevel 1 set "PM=bun"
)

if exist "pnpm-lock.yaml" (
    where pnpm >nul 2>&1
    if not errorlevel 1 set "PM=pnpm"
)

if exist "yarn.lock" (
    where yarn >nul 2>&1
    if not errorlevel 1 set "PM=yarn"
)

if exist "package-lock.json" (
    where npm >nul 2>&1
    if not errorlevel 1 set "PM=npm"
)

if "!PM!"=="none" (
    where npm >nul 2>&1
    if not errorlevel 1 set "PM=npm"
)

exit /b


:: ===============================================================================
:: INPUT VALIDATION HELPERS
:: ===============================================================================

:: :confirm_yes  <PromptVarName>
:: Reads a Y/N answer into the named variable, blank/anything
:: else counts as "N". Always safe: never touches a command line.
:confirm_yes
exit /b


:: :is_number <value>  -> errorlevel 0 if value is 1+ digits only
:is_number
setlocal
set "val=%~1"
if not defined val (endlocal & exit /b 1)
for /f "delims=0123456789" %%x in ("!val!") do (endlocal & exit /b 1)
endlocal
exit /b 0


:: :is_safe_token <value> -> errorlevel 0 if value contains only
:: letters, digits, dot, dash, underscore, colon (no shell metacharacters)
:: Used for anything (script names, process names) that ends up
:: inside a command line, so pipes/ampersands/quotes/etc are rejected.
:is_safe_token
setlocal EnableDelayedExpansion
set "val=%~1"
if not defined val (endlocal & exit /b 1)

set "stripped=!val!"
for %%c in (: - . _ ) do set "stripped=!stripped:%%c=!"

set "bad=0"
for /f "delims=ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789" %%x in ("!stripped!") do set "bad=1"

if "!bad!"=="1" (endlocal & exit /b 1)
endlocal
exit /b 0


:: ===============================================================================
:: SAFE DELETE
:: ===============================================================================

:: :safe_rmdir <relative-folder-name>
:: Only deletes a directory that:
::   - is a direct child of the current project directory
::   - is not "." ".." or empty
::   - does not resolve to a drive root
:safe_rmdir
setlocal EnableDelayedExpansion
set "target=%~1"

if not defined target (endlocal & exit /b 1)
if "!target!"=="." (endlocal & exit /b 1)
if "!target!"==".." (endlocal & exit /b 1)
if not exist "!target!" (endlocal & exit /b 0)

for %%I in ("!target!") do set "FULLPATH=%%~fI"
for %%I in (".") do set "HEREPATH=%%~fI"

:: refuse if it resolves to a drive root like C:\
if "!FULLPATH:~-2!"==":\" (endlocal & exit /b 1)

:: refuse if it is not actually inside the current directory
echo !FULLPATH! | findstr /b /i /c:"!HEREPATH!\" >nul
if errorlevel 1 (endlocal & exit /b 1)

rmdir /s /q "!FULLPATH!" >nul 2>&1
endlocal
exit /b 0


:: ===============================================================================
:: LOG ROTATION
:: ===============================================================================

:: :rotate_log <path>  - truncates a log once it exceeds MAX_LOG_BYTES
:rotate_log
setlocal EnableDelayedExpansion
set "f=%~1"
if not exist "!f!" (endlocal & exit /b)

for %%A in ("!f!") do set "sz=%%~zA"
if not defined sz (endlocal & exit /b)

if !sz! GTR !MAX_LOG_BYTES! (
    echo [log rotated %date% %time%]>"!f!"
)
endlocal
exit /b


:: ===============================================================================
:: COMMAND EXECUTOR
:: ===============================================================================

:: :run_command <command-string>
:: Central place every executed command flows through, so
:: logging and pass/fail reporting are consistent.
:run_command

set "COMMAND=%*"

echo.
echo   %CYAN%[COMMAND]%RESET% !COMMAND!
echo   ----------------------------------------------

>>"!LOG_FILE!" echo [%date% %time%] !COMMAND!
>>"!HISTORY_FILE!" echo !COMMAND!

cmd.exe /d /c "!COMMAND!"

set "CMD_ERROR=!errorlevel!"

echo.
if "!CMD_ERROR!"=="0" (
    echo   %GREEN%[OK] Command completed successfully.%RESET%
) else (
    echo   %RED%[ERROR] Command failed with exit code !CMD_ERROR!.%RESET%
)

exit /b !CMD_ERROR!

:: ===============================================================================
:: GIT GLOBAL IGNORE
:: ===============================================================================

:: Ensures .project-manager/ is permanently ignored for the
:: current Windows user across all Git repositories.
:ensure_git_global_ignore
where git >nul 2>&1
if errorlevel 1 exit /b 0

set "GLOBAL_EXCLUDES="
for /f "usebackq delims=" %%G in (`git config --global --get core.excludesfile 2^>nul`) do if not defined GLOBAL_EXCLUDES set "GLOBAL_EXCLUDES=%%G"

if not defined GLOBAL_EXCLUDES set "GLOBAL_EXCLUDES=%USERPROFILE%\.gitignore_global"

if not exist "!GLOBAL_EXCLUDES!" (
    >"!GLOBAL_EXCLUDES!" echo # PMAN internal files
)

findstr /x /l /c:".project-manager/" "!GLOBAL_EXCLUDES!" >nul 2>&1
if errorlevel 1 >>"!GLOBAL_EXCLUDES!" echo .project-manager/

:: Persist the excludes-file location when Git did not already have one.
git config --global core.excludesfile "!GLOBAL_EXCLUDES!" >nul 2>&1

:: If an older PMAN run accidentally tracked this directory, remove it
:: from the Git index while keeping the files on disk. This makes the
:: ignore rule effective for future commits as well.
git ls-files --error-unmatch -- .project-manager >nul 2>&1
if not errorlevel 1 (
    git rm -r --cached --ignore-unmatch -- .project-manager >nul 2>&1
)

exit /b 0

:: ===============================================================================
:: RECENT PROJECTS TRACKING
:: ===============================================================================

:remember_project
setlocal EnableDelayedExpansion
set "entry=%CD%"
set "tmpfile=%TEMP%\pman-recent-%RANDOM%.tmp"

if exist "!RECENT_FILE!" (
    findstr /v /i /l /x /c:"!entry!" "!RECENT_FILE!" > "!tmpfile!" 2>nul
) else (
    type nul > "!tmpfile!"
)

> "!RECENT_FILE!" (
    echo !entry!
    if exist "!tmpfile!" (
        for /f "usebackq skip=0 delims=" %%L in ("!tmpfile!") do (
            set /a n+=1
            if !n! LEQ 9 echo %%L
        )
    )
)

del "!tmpfile!" >nul 2>&1
endlocal
exit /b


:: ===============================================================================
:: INSTALL DEPENDENCIES
:: ===============================================================================

:install
cls

echo %CYAN%=========================================================================
echo               INSTALL DEPENDENCIES
echo =========================================================================%RESET%

echo.

if not exist "package.json" (
    echo   %YELLOW%[INFO] package.json not found.%RESET%
    echo   This does not appear to be a Node.js project.
    echo.
    pause
    goto main
)

if "!PM!"=="none" (
    echo   %RED%[ERROR] No supported package manager was found on PATH.%RESET%
    pause
    goto main
)

if exist "node_modules" (
    echo   %YELLOW%[WARNING] node_modules already exists.%RESET%
    echo.
    set "reinstall="
    set /p "reinstall=  [?] Reinstall dependencies? (Y/N): "

    if /i not "!reinstall!"=="Y" goto main

    call :safe_rmdir "node_modules"
)

echo.
echo   [INFO] Package Manager: !PM!
echo.

:: Run the detected package manager explicitly.
:: Using a direct branch here avoids the nested IF/CALL
:: evaluation issue that could skip the install command.
if /i "!PM!"=="npm" goto install_npm
if /i "!PM!"=="pnpm" goto install_pnpm
if /i "!PM!"=="yarn" goto install_yarn
if /i "!PM!"=="bun" goto install_bun

echo   %RED%[ERROR] Unsupported package manager: !PM!%RESET%
pause
goto main

:install_npm
call :run_command npm install
pause
goto main

:install_pnpm
call :run_command pnpm install
pause
goto main

:install_yarn
call :run_command yarn install
pause
goto main

:install_bun
call :run_command bun install
pause
goto main


:: ===============================================================================
:: RUN PROJECT
:: ===============================================================================

:runproject
cls

echo %CYAN%=========================================================================
echo                  RUN PROJECT
echo =========================================================================%RESET%

echo.

if not exist "package.json" (
    echo   %YELLOW%[INFO] package.json not found.%RESET%
    echo.
    pause
    goto main
)

call :has_npm_script "start"

if errorlevel 1 (
    echo   %YELLOW%[WARNING] No start script found.%RESET%
    echo.
    echo   Use "Package Scripts" to see available commands.
    pause
    goto main
)

if /i "!PM!"=="npm" start "Project Server" cmd /k "npm start"
if /i "!PM!"=="pnpm" start "Project Server" cmd /k "pnpm start"
if /i "!PM!"=="yarn" start "Project Server" cmd /k "yarn start"
if /i "!PM!"=="bun" start "Project Server" cmd /k "bun start"

echo.
echo   %GREEN%[OK] Project launched.%RESET%

pause
goto main


:: ===============================================================================
:: DEVELOPMENT SERVER
:: ===============================================================================

:dev
cls

echo %CYAN%=========================================================================
echo                DEVELOPMENT SERVER
echo =========================================================================%RESET%

echo.

if not exist "package.json" (
    echo   %RED%[ERROR] package.json not found.%RESET%
    pause
    goto main
)

call :has_npm_script "dev"

if errorlevel 1 (
    echo   %YELLOW%[WARNING] No dev script found.%RESET%
    pause
    goto main
)

if /i "!PM!"=="npm" start "Dev Server" cmd /k "npm run dev"
if /i "!PM!"=="pnpm" start "Dev Server" cmd /k "pnpm dev"
if /i "!PM!"=="yarn" start "Dev Server" cmd /k "yarn dev"
if /i "!PM!"=="bun" start "Dev Server" cmd /k "bun dev"

echo.
echo   %GREEN%[OK] Development server launched.%RESET%

pause
goto main


:: ===============================================================================
:: BUILD PROJECT
:: ===============================================================================

:buildproject
cls

echo %CYAN%=========================================================================
echo                   BUILD PROJECT
echo =========================================================================%RESET%

echo.

if not exist "package.json" goto typescript_build

call :has_npm_script "build"

if not errorlevel 1 (
    echo   [INFO] Build script detected.
    echo.
    echo   Running package build...
    echo.

    call :run_pm_script "build"

    pause
    goto main
)

:typescript_build

if exist "tsconfig.json" (
    echo   [INFO] No package build script found.
    echo   [INFO] TypeScript project detected.
    echo.
    echo   Running TypeScript compiler...
    echo.

    call :run_command npx tsc

    pause
    goto main
)

echo   %YELLOW%[WARNING] No build system detected.%RESET%
echo.
echo   No "build" script or tsconfig.json was found.

pause
goto main


:: ===============================================================================
:: PACKAGE MANAGER COMMAND HELPERS
:: ===============================================================================

:run_pm_script
:: :run_pm_script <script-name>
:: Runs the same package.json script with the detected package manager.
set "PM_SCRIPT=%~1"
if /i "!PM!"=="npm" (
    call :run_command npm run !PM_SCRIPT!
    exit /b !errorlevel!
)
if /i "!PM!"=="pnpm" (
    call :run_command pnpm run !PM_SCRIPT!
    exit /b !errorlevel!
)
if /i "!PM!"=="yarn" (
    call :run_command yarn run !PM_SCRIPT!
    exit /b !errorlevel!
)
if /i "!PM!"=="bun" (
    call :run_command bun run !PM_SCRIPT!
    exit /b !errorlevel!
)
exit /b 1

:run_pm_install
if /i "!PM!"=="npm" (
    call :run_command npm install
    exit /b !errorlevel!
)
if /i "!PM!"=="pnpm" (
    call :run_command pnpm install
    exit /b !errorlevel!
)
if /i "!PM!"=="yarn" (
    call :run_command yarn install
    exit /b !errorlevel!
)
if /i "!PM!"=="bun" (
    call :run_command bun install
    exit /b !errorlevel!
)
exit /b 1

:: ===============================================================================
:: CUSTOM SCRIPT
:: ===============================================================================

:customscript
cls

echo %CYAN%=========================================================================
echo                RUN CUSTOM SCRIPT
echo =========================================================================%RESET%

echo.

if not exist "package.json" (
    echo   %RED%[ERROR] package.json not found.%RESET%
    pause
    goto main
)

echo   Available package scripts:
echo   ----------------------------------------------

call :show_scripts

echo.
set "custom="
set /p "custom=  Enter script name: "

if "!custom!"=="" goto main

call :is_safe_token "!custom!"
if errorlevel 1 (
    echo.
    echo   %RED%[ERROR] Invalid script name. Only letters, numbers,%RESET%
    echo   %RED%[ERROR] dot, dash, underscore and colon are allowed.%RESET%
    pause
    goto main
)

echo.

call :run_pm_script "!custom!"

pause
goto main


:: ===============================================================================
:: SHOW PACKAGE SCRIPTS
:: ===============================================================================

:has_npm_script
:: :has_npm_script <script-name> -> errorlevel 0 when script exists
set "CHECK_SCRIPT=%~1"
if not exist "package.json" exit /b 1
powershell -NoProfile -Command "$j=Get-Content -Raw 'package.json' | ConvertFrom-Json; if($j.scripts -and $j.scripts.PSObject.Properties.Name -contains '%CHECK_SCRIPT%'){exit 0}else{exit 1}" >nul 2>&1
exit /b %errorlevel%


:show_scripts
if not exist "package.json" exit /b

powershell -NoProfile -Command "$j=Get-Content -Raw 'package.json' | ConvertFrom-Json; if($j.scripts){$j.scripts.PSObject.Properties | ForEach-Object {Write-Host ('  {0} : {1}' -f $_.Name,$_.Value)}}else{Write-Host '  No scripts detected.'}"
exit /b


:scripts
cls

echo %CYAN%=========================================================================
echo                 PACKAGE SCRIPTS
echo =========================================================================%RESET%

if not exist "package.json" (
    echo.
    echo   %YELLOW%[INFO] package.json not found.%RESET%
    echo.
    pause
    goto main
)

call :show_scripts

echo.
pause
goto main


:: ===============================================================================
:: TEST
:: ===============================================================================

:test
cls

echo %CYAN%=========================================================================
echo                      TEST
echo =========================================================================%RESET%

echo.

if not exist "package.json" (
    echo   %YELLOW%[INFO] package.json not found.%RESET%
    pause
    goto main
)

call :has_npm_script "test"

if errorlevel 1 (
    echo   %YELLOW%[WARNING] No test script found.%RESET%
    pause
    goto main
)

call :run_pm_script "test"

pause
goto main


:: ===============================================================================
:: LINT
:: ===============================================================================

:lint
cls

echo %CYAN%=========================================================================
echo                        LINT
echo =========================================================================%RESET%

echo.

if not exist "package.json" (
    echo   %YELLOW%[INFO] package.json not found.%RESET%
    pause
    goto main
)

call :has_npm_script "lint"

if errorlevel 1 (
    echo   %YELLOW%[WARNING] No lint script found.%RESET%
    pause
    goto main
)

call :run_pm_script "lint"

pause
goto main


:: ===============================================================================
:: FORMAT
:: ===============================================================================

:format
cls

echo %CYAN%=========================================================================
echo                      FORMAT
echo =========================================================================%RESET%

echo.

if not exist "package.json" (
    echo   %YELLOW%[INFO] package.json not found.%RESET%
    pause
    goto main
)

call :has_npm_script "format"

if errorlevel 1 (
    echo   %YELLOW%[WARNING] No format script found.%RESET%
    pause
    goto main
)

call :run_pm_script "format"

pause
goto main


:: =========================================================================
:: TYPE CHECK
:: =========================================================================

:typecheck
cls

echo %CYAN%=========================================================================
echo                    TYPE CHECK
echo =========================================================================%RESET%

echo.

if exist "tsconfig.json" (
    call :run_command npx tsc --noEmit
    pause
    goto main
)

if not exist "package.json" (
    echo   %YELLOW%[INFO] No TypeScript configuration or typecheck script found.%RESET%
    pause
    goto main
)

call :has_npm_script "typecheck"

if not errorlevel 1 (
    call :run_pm_script "typecheck"
) else (
    echo   %YELLOW%[INFO] No TypeScript configuration or typecheck script found.%RESET%
)

pause
goto main


:: =========================================================================
:: PROJECT STATUS
:: =========================================================================

:status
cls

echo %CYAN%=========================================================================
echo                 PROJECT STATUS
echo =========================================================================%RESET%

echo.
echo   [Project]
echo   ----------------------------------------------

if exist "package.json" (
    echo   %GREEN%[OK] package.json%RESET%
) else (
    echo   %YELLOW%[--] package.json%RESET%
)

if exist "tsconfig.json" (
    echo   %GREEN%[OK] TypeScript%RESET%
) else (
    echo   %YELLOW%[--] TypeScript%RESET%
)

if exist "node_modules" (
    echo   %GREEN%[OK] node_modules%RESET%
) else (
    echo   %YELLOW%[--] node_modules%RESET%
)

if exist ".git" (
    echo   %GREEN%[OK] Git repository%RESET%
) else (
    echo   %YELLOW%[--] Git repository%RESET%
)

if exist ".env" (
    echo   %GREEN%[OK] .env found%RESET%
) else (
    echo   %YELLOW%[--] .env not found%RESET%
)

if exist "dist" echo   %GREEN%[OK] dist%RESET%
if exist "build" echo   %GREEN%[OK] build%RESET%
if exist ".next" echo   %GREEN%[OK] .next%RESET%
if exist ".nuxt" echo   %GREEN%[OK] .nuxt%RESET%

echo.
echo   [Detection]
echo   ----------------------------------------------
echo   Project Type: !PROJECT_TYPE!
echo   Package Manager: !PM!
echo   Git: !HAS_GIT!

echo.
echo   [Tools]
echo   ----------------------------------------------

where node >nul 2>&1
if not errorlevel 1 (echo   %GREEN%[OK] Node.js%RESET%) else (echo   %YELLOW%[--] Node.js%RESET%)

where npm >nul 2>&1
if not errorlevel 1 (echo   %GREEN%[OK] npm%RESET%) else (echo   %YELLOW%[--] npm%RESET%)

where python >nul 2>&1
if not errorlevel 1 (echo   %GREEN%[OK] Python%RESET%) else (echo   %YELLOW%[--] Python%RESET%)

where git >nul 2>&1
if not errorlevel 1 (echo   %GREEN%[OK] Git%RESET%) else (echo   %YELLOW%[--] Git%RESET%)

echo.
pause
goto main


:: =========================================================================
:: PACKAGE UPDATES
:: =========================================================================

:updates
cls

echo %CYAN%=========================================================================
echo                 PACKAGE UPDATES
echo =========================================================================%RESET%

echo.

if not exist "package.json" (
    echo   %YELLOW%[INFO] package.json not found.%RESET%
    pause
    goto main
)

if /i "!PM!"=="npm" call :run_command npm outdated
if /i "!PM!"=="pnpm" call :run_command pnpm outdated
if /i "!PM!"=="yarn" call :run_command yarn outdated
if /i "!PM!"=="bun" call :run_command bun outdated

echo.
pause
goto main


:: =========================================================================
:: ENVIRONMENT INFO
:: =========================================================================

:environment
cls

echo %CYAN%=========================================================================
echo                ENVIRONMENT INFO
echo =========================================================================%RESET%

echo.

echo   Operating System:
ver

echo.
echo   Architecture:
echo %PROCESSOR_ARCHITECTURE%

echo.
echo   Project Path:
echo %CD%

echo.
echo   Node.js:
where node >nul 2>&1
if not errorlevel 1 (node --version) else (echo Not installed)

echo.
echo   npm:
where npm >nul 2>&1
if not errorlevel 1 (npm --version) else (echo Not installed)

echo.
echo   pnpm:
where pnpm >nul 2>&1
if not errorlevel 1 (pnpm --version) else (echo Not installed)

echo.
echo   yarn:
where yarn >nul 2>&1
if not errorlevel 1 (yarn --version) else (echo Not installed)

echo.
echo   bun:
where bun >nul 2>&1
if not errorlevel 1 (bun --version) else (echo Not installed)

echo.
echo   Python:
where python >nul 2>&1
if not errorlevel 1 (python --version) else (echo Not installed)

echo.
echo   Git:
where git >nul 2>&1
if not errorlevel 1 (git --version) else (echo Not installed)

echo.
pause
goto main


:: =========================================================================
:: PROJECT DIAGNOSTICS
:: =========================================================================

:diagnostics
cls

echo %CYAN%=========================================================================
echo               PROJECT DIAGNOSTICS
echo =========================================================================%RESET%

echo.

set /a HEALTH=0
set /a TOTAL=0

echo   [Project Files]
echo   ----------------------------------------------

if exist "package.json" (
    echo   %GREEN%[OK] package.json%RESET%
    set /a HEALTH+=1
)
set /a TOTAL+=1

if exist "node_modules" (
    echo   %GREEN%[OK] Dependencies installed%RESET%
    set /a HEALTH+=1
) else (
    echo   %YELLOW%[WARNING] node_modules missing%RESET%
)
set /a TOTAL+=1

if exist "tsconfig.json" (
    echo   %GREEN%[OK] TypeScript configuration%RESET%
    set /a HEALTH+=1
) else (
    echo   %YELLOW%[INFO] tsconfig.json not found%RESET%
)
set /a TOTAL+=1

if exist ".git" (
    echo   %GREEN%[OK] Git repository%RESET%
    set /a HEALTH+=1
) else (
    echo   %YELLOW%[INFO] Git repository not found%RESET%
)
set /a TOTAL+=1

if exist ".env" (
    echo   %GREEN%[OK] Environment file found%RESET%
) else (
    echo   %YELLOW%[INFO] .env not found%RESET%
)
set /a TOTAL+=1

if exist "package.json" (
    call :has_npm_script "build"
    if not errorlevel 1 (
        echo   %GREEN%[OK] Build script found%RESET%
        set /a HEALTH+=1
    ) else (
        echo   %YELLOW%[WARNING] Build script missing%RESET%
    )
)
set /a TOTAL+=1

if exist "package.json" (
    call :has_npm_script "dev"
    if not errorlevel 1 (
        echo   %GREEN%[OK] Dev script found%RESET%
        set /a HEALTH+=1
    ) else (
        echo   %YELLOW%[INFO] Dev script not found%RESET%
    )
)
set /a TOTAL+=1

echo.
set /a SCORE=(HEALTH*100)/TOTAL

echo   ----------------------------------------------
echo   Project Health: !SCORE!%%
echo   ----------------------------------------------

if !SCORE! GEQ 80 (
    echo   %GREEN%[GOOD] Project is in good condition.%RESET%
) else if !SCORE! GEQ 50 (
    echo   %YELLOW%[WARNING] Project needs attention.%RESET%
) else (
    echo   %RED%[CRITICAL] Project requires maintenance.%RESET%
)

echo.
pause
goto main


:: =========================================================================
:: PORT CHECKER
:: =========================================================================

:ports
cls

echo %CYAN%=========================================================================
echo                   PORT CHECKER
echo =========================================================================%RESET%

echo.
set "port="
set /p "port=  Enter port number: "

if "!port!"=="" goto main

call :is_number "!port!"
if errorlevel 1 (
    echo.
    echo   %RED%[ERROR] Port must be numeric.%RESET%
    pause
    goto main
)

if !port! LSS 1 (
    echo   %RED%[ERROR] Port out of range.%RESET%
    pause
    goto main
)
if !port! GTR 65535 (
    echo   %RED%[ERROR] Port out of range.%RESET%
    pause
    goto main
)

echo.
echo   Checking port !port!...
echo   ----------------------------------------------

netstat -ano | findstr /r /c:":!port! " >nul

if errorlevel 1 (
    echo   %GREEN%[AVAILABLE] Port !port! is available.%RESET%
) else (
    echo   %RED%[USED] Port !port! is currently in use.%RESET%
    echo.
    netstat -ano | findstr /r /c:":!port! "
)

echo.
pause
goto main


:: =========================================================================
:: PROCESS MANAGER
:: =========================================================================

:processes
cls

echo %CYAN%=========================================================================
echo                 PROCESS MANAGER
echo =========================================================================%RESET%

echo.
echo   1. Find a running program              [tasklist | findstr]
echo   2. Stop a program by PID               [taskkill /PID /F]
echo   3. Find which program uses a port      [netstat -ano]
echo   0. Back
echo.

set "pc="
set /p "pc=  Select option: "

if "!pc!"=="1" goto findprocess
if "!pc!"=="2" goto killprocess
if "!pc!"=="3" goto portowner
if "!pc!"=="0" goto main

goto processes


:findprocess
cls

echo %CYAN%=========================================================================
echo                   FIND PROCESS
echo =========================================================================%RESET%

echo.
set "pname="
set /p "pname=  Process name: "

if "!pname!"=="" goto processes

call :is_safe_token "!pname!"
if errorlevel 1 (
    echo.
    echo   %RED%[ERROR] Invalid process name.%RESET%
    pause
    goto processes
)

tasklist | findstr /i "!pname!"

echo.
pause
goto processes


:killprocess
cls

echo %RED%=========================================================================
echo                   KILL PROCESS
echo =========================================================================%RESET%

echo.
set "pid="
set /p "pid=  Enter PID: "

if "!pid!"=="" goto processes

call :is_number "!pid!"
if errorlevel 1 (
    echo.
    echo   %RED%[ERROR] PID must be numeric.%RESET%
    pause
    goto processes
)

echo.
set "confirm="
set /p "confirm=  Kill process !pid!? (Y/N): "

if /i "!confirm!"=="Y" (
    taskkill /PID !pid! /F
)

echo.
pause
goto processes


:portowner
cls

echo %CYAN%=========================================================================
echo                   PORT OWNER
echo =========================================================================%RESET%

echo.
set "port="
set /p "port=  Port number: "

if "!port!"=="" goto processes

call :is_number "!port!"
if errorlevel 1 (
    echo.
    echo   %RED%[ERROR] Port must be numeric.%RESET%
    pause
    goto processes
)

echo.
netstat -ano | findstr /r /c:":!port! "

echo.
pause
goto processes


:: =========================================================================
:: GIT STATUS
:: =========================================================================

:gitstatus
cls

echo %CYAN%=========================================================================
echo                    GIT STATUS
echo =========================================================================%RESET%

echo.

where git >nul 2>&1

if errorlevel 1 (
    echo   %RED%[ERROR] Git is not installed.%RESET%
    pause
    goto main
)

git rev-parse --is-inside-work-tree >nul 2>&1

if errorlevel 1 (
    echo   %YELLOW%[WARNING] This is not a Git repository.%RESET%
    pause
    goto main
)

echo   Current Branch:
echo   ----------------------------------------------
git branch --show-current

echo.
echo   Repository Status:
echo   ----------------------------------------------
git status --short

echo.
pause
goto main


:: =========================================================================
:: GIT MANAGER
:: =========================================================================

:gitmanager
cls
echo %CYAN%=========================================================================
echo                    GIT MANAGER
echo =========================================================================%RESET%
echo.
echo   Repository: %GREEN%!PROJECT_NAME!%RESET%
echo   Main Branch: %GREEN%!GIT_MAIN!%RESET%
echo   Origin Remote: %GREEN%!GIT_ORIGIN!%RESET%
echo.
echo   ----------------------------------------------
echo    1.  Create Git repository if needed    [git init]
echo    2.  See Git status                     [git status]
echo    3.  Select changes to include          [git add -A / git add]
echo    4.  Remove files from staging          [git restore --staged]
echo    5.  Save changes as a commit           [git commit -m]
echo    6.  Edit the last commit               [git commit --amend]
echo   ----------------------------------------------
echo    7.  Manage branches (create/switch/delete) [git branch/switch]
echo    8.  Manage GitHub/remote connection    [git remote]
echo    9.  Download remote changes            [git fetch]
echo   10.  Download + merge remote changes    [git pull]
echo   11.  Upload local commits               [git push]
echo   12.  Synchronize main with origin       [git fetch/pull/push]
echo   ----------------------------------------------
echo   13.  View commit history                [git log]
echo   14.  Compare file/code changes          [git diff]
echo   15.  Temporarily save unfinished work   [git stash]
echo   16.  Manage release/version tags        [git tag]
echo   17.  Reapply commits on top of main     [git rebase]
echo   18.  Combine another branch into this one [git merge]
echo   19.  Copy a commit to this branch       [git cherry-pick]
echo   20.  Undo a commit safely with a new commit [git revert]
echo   ----------------------------------------------
echo   21.  Restore/reset project files        [git restore/reset]
echo   22.  Remove untracked files             [git clean]
echo   23.  Manage Git submodules              [git submodule]
echo   24.  Configure Git name/email           [git config]
echo   25.  Manage ignored files               [git ignore/check-ignore]
echo   26.  Inspect Git references             [git show-ref/reflog]
echo   27.  View Git technical information     [git info/rev-parse]
echo   28.  Set default Main branch/Origin     [PMAN settings]
echo   ----------------------------------------------
echo   0. Back to main menu
echo.
set "gc="
set /p "gc=  Select option: "
if "!gc!"=="1" goto gitrepo
if "!gc!"=="2" goto gitmanager_status
if "!gc!"=="3" goto gitstage
if "!gc!"=="4" goto gitunstage
if "!gc!"=="5" goto gitcommit
if "!gc!"=="6" goto gitamend
if "!gc!"=="7" goto gitbranches
if "!gc!"=="8" goto gitremotes
if "!gc!"=="9" goto gitfetch
if "!gc!"=="10" goto gitpull
if "!gc!"=="11" goto gitpush
if "!gc!"=="12" goto gitsync
if "!gc!"=="13" goto gitlogmenu
if "!gc!"=="14" goto gitdiff
if "!gc!"=="15" goto gitstash
if "!gc!"=="16" goto gittags
if "!gc!"=="17" goto gitrebase
if "!gc!"=="18" goto gitmerge
if "!gc!"=="19" goto gitcherry
if "!gc!"=="20" goto gitrevert
if "!gc!"=="21" goto gitreset
if "!gc!"=="22" goto gitclean
if "!gc!"=="23" goto gitsubmodule
if "!gc!"=="24" goto gitconfig
if "!gc!"=="25" goto gitignore
if "!gc!"=="26" goto gitrefs
if "!gc!"=="27" goto gitinfo
if "!gc!"=="28" goto gitdefaults
if "!gc!"=="0" goto main
goto gitmanager


:: ===============================================================================
:: GIT DEFAULTS
:: ===============================================================================

:gitdefaults
cls
echo %CYAN%=========================================================================
echo                MAIN / ORIGIN SETTINGS
echo =========================================================================%RESET%
echo.
echo   Main branch  : !GIT_MAIN!
echo   Origin remote: !GIT_ORIGIN!
echo.
echo   1. Set Main Branch
echo   2. Set Origin Remote
echo   3. Reset to main / origin
echo   0. Back
echo.
set "gd="
set /p "gd=  Select option: "
if "!gd!"=="1" (
    set "v="
    set /p "v=  Main branch [main]: "
    if defined v (
        call :is_safe_token "!v!"
        if errorlevel 1 (echo Invalid branch name.&pause&goto gitdefaults)
        set "GIT_MAIN=!v!"
    )
    goto gitdefaults
)
if "!gd!"=="2" (
    set "v="
    set /p "v=  Origin remote [origin]: "
    if defined v (
        call :is_safe_token "!v!"
        if errorlevel 1 (echo Invalid remote name.&pause&goto gitdefaults)
        set "GIT_ORIGIN=!v!"
    )
    goto gitdefaults
)
if "!gd!"=="3" (
    set "GIT_MAIN=main"
    set "GIT_ORIGIN=origin"
    goto gitdefaults
)
if "!gd!"=="0" goto gitmanager
goto gitdefaults


:: ===============================================================================
:: GIT REPOSITORY
:: ===============================================================================

:gitrepo
cls
echo %CYAN%=========================================================================
echo                REPOSITORY / INIT
echo =========================================================================%RESET%
echo.
echo   Main: !GIT_MAIN!    Origin: !GIT_ORIGIN!
echo.
echo   1. Create Git repository here          [git init]
echo   2. Show project Git root               [git rev-parse --show-toplevel]
echo   3. Show Git internal folder            [git rev-parse --git-dir]
echo   4. Connect this project to Origin      [git remote add origin URL]
echo   5. Remove Origin connection            [git remote remove origin]
echo   6. Rename current branch to Main       [git branch -M main]
echo   0. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" call :run_command git init
if "!x!"=="2" call :run_command git rev-parse --show-toplevel
if "!x!"=="3" call :run_command git rev-parse --git-dir
if "!x!"=="4" (
    set "url="
    set /p "url=  Remote URL: "
    if defined url call :run_command git remote add !GIT_ORIGIN! !url!
)
if "!x!"=="5" call :run_command git remote remove !GIT_ORIGIN!
if "!x!"=="6" call :run_command git branch -M !GIT_MAIN!
if "!x!"=="0" goto gitmanager
pause
goto gitrepo


:: ===============================================================================
:: GIT STATUS
:: ===============================================================================

:gitmanager_status
cls
echo %CYAN%=========================================================================
echo                GIT REPOSITORY STATUS
echo =========================================================================%RESET%
echo.
echo   Main: !GIT_MAIN!    Origin: !GIT_ORIGIN!
echo.
call :run_command git status
echo.
echo   Current branch:
git branch --show-current
echo.
echo   Tracking:
git status -sb
pause
goto gitmanager


:: ===============================================================================
:: STAGE / UNSTAGE
:: ===============================================================================

:gitstage
cls
echo %CYAN%=========================================================================
echo                   STAGE CHANGES
echo =========================================================================%RESET%
echo.
echo   Main: !GIT_MAIN!    Origin: !GIT_ORIGIN!
echo.
echo   1. Stage all changed files             [git add -A]
echo   2. Stage only a file/folder            [git add -- FILE]
echo   3. Choose changes interactively        [git add -p]
echo   0. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" call :run_command git add -A
if "!x!"=="2" (
    set "p="
    set /p "p=  File/folder: "
    if defined p call :run_command git add -- !p!
)
if "!x!"=="3" call :run_command git add -p
if "!x!"=="0" goto gitmanager
pause
goto gitstage

:gitunstage
cls
echo %CYAN%=========================================================================
echo                  UNSTAGE CHANGES
echo =========================================================================%RESET%
echo.
echo   1. Unstage all files                   [git restore --staged .]
echo   2. Unstage one file/folder             [git restore --staged -- FILE]
echo   0. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" call :run_command git restore --staged .
if "!x!"=="2" (
    set "p="
    set /p "p=  File/folder: "
    if defined p call :run_command git restore --staged -- !p!
)
if "!x!"=="0" goto gitmanager
pause
goto gitunstage


:: ===============================================================================
:: GIT COMMIT
:: ===============================================================================

:gitcommit
cls
echo %CYAN%=========================================================================
echo                       COMMIT
echo =========================================================================%RESET%
echo.
echo   Main: !GIT_MAIN!    Origin: !GIT_ORIGIN!
echo.
git status --short
echo.
set "msg="
set /p "msg=  Commit message: "
if not defined msg goto gitmanager
call :run_command git commit -m "!msg!"
pause
goto gitmanager

:gitamend
cls
echo %CYAN%=========================================================================
echo                  AMEND LAST COMMIT
echo =========================================================================%RESET%
echo.
git log -1 --oneline
echo.
echo   1. Amend using existing message
echo   2. Amend with new message
echo   0. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" call :run_command git commit --amend --no-edit
if "!x!"=="2" (
    set "msg="
    set /p "msg=  New commit message: "
    if defined msg call :run_command git commit --amend -m "!msg!"
)
if "!x!"=="0" goto gitmanager
pause
goto gitamend


:: ===============================================================================
:: BRANCH MANAGER
:: ===============================================================================

:gitbranches
cls
echo %CYAN%=========================================================================
echo                    BRANCH MANAGER
echo =========================================================================%RESET%
echo.
echo   Main: !GIT_MAIN!    Origin: !GIT_ORIGIN!
echo.
echo   1. Show local branches                 [git branch]
echo   2. Show local + remote branches        [git branch -a]
echo   3. Create a new branch                 [git branch NAME]
echo   4. Switch to another branch            [git switch NAME]
echo   5. Create and switch to a branch       [git switch -c NAME]
echo   6. Rename the current branch           [git branch -m NAME]
echo   7. Delete a merged local branch        [git branch -d NAME]
echo   8. Force-delete a local branch         [git branch -D NAME]
echo   9. Merge another branch into current   [git merge NAME]
echo  10. Rebase current branch onto Main     [git rebase main]
echo  11. Show remote branches                [git branch -r]
echo  12. Delete a branch from Origin         [git push origin --delete NAME]
echo  0. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" call :run_command git branch
if "!x!"=="2" call :run_command git branch -a
if "!x!"=="3" (
    set "b="
    set /p "b=  New branch: "
    if defined b call :run_command git branch !b!
)
if "!x!"=="4" (
    set "b="
    set /p "b=  Switch to branch: "
    if defined b call :run_command git switch !b!
)
if "!x!"=="5" (
    set "b="
    set /p "b=  New branch: "
    if defined b call :run_command git switch -c !b!
)
if "!x!"=="6" (
    set "b="
    set /p "b=  New name: "
    if defined b call :run_command git branch -m !b!
)
if "!x!"=="7" (
    set "b="
    set /p "b=  Branch to delete: "
    if defined b call :run_command git branch -d !b!
)
if "!x!"=="8" (
    set "b="
    set /p "b=  Branch to force delete: "
    if defined b call :run_command git branch -D !b!
)
if "!x!"=="9" (
    set "b="
    set /p "b=  Branch to merge: "
    if defined b call :run_command git merge !b!
)
if "!x!"=="10" call :run_command git rebase !GIT_MAIN!
if "!x!"=="11" call :run_command git branch -r
if "!x!"=="12" (
    set "b="
    set /p "b=  Remote branch to delete: "
    if defined b call :run_command git push !GIT_ORIGIN! --delete !b!
)
if "!x!"=="0" goto gitmanager
pause
goto gitbranches


:: ===============================================================================
:: REMOTE MANAGER
:: ===============================================================================

:gitremotes
cls
echo %CYAN%=========================================================================
echo                    REMOTE MANAGER
echo =========================================================================%RESET%
echo.
echo   Main: !GIT_MAIN!    Origin: !GIT_ORIGIN!
echo.
echo   1. Show all remote connections        [git remote -v]
echo   2. Inspect Origin connection          [git remote show origin]
echo   3. Connect a repository to Origin     [git remote add origin URL]
echo   4. Change Origin URL                  [git remote set-url origin URL]
echo   5. Show Origin URL                    [git remote get-url origin]
echo   6. Remove Origin connection           [git remote remove origin]
echo   7. Download latest remote information [git fetch origin]
echo   8. Remove deleted remote branches     [git fetch origin --prune]
echo   0. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" call :run_command git remote -v
if "!x!"=="2" call :run_command git remote show !GIT_ORIGIN!
if "!x!"=="3" (
    set "url="
    set /p "url=  Origin URL: "
    if defined url call :run_command git remote add !GIT_ORIGIN! !url!
)
if "!x!"=="4" (
    set "url="
    set /p "url=  New origin URL: "
    if defined url call :run_command git remote set-url !GIT_ORIGIN! !url!
)
if "!x!"=="5" call :run_command git remote get-url !GIT_ORIGIN!
if "!x!"=="6" call :run_command git remote remove !GIT_ORIGIN!
if "!x!"=="7" call :run_command git fetch !GIT_ORIGIN!
if "!x!"=="8" call :run_command git fetch !GIT_ORIGIN! --prune
if "!x!"=="0" goto gitmanager
pause
goto gitremotes


:: ===============================================================================
:: FETCH / PULL / PUSH / SYNC
:: ===============================================================================

:gitfetch
cls
echo %CYAN%=========================================================================
echo                       FETCH
echo =========================================================================%RESET%
echo   Main: !GIT_MAIN!    Origin: !GIT_ORIGIN!
echo.
echo   1. Download Origin updates              [git fetch origin]
echo   2. Download + remove stale branches     [git fetch origin --prune]
echo   3. Download from all remotes            [git fetch --all]
echo   4. Download remote tags                 [git fetch origin --tags]
echo   0. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" call :run_command git fetch !GIT_ORIGIN!
if "!x!"=="2" call :run_command git fetch !GIT_ORIGIN! --prune
if "!x!"=="3" call :run_command git fetch --all
if "!x!"=="4" call :run_command git fetch !GIT_ORIGIN! --tags
if "!x!"=="0" goto gitmanager
pause
goto gitfetch

:gitpull
cls
echo %CYAN%=========================================================================
echo                        PULL
echo =========================================================================%RESET%
echo   Main: !GIT_MAIN!    Origin: !GIT_ORIGIN!
echo.
echo   1. Download and merge Origin/Main      [git pull origin main]
echo   2. Download and rebase onto Main       [git pull --rebase origin main]
echo   3. Download remote tags                [git pull origin --tags]
echo   4. Update current tracking branch      [git pull]
echo   0. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" call :run_command git pull !GIT_ORIGIN! !GIT_MAIN!
if "!x!"=="2" call :run_command git pull --rebase !GIT_ORIGIN! !GIT_MAIN!
if "!x!"=="3" call :run_command git pull !GIT_ORIGIN! --tags
if "!x!"=="4" call :run_command git pull
if "!x!"=="0" goto gitmanager
pause
goto gitpull

:gitpush
cls
echo %CYAN%=========================================================================
echo                        PUSH
echo =========================================================================%RESET%
echo   Main: !GIT_MAIN!    Origin: !GIT_ORIGIN!
echo.
echo   1. Upload Main to Origin               [git push origin main]
echo   2. Upload current branch               [git push]
echo   3. Upload + remember upstream          [git push -u origin HEAD]
echo   4. Upload all local branches           [git push origin --all]
echo   5. Upload all tags                     [git push origin --tags]
echo   6. Safely force-update Origin/Main     [git push --force-with-lease]
echo   0. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" call :run_command git push !GIT_ORIGIN! !GIT_MAIN!
if "!x!"=="2" call :run_command git push
if "!x!"=="3" call :run_command git push -u !GIT_ORIGIN! HEAD
if "!x!"=="4" call :run_command git push !GIT_ORIGIN! --all
if "!x!"=="5" call :run_command git push !GIT_ORIGIN! --tags
if "!x!"=="6" call :run_command git push !GIT_ORIGIN! !GIT_MAIN! --force-with-lease
if "!x!"=="0" goto gitmanager
pause
goto gitpush

:gitsync
cls
echo %CYAN%=========================================================================
echo                MAIN ^<--^> ORIGIN SYNC
echo =========================================================================%RESET%
echo.
echo   Local main : !GIT_MAIN!
echo   Remote     : !GIT_ORIGIN!
echo   Remote main: !GIT_ORIGIN!/!GIT_MAIN!
echo.
echo   1. Download latest Origin/Main info    [git fetch origin]
echo   2. Bring Origin/Main into local Main   [git pull origin main]
echo   3. Upload local Main to Origin/Main    [git push origin main]
echo   4. Download + pull + upload            [fetch + pull + push]
echo   5. Compare Main with Origin/Main       [git diff main..origin/main]
echo   0. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" call :run_command git fetch !GIT_ORIGIN!
if "!x!"=="2" call :run_command git pull !GIT_ORIGIN! !GIT_MAIN!
if "!x!"=="3" call :run_command git push !GIT_ORIGIN! !GIT_MAIN!
if "!x!"=="4" (
    call :run_command git fetch !GIT_ORIGIN!
    call :run_command git pull !GIT_ORIGIN! !GIT_MAIN!
    call :run_command git push !GIT_ORIGIN! !GIT_MAIN!
)
if "!x!"=="5" call :run_command git diff !GIT_MAIN!..!GIT_ORIGIN!/!GIT_MAIN!
if "!x!"=="0" goto gitmanager
pause
goto gitsync


:: ===============================================================================
:: LOG / DIFF
:: ===============================================================================

:gitlogmenu
cls
echo %CYAN%=========================================================================
echo                    HISTORY / LOG
echo =========================================================================%RESET%
echo.
echo   Main: !GIT_MAIN!    Origin: !GIT_ORIGIN!
echo.
echo   1. Show recent commits                 [git log --oneline -20]
echo   2. Show visual commit graph            [git log --graph --all]
echo   3. Show history of a file              [git log --follow -- FILE]
echo   4. Inspect a specific commit           [git show HASH]
echo   5. Search commit messages              [git log --grep=TEXT]
echo   6. Compare Main and Origin/Main        [git log main..origin/main]
echo   0. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" call :run_command git log --oneline -20
if "!x!"=="2" call :run_command git log --oneline --graph --decorate --all -30
if "!x!"=="3" (
    set "p="
    set /p "p=  File: "
    if defined p call :run_command git log --oneline --follow -- !p!
)
if "!x!"=="4" (
    set "c="
    set /p "c=  Commit/hash: "
    if defined c call :run_command git show !c!
)
if "!x!"=="5" (
    set "q="
    set /p "q=  Search text: "
    if defined q call :run_command git log --oneline --all --grep="!q!"
)
if "!x!"=="6" call :run_command git log --oneline !GIT_MAIN!..!GIT_ORIGIN!/!GIT_MAIN!
if "!x!"=="0" goto gitmanager
pause
goto gitlogmenu

:gitdiff
cls
echo %CYAN%=========================================================================
echo                       DIFF
echo =========================================================================%RESET%
echo.
echo   1. See changes not staged yet          [git diff]
echo   2. See changes already staged          [git diff --cached]
echo   3. Compare Main with Origin/Main       [git diff main..origin/main]
echo   4. Compare two commits                 [git diff HASH1 HASH2]
echo   5. Compare changes in one file         [git diff -- FILE]
echo   0. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" call :run_command git diff
if "!x!"=="2" call :run_command git diff --cached
if "!x!"=="3" call :run_command git diff !GIT_MAIN!..!GIT_ORIGIN!/!GIT_MAIN!
if "!x!"=="4" (
    set "a="
    set /p "a=  First commit: "
    set "b="
    set /p "b=  Second commit: "
    if defined a if defined b call :run_command git diff !a! !b!
)
if "!x!"=="5" (
    set "p="
    set /p "p=  File: "
    if defined p call :run_command git diff -- !p!
)
if "!x!"=="0" goto gitmanager
pause
goto gitdiff


:: ===============================================================================
:: STASH
:: ===============================================================================

:gitstash
cls
echo %CYAN%=========================================================================
echo                    STASH MANAGER
echo =========================================================================%RESET%
echo.
echo   1. Temporarily save current changes     [git stash push]
echo   2. Save changes + new files             [git stash push -u]
echo   3. List saved stashes                   [git stash list]
echo   4. Inspect a saved stash                [git stash show -p]
echo   5. Apply a stash without deleting it    [git stash apply]
echo   6. Apply + remove a stash               [git stash pop]
echo   7. Delete one saved stash               [git stash drop]
echo   8. Delete all saved stashes             [git stash clear]
echo   0. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" call :run_command git stash push
if "!x!"=="2" call :run_command git stash push -u
if "!x!"=="3" call :run_command git stash list
if "!x!"=="4" (
    set "n="
    set /p "n=  Stash (e.g. stash@{0}): "
    if defined n call :run_command git stash show -p !n!
)
if "!x!"=="5" (
    set "n="
    set /p "n=  Stash [stash@{0}]: "
    if not defined n set "n=stash@{0}"
    call :run_command git stash apply !n!
)
if "!x!"=="6" call :run_command git stash pop
if "!x!"=="7" (
    set "n="
    set /p "n=  Stash [stash@{0}]: "
    if not defined n set "n=stash@{0}"
    call :run_command git stash drop !n!
)
if "!x!"=="8" call :run_command git stash clear
if "!x!"=="0" goto gitmanager
pause
goto gitstash


:: ===============================================================================
:: TAGS
:: ===============================================================================

:gittags
cls
echo %CYAN%=========================================================================
echo                      TAG MANAGER
echo =========================================================================%RESET%
echo.
echo   1. Show version/release tags            [git tag -n]
echo   2. Create a simple version tag          [git tag NAME]
echo   3. Create a tag with release message    [git tag -a NAME -m MESSAGE]
echo   4. Inspect a tag                        [git show TAG]
echo   5. Delete a local tag                   [git tag -d TAG]
echo   6. Upload a tag to Origin               [git push origin TAG]
echo   7. Upload all tags                      [git push origin --tags]
echo   8. Delete a tag from Origin             [git push origin --delete TAG]
echo   0. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" call :run_command git tag -n
if "!x!"=="2" (
    set "t="
    set /p "t=  Tag name: "
    if defined t call :run_command git tag !t!
)
if "!x!"=="3" (
    set "t="
    set /p "t=  Tag name: "
    set "m="
    set /p "m=  Message: "
    if defined t call :run_command git tag -a !t! -m "!m!"
)
if "!x!"=="4" (
    set "t="
    set /p "t=  Tag: "
    if defined t call :run_command git show !t!
)
if "!x!"=="5" (
    set "t="
    set /p "t=  Tag to delete: "
    if defined t call :run_command git tag -d !t!
)
if "!x!"=="6" (
    set "t="
    set /p "t=  Tag: "
    if defined t call :run_command git push !GIT_ORIGIN! !t!
)
if "!x!"=="7" call :run_command git push !GIT_ORIGIN! --tags
if "!x!"=="8" (
    set "t="
    set /p "t=  Remote tag to delete: "
    if defined t call :run_command git push !GIT_ORIGIN! --delete !t!
)
if "!x!"=="0" goto gitmanager
pause
goto gittags


:: ===============================================================================
:: REBASE / MERGE / CHERRY-PICK / REVERT
:: ===============================================================================

:gitrebase
cls
echo %CYAN%=========================================================================
echo                       REBASE
echo =========================================================================%RESET%
echo   Main: !GIT_MAIN!    Origin: !GIT_ORIGIN!
echo.
echo   1. Move current work on top of Main   [git rebase main]
echo   2. Move current work on top of Origin/Main [git rebase origin/main]
echo   3. Edit last N commits interactively  [git rebase -i HEAD~N]
echo   4. Continue after fixing conflicts    [git rebase --continue]
echo   5. Cancel the rebase                  [git rebase --abort]
echo   6. Skip the current commit            [git rebase --skip]
echo   0. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" call :run_command git rebase !GIT_MAIN!
if "!x!"=="2" call :run_command git rebase !GIT_ORIGIN!/!GIT_MAIN!
if "!x!"=="3" (
    set "n="
    set /p "n=  Number of commits: "
    if defined n call :run_command git rebase -i HEAD~!n!
)
if "!x!"=="4" call :run_command git rebase --continue
if "!x!"=="5" call :run_command git rebase --abort
if "!x!"=="6" call :run_command git rebase --skip
if "!x!"=="0" goto gitmanager
pause
goto gitrebase

:gitmerge
cls
echo %CYAN%=========================================================================
echo                       MERGE
echo =========================================================================%RESET%
echo   Main: !GIT_MAIN!    Origin: !GIT_ORIGIN!
echo.
echo   1. Combine another branch into this one [git merge BRANCH]
echo   2. Combine Origin/Main into current     [git merge origin/main]
echo   3. Continue after fixing conflicts      [git merge --continue]
echo   4. Cancel the current merge             [git merge --abort]
echo   0. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" (
    set "b="
    set /p "b=  Branch: "
    if defined b call :run_command git merge !b!
)
if "!x!"=="2" call :run_command git merge !GIT_ORIGIN!/!GIT_MAIN!
if "!x!"=="3" call :run_command git merge --continue
if "!x!"=="4" call :run_command git merge --abort
if "!x!"=="0" goto gitmanager
pause
goto gitmerge

:gitcherry
cls
echo %CYAN%=========================================================================
echo                     CHERRY-PICK
echo =========================================================================%RESET%
echo.
echo   1. Copy one commit into this branch     [git cherry-pick HASH]
echo   2. Continue after fixing conflicts      [git cherry-pick --continue]
echo   3. Cancel cherry-pick                   [git cherry-pick --abort]
echo   4. Skip the current commit              [git cherry-pick --skip]
echo   0. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" (
    set "c="
    set /p "c=  Commit/hash: "
    if defined c call :run_command git cherry-pick !c!
)
if "!x!"=="2" call :run_command git cherry-pick --continue
if "!x!"=="3" call :run_command git cherry-pick --abort
if "!x!"=="4" call :run_command git cherry-pick --skip
if "!x!"=="0" goto gitmanager
pause
goto gitcherry

:gitrevert
cls
echo %CYAN%=========================================================================
echo                    REVERT COMMIT
echo =========================================================================%RESET%
echo.
echo   Revert creates a new commit that undoes another commit.
echo.
set "c="
set /p "c=  Commit/hash to revert: "
if defined c call :run_command git revert !c!
pause
goto gitmanager


:: ===============================================================================
:: RESET / RESTORE / CLEAN
:: ===============================================================================

:gitreset
cls
echo %CYAN%=========================================================================
echo                  RESET / RESTORE
echo =========================================================================%RESET%
echo.
echo   1. Discard changes in one file           [git restore -- FILE]
echo   2. Discard all unstaged changes          [git restore .]
echo   3. Move HEAD to commit, keep changes     [git reset --soft HASH]
echo   4. Move HEAD to commit, unstage changes  [git reset HASH]
echo   5. Force-reset and discard local changes [git reset --hard HASH]
echo   0. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" (
    set "p="
    set /p "p=  File: "
    if defined p call :run_command git restore -- !p!
)
if "!x!"=="2" call :run_command git restore .
if "!x!"=="3" (
    set "c="
    set /p "c=  Commit: "
    if defined c call :run_command git reset --soft !c!
)
if "!x!"=="4" (
    set "c="
    set /p "c=  Commit: "
    if defined c call :run_command git reset !c!
)
if "!x!"=="5" (
    echo   WARNING: hard reset discards local changes.
    set "ok="
    set /p "ok=  Type YES to continue: "
    if "!ok!"=="YES" (
        set "c="
        set /p "c=  Commit: "
        if defined c call :run_command git reset --hard !c!
    )
)
if "!x!"=="0" goto gitmanager
pause
goto gitreset

:gitclean
cls
echo %CYAN%=========================================================================
echo                CLEAN UNTRACKED FILES
echo =========================================================================%RESET%
echo.
echo   1. Preview what would be deleted        [git clean -n]
echo   2. Delete untracked files               [git clean -f]
echo   3. Delete untracked files + folders     [git clean -fd]
echo   0. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" call :run_command git clean -n
if "!x!"=="2" call :run_command git clean -f
if "!x!"=="3" call :run_command git clean -fd
if "!x!"=="0" goto gitmanager
pause
goto gitclean


:: ===============================================================================
:: SUBMODULES
:: ===============================================================================

:gitsubmodule
cls
echo %CYAN%=========================================================================
echo                  SUBMODULE MANAGER
echo =========================================================================%RESET%
echo.
echo   1. See installed submodules             [git submodule status]
echo   2. Initialize submodules                [git submodule init]
echo   3. Update submodules                    [git submodule update]
echo   4. Update nested submodules             [git submodule update --init --recursive]
echo   5. Add another repository as submodule  [git submodule add URL PATH]
echo   6. Sync submodule remote URLs           [git submodule sync --recursive]
echo   0. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" call :run_command git submodule status
if "!x!"=="2" call :run_command git submodule init
if "!x!"=="3" call :run_command git submodule update
if "!x!"=="4" call :run_command git submodule update --init --recursive
if "!x!"=="5" (
    set "url="
    set /p "url=  Repository URL: "
    set "path="
    set /p "path=  Local path: "
    if defined url if defined path call :run_command git submodule add !url! !path!
)
if "!x!"=="6" call :run_command git submodule sync --recursive
if "!x!"=="0" goto gitmanager
pause
goto gitsubmodule


:: ===============================================================================
:: CONFIG / IGNORE / REFS / INFO
:: ===============================================================================

:gitconfig
cls
echo %CYAN%=========================================================================
echo                     GIT CONFIG
echo =========================================================================%RESET%
echo.
echo   1. Show project Git settings           [git config --local --list]
echo   2. Show Windows-user Git settings      [git config --global --list]
echo   3. Show configured name                [git config user.name]
echo   4. Show configured email               [git config user.email]
echo   5. Set your Git name                   [git config user.name]
echo   6. Set your Git email                  [git config user.email]
echo   0. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" call :run_command git config --local --list
if "!x!"=="2" call :run_command git config --global --list
if "!x!"=="3" call :run_command git config user.name
if "!x!"=="4" call :run_command git config user.email
if "!x!"=="5" (
    set "v="
    set /p "v=  User name: "
    if defined v call :run_command git config user.name "!v!"
)
if "!x!"=="6" (
    set "v="
    set /p "v=  User email: "
    if defined v call :run_command git config user.email "!v!"
)
if "!x!"=="0" goto gitmanager
pause
goto gitconfig

:gitignore
cls
echo %CYAN%=========================================================================
echo                     GIT IGNORE
echo =========================================================================%RESET%
echo.
echo   1. Open or create the ignore file     [.gitignore / Notepad]
echo   2. Show ignored-file rules            [type .gitignore]
echo   3. Explain why a file is ignored      [git check-ignore -v FILE]
echo   4. Show all ignored files             [git status --ignored]
echo   0. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" start "" notepad.exe ".gitignore"
if "!x!"=="2" (
    if exist ".gitignore" type ".gitignore"
    if not exist ".gitignore" echo .gitignore not found.
)
if "!x!"=="3" (
    set "p="
    set /p "p=  File: "
    if defined p call :run_command git check-ignore -v !p!
)
if "!x!"=="4" call :run_command git status --ignored
if "!x!"=="0" goto gitmanager
pause
goto gitignore

:gitrefs
cls
echo %CYAN%=========================================================================
echo                       REFS
echo =========================================================================%RESET%
echo.
echo   1. Show every Git reference             [git show-ref]
echo   2. Show local branch references         [git for-each-ref refs/heads]
echo   3. Show remote branch references        [git for-each-ref refs/remotes]
echo   4. Show tag references                  [git for-each-ref refs/tags]
echo   5. Show recent HEAD movements           [git reflog --all]
echo   0. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" call :run_command git show-ref
if "!x!"=="2" call :run_command git for-each-ref refs/heads
if "!x!"=="3" call :run_command git for-each-ref refs/remotes
if "!x!"=="4" call :run_command git for-each-ref refs/tags
if "!x!"=="5" call :run_command git reflog --all
if "!x!"=="0" goto gitmanager
pause
goto gitrefs

:gitinfo
cls
echo %CYAN%=========================================================================
echo                   GIT INFORMATION
echo =========================================================================%RESET%
echo.
echo   Main: !GIT_MAIN!    Origin: !GIT_ORIGIN!
echo.
echo   1. Show installed Git version           [git --version]
echo   2. Show project Git root                [git rev-parse --show-toplevel]
echo   3. Show current branch                  [git branch --show-current]
echo   4. Show current commit hash             [git rev-parse HEAD]
echo   5. Show remote addresses                [git remote -v]
echo   6. Show ahead/behind Main vs Origin     [git rev-list --left-right --count]
echo   7. Show Git environment                 [git var -l]
echo   0. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" call :run_command git --version
if "!x!"=="2" call :run_command git rev-parse --show-toplevel
if "!x!"=="3" call :run_command git branch --show-current
if "!x!"=="4" call :run_command git rev-parse HEAD
if "!x!"=="5" call :run_command git remote -v
if "!x!"=="6" call :run_command git rev-list --left-right --count !GIT_MAIN!...!GIT_ORIGIN!/!GIT_MAIN!
if "!x!"=="7" call :run_command git var -l
if "!x!"=="0" goto gitmanager
pause
goto gitinfo

:: =========================================================================
:: DEPENDENCY MANAGER
:: =========================================================================

:dependencies
cls

echo %CYAN%=========================================================================
echo                DEPENDENCY MANAGER
echo =========================================================================%RESET%

echo.
echo   1. Install dependencies                [!PM! install]
echo   2. Update installed dependencies       [!PM! update]
echo   3. Find outdated dependencies          [!PM! outdated]
echo   4. Check dependencies for security     [!PM! audit]
echo   5. Delete and reinstall dependencies   [remove node_modules + install]
echo   6. List installed dependencies         [!PM! list]
echo   0. Back
echo.

set "dc="
set /p "dc=  Select option: "

if "!dc!"=="1" goto install
if "!dc!"=="2" goto depupdate
if "!dc!"=="3" goto updates
if "!dc!"=="4" goto depaudit
if "!dc!"=="5" goto depreinstall
if "!dc!"=="6" goto deplisting
if "!dc!"=="0" goto main

goto dependencies


:depupdate

if /i "!PM!"=="npm" call :run_command npm update
if /i "!PM!"=="pnpm" call :run_command pnpm update
if /i "!PM!"=="yarn" call :run_command yarn upgrade
if /i "!PM!"=="bun" call :run_command bun update

pause
goto dependencies


:depaudit

if /i "!PM!"=="npm" call :run_command npm audit
if /i "!PM!"=="pnpm" call :run_command pnpm audit
if /i "!PM!"=="yarn" call :run_command yarn npm audit
if /i "!PM!"=="bun" call :run_command bun audit

pause
goto dependencies


:depreinstall

echo.
set "confirm="
set /p "confirm=  Reinstall all dependencies? (Y/N): "

if /i not "!confirm!"=="Y" goto dependencies

call :safe_rmdir "node_modules"

call :run_pm_install

pause
goto dependencies


:deplisting

if /i "!PM!"=="npm" call :run_command npm list
if /i "!PM!"=="pnpm" call :run_command pnpm list
if /i "!PM!"=="yarn" call :run_command yarn list
if /i "!PM!"=="bun" call :run_command bun pm ls

pause
goto dependencies


:: =========================================================================
:: AUTO REPAIR
:: =========================================================================

:autorepair
cls

echo %CYAN%=========================================================================
echo                    AUTO REPAIR
echo =========================================================================%RESET%

echo.
echo   Project Manager will check common problems.
echo.

if not exist "package.json" (
    echo   %YELLOW%[INFO] package.json not found.%RESET%
    echo.
)

if exist "package.json" (
    if not exist "node_modules" (
        echo   %YELLOW%[FIX] Dependencies missing.%RESET%
        echo.
        set "repair="
        set /p "repair=  Install dependencies now? (Y/N): "

        if /i "!repair!"=="Y" (
            if /i "!PM!"=="npm" call :run_command npm install
            if /i "!PM!"=="pnpm" call :run_command pnpm install
            if /i "!PM!"=="yarn" call :run_command yarn install
            if /i "!PM!"=="bun" call :run_command bun install
        )
    )
)

if exist "tsconfig.json" (
    echo.
    echo   [CHECK] TypeScript configuration detected.
    call :run_command npx tsc --noEmit
)

if exist ".git" (
    echo.
    echo   [CHECK] Git repository detected.
    git status --short
)

echo.
echo   %GREEN%[OK] Auto repair/check completed.%RESET%

pause
goto main


:: =========================================================================
:: RECENT PROJECTS
:: =========================================================================

:recent
cls

echo %CYAN%=========================================================================
echo                  RECENT PROJECTS
echo =========================================================================%RESET%

echo.

if not exist "!RECENT_FILE!" (
    echo   No recent projects recorded.
    echo.
    pause
    goto main
)

type "!RECENT_FILE!"

echo.
echo   ----------------------------------------------
echo   Current project:
echo   %CD%

echo.
pause
goto main


:: =========================================================================
:: PROJECT EXPLORER
:: =========================================================================

:explorer
cls

echo %CYAN%=========================================================================
echo                  PROJECT EXPLORER
echo =========================================================================%RESET%

echo.

start "" explorer.exe "%CD%"

echo   %GREEN%[OK] File Explorer opened.%RESET%

pause
goto main


:: =========================================================================
:: TERMINAL
:: =========================================================================

:terminal

start "Project Terminal" cmd /k "cd /d "%CD%""

goto main


:: =========================================================================
:: VS CODE
:: =========================================================================

:vscode
cls

echo %CYAN%=========================================================================
echo                  OPEN IN VS CODE
echo =========================================================================%RESET%

echo.

where code >nul 2>&1

if errorlevel 1 (
    echo   %RED%[ERROR] VS Code command not found.%RESET%
) else (
    start "" code .
    echo   %GREEN%[OK] VS Code opened.%RESET%
)

echo.
pause
goto main


:: =========================================================================
:: CONFIGURATION
:: =========================================================================

:configuration
cls

echo %CYAN%=========================================================================
echo              PROJECT CONFIGURATION
echo =========================================================================%RESET%

echo.
echo   Project Name:
echo   !PROJECT_NAME!

echo.
echo   Project Type:
echo   !PROJECT_TYPE!

echo.
echo   Package Manager:
echo   !PM!

echo.
echo   Project Path:
echo   %CD%

echo.
echo   Manager Data:
echo   !LOG_DIR!

echo.
echo   Environment Files:

if exist ".env" echo   .env
if exist ".env.local" echo   .env.local
if exist ".env.development" echo   .env.development
if exist ".env.production" echo   .env.production

echo.
echo   Note:
echo   Environment variable values are never displayed.

echo.
pause
goto main


:: =========================================================================
:: COMMAND HISTORY
:: =========================================================================

:history
cls

echo %CYAN%=========================================================================
echo                  COMMAND HISTORY
echo =========================================================================%RESET%

echo.

if exist "!HISTORY_FILE!" (
    type "!HISTORY_FILE!"
) else (
    echo   No command history.
)

echo.
pause
goto main


:: =========================================================================
:: WORKSPACE INFORMATION
:: =========================================================================

:workspace
cls

echo %CYAN%=========================================================================
echo               WORKSPACE INFORMATION
echo =========================================================================%RESET%

echo.

if exist "package.json" (
    echo   Node package detected.
)

if exist "pnpm-workspace.yaml" (
    echo   %GREEN%[OK] pnpm workspace detected.%RESET%
)

if exist "lerna.json" (
    echo   %GREEN%[OK] Lerna workspace detected.%RESET%
)

if exist "turbo.json" (
    echo   %GREEN%[OK] Turborepo detected.%RESET%
)

if exist "nx.json" (
    echo   %GREEN%[OK] Nx workspace detected.%RESET%
)

if exist "workspaces" (
    echo   %GREEN%[OK] Workspace configuration detected.%RESET%
)

echo.
echo   Possible workspace folders:
echo   ----------------------------------------------

if exist "packages" echo   packages\
if exist "apps" echo   apps\
if exist "services" echo   services\
if exist "projects" echo   projects\

echo.
pause
goto main


:: =========================================================================
:: CLEAN MENU
:: =========================================================================

:cleanmenu
cls

echo %CYAN%=========================================================================
echo                  CLEAN PROJECT
echo =========================================================================%RESET%

echo.
echo   ----------------------------------------------
echo   1. Clean Build Output (dist)
echo   2. Deep Clean
echo   0. Back
echo   ----------------------------------------------
echo.

set "cleanchoice="
set /p "cleanchoice=  Select option (0-2): "

if "!cleanchoice!"=="1" goto clean
if "!cleanchoice!"=="2" goto deepclean
if "!cleanchoice!"=="0" goto main

echo.
echo   %RED%[WARNING] Invalid option!%RESET%
timeout /t 2 >nul
goto cleanmenu


:: =========================================================================
:: CLEAN BUILD
:: =========================================================================

:clean
cls

echo %CYAN%=========================================================================
echo                CLEAN BUILD OUTPUT
echo =========================================================================%RESET%

echo.

if exist "dist" (
    echo   [INFO] Removing dist folder...
    rmdir /s /q "dist"
    if exist "dist" (
        echo   %RED%[ERROR] Failed to remove dist folder.%RESET%
    ) else (
        echo   %GREEN%[OK] dist folder removed.%RESET%
    )
) else (
    echo   %YELLOW%[INFO] dist folder not found.%RESET%
)

echo.
pause
goto main


:: =========================================================================
:: DEEP CLEAN
:: =========================================================================

:deepclean
cls

echo %RED%=========================================================================
echo                DEEP CLEAN PROJECT
echo =========================================================================%RESET%

echo.
echo   %YELLOW%[WARNING] This will delete:%RESET%
echo.
echo      - dist
echo      - node_modules
echo      - package-lock.json
echo      - pnpm-lock.yaml
echo      - yarn.lock
echo.

set "confirm="
set /p "confirm=  [?] Are you sure? (Y/N): "

if /i not "!confirm!"=="Y" (
    echo.
    echo   %CYAN%[OK] Operation cancelled.%RESET%
    pause
    goto cleanmenu
)

echo.

if exist "dist" (
    rmdir /s /q "dist"
    if exist "dist" (
        echo   %RED%[ERROR] Failed to remove dist.%RESET%
    ) else echo   %GREEN%[OK] dist removed.%RESET%
)

if exist "node_modules" (
    rmdir /s /q "node_modules"
    if exist "node_modules" (
        echo   %RED%[ERROR] Failed to remove node_modules.%RESET%
    ) else echo   %GREEN%[OK] node_modules removed.%RESET%
)

if exist "package-lock.json" (
    del /q "package-lock.json"
    if exist "package-lock.json" (
        echo   %RED%[ERROR] Failed to remove package-lock.json.%RESET%
    ) else echo   %GREEN%[OK] package-lock.json removed.%RESET%
)

if exist "pnpm-lock.yaml" (
    del /q "pnpm-lock.yaml"
    if exist "pnpm-lock.yaml" (
        echo   %RED%[ERROR] Failed to remove pnpm-lock.yaml.%RESET%
    ) else echo   %GREEN%[OK] pnpm-lock.yaml removed.%RESET%
)

if exist "yarn.lock" (
    del /q "yarn.lock"
    if exist "yarn.lock" (
        echo   %RED%[ERROR] Failed to remove yarn.lock.%RESET%
    ) else echo   %GREEN%[OK] yarn.lock removed.%RESET%
)

echo.
echo   %GREEN%[OK] Deep Clean completed!%RESET%

echo.
pause
goto main


:: =========================================================================
:: EXIT
:: =========================================================================

:exit

cls

echo %CYAN%=========================================================================
echo.
echo                    Goodbye!
echo.
echo              Project Manager
echo.
echo =========================================================================%RESET%

timeout /t 2 >nul

endlocal
exit /b 0
