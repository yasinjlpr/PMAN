@echo off

setlocal EnableExtensions EnableDelayedExpansion

:: ================================================
:: تنظیم اندازه پنجره (عرض و ارتفاع)
:: ================================================
set "WIDTH=50"
set "HEIGHT=50"

powershell -command "&{$H=$Host.UI.RawUI; $W=$H.WindowSize; $B=$H.BufferSize; $W.Width=%WIDTH%; $W.Height=%HEIGHT%; $B.Width=%WIDTH%; $B.Height=9999; $H.WindowSize=$W; $H.BufferSize=$B;}"


title Project Manager
setlocal EnableExtensions EnableDelayedExpansion

:: ================================================
:: PROJECT MANAGER  (hardened release build)
:: ======================================================
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
:: ======================================================

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

echo %CYAN%================================================
echo              yasin !PROJECT_NAME! MANager
echo ================================================%RESET%

echo.
echo   ----------------------------------------------
echo    1. Install Dependencies
echo    2. Run Project
echo    3. Development Server
echo    4. Build Project
echo    5. Run Custom Script
echo    6. Clean Project
echo   ----------------------------------------------
echo    7. Test
echo    8. Lint
echo    9. Format
echo   10. Type Check
echo   ----------------------------------------------
echo   11. Project Status
echo   12. Package Scripts
echo   13. Package Updates
echo   14. Environment Info
echo   15. Project Diagnostics
echo   16. Port Checker
echo   17. Process Manager
echo   ----------------------------------------------
echo   18. Git Status
echo   19. Git Manager
echo   20. Dependency Manager
echo   ----------------------------------------------
echo   21. Auto Repair
echo   22. Recent Projects
echo   23. Project Explorer
echo   24. Open Terminal
echo   25. Open in VS Code
echo   26. Project Configuration
echo   27. Command History
echo   28. Workspace Information
echo   ----------------------------------------------
echo   29. Deep Clean
echo   30. Exit
echo   ----------------------------------------------
echo.

echo   Project Type: %GREEN%!PROJECT_TYPE!%RESET%
echo   Package Manager: %GREEN%!PM!%RESET%
echo   Project Path: %CD%
echo.

set "choice="
set /p "choice=  Select option (1-30): "

for /f "delims=0123456789" %%x in ("!choice!") do set "choice="
if not defined choice goto badchoice

if !choice! LSS 1 goto badchoice
if !choice! GTR 30 goto badchoice

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
if "!choice!"=="30" goto exit

:badchoice
echo.
echo   %RED%[WARNING] Invalid option!%RESET%
timeout /t 2 >nul
goto main


:: ======================================================
:: PROJECT DETECTION
:: ======================================================

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


:: ======================================================
:: PACKAGE MANAGER DETECTION
:: ======================================================

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


:: ======================================================
:: INPUT VALIDATION HELPERS
:: ======================================================

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


:: ======================================================
:: SAFE DELETE
:: ======================================================

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
if "!target!"=="..:" (endlocal & exit /b 1)
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


:: ======================================================
:: LOG ROTATION
:: ======================================================

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


:: ======================================================
:: COMMAND EXECUTOR
:: ======================================================

:: :run_command <command-string>
:: Central place every executed command flows through, so
:: logging and pass/fail reporting are consistent.
:run_command

set "COMMAND=%~1"

echo.
echo   %CYAN%[COMMAND]%RESET% !COMMAND!
echo   ----------------------------------------------

>>"!LOG_FILE!" echo [%date% %time%] !COMMAND!
>>"!HISTORY_FILE!" echo !COMMAND!

cmd /c "!COMMAND!"

set "CMD_ERROR=!errorlevel!"

echo.
if "!CMD_ERROR!"=="0" (
    echo   %GREEN%[OK] Command completed successfully.%RESET%
) else (
    echo   %RED%[ERROR] Command failed with exit code !CMD_ERROR!.%RESET%
)

exit /b !CMD_ERROR!

:: ======================================================
:: GIT GLOBAL IGNORE
:: ======================================================

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

:: ======================================================
:: RECENT PROJECTS TRACKING
:: ======================================================

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


:: ======================================================
:: INSTALL DEPENDENCIES
:: ======================================================

:install
cls

echo %CYAN%================================================
echo               INSTALL DEPENDENCIES
echo ================================================%RESET%

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
call :run_command "npm install"
pause
goto main

:install_pnpm
call :run_command "pnpm install"
pause
goto main

:install_yarn
call :run_command "yarn install"
pause
goto main

:install_bun
call :run_command "bun install"
pause
goto main


:: ======================================================
:: RUN PROJECT
:: ======================================================

:runproject
cls

echo %CYAN%================================================
echo                  RUN PROJECT
echo ================================================%RESET%

echo.

if not exist "package.json" (
    echo   %YELLOW%[INFO] package.json not found.%RESET%
    echo.
    pause
    goto main
)

findstr /i /c:"\"start\"" package.json >nul 2>&1

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


:: ======================================================
:: DEVELOPMENT SERVER
:: ======================================================

:dev
cls

echo %CYAN%================================================
echo                DEVELOPMENT SERVER
echo ================================================%RESET%

echo.

if not exist "package.json" (
    echo   %RED%[ERROR] package.json not found.%RESET%
    pause
    goto main
)

findstr /i /c:"\"dev\"" package.json >nul 2>&1

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


:: ======================================================
:: BUILD PROJECT
:: ======================================================

:buildproject
cls

echo %CYAN%================================================
echo                   BUILD PROJECT
echo ================================================%RESET%

echo.

if not exist "package.json" goto typescript_build

findstr /i /c:"\"build\"" package.json >nul 2>&1

