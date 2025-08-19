@echo off
setlocal EnableExtensions EnableDelayedExpansion
:: --------------------------------------------
:: Block Adobe executables from outbound net
:: Run as Administrator - COMPLETE VERSION
:: --------------------------------------------

:: Admin check
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo [ERROR] This script must be run as Administrator.
  echo Right-click the .bat and choose "Run as administrator".
  echo.
  pause
  exit /b 1
)

:: Setup log file
set "LOG=%~dp0adobe_firewall_block.log"
echo ==================================================>>"%LOG%"
echo === Run %DATE% %TIME% ===>>"%LOG%"

:: Display menu
:MENU
cls
echo ==================================================
echo    Adobe Firewall Blocker
echo ==================================================
echo.
echo Choose an option:
echo.
echo [1] Block MAIN Adobe apps only (Photoshop, Illustrator, etc.)
echo [2] Block ALL .exe files in Adobe directories (complete block)
echo [3] View all Adobe firewall rules
echo [4] Remove all Adobe firewall blocks
echo [5] Exit
echo.
set /p "CHOICE=Enter your choice (1-5): "

if "%CHOICE%"=="1" goto MAIN_APPS
if "%CHOICE%"=="2" goto ALL_EXES
if "%CHOICE%"=="3" goto VIEW_RULES
if "%CHOICE%"=="4" goto REMOVE_RULES
if "%CHOICE%"=="5" goto END
echo Invalid choice. Please try again.
pause
goto MENU

:: --------------------------------------------
:: OPTION 1: Block main Adobe apps only
:: --------------------------------------------
:MAIN_APPS
echo.
echo ==================================================
echo Option 1: Blocking main Adobe applications only...
echo ==================================================
echo.
>>"%LOG%" echo [MODE] Main Apps Only

:: List of known main Adobe executables
set "TARGETS=Photoshop.exe Illustrator.exe AfterFX.exe MediaEncoder.exe Acrobat.exe AcroRd32.exe InDesign.exe Premiere.exe PremierePro.exe Audition.exe Bridge.exe Animate.exe CharacterAnimator.exe Lightroom.exe LightroomClassic.exe Dreamweaver.exe Dimension.exe Fresco.exe XD.exe InCopy.exe Prelude.exe Rush.exe SpeedGrade.exe"
set /a COUNT=0

:: Process each Adobe directory
for %%D in (
  "%ProgramFiles%\Adobe"
  "%ProgramFiles(x86)%\Adobe"
  "%ProgramData%\Adobe"
  "%ProgramFiles%\Common Files\Adobe"
  "%ProgramFiles(x86)%\Common Files\Adobe"
) do (
  if exist "%%~D" (
    echo.
    echo [SCAN] Searching recursively in: %%~D
    echo        Looking for main Adobe apps...
    
    :: Use dir command with /s for recursive search
    for /f "delims=" %%F in ('dir /s /b "%%~D\*.exe" 2^>nul') do (
      set "FULLPATH=%%F"
      set "FILENAME=%%~nxF"
      
      :: Check if this exe is in our target list
      for %%T in (%TARGETS%) do (
        if /i "!FILENAME!"=="%%T" (
          :: Delete any existing outbound rule for this exe
          netsh advfirewall firewall delete rule name=all program="!FULLPATH!" dir=out >nul 2>&1
          
          :: Add block rule
          netsh advfirewall firewall add rule ^
            name="Block Adobe - !FILENAME!" ^
            dir=out action=block program="!FULLPATH!" ^
            enable=yes profile=any >nul
          
          if !errorlevel! equ 0 (
            echo [BLOCKED] !FILENAME! at !FULLPATH!
            >>"%LOG%" echo [BLOCKED] !FULLPATH!
            set /a COUNT+=1
          ) else (
            echo [WARN] Failed to block: !FILENAME!
            >>"%LOG%" echo [WARN] Failed: !FULLPATH!
          )
        )
      )
    )
  ) else (
    echo [SKIP] Directory not found: %%~D
  )
)
goto SUMMARY

:: --------------------------------------------
:: OPTION 2: Block ALL .exe files
:: --------------------------------------------
:ALL_EXES
echo.
echo ==================================================
echo Option 2: Blocking ALL .exe files in Adobe directories...
echo ==================================================
echo.
echo WARNING: This will block EVERY executable in Adobe folders!
echo Press Ctrl+C to cancel, or
pause

>>"%LOG%" echo [MODE] All Executables
set /a COUNT=0

:: Process each Adobe directory
for %%D in (
  "%ProgramFiles%\Adobe"
  "%ProgramFiles(x86)%\Adobe"
  "%ProgramData%\Adobe"
  "%ProgramFiles%\Common Files\Adobe"
  "%ProgramFiles(x86)%\Common Files\Adobe"
  "%ProgramFiles%\Adobe Creative Cloud"
  "%ProgramFiles(x86)%\Adobe Creative Cloud"
) do (
  if exist "%%~D" (
    echo.
    echo [SCAN] Searching ALL .exe files recursively in: %%~D
    
    :: Use dir command with /s for recursive search
    for /f "delims=" %%F in ('dir /s /b "%%~D\*.exe" 2^>nul') do (
      set "FULLPATH=%%F"
      set "FILENAME=%%~nxF"
      
      :: Skip certain system/common files if needed
      set "SKIP=0"
      if /i "!FILENAME!"=="unins000.exe" set "SKIP=1"
      if /i "!FILENAME!"=="unins001.exe" set "SKIP=1"
      if /i "!FILENAME!"=="uninstall.exe" set "SKIP=1"
      if /i "!FILENAME!"=="uninst.exe" set "SKIP=1"
      
      if "!SKIP!"=="0" (
        :: Delete any existing outbound rule for this exe
        netsh advfirewall firewall delete rule name=all program="!FULLPATH!" dir=out >nul 2>&1
        
        :: Add block rule
        netsh advfirewall firewall add rule ^
          name="Block Adobe - !FILENAME!" ^
          dir=out action=block program="!FULLPATH!" ^
          enable=yes profile=any >nul
        
        if !errorlevel! equ 0 (
          echo [BLOCKED] !FILENAME!
          echo          Path: !FULLPATH!
          >>"%LOG%" echo [BLOCKED] !FULLPATH!
          set /a COUNT+=1
        ) else (
          echo [WARN] Failed to block: !FILENAME!
          >>"%LOG%" echo [WARN] Failed: !FULLPATH!
        )
      ) else (
        echo [SKIP] Uninstaller: !FILENAME!
      )
    )
  ) else (
    echo [SKIP] Directory not found: %%~D
  )
)
goto SUMMARY

