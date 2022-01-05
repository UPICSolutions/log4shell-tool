﻿<#
.SYNOPSIS
    Log4j Vulnerability (CVE-2021-44228) file scanner [windows] :: build 8b/seagull & Proval Tech - Upic Solutions Fork
.EXAMPLE
    Runs the scan tool, using Everything (https://www.voidtools.com) to search for files. Updates YARA definitions and adds the env variable LOG4J_FORMAT_MSG_NO_LOOKUPS mitigation.
    PS C:\> .\scanner-8b.ps1 -EverythingSearch -usrUpdateDefs $true -usrMitigate 'Y'
.PARAMETER usrScanscope
    Sets the scope for drive scanning. -EverythingSearch overrides this setting.
    1 - Home drive only
    2 - All non-network drives
    3 - All drives (local and network)
.PARAMETER usrUpdateDefs
    Determines if defintion updates for YARA will be updated before scanning.
    $true - Definitions will be updated.
    $false - Definitions will not be updated.
.PARAMETER usrMitigate
    Determines if the LOG4J_FORMAT_MSG_NO_LOOKUPS mitigation will be applied.
    'Y' - Mitigation will be applied.
    'N' - Mitigation will be removed.
    'X' - Take no action.
.PARAMETER EverythingSearch
    Use this switch to enable searching with Everything (https://www.voidtools.com) instead of Get-ChildItem.
    This will install the PSEverything module from PSGallery and temporarily install the Everything service.
.NOTES
    Uses Florian Roth and Jai Minton's research (thank you!)
    RELEASED PUBLICLY for all MSPs, originally a Datto RMM ComStore Component.
    If you use code from this script, please credit Datto & seagull.
    Fork by Upic Solutions
    Fork Changes:
    - Added param block, preserving initial $env variable usage
    - Changed appropriate paths to point to the location of the script and not the current directory of the shell
    - Editing some formatting
    - Implemented Everything search option
    - Implemented Luna scan from https://github.com/lunasec-io/lunasec/tree/master/tools/log4shell
    - Implemented C++ installation
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)][ValidateSet(1,2,3)][int]$usrScanscope = $env:usrScanscope,
    [Parameter(Mandatory=$false)][bool]$usrUpdateDefs = [System.Convert]::ToBoolean($env:usrUpdateDefs),
    [Parameter(Mandatory=$false)][ValidateSet('Y','N','X')][char]$usrMitigate = $env:usrMitigate,
    [Parameter(Mandatory=$false)][switch]$EverythingSearch
)
[Net.ServicePointManager]::SecurityProtocol = [Enum]::ToObject([Net.SecurityProtocolType], 3072)
$scriptObject = Get-Item -Path $script:PSCommandPath
$workingPath = $($scriptObject.DirectoryName)
$skipYARA = $false
if($EverythingSearch) {
    Write-Host "Everything search requested."
    Write-Host "Downloading Everything search."
    $portableEverythingURL = "https://www.voidtools.com/Everything-1.4.1.1009.x64.zip"
    $portableEverythingZIP = "$workingPath\Everything.zip"
    $portableEverythingPath = "$workingPath\Everything"
    if(Test-Path "$portableEverythingPath\everything.exe") {
        & "$portableEverythingPath\everything.exe" -uninstall-service
        Get-Process -Name Everything -ErrorAction SilentlyContinue | Where-Object {$_.Path -eq "$portableEverythingPath\everything.exe"} -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -Path $portableEverythingZIP -ErrorAction SilentlyContinue
    (New-Object System.Net.WebClient).DownloadFile($portableEverythingURL,$portableEverythingZIP)
    Write-Host "Expanding $portableEverythingZIP."
    Expand-Archive -Path $portableEverythingZIP -DestinationPath $portableEverythingPath -Force -ErrorAction SilentlyContinue
    if (!(Get-Service "Everything" -ErrorAction SilentlyContinue)) {
        Write-Host "Installing Everything service."
        & "$portableEverythingPath\everything.exe" -install-service
    }
    Write-Host "Installing Everything config."
    & "$portableEverythingPath\everything.exe" -install-config "$workingPath\EverythingConfig.ini"
    Write-Host "Reindexing Everything."
    & "$portableEverythingPath\everything.exe" -reindex -close
    if(Get-Module -Name PSEverything -ListAvailable -ErrorAction SilentlyContinue) {
        Write-Host "Importing PSEverything."
        Import-Module -Name PSEverything
    } else {
        Write-Host "Installing PSEverything."
        Install-PackageProvider -Name NuGet -Force -ErrorAction SilentlyContinue
        Register-PSRepository -Default
        Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
        Install-Module PSEverything
    }
    if(-not (Get-Module -Name PSEverything -ErrorAction SilentlyContinue)) {
        Write-Host "Failed to import PSEverything. Reverting back to Get-ChildItem."
        & "$portableEverythingPath\everything.exe" -uninstall-service
        $EverythingSearch = $false
        $usrScanScope = 2
    }
}

[string]$varch=[intPtr]::Size*8
$script:varDetection=0
$varEpoch=[int][double]::Parse((Get-Date -UFormat %s))

Write-Host "Log4j/Log4Shell CVE-2021-44228 Scanning/Mitigation Tool (seagull/Datto)"
Write-Host "======================================================================="
if ($env:CS_CC_HOST) {
    Write-Host "Set up a File/Folder Size Monitor against devices"
    Write-Host "(File/s named $env:PROGRAMDATA\UpicSolutions\L4Jdetections.txt : is over : 0MB)"
    Write-Host "to alert proactively if this Component reports signs of infection."
    Write-Host "======================================================================="
}

#is there already a detections.txt file?
if (Test-Path "$env:PROGRAMDATA\UpicSolutions\L4Jdetections.txt" -ErrorAction SilentlyContinue) {
    Write-Host "- An existing L4JDetections.txt file was found. It has been renamed to:"
    Write-Host "  $varEpoch-L4JDetections.txt"
    Rename-Item -Path "$env:PROGRAMDATA\UpicSolutions\L4Jdetections.txt" "$env:PROGRAMDATA\UpicSolutions\$varEpoch-L4Jdetections.txt" -Force
}

#did the user turn NOLOOKUPS (2.10+ mitigation) on?
switch ($usrMitigate) {
    'Y' {
        if ([System.Environment]::GetEnvironmentVariable('LOG4J_FORMAT_MSG_NO_LOOKUPS','machine') -eq 'true') {
            Write-Host "- Log4j 2.10+ exploit mitigation (LOG4J_FORMAT_MSG_NO_LOOKUPS) already set."
        } else {
            Write-Host "- Enabling Log4j 2.10+ exploit mitigation: Enable LOG4J_FORMAT_MSG_NO_LOOKUPS"
            [Environment]::SetEnvironmentVariable("LOG4J_FORMAT_MSG_NO_LOOKUPS","true","Machine")
        }
    } 'N' {
        Write-Host "- Reversing Log4j 2.10+ explot mitigation (enable LOG4J_FORMAT_MSG_NO_LOOKUPS)"
        Write-Host "  (NOTE: This potentially makes a secure system vulnerable again! Use with caution!)"
        [Environment]::SetEnvironmentVariable("LOG4J_FORMAT_MSG_NO_LOOKUPS","false","Machine")
    } 'X' {
        Write-Host "- Not adjusting existing LOG4J_FORMAT_MSG_NO_LOOKUPS setting."
    }
}

#map input variable usrScanScope to an actual value
if($EverythingSearch) {
    Write-Host "Everything search requested. Scanning all possible drives."
    $script:varDrives = @(Get-WmiObject -Class Win32_logicaldisk | Where-Object {$_.DriveType -eq 2 -or $_.DriveType -eq 3} | Where-Object {$_.FreeSpace} | ForEach-Object {$_.DeviceID})
} else {
    switch ($usrScanScope) {
        1 {
            Write-Host "- Scan scope: Home Drive"
            $script:varDrives = @($env:HomeDrive)
        } 2 {
            Write-Host "- Scan scope: Fixed & Removable Drives"
            $script:varDrives = @(Get-WmiObject -Class Win32_logicaldisk | Where-Object {$_.DriveType -eq 2 -or $_.DriveType -eq 3} | Where-Object {$_.FreeSpace} | ForEach-Object {$_.DeviceID})
        } 3 {
            Write-Host "- Scan scope: All drives, including Network"
            $script:varDrives = @(Get-WmiObject -Class Win32_logicaldisk | Where-Object {$_.FreeSpace} | ForEach-Object {$_.DeviceID})
        } default {
            Write-Host "! ERROR: Unable to map scan scope variable to a value. (This should never happen!)"
            Write-Host "  The acceptable values for env:usrScanScope are:"
            Write-Host "    1: Scan files on Home Drive"
            Write-Host "    2: Scan files on fixed and removable drives"
            Write-Host "    3: Scan files on all detected drives, even network drives"
            exit 1
        }
    }
}

#if user opted to update yara rules, do that
if ($usrUpdateDefs) {
    [Net.ServicePointManager]::SecurityProtocol = [Enum]::ToObject([Net.SecurityProtocolType], 3072)
    $varYaraNew = (New-Object System.Net.WebClient).DownloadString('https://github.com/Neo23x0/signature-base/raw/master/yara/expl_log4j_cve_2021_44228.yar')
    #quick verification check
    if ($varYaraNew -match 'TomcatBypass') {
        Set-Content -Value $varYaraNew -Path "$workingPath\yara.yar" -Force
        Write-Host "- New YARA definitions downloaded."
    } else {
        Write-Host "! ERROR: New YARA definition download failed."
        Write-Host "  Falling back to built-in definitions."
        Copy-Item -Path "$workingPath\expl_log4j_cve_2021_44228.yar" -Destination "$workingPath\yara.yar" -Force
    }
} else {
    Copy-Item -Path "$workingPath\expl_log4j_cve_2021_44228.yar" -Destination "$workingPath\yara.yar" -Force
    Write-Host "- Not downloading new YARA definitions."
}

#check yara32 and yara64 are there and that they'll run
foreach ($iteration in ('yara32.exe','yara64.exe')) {
    if (!(Test-Path "$workingPath\$iteration")) {
        Write-Host "! ERROR: ""$workingPath\$iteration"" not found. It needs to be in the same directory as the script."
        Write-Host "  Download Yara from https://github.com/virustotal/yara/releases/latest and place them here."
        exit 1
    } else {
        Write-Host "- Verified presence of ""$workingPath\$iteration""."
    }

    cmd /c """$workingPath\$iteration"" -v >nul 2>&1"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "! ERROR: YARA was unable to run on this device."
        Write-Host "  The Visual C++ Redistributable is required in order to use YARA."
        Write-Host "  Installing..."
        # (New-Object System.Net.WebClient).DownloadFile("https://aka.ms/vs/17/release/vc_redist.x64.exe","$workingPath\vc_redist.x64.exe")
        # Start-Sleep -Seconds 5
        # & "$workingPath\vc_redist.x64.exe" /s
        # Start-Sleep -Seconds 5
        cmd /c """$workingPath\$iteration"" -v >nul 2>&1"
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  YARA was still unable to run. Skipping YARA scanning."
            $skipYARA = $true
        }
    }
}