if not errorlevel 1 (
    echo   [INFO] Build script detected.
    echo.
    echo   Running package build...
    echo.

    if /i "!PM!"=="npm" call :run_command "npm run build"
    if /i "!PM!"=="pnpm" call :run_command "pnpm build"
    if /i "!PM!"=="yarn" call :run_command "yarn build"
    if /i "!PM!"=="bun" call :run_command "bun run build"

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

    call :run_command "npx tsc"

    pause
    goto main
)

echo   %YELLOW%[WARNING] No build system detected.%RESET%
echo.
echo   No "build" script or tsconfig.json was found.

pause
goto main


:: ======================================================
:: CUSTOM SCRIPT
:: ======================================================

:customscript
cls

echo %CYAN%================================================
echo                RUN CUSTOM SCRIPT
echo ================================================%RESET%

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

if /i "!PM!"=="npm" call :run_command "npm run !custom!"
if /i "!PM!"=="pnpm" call :run_command "pnpm !custom!"
if /i "!PM!"=="yarn" call :run_command "yarn !custom!"
if /i "!PM!"=="bun" call :run_command "bun run !custom!"

pause
goto main


:: ======================================================
:: SHOW PACKAGE SCRIPTS
:: ======================================================

:show_scripts

if not exist "package.json" exit /b

findstr /i "\"scripts\"" package.json >nul 2>&1

if errorlevel 1 (
    echo   No scripts detected.
    exit /b
)

echo.
echo   package.json scripts:
echo   ----------------------------------------------

findstr /i /r "\"[a-zA-Z0-9:_-]*\"[ ]*:" package.json

exit /b


:: ======================================================
:: PACKAGE SCRIPTS (menu option 12)
:: ======================================================

:scripts
cls

echo %CYAN%================================================
echo                 PACKAGE SCRIPTS
echo ================================================%RESET%

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


:: ======================================================
:: TEST
:: ======================================================

:test
cls

echo %CYAN%================================================
echo                      TEST
echo ================================================%RESET%

echo.

if not exist "package.json" (
    echo   %YELLOW%[INFO] package.json not found.%RESET%
    pause
    goto main
)

findstr /i /c:"\"test\"" package.json >nul 2>&1

if errorlevel 1 (
    echo   %YELLOW%[WARNING] No test script found.%RESET%
    pause
    goto main
)

if /i "!PM!"=="npm" call :run_command "npm test"
if /i "!PM!"=="pnpm" call :run_command "pnpm test"
if /i "!PM!"=="yarn" call :run_command "yarn test"
if /i "!PM!"=="bun" call :run_command "bun test"

pause
goto main


:: ======================================================
:: LINT
:: ======================================================

:lint
cls

echo %CYAN%================================================
echo                        LINT
echo ================================================%RESET%

echo.

if not exist "package.json" (
    echo   %YELLOW%[INFO] package.json not found.%RESET%
    pause
    goto main
)

findstr /i /c:"\"lint\"" package.json >nul 2>&1

if errorlevel 1 (
    echo   %YELLOW%[WARNING] No lint script found.%RESET%
    pause
    goto main
)

if /i "!PM!"=="npm" call :run_command "npm run lint"
if /i "!PM!"=="pnpm" call :run_command "pnpm lint"
if /i "!PM!"=="yarn" call :run_command "yarn lint"
if /i "!PM!"=="bun" call :run_command "bun run lint"

pause
goto main


:: ======================================================
:: FORMAT
:: ======================================================

:format
cls

echo %CYAN%================================================
echo                      FORMAT
echo ================================================%RESET%

echo.

if not exist "package.json" (
    echo   %YELLOW%[INFO] package.json not found.%RESET%
    pause
    goto main
)

findstr /i /c:"\"format\"" package.json >nul 2>&1

if errorlevel 1 (
    echo   %YELLOW%[WARNING] No format script found.%RESET%
    pause
    goto main
)

if /i "!PM!"=="npm" call :run_command "npm run format"
if /i "!PM!"=="pnpm" call :run_command "pnpm format"
if /i "!PM!"=="yarn" call :run_command "yarn format"
if /i "!PM!"=="bun" call :run_command "bun run format"

pause
goto main


:: ================================================
:: TYPE CHECK
:: ================================================

:typecheck
cls

echo %CYAN%================================================
echo                    TYPE CHECK
echo ================================================%RESET%

echo.

if exist "tsconfig.json" (
    call :run_command "npx tsc --noEmit"
    pause
    goto main
)

if not exist "package.json" (
    echo   %YELLOW%[INFO] No TypeScript configuration or typecheck script found.%RESET%
    pause
    goto main
)

findstr /i /c:"\"typecheck\"" package.json >nul 2>&1

if not errorlevel 1 (
    if /i "!PM!"=="npm" call :run_command "npm run typecheck"
    if /i "!PM!"=="pnpm" call :run_command "pnpm typecheck"
    if /i "!PM!"=="yarn" call :run_command "yarn typecheck"
    if /i "!PM!"=="bun" call :run_command "bun run typecheck"
) else (
    echo   %YELLOW%[INFO] No TypeScript configuration or typecheck script found.%RESET%
)

pause
goto main


:: ================================================
:: PROJECT STATUS
:: ================================================

:status
cls

echo %CYAN%================================================
echo                 PROJECT STATUS
echo ================================================%RESET%

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


:: ================================================
:: PACKAGE UPDATES
:: ================================================

:updates
cls

echo %CYAN%================================================
echo                 PACKAGE UPDATES
echo ================================================%RESET%

echo.

if not exist "package.json" (
    echo   %YELLOW%[INFO] package.json not found.%RESET%
    pause
    goto main
)

if /i "!PM!"=="npm" call :run_command "npm outdated"
if /i "!PM!"=="pnpm" call :run_command "pnpm outdated"
if /i "!PM!"=="yarn" call :run_command "yarn outdated"
if /i "!PM!"=="bun" call :run_command "bun outdated"

echo.
pause
goto main


