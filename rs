<#
.SYNOPSIS
    Interactive (TUI) script to register a scheduled task that restarts a
    Windows service N seconds after the current user logs on.

.DESCRIPTION
    Prompts the user for:
      - Service name
      - Task name (default: Restart<ServiceName>)
      - Logon delay in seconds (default: 30)
      - Stop->Start wait in seconds (default: 5)
    Then registers a hidden scheduled task with HighestAvailable run level
    that restarts the service via sc.exe at logon.

.NOTES
    Run from an elevated (Administrator) PowerShell session.
#>

# --- Helpers -----------------------------------------------------------------

function Read-WithDefault {
    param(
        [Parameter(Mandatory)] [string]$Prompt,
        [string]$Default = ""
    )
    if ($Default -ne "") {
        $shown = "$Prompt [$Default]"
    } else {
        $shown = $Prompt
    }
    $val = Read-Host $shown
    if ([string]::IsNullOrWhiteSpace($val)) { return $Default }
    return $val.Trim()
}

function Read-IntWithDefault {
    param(
        [Parameter(Mandatory)] [string]$Prompt,
        [Parameter(Mandatory)] [int]$Default,
        [int]$Min = 0,
        [int]$Max = [int]::MaxValue
    )
    while ($true) {
        $raw = Read-Host "$Prompt [$Default]"
        if ([string]::IsNullOrWhiteSpace($raw)) { return $Default }
        $n = 0
        if ([int]::TryParse($raw.Trim(), [ref]$n)) {
            if ($n -ge $Min -and $n -le $Max) { return $n }
            Write-Host "  Value must be between $Min and $Max." -ForegroundColor Yellow
        } else {
            Write-Host "  Please enter a valid integer." -ForegroundColor Yellow
        }
    }
}

function Write-Header {
    param([string]$Text)
    $line = '=' * 60
    Write-Host ""
    Write-Host $line -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host $line -ForegroundColor Cyan
    Write-Host ""
}

function Write-KV {
    param([string]$Key, [string]$Value)
    Write-Host ("  {0,-18}: " -f $Key) -NoNewline -ForegroundColor Gray
    Write-Host $Value -ForegroundColor White
}

# --- Elevation check ---------------------------------------------------------

$currentPrincipal = New-Object System.Security.Principal.WindowsPrincipal(
    [System.Security.Principal.WindowsIdentity]::GetCurrent()
)
if (-not $currentPrincipal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host ""
    Write-Host "  ERROR: This script must be run as Administrator." -ForegroundColor Red
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

# --- Banner ------------------------------------------------------------------

function Show-Branding {
    Write-Host ""
    Write-Host "  +--------------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  |" -ForegroundColor Cyan -NoNewline
    Write-Host "             A M A N J   S O F T W A R E            " -ForegroundColor White -NoNewline
    Write-Host "|" -ForegroundColor Cyan
    Write-Host "  |" -ForegroundColor Cyan -NoNewline
    Write-Host "       Restart-Service-On-Logon Task Registrar      " -ForegroundColor Gray -NoNewline
    Write-Host "|" -ForegroundColor Cyan
    Write-Host "  +--------------------------------------------------+" -ForegroundColor Cyan
    Write-Host ""
}

Clear-Host
Show-Branding

$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$userSid  = $identity.User.Value
$userName = $identity.Name

Write-KV "Current user" $userName
Write-KV "User SID"     $userSid
Write-Host ""

# --- Prompt loop (allows re-entry after review) ------------------------------

do {
    Write-Header "Configuration"

    # Service name (required, no default)
    do {
        $ServiceName = Read-WithDefault -Prompt "Service name (e.g. MariaDB)"
        if ([string]::IsNullOrWhiteSpace($ServiceName)) {
            Write-Host "  Service name is required." -ForegroundColor Yellow
        }
    } while ([string]::IsNullOrWhiteSpace($ServiceName))

    # Warn if service is missing
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Host "  WARNING: Service '$ServiceName' was not found on this machine." -ForegroundColor Yellow
        Write-Host "           The task will still be created." -ForegroundColor Yellow
    } else {
        Write-Host "  Found service: $($svc.DisplayName) [$($svc.Status)]" -ForegroundColor Green
    }

    $defaultTaskName = "Restart$ServiceName"
    $TaskName        = Read-WithDefault    -Prompt "Task name"          -Default $defaultTaskName
    $DelaySeconds    = Read-IntWithDefault -Prompt "Logon delay (sec)"  -Default 30 -Min 0  -Max 86400
    $WaitSeconds     = Read-IntWithDefault -Prompt "Stop->Start wait (sec)" -Default 5  -Min 0  -Max 3600

    # --- Review --------------------------------------------------------------
    Write-Header "Review"
    Write-KV "Service name"        $ServiceName
    Write-KV "Task name"           $TaskName
    Write-KV "Logon delay"         "$DelaySeconds second(s)"
    Write-KV "Stop->Start wait"    "$WaitSeconds second(s)"
    Write-KV "Run as"              "$userName (HighestAvailable)"
    Write-Host ""

    $confirm = Read-WithDefault -Prompt "Proceed? (Y=yes / N=re-enter / Q=quit)" -Default "Y"
    switch ($confirm.ToUpper()) {
        "Y" { $done = $true }
        "Q" {
            Write-Host "Aborted by user." -ForegroundColor Yellow
            exit 0
        }
        default { $done = $false }
    }
} while (-not $done)

# --- Build the action command -----------------------------------------------
# /c sc query "<svc>" | find "RUNNING" >nul && (sc stop "<svc>" && timeout /t <wait> >nul) & sc start "<svc>"
$cmdArgs    = '/c sc query "{0}" | find "RUNNING" >nul && (sc stop "{0}" && timeout /t {1} >nul) & sc start "{0}"' -f $ServiceName, $WaitSeconds
$cmdArgsXml = [System.Security.SecurityElement]::Escape($cmdArgs)

$delayDuration = "PT${DelaySeconds}S"
$nowIso        = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffffff")

# --- Compose XML -------------------------------------------------------------
$xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Date>$nowIso</Date>
    <Author>$userName</Author>
    <URI>\$TaskName</URI>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <Delay>$delayDuration</Delay>
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$userSid</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>true</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>true</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>false</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>true</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>true</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <DisallowStartOnRemoteAppSession>false</DisallowStartOnRemoteAppSession>
    <UseUnifiedSchedulingEngine>true</UseUnifiedSchedulingEngine>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT72H</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>cmd.exe</Command>
      <Arguments>$cmdArgsXml</Arguments>
    </Exec>
  </Actions>
</Task>
"@

# --- Register ---------------------------------------------------------------
Write-Header "Registering task"

$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "  Existing task '$TaskName' found. Removing it first..." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

try {
    Register-ScheduledTask -TaskName $TaskName -Xml $xml -Force | Out-Null
    Write-Host "  SUCCESS: Scheduled task '$TaskName' created." -ForegroundColor Green
    Write-Host ""
    Write-KV "Triggers on"  "Logon of $userName, after $DelaySeconds sec"
    Write-KV "Will run"     "sc stop -> wait $WaitSeconds sec -> sc start  ($ServiceName)"
    Write-Host ""
    Write-Host "  --- Amanj Software ---" -ForegroundColor DarkCyan
    Write-Host ""
}
catch {
    Write-Host "  ERROR: Failed to register scheduled task: $_" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

Read-Host "Press Enter to exit"