:: --------------------------------------------
:: OPTION 3: View all Adobe firewall rules
:: --------------------------------------------
:VIEW_RULES
cls
echo ==================================================
echo    Viewing All Adobe Firewall Rules
echo ==================================================
echo.
echo Fetching all "Block Adobe" rules...
echo.

set /a RULE_COUNT=0
:: Get all Adobe block rules
for /f "tokens=*" %%A in ('netsh advfirewall firewall show rule name^=all ^| findstr /B "Rule Name:" ^| findstr /C:"Block Adobe"') do (
  set /a RULE_COUNT+=1
)

echo Found %RULE_COUNT% Adobe blocking rules:
echo --------------------------------------------
echo.

:: Show detailed info for each Adobe rule
netsh advfirewall firewall show rule name=all | findstr /B "Rule Name: Block Adobe" >nul 2>&1
if %errorlevel% equ 0 (
  for /f "tokens=2*" %%A in ('netsh advfirewall firewall show rule name^=all ^| findstr /B "Rule Name:" ^| findstr /C:"Block Adobe"') do (
    set "RULENAME=%%B"
    echo Rule: !RULENAME!
    for /f "tokens=*" %%P in ('netsh advfirewall firewall show rule name^="!RULENAME!" ^| findstr /C:"Program:"') do echo   %%P
    for /f "tokens=*" %%D in ('netsh advfirewall firewall show rule name^="!RULENAME!" ^| findstr /C:"Direction:"') do echo   %%D
    for /f "tokens=*" %%A in ('netsh advfirewall firewall show rule name^="!RULENAME!" ^| findstr /C:"Action:"') do echo   %%A
    echo.
  )
) else (
  echo No Adobe firewall rules found.
)

echo --------------------------------------------
echo Total Adobe rules: %RULE_COUNT%
echo.
pause
goto MENU

:: --------------------------------------------
:: OPTION 4: Remove all Adobe firewall blocks
:: --------------------------------------------
:REMOVE_RULES
cls
echo ==================================================
echo    Remove All Adobe Firewall Blocks
echo ==================================================
echo.
echo WARNING: This will remove ALL Adobe firewall blocking rules!
echo.
echo Are you sure you want to remove all Adobe blocks?
set /p "CONFIRM=Type YES to confirm (or anything else to cancel): "

if /i not "%CONFIRM%"=="YES" (
  echo.
  echo Operation cancelled.
  pause
  goto MENU
)

echo.
echo Removing all Adobe firewall blocking rules...
echo.
>>"%LOG%" echo [MODE] Remove All Rules

set /a REMOVED=0
:: Remove all rules that start with "Block Adobe"
for /f "tokens=2*" %%A in ('netsh advfirewall firewall show rule name^=all ^| findstr /B "Rule Name:" ^| findstr /C:"Block Adobe"') do (
  set "RULENAME=%%B"
  echo [REMOVING] !RULENAME!
  netsh advfirewall firewall delete rule name="!RULENAME!" >nul 2>&1
  if !errorlevel! equ 0 (
    set /a REMOVED+=1
    >>"%LOG%" echo [REMOVED] !RULENAME!
  ) else (
    echo [WARN] Failed to remove: !RULENAME!
    >>"%LOG%" echo [WARN] Failed to remove: !RULENAME!
  )
)

echo.
echo ==================================================
echo  Removal Summary:
echo    Total rules removed: %REMOVED%
echo ==================================================
echo.
pause
goto MENU

:: --------------------------------------------
:: Summary after blocking
:: --------------------------------------------
:SUMMARY
echo.
echo ==================================================
echo  Summary:
echo    Total executables blocked: %COUNT%
echo    Log file: %LOG%
echo ==================================================
echo.
echo Recent blocks from this run:
echo.
type "%LOG%" 2>nul | findstr /C:"[BLOCKED]" | findstr /C:"%DATE%" 2>nul || echo (No new blocks recorded this run)
echo.
pause
goto MENU

:: --------------------------------------------
:: Exit
:: --------------------------------------------
:END
cls
echo ==================================================
echo    Adobe Firewall Blocker - Goodbye
echo ==================================================
echo.
echo Current status:
echo.
set /a CURRENT_RULES=0
for /f "tokens=*" %%A in ('netsh advfirewall firewall show rule name^=all ^| findstr /B "Rule Name:" ^| findstr /C:"Block Adobe"') do (
  set /a CURRENT_RULES+=1
)
echo Active Adobe blocking rules: %CURRENT_RULES%
echo.
echo Log file saved at: %LOG%
echo.
echo To manage rules manually:
echo - Open Windows Defender Firewall with Advanced Security
echo - Check Outbound Rules for "Block Adobe" entries
echo.
pause
endlocal
exit /b 0