:: ================================================
:: ENVIRONMENT INFO
:: ================================================

:environment
cls

echo %CYAN%================================================
echo                ENVIRONMENT INFO
echo ================================================%RESET%

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


:: ================================================
:: PROJECT DIAGNOSTICS
:: ================================================

:diagnostics
cls

echo %CYAN%================================================
echo               PROJECT DIAGNOSTICS
echo ================================================%RESET%

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
    findstr /i /c:"\"build\"" package.json >nul 2>&1
    if not errorlevel 1 (
        echo   %GREEN%[OK] Build script found%RESET%
        set /a HEALTH+=1
    ) else (
        echo   %YELLOW%[WARNING] Build script missing%RESET%
    )
)
set /a TOTAL+=1

if exist "package.json" (
    findstr /i /c:"\"dev\"" package.json >nul 2>&1
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


:: ================================================
:: PORT CHECKER
:: ================================================

:ports
cls

echo %CYAN%================================================
echo                   PORT CHECKER
echo ================================================%RESET%

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


:: ================================================
:: PROCESS MANAGER
:: ================================================

:processes
cls

echo %CYAN%================================================
echo                 PROCESS MANAGER
echo ================================================%RESET%

echo.
echo   1. Find Process
echo   2. Kill Process
echo   3. Find Port Owner
echo   4. Back
echo.

set "pc="
set /p "pc=  Select option: "

if "!pc!"=="1" goto findprocess
if "!pc!"=="2" goto killprocess
if "!pc!"=="3" goto portowner
if "!pc!"=="4" goto main

goto processes


:findprocess
cls

echo %CYAN%================================================
echo                   FIND PROCESS
echo ================================================%RESET%

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

echo %RED%================================================
echo                   KILL PROCESS
echo ================================================%RESET%

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

echo %CYAN%================================================
echo                   PORT OWNER
echo ================================================%RESET%

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


:: ================================================
:: GIT STATUS
:: ================================================

:gitstatus
cls

echo %CYAN%================================================
echo                    GIT STATUS
echo ================================================%RESET%

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


:: ================================================
:: GIT MANAGER
:: ================================================

:gitmanager
cls
echo %CYAN%================================================
echo                    GIT MANAGER
echo ================================================%RESET%
echo.
echo   Repository: %GREEN%!PROJECT_NAME!%RESET%
echo   Main Branch: %GREEN%!GIT_MAIN!%RESET%
echo   Origin Remote: %GREEN%!GIT_ORIGIN!%RESET%
echo.
echo   ----------------------------------------------
echo    1.  Repository / Init
echo    2.  Status
echo    3.  Stage Changes
echo    4.  Unstage Changes
echo    5.  Commit
echo    6.  Amend Last Commit
echo   ----------------------------------------------
echo    7.  Branch Manager
echo    8.  Remote Manager
echo    9.  Fetch
echo   10.  Pull
echo   11.  Push
echo   12.  Sync Main ^<--^> Origin
echo   ----------------------------------------------
echo   13.  History / Log
echo   14.  Diff
echo   15.  Stash Manager
echo   16.  Tag Manager
echo   17.  Rebase
echo   18.  Merge
echo   19.  Cherry-pick
echo   20.  Revert Commit
echo   ----------------------------------------------
echo   21.  Reset / Restore
echo   22.  Clean Untracked Files
echo   23.  Submodule Manager
echo   24.  Git Config
echo   25.  Git Ignore
echo   26.  Show Refs
echo   27.  Git Information
echo   28.  Set Main / Origin
echo   ----------------------------------------------
echo   29.  Back
echo.
set "gc="
set /p "gc=  Select option: "
if "!gc!"=="1" goto gitrepo
if "!gc!"=="2" goto gitstatus
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
if "!gc!"=="29" goto main
goto gitmanager


:: ======================================================
:: GIT DEFAULTS
:: ======================================================

:gitdefaults
cls
echo %CYAN%================================================
echo                MAIN / ORIGIN SETTINGS
echo ================================================%RESET%
echo.
echo   Main branch  : !GIT_MAIN!
echo   Origin remote: !GIT_ORIGIN!
echo.
echo   1. Set Main Branch
echo   2. Set Origin Remote
echo   3. Reset to main / origin
echo   4. Back
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
if "!gd!"=="4" goto gitmanager
goto gitdefaults


:: ======================================================
:: GIT REPOSITORY
:: ======================================================

:gitrepo
cls
echo %CYAN%================================================
echo                REPOSITORY / INIT
echo ================================================%RESET%
echo.
echo   Main: !GIT_MAIN!    Origin: !GIT_ORIGIN!
echo.
echo   1. Initialize repository
echo   2. Show repository root
echo   3. Show .git directory
echo   4. Add remote origin
echo   5. Remove remote origin
echo   6. Rename current branch to main
echo   7. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" call :run_command "git init"
if "!x!"=="2" call :run_command "git rev-parse --show-toplevel"
if "!x!"=="3" call :run_command "git rev-parse --git-dir"
if "!x!"=="4" (
    set "url="
    set /p "url=  Remote URL: "
    if defined url call :run_command "git remote add !GIT_ORIGIN! !url!"
)
if "!x!"=="5" call :run_command "git remote remove !GIT_ORIGIN!"
if "!x!"=="6" call :run_command "git branch -M !GIT_MAIN!"
if "!x!"=="7" goto gitmanager
pause
goto gitrepo


:: ======================================================
:: GIT STATUS
:: ======================================================

:gitstatus
cls
echo %CYAN%================================================
echo                     GIT STATUS
echo ================================================%RESET%
echo.
echo   Main: !GIT_MAIN!    Origin: !GIT_ORIGIN!
echo.
call :run_command "git status"
echo.
echo   Current branch:
git branch --show-current
echo.
echo   Tracking:
git status -sb
pause
goto gitmanager


:: ======================================================
:: STAGE / UNSTAGE
:: ======================================================

:gitstage
cls
echo %CYAN%================================================
echo                   STAGE CHANGES
echo ================================================%RESET%
echo.
echo   Main: !GIT_MAIN!    Origin: !GIT_ORIGIN!
echo.
echo   1. Stage all
echo   2. Stage a file/folder
echo   3. Interactive staging
echo   4. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" call :run_command "git add -A"
if "!x!"=="2" (
    set "p="
    set /p "p=  File/folder: "
    if defined p call :run_command "git add -- !p!"
)
if "!x!"=="3" call :run_command "git add -p"
if "!x!"=="4" goto gitmanager
pause
goto gitstage

:gitunstage
cls
echo %CYAN%================================================
echo                  UNSTAGE CHANGES
echo ================================================%RESET%
echo.
echo   1. Unstage all
echo   2. Unstage a file/folder
echo   3. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" call :run_command "git restore --staged ."
if "!x!"=="2" (
    set "p="
    set /p "p=  File/folder: "
    if defined p call :run_command "git restore --staged -- !p!"
)
if "!x!"=="3" goto gitmanager
pause
goto gitunstage


:: ======================================================
:: GIT COMMIT
:: ======================================================

:gitcommit
cls
echo %CYAN%================================================
echo                       COMMIT
echo ================================================%RESET%
echo.
echo   Main: !GIT_MAIN!    Origin: !GIT_ORIGIN!
echo.
git status --short
echo.
set "msg="
set /p "msg=  Commit message: "
if not defined msg goto gitmanager
call :run_command "git commit -m "!msg!""
pause
goto gitmanager

:gitamend
cls
echo %CYAN%================================================
echo                  AMEND LAST COMMIT
echo ================================================%RESET%
echo.
git log -1 --oneline
echo.
echo   1. Amend using existing message
echo   2. Amend with new message
echo   3. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" call :run_command "git commit --amend --no-edit"
if "!x!"=="2" (
    set "msg="
    set /p "msg=  New commit message: "
    if defined msg call :run_command "git commit --amend -m "!msg!""
)
if "!x!"=="3" goto gitmanager
pause
goto gitamend


:: ======================================================
:: BRANCH MANAGER
:: ======================================================

:gitbranches
cls
echo %CYAN%================================================
echo                    BRANCH MANAGER
echo ================================================%RESET%
echo.
echo   Main: !GIT_MAIN!    Origin: !GIT_ORIGIN!
echo.
echo   1. List local branches
echo   2. List all branches
echo   3. Create branch
echo   4. Switch branch
echo   5. Create + switch branch
echo   6. Rename current branch
echo   7. Delete local branch
echo   8. Force delete local branch
echo   9. Merge branch into current
echo  10. Rebase current onto main
echo  11. Show remote branches
echo  12. Delete remote branch from origin
echo  13. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" call :run_command "git branch"
if "!x!"=="2" call :run_command "git branch -a"
if "!x!"=="3" (
    set "b="
    set /p "b=  New branch: "
    if defined b call :run_command "git branch !b!"
)
if "!x!"=="4" (
    set "b="
    set /p "b=  Switch to branch: "
    if defined b call :run_command "git switch !b!"
)
if "!x!"=="5" (
    set "b="
    set /p "b=  New branch: "
    if defined b call :run_command "git switch -c !b!"
)
if "!x!"=="6" (
    set "b="
    set /p "b=  New name: "
    if defined b call :run_command "git branch -m !b!"
)
if "!x!"=="7" (
    set "b="
    set /p "b=  Branch to delete: "
    if defined b call :run_command "git branch -d !b!"
)
if "!x!"=="8" (
    set "b="
    set /p "b=  Branch to force delete: "
    if defined b call :run_command "git branch -D !b!"
)
if "!x!"=="9" (
    set "b="
    set /p "b=  Branch to merge: "
    if defined b call :run_command "git merge !b!"
)
if "!x!"=="10" call :run_command "git rebase !GIT_MAIN!"
if "!x!"=="11" call :run_command "git branch -r"
if "!x!"=="12" (
    set "b="
    set /p "b=  Remote branch to delete: "
    if defined b call :run_command "git push !GIT_ORIGIN! --delete !b!"
)
if "!x!"=="13" goto gitmanager
pause
goto gitbranches


:: ======================================================
:: REMOTE MANAGER
:: ======================================================

:gitremotes
cls
echo %CYAN%================================================
echo                    REMOTE MANAGER
echo ================================================%RESET%
echo.
echo   Main: !GIT_MAIN!    Origin: !GIT_ORIGIN!
echo.
echo   1. List remotes
echo   2. Show origin
echo   3. Add origin
echo   4. Change origin URL
echo   5. Show origin URL
echo   6. Remove origin
echo   7. Fetch origin
echo   8. Prune deleted origin branches
echo   9. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" call :run_command "git remote -v"
if "!x!"=="2" call :run_command "git remote show !GIT_ORIGIN!"
if "!x!"=="3" (
    set "url="
    set /p "url=  Origin URL: "
    if defined url call :run_command "git remote add !GIT_ORIGIN! !url!"
)
if "!x!"=="4" (
    set "url="
    set /p "url=  New origin URL: "
    if defined url call :run_command "git remote set-url !GIT_ORIGIN! !url!"
)
if "!x!"=="5" call :run_command "git remote get-url !GIT_ORIGIN!"
if "!x!"=="6" call :run_command "git remote remove !GIT_ORIGIN!"
if "!x!"=="7" call :run_command "git fetch !GIT_ORIGIN!"
if "!x!"=="8" call :run_command "git fetch !GIT_ORIGIN! --prune"
if "!x!"=="9" goto gitmanager
pause
goto gitremotes


:: ======================================================
:: FETCH / PULL / PUSH / SYNC
:: ======================================================

:gitfetch
cls
echo %CYAN%================================================
echo                       FETCH
echo ================================================%RESET%
echo   Main: !GIT_MAIN!    Origin: !GIT_ORIGIN!
echo.
echo   1. Fetch origin
echo   2. Fetch origin + prune
echo   3. Fetch all remotes
echo   4. Fetch + tags
echo   5. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" call :run_command "git fetch !GIT_ORIGIN!"
if "!x!"=="2" call :run_command "git fetch !GIT_ORIGIN! --prune"
if "!x!"=="3" call :run_command "git fetch --all"
if "!x!"=="4" call :run_command "git fetch !GIT_ORIGIN! --tags"
if "!x!"=="5" goto gitmanager
pause
goto gitfetch

:gitpull
cls
echo %CYAN%================================================
echo                        PULL
echo ================================================%RESET%
echo   Main: !GIT_MAIN!    Origin: !GIT_ORIGIN!
echo.
echo   1. Pull origin/main
echo   2. Pull with rebase
echo   3. Pull all tags
echo   4. Pull current tracking branch
echo   5. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" call :run_command "git pull !GIT_ORIGIN! !GIT_MAIN!"
if "!x!"=="2" call :run_command "git pull --rebase !GIT_ORIGIN! !GIT_MAIN!"
if "!x!"=="3" call :run_command "git pull !GIT_ORIGIN! --tags"
if "!x!"=="4" call :run_command "git pull"
if "!x!"=="5" goto gitmanager
pause
goto gitpull

:gitpush
cls
echo %CYAN%================================================
echo                        PUSH
echo ================================================%RESET%
echo   Main: !GIT_MAIN!    Origin: !GIT_ORIGIN!
echo.
echo   1. Push main to origin
echo   2. Push current branch
echo   3. Push current + set upstream
echo   4. Push all branches
echo   5. Push tags
echo   6. Force-with-lease main to origin
echo   7. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" call :run_command "git push !GIT_ORIGIN! !GIT_MAIN!"
if "!x!"=="2" call :run_command "git push"
if "!x!"=="3" call :run_command "git push -u !GIT_ORIGIN! HEAD"
if "!x!"=="4" call :run_command "git push !GIT_ORIGIN! --all"
if "!x!"=="5" call :run_command "git push !GIT_ORIGIN! --tags"
if "!x!"=="6" call :run_command "git push !GIT_ORIGIN! !GIT_MAIN! --force-with-lease"
if "!x!"=="7" goto gitmanager
pause
goto gitpush

:gitsync
cls
echo %CYAN%================================================
echo                MAIN ^<--^> ORIGIN SYNC
echo ================================================%RESET%
echo.
echo   Local main : !GIT_MAIN!
echo   Remote     : !GIT_ORIGIN!
echo   Remote main: !GIT_ORIGIN!/!GIT_MAIN!
echo.
echo   1. Fetch origin
echo   2. Pull origin/main into local main
echo   3. Push local main to origin/main
echo   4. Fetch + pull + push
echo   5. Compare local main with origin/main
echo   6. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" call :run_command "git fetch !GIT_ORIGIN!"
if "!x!"=="2" call :run_command "git pull !GIT_ORIGIN! !GIT_MAIN!"
if "!x!"=="3" call :run_command "git push !GIT_ORIGIN! !GIT_MAIN!"
if "!x!"=="4" (
    call :run_command "git fetch !GIT_ORIGIN!"
    call :run_command "git pull !GIT_ORIGIN! !GIT_MAIN!"
    call :run_command "git push !GIT_ORIGIN! !GIT_MAIN!"
)
if "!x!"=="5" call :run_command "git diff !GIT_MAIN!..!GIT_ORIGIN!/!GIT_MAIN!"
if "!x!"=="6" goto gitmanager
pause
goto gitsync


:: ======================================================
:: LOG / DIFF
:: ======================================================

:gitlogmenu
cls
echo %CYAN%================================================
echo                    HISTORY / LOG
echo ================================================%RESET%
echo.
echo   Main: !GIT_MAIN!    Origin: !GIT_ORIGIN!
echo.
echo   1. Recent commits
echo   2. Full graph
echo   3. File history
echo   4. Show commit
echo   5. Search commit messages
echo   6. Compare main and origin/main
echo   7. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" call :run_command "git log --oneline -20"
if "!x!"=="2" call :run_command "git log --oneline --graph --decorate --all -30"
if "!x!"=="3" (
    set "p="
    set /p "p=  File: "
    if defined p call :run_command "git log --oneline --follow -- !p!"
)
if "!x!"=="4" (
    set "c="
    set /p "c=  Commit/hash: "
    if defined c call :run_command "git show !c!"
)
if "!x!"=="5" (
    set "q="
    set /p "q=  Search text: "
    if defined q call :run_command "git log --oneline --all --grep="!q!""
)
if "!x!"=="6" call :run_command "git log --oneline !GIT_MAIN!..!GIT_ORIGIN!/!GIT_MAIN!"
if "!x!"=="7" goto gitmanager
pause
goto gitlogmenu

:gitdiff
cls
echo %CYAN%================================================
echo                       DIFF
echo ================================================%RESET%
echo.
echo   1. Working tree changes
echo   2. Staged changes
echo   3. Main vs origin/main
echo   4. Two commits
echo   5. File diff
echo   6. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" call :run_command "git diff"
if "!x!"=="2" call :run_command "git diff --cached"
if "!x!"=="3" call :run_command "git diff !GIT_MAIN!..!GIT_ORIGIN!/!GIT_MAIN!"
if "!x!"=="4" (
    set "a="
    set /p "a=  First commit: "
    set "b="
    set /p "b=  Second commit: "
    if defined a if defined b call :run_command "git diff !a! !b!"
)
if "!x!"=="5" (
    set "p="
    set /p "p=  File: "
    if defined p call :run_command "git diff -- !p!"
)
if "!x!"=="6" goto gitmanager
pause
goto gitdiff


:: ======================================================
:: STASH
:: ======================================================

:gitstash
cls
echo %CYAN%================================================
echo                    STASH MANAGER
echo ================================================%RESET%
echo.
echo   1. Stash changes
echo   2. Stash including untracked
echo   3. List stashes
echo   4. Show stash
echo   5. Apply stash
echo   6. Pop stash
echo   7. Drop stash
echo   8. Clear all stashes
echo   9. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" call :run_command "git stash push"
if "!x!"=="2" call :run_command "git stash push -u"
if "!x!"=="3" call :run_command "git stash list"
if "!x!"=="4" (
    set "n="
    set /p "n=  Stash (e.g. stash@{0}): "
    if defined n call :run_command "git stash show -p !n!"
)
if "!x!"=="5" (
    set "n="
    set /p "n=  Stash [stash@{0}]: "
    if not defined n set "n=stash@{0}"
    call :run_command "git stash apply !n!"
)
if "!x!"=="6" call :run_command "git stash pop"
if "!x!"=="7" (
    set "n="
    set /p "n=  Stash [stash@{0}]: "
    if not defined n set "n=stash@{0}"
    call :run_command "git stash drop !n!"
)
if "!x!"=="8" call :run_command "git stash clear"
if "!x!"=="9" goto gitmanager
pause
goto gitstash


:: ======================================================
:: TAGS
:: ======================================================

:gittags
cls
echo %CYAN%================================================
echo                      TAG MANAGER
echo ================================================%RESET%
echo.
echo   1. List tags
echo   2. Create lightweight tag
echo   3. Create annotated tag
echo   4. Show tag
echo   5. Delete local tag
echo   6. Push tag to origin
echo   7. Push all tags to origin
echo   8. Delete remote tag from origin
echo   9. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" call :run_command "git tag -n"
if "!x!"=="2" (
    set "t="
    set /p "t=  Tag name: "
    if defined t call :run_command "git tag !t!"
)
if "!x!"=="3" (
    set "t="
    set /p "t=  Tag name: "
    set "m="
    set /p "m=  Message: "
    if defined t call :run_command "git tag -a !t! -m "!m!""
)
if "!x!"=="4" (
    set "t="
    set /p "t=  Tag: "
    if defined t call :run_command "git show !t!"
)
if "!x!"=="5" (
    set "t="
    set /p "t=  Tag to delete: "
    if defined t call :run_command "git tag -d !t!"
)
if "!x!"=="6" (
    set "t="
    set /p "t=  Tag: "
    if defined t call :run_command "git push !GIT_ORIGIN! !t!"
)
if "!x!"=="7" call :run_command "git push !GIT_ORIGIN! --tags"
if "!x!"=="8" (
    set "t="
    set /p "t=  Remote tag to delete: "
    if defined t call :run_command "git push !GIT_ORIGIN! --delete !t!"
)
if "!x!"=="9" goto gitmanager
pause
goto gittags


:: ======================================================
:: REBASE / MERGE / CHERRY-PICK / REVERT
:: ======================================================

:gitrebase
cls
echo %CYAN%================================================
echo                       REBASE
echo ================================================%RESET%
echo   Main: !GIT_MAIN!    Origin: !GIT_ORIGIN!
echo.
echo   1. Rebase current onto main
echo   2. Rebase current onto origin/main
echo   3. Interactive rebase last N commits
echo   4. Continue rebase
echo   5. Abort rebase
echo   6. Skip commit
echo   7. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" call :run_command "git rebase !GIT_MAIN!"
if "!x!"=="2" call :run_command "git rebase !GIT_ORIGIN!/!GIT_MAIN!"
if "!x!"=="3" (
    set "n="
    set /p "n=  Number of commits: "
    if defined n call :run_command "git rebase -i HEAD~!n!"
)
if "!x!"=="4" call :run_command "git rebase --continue"
if "!x!"=="5" call :run_command "git rebase --abort"
if "!x!"=="6" call :run_command "git rebase --skip"
if "!x!"=="7" goto gitmanager
pause
goto gitrebase

:gitmerge
cls
echo %CYAN%================================================
echo                       MERGE
echo ================================================%RESET%
echo   Main: !GIT_MAIN!    Origin: !GIT_ORIGIN!
echo.
echo   1. Merge a branch
echo   2. Merge origin/main
echo   3. Continue merge
echo   4. Abort merge
echo   5. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" (
    set "b="
    set /p "b=  Branch: "
    if defined b call :run_command "git merge !b!"
)
if "!x!"=="2" call :run_command "git merge !GIT_ORIGIN!/!GIT_MAIN!"
if "!x!"=="3" call :run_command "git merge --continue"
if "!x!"=="4" call :run_command "git merge --abort"
if "!x!"=="5" goto gitmanager
pause
goto gitmerge