#start a logfile
$host.ui.WriteErrorLine("`r`nPlease expect some permissions errors as some locations are forbidden from traversal.`r`n=====================================================`r`n")
$logPath = "$workingPath\log.txt"
Set-Content -Path $logPath -Force -Value "Files scanned:"
Add-Content $logPath -Value "====================================================="
Add-Content $logPath -Value " :: Scan Started: $(get-date) ::"


#get a list of all files-of-interest on the device (depending on scope) :: GCI is broken; permissions errors when traversing root dirs cause aborts (!!!)
$arrFiles=@()
if($EverythingSearch) {
    $arrFiles = Search-Everything -Global -Extension "jar","log","txt"
    & "$portableEverythingPath\everything.exe" -uninstall-service
    Get-Process -Name Everything | Where-Object {$_.Path -eq "$portableEverythingPath\everything.exe"} | Stop-Process -Force
} else {
    foreach ($drive in $varDrives) {
        Get-ChildItem "$drive\" -force | Where-Object {$_.PSIsContainer} | ForEach-Object {
            Get-ChildItem -path "$drive\$_\" -Recurse -Force -ErrorAction 0 | Where-Object {$_.Extension -in ".jar",".log",".txt"} | ForEach-Object {
                $arrFiles += $_.FullName
            }
        }
    }
}
Write-Host "Scanning $($arrFiles.Length) files for potential vulnerabilities."