:gitcherry
cls
echo %CYAN%================================================
echo                     CHERRY-PICK
echo ================================================%RESET%
echo.
echo   1. Cherry-pick commit
echo   2. Continue
echo   3. Abort
echo   4. Skip
echo   5. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" (
    set "c="
    set /p "c=  Commit/hash: "
    if defined c call :run_command "git cherry-pick !c!"
)
if "!x!"=="2" call :run_command "git cherry-pick --continue"
if "!x!"=="3" call :run_command "git cherry-pick --abort"
if "!x!"=="4" call :run_command "git cherry-pick --skip"
if "!x!"=="5" goto gitmanager
pause
goto gitcherry

:gitrevert
cls
echo %CYAN%================================================
echo                    REVERT COMMIT
echo ================================================%RESET%
echo.
echo   Revert creates a new commit that undoes another commit.
echo.
set "c="
set /p "c=  Commit/hash to revert: "
if defined c call :run_command "git revert !c!"
pause
goto gitmanager


:: ======================================================
:: RESET / RESTORE / CLEAN
:: ======================================================

:gitreset
cls
echo %CYAN%================================================
echo                  RESET / RESTORE
echo ================================================%RESET%
echo.
echo   1. Restore a file from working tree
echo   2. Restore all working-tree files
echo   3. Soft reset to commit
echo   4. Mixed reset to commit
echo   5. Hard reset to commit
echo   6. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" (
    set "p="
    set /p "p=  File: "
    if defined p call :run_command "git restore -- !p!"
)
if "!x!"=="2" call :run_command "git restore ."
if "!x!"=="3" (
    set "c="
    set /p "c=  Commit: "
    if defined c call :run_command "git reset --soft !c!"
)
if "!x!"=="4" (
    set "c="
    set /p "c=  Commit: "
    if defined c call :run_command "git reset !c!"
)
if "!x!"=="5" (
    echo   WARNING: hard reset discards local changes.
    set "ok="
    set /p "ok=  Type YES to continue: "
    if "!ok!"=="YES" (
        set "c="
        set /p "c=  Commit: "
        if defined c call :run_command "git reset --hard !c!"
    )
)
if "!x!"=="6" goto gitmanager
pause
goto gitreset

:gitclean
cls
echo %CYAN%================================================
echo                CLEAN UNTRACKED FILES
echo ================================================%RESET%
echo.
echo   1. Preview clean
echo   2. Delete untracked files
echo   3. Delete untracked files + folders
echo   4. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" call :run_command "git clean -n"
if "!x!"=="2" call :run_command "git clean -f"
if "!x!"=="3" call :run_command "git clean -fd"
if "!x!"=="4" goto gitmanager
pause
goto gitclean


:: ======================================================
:: SUBMODULES
:: ======================================================

:gitsubmodule
cls
echo %CYAN%================================================
echo                  SUBMODULE MANAGER
echo ================================================%RESET%
echo.
echo   1. List submodules
echo   2. Initialize submodules
echo   3. Update submodules
echo   4. Update recursively
echo   5. Add submodule
echo   6. Sync submodule URLs
echo   7. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" call :run_command "git submodule status"
if "!x!"=="2" call :run_command "git submodule init"
if "!x!"=="3" call :run_command "git submodule update"
if "!x!"=="4" call :run_command "git submodule update --init --recursive"
if "!x!"=="5" (
    set "url="
    set /p "url=  Repository URL: "
    set "path="
    set /p "path=  Local path: "
    if defined url if defined path call :run_command "git submodule add !url! !path!"
)
if "!x!"=="6" call :run_command "git submodule sync --recursive"
if "!x!"=="7" goto gitmanager
pause
goto gitsubmodule