#scan i: JARs containing vulnerable Log4j code
Write-Host "====================================================="
Write-Host "- Scanning for JAR files containing potentially insecure Log4j code..."
$arrFiles | Where-Object {$_ -match '\.jar$'} | ForEach-Object {
    if (select-string -Quiet -Path $_ "JndiLookup.class") {
        Write-Host "! ALERT: Potentially vulnerable file at $($_)!"
        if (!(Test-Path "$env:PROGRAMDATA\UpicSolutions\L4Jdetections.txt" -ErrorAction SilentlyContinue)) {Set-Content -path "$env:PROGRAMDATA\UpicSolutions\L4Jdetections.txt" -Value "! CAUTION !`r`n$(Get-Date)"}
        Add-Content "$env:PROGRAMDATA\UpicSolutions\L4Jdetections.txt" -Value "POTENTIALLY VULNERABLE JAR: $($_)"
        $script:varDetection=1
    }
}

if(-not $skipYARA) {
    #scan ii: YARA for logfiles & JARs
    Write-Host "====================================================="
    Write-Host "- Scanning LOGs, TXTs and JARs for common attack strings via YARA scan......"
    foreach ($file in $arrFiles) {
        if ($file -match 'UpicSolutions' -or $file -match 'L4Jdetections\.txt') {
            #do nothing -- this isn't a security threat; we're looking at the pathname of the log, not the contents
        } else {
            #add it to the logfile, with a pause for handling
            try {
                Add-Content $logPath -Value $file -ErrorAction Stop
            } catch {
                Start-Sleep -Seconds 1
                Add-Content $logPath -Value $file -ErrorAction SilentlyContinue
            }

            #scan it
            Clear-Variable yaResult -ErrorAction SilentlyContinue
            $yaResult = cmd /c """$workingPath\yara$varch.exe"" ""$workingPath\yara.yar"" ""$file"" -s"
            if ($yaResult) {
                #sound an alarm
                Write-Host "====================================================="
                $script:varDetection=1
                Write-Host "! DETECTION:"
                Write-Host $yaResult
                #write to a file
                if (!(Test-Path "$env:PROGRAMDATA\UpicSolutions\L4Jdetections.txt" -ErrorAction SilentlyContinue)) {Set-Content -path "$env:PROGRAMDATA\UpicSolutions\L4Jdetections.txt" -Value "! INFECTION DETECTION !`r`n$(get-date)"}
                Add-Content "$env:PROGRAMDATA\UpicSolutions\L4Jdetections.txt" -Value $yaResult
            }
        }
    }
}

Write-Host "====================================================="
Write-Host "- Scanning for known vulnerable libraries via Luna scan......"
Write-Host "Ref: https://github.com/lunasec-io/lunasec/tree/master/tools/log4shell"
$lunaUrl = "https://github.com/lunasec-io/lunasec/releases/download/v1.3.0-log4shell/log4shell_1.3.0-log4shell_Windows_x86_64.exe"
$lunaPath = "$workingPath\log4shell.exe"
$lunaLog = "$workingPath\luna.log"
Remove-Item -Path $lunaPath -Force -ErrorAction SilentlyContinue
Remove-Item -Path $lunaLog -Force -ErrorAction SilentlyContinue
[Net.ServicePointManager]::SecurityProtocol = [Enum]::ToObject([Net.SecurityProtocolType], 3072)
(New-Object System.Net.WebClient).DownloadFile($lunaUrl,$lunaPath)
foreach($drive in $script:varDrives) {
    $lunaResults = @(cmd /c """$lunaPath"" s --json $drive\ 2>&1")
    Add-Content -Value $lunaResults -Path $lunaLog
    foreach($entry in $lunaResults) {
        if($entry -match """severity"":") {
            Write-Host "! LUNA DETECTION: $entry"
            $script:varDetection = 1
        }
    }
}
Add-Content $logPath -Value " :: Scan Finished: $(get-date) ::"

if ($script:varDetection -eq 1) {
    Write-Host "====================================================="
    Write-Host "! Evidence of one or more Log4Shell attack attempts, vulnerable files, or vulnerable libraries has been found on the system."
    Write-Host "  The location of the files demonstrating this are noted in the following logs:"
    Write-Host "  Vulnerable files/Attack Attempts: $env:PROGRAMDATA\UpicSolutions\L4Jdetections.txt"
    Write-Host "  Vulnerable libraries: $lunaLog"
} else {
    Write-Host "- There is no indication that this system has vulnerable files, libraries, or has received Log4Shell attack attempts."
}

Write-Host `r
Write-Host "Datto recommends that you follow best practices with your systems by implementing WAF rules,"
Write-Host "mitigation and remediation recommendations from your vendors. For more information on Datto's"
Write-Host "response to the log4j vulnerabilty, please refer to https://www.datto.com/blog/dattos-response-to-log4shell."