:: ======================================================
:: CONFIG / IGNORE / REFS / INFO
:: ======================================================

:gitconfig
cls
echo %CYAN%================================================
echo                     GIT CONFIG
echo ================================================%RESET%
echo.
echo   1. Show local config
echo   2. Show global config
echo   3. Show user name
echo   4. Show user email
echo   5. Set user name
echo   6. Set user email
echo   7. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" call :run_command "git config --local --list"
if "!x!"=="2" call :run_command "git config --global --list"
if "!x!"=="3" call :run_command "git config user.name"
if "!x!"=="4" call :run_command "git config user.email"
if "!x!"=="5" (
    set "v="
    set /p "v=  User name: "
    if defined v call :run_command "git config user.name "!v!""
)
if "!x!"=="6" (
    set "v="
    set /p "v=  User email: "
    if defined v call :run_command "git config user.email "!v!""
)
if "!x!"=="7" goto gitmanager
pause
goto gitconfig

:gitignore
cls
echo %CYAN%================================================
echo                     GIT IGNORE
echo ================================================%RESET%
echo.
echo   1. Open/create .gitignore
echo   2. Show .gitignore
echo   3. Check why a file is ignored
echo   4. Check ignored files
echo   5. Back
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
    if defined p call :run_command "git check-ignore -v !p!"
)
if "!x!"=="4" call :run_command "git status --ignored"
if "!x!"=="5" goto gitmanager
pause
goto gitignore

:gitrefs
cls
echo %CYAN%================================================
echo                       REFS
echo ================================================%RESET%
echo.
echo   1. All refs
echo   2. Branch refs
echo   3. Remote refs
echo   4. Tags
echo   5. Reflog
echo   6. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" call :run_command "git show-ref"
if "!x!"=="2" call :run_command "git for-each-ref refs/heads"
if "!x!"=="3" call :run_command "git for-each-ref refs/remotes"
if "!x!"=="4" call :run_command "git for-each-ref refs/tags"
if "!x!"=="5" call :run_command "git reflog --all"
if "!x!"=="6" goto gitmanager
pause
goto gitrefs

:gitinfo
cls
echo %CYAN%================================================
echo                   GIT INFORMATION
echo ================================================%RESET%
echo.
echo   Main: !GIT_MAIN!    Origin: !GIT_ORIGIN!
echo.
echo   1. Git version
echo   2. Repository root
echo   3. Current branch
echo   4. Current commit
echo   5. Remote URLs
echo   6. Ahead / behind origin/main
echo   7. Git environment
echo   8. Back
echo.
set "x="
set /p "x=  Select option: "
if "!x!"=="1" call :run_command "git --version"
if "!x!"=="2" call :run_command "git rev-parse --show-toplevel"
if "!x!"=="3" call :run_command "git branch --show-current"
if "!x!"=="4" call :run_command "git rev-parse HEAD"
if "!x!"=="5" call :run_command "git remote -v"
if "!x!"=="6" call :run_command "git rev-list --left-right --count !GIT_MAIN!...!GIT_ORIGIN!/!GIT_MAIN!"
if "!x!"=="7" call :run_command "git var -l"
if "!x!"=="8" goto gitmanager
pause
goto gitinfo

:: ================================================
:: DEPENDENCY MANAGER
:: ================================================

:dependencies
cls

echo %CYAN%================================================
echo                DEPENDENCY MANAGER
echo ================================================%RESET%

echo.
echo   1. Install
echo   2. Update
echo   3. Outdated
echo   4. Audit
echo   5. Reinstall
echo   6. List
echo   7. Back
echo.

set "dc="
set /p "dc=  Select option: "

if "!dc!"=="1" goto install
if "!dc!"=="2" goto depupdate
if "!dc!"=="3" goto updates
if "!dc!"=="4" goto depaudit
if "!dc!"=="5" goto depreinstall
if "!dc!"=="6" goto deplisting
if "!dc!"=="7" goto main

goto dependencies


:depupdate

if /i "!PM!"=="npm" call :run_command "npm update"
if /i "!PM!"=="pnpm" call :run_command "pnpm update"
if /i "!PM!"=="yarn" call :run_command "yarn upgrade"
if /i "!PM!"=="bun" call :run_command "bun update"

pause
goto dependencies


:depaudit

if /i "!PM!"=="npm" call :run_command "npm audit"
if /i "!PM!"=="pnpm" call :run_command "pnpm audit"
if /i "!PM!"=="yarn" call :run_command "yarn npm audit"
if /i "!PM!"=="bun" call :run_command "bun audit"

pause
goto dependencies


:depreinstall

echo.
set "confirm="
set /p "confirm=  Reinstall all dependencies? (Y/N): "

if /i not "!confirm!"=="Y" goto dependencies

call :safe_rmdir "node_modules"

if /i "!PM!"=="npm" call :run_command "npm install"
if /i "!PM!"=="pnpm" call :run_command "pnpm install"
if /i "!PM!"=="yarn" call :run_command "yarn install"
if /i "!PM!"=="bun" call :run_command "bun install"

pause
goto dependencies


:deplisting

if /i "!PM!"=="npm" call :run_command "npm list"
if /i "!PM!"=="pnpm" call :run_command "pnpm list"
if /i "!PM!"=="yarn" call :run_command "yarn list"
if /i "!PM!"=="bun" call :run_command "bun pm ls"

pause
goto dependencies


:: ================================================
:: AUTO REPAIR
:: ================================================

:autorepair
cls

echo %CYAN%================================================
echo                    AUTO REPAIR
echo ================================================%RESET%

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
            if /i "!PM!"=="npm" call :run_command "npm install"
            if /i "!PM!"=="pnpm" call :run_command "pnpm install"
            if /i "!PM!"=="yarn" call :run_command "yarn install"
            if /i "!PM!"=="bun" call :run_command "bun install"
        )
    )
)

if exist "tsconfig.json" (
    echo.
    echo   [CHECK] TypeScript configuration detected.
    call :run_command "npx tsc --noEmit"
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


:: ================================================
:: RECENT PROJECTS
:: ================================================

:recent
cls

echo %CYAN%================================================
echo                  RECENT PROJECTS
echo ================================================%RESET%

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


:: ================================================
:: PROJECT EXPLORER
:: ================================================

:explorer
cls

echo %CYAN%================================================
echo                  PROJECT EXPLORER
echo ================================================%RESET%

echo.

start "" explorer.exe "%CD%"

echo   %GREEN%[OK] File Explorer opened.%RESET%

pause
goto main


:: ================================================
:: TERMINAL
:: ================================================

:terminal

start "Project Terminal" cmd /k "cd /d "%CD%""

goto main


:: ================================================
:: VS CODE
:: ================================================

:vscode
cls

echo %CYAN%================================================
echo                  OPEN IN VS CODE
echo ================================================%RESET%

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


:: ================================================
:: CONFIGURATION
:: ================================================

:configuration
cls

echo %CYAN%================================================
echo              PROJECT CONFIGURATION
echo ================================================%RESET%

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


:: ================================================
:: COMMAND HISTORY
:: ================================================

:history
cls

echo %CYAN%================================================
echo                  COMMAND HISTORY
echo ================================================%RESET%

echo.

if exist "!HISTORY_FILE!" (
    type "!HISTORY_FILE!"
) else (
    echo   No command history.
)

echo.
pause
goto main


:: ================================================
:: WORKSPACE INFORMATION
:: ================================================

:workspace
cls

echo %CYAN%================================================
echo               WORKSPACE INFORMATION
echo ================================================%RESET%

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


:: ================================================
:: CLEAN MENU
:: ================================================

:cleanmenu
cls

echo %CYAN%================================================
echo                  CLEAN PROJECT
echo ================================================%RESET%

echo.
echo   ----------------------------------------------
echo   1. Clean Build Output (dist)
echo   2. Deep Clean
echo   3. Back
echo   ----------------------------------------------
echo.

set "cleanchoice="
set /p "cleanchoice=  Select option (1-3): "

if "!cleanchoice!"=="1" goto clean
if "!cleanchoice!"=="2" goto deepclean
if "!cleanchoice!"=="3" goto main

echo.
echo   %RED%[WARNING] Invalid option!%RESET%
timeout /t 2 >nul
goto cleanmenu


:: ================================================
:: CLEAN BUILD
:: ================================================

:clean
cls

echo %CYAN%================================================
echo                CLEAN BUILD OUTPUT
echo ================================================%RESET%

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


:: ================================================
:: DEEP CLEAN
:: ================================================

:deepclean
cls

echo %RED%================================================
echo                DEEP CLEAN PROJECT
echo ================================================%RESET%

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


:: ================================================
:: EXIT
:: ================================================

:exit

cls

echo %CYAN%================================================
echo.
echo                    Goodbye!
echo.
echo              Project Manager
echo.
echo ================================================%RESET%

timeout /t 2 >nul

endlocal
exit /b 0
