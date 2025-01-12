﻿<#  FOR NON-DATTO RMM CUSTOMERS:
    Remove the hashes (#) from the next few lines to configure your variables. 
    Consult the "Usage" section of the readme for more information. #>

#$env:usrScanScope = 1                                                                                                                    
#$env:usrUpdateDefs = "True"
#$env:usrMitigate = 'Y'

<#
    Log4j Vulnerability (CVE-2021-44228) file scanner [windows] :: build 9c [GITHUB VERSION]/seagull
    Uses Florian Roth and Jai Minton's research (thank you!)
    RELEASED PUBLICLY for all MSPs, originally a Datto RMM ComStore Component.
    If you use code from this script, please credit Datto & seagull.

    USER VARIABLES:
    usrScanScope  (1/2/3): just home drive / all fixed drives / all drives
    usrUpdateDefs (bool):  download the latest yara definitions from florian? https://github.com/Neo23x0/signature-base/raw/master/yara/expl_log4j_cve_2021_44228.yar
    usrMitigate   (Y/N/X): ternary option to enable/disable 2.10+ mitigation (or do nothing). https://twitter.com/CyberRaiju/status/1469505680138661890
#>

[string]$varch=[intPtr]::Size*8
$script:varDetection=0
$varEpoch=[int][double]::Parse((Get-Date -UFormat %s))
$varCurrentDir=split-path -parent $MyInvocation.MyCommand.Definition

write-host "Log4j/Log4Shell CVE-2021-44228 Scanning/Mitigation Tool (seagull/Datto)"
write-host "======================================================================="
#add to intro :: directory checks
if ($env:CS_CC_HOST) {
    #is there a centrastage folder? if not, use current dir
    $varProgData="$env:PROGRAMDATA\CentraStage"
    #add to intro
    write-host "Set up a File/Folder Size Monitor against devices"
    write-host "(File/s named $varProgData\L4Jdetections.txt : is over : 0MB)"
    write-host "to alert proactively if this Component reports signs of infection."
    write-host "======================================================================="
} else {
    $varProgData=$varCurrentDir
}

#check to see if the user mapped the variables properly
if (!$env:usrScanScope -or !$env:usrUpdateDefs -or !$env:usrMitigate) {
    write-host "! ERROR: Script variables not defined."
    write-host "  You must configure the usrScanScope, usrUpdateDefs and usrMitigate parameters"
    write-host "  either via your RMM or directly via the script before running."
    write-host "  Open the script in Notepad for more information."
    exit 1
}

#are we admin?
if (!([bool](([System.Security.Principal.WindowsIdentity]::GetCurrent()).groups -match "S-1-5-32-544"))) {
    write-host "! ERROR: Administrative permissions required."
    exit 1
}

#is there already a detections.txt file?
if (test-path "$varProgData\L4Jdetections.txt" -ErrorAction SilentlyContinue) {
    write-host "- An existing L4JDetections.txt file was found. It has been renamed to:"
    write-host "  $varEpoch-L4JDetections.txt"
    Rename-Item -Path "$varProgData\L4Jdetections.txt" "$varProgData\$varEpoch-L4Jdetections.txt" -Force
}

#did the user turn NOLOOKUPS (2.10+ mitigation) on?
switch ($env:usrMitigate) {
    'Y' {
        if ([System.Environment]::GetEnvironmentVariable('LOG4J_FORMAT_MSG_NO_LOOKUPS','machine') -eq 'true') {
            write-host "- Log4j 2.10+ exploit mitigation (LOG4J_FORMAT_MSG_NO_LOOKUPS) already set."
        } else {
            write-host "- Enabling Log4j 2.10+ exploit mitigation: Enable LOG4J_FORMAT_MSG_NO_LOOKUPS"
            [Environment]::SetEnvironmentVariable("LOG4J_FORMAT_MSG_NO_LOOKUPS","true","Machine")
        }
    } 'N' {
        write-host "- Reversing Log4j 2.10+ explot mitigation (enable LOG4J_FORMAT_MSG_NO_LOOKUPS)"
        write-host "  (NOTE: This potentially makes a secure system vulnerable again! Use with caution!)"
        [Environment]::SetEnvironmentVariable("LOG4J_FORMAT_MSG_NO_LOOKUPS","false","Machine")
    } 'X' {
        write-host "- Not adjusting existing LOG4J_FORMAT_MSG_NO_LOOKUPS setting."
    }
}

#map input variable usrScanScope to an actual value
switch ($env:usrScanScope) {
    1   {
        write-host "- Scan scope: Home Drive"
        $script:varDrives=@($env:HomeDrive)
    } 2 {
        write-host "- Scan scope: Fixed & Removable Drives"
        $script:varDrives=Get-WmiObject -Class Win32_logicaldisk | ? {$_.DriveType -eq 2 -or $_.DriveType -eq 3} | ? {$_.FreeSpace} | % {$_.DeviceID}
    } 3 {
        write-host "- Scan scope: All drives, including Network"
        $script:varDrives=Get-WmiObject -Class Win32_logicaldisk | ? {$_.FreeSpace} | % {$_.DeviceID}
    } default {
        write-host "! ERROR: Unable to map scan scope variable to a value. (This should never happen!)"
        write-host "  The acceptable values for env:usrScanScope are:"
        write-host "    1: Scan files on Home Drive"
        write-host "    2: Scan files on fixed and removable drives"
        write-host "    3: Scan files on all detected drives, even network drives"
        exit 1
    }
}

#if user opted to update yara rules, do that
if ($env:usrUpdateDefs -match 'true') {
    [Net.ServicePointManager]::SecurityProtocol = [Enum]::ToObject([Net.SecurityProtocolType], 3072)
    $varYaraNew=(new-object System.Net.WebClient).DownloadString('https://github.com/Neo23x0/signature-base/raw/master/yara/expl_log4j_cve_2021_44228.yar')
    #quick verification check
    if ($varYaraNew -match 'TomcatBypass') {
        Set-Content -Value $varYaraNew -Path "$varCurrentDir\yara.yar" -Force
        write-host "- New YARA definitions downloaded."
    } else {
        write-host "! ERROR: New YARA definition download failed."
        write-host "  Falling back to built-in definitions."
        copy-item -Path expl_log4j_cve_2021_44228.yar -Destination "$varCurrentDir\yara.yar" -Force
    }
} else {
    copy-item -Path expl_log4j_cve_2021_44228.yar -Destination "$varCurrentDir\yara.yar" -Force
    write-host "- Not downloading new YARA definitions."
}

#check yara32 and yara64 are there and that they'll run
foreach ($iteration in ('yara32.exe','yara64.exe')) {
    if (!(test-path "$varCurrentDir\$iteration")) {
        write-host "! ERROR: $iteration not found. It needs to be in the same directory as the script."
        write-host "  Download Yara from https://github.com/virustotal/yara/releases/latest and place them here."
        exit 1
    } else {
        write-host "- Verified presence of $iteration."
    }

    cmd /c "$iteration -v >nul 2>&1"
    if ($LASTEXITCODE -ne 0) {
        write-host "! ERROR: YARA was unable to run on this device."
        write-host "  The Visual C++ Redistributable is required in order to use YARA."
        write-host "  Download it (both architectures) at:"
        write-host "  https://docs.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist?view=msvc-170"
        if ($env:CS_CC_HOST) {
            write-host "  An installer Component is also available from the ComStore."
        }
        exit 1
    }
}

#start a logfile
$host.ui.WriteErrorLine("`r`nPlease expect some permissions errors as some locations are forbidden from traversal.`r`n=====================================================`r`n")
set-content -Path "$varProgData\log.txt" -Force -Value "Files scanned:"
Add-Content "$varProgData\log.txt" -Value "====================================================="
Add-Content "$varProgData\log.txt" -Value " :: Scan Started: $(get-date) ::"


#get a list of all files-of-interest on the device (depending on scope) :: GCI is broken; permissions errors when traversing root dirs cause aborts (!!!)
$arrFiles=@()
foreach ($drive in $varDrives) {
    gci "$drive\" -force | ? {$_.PSIsContainer} | % {
        gci -path "$drive\$_\" -rec -force -include *.jar,*.log,*.txt -ErrorAction 0 | % {
            $arrFiles+=$_.FullName
        }
    }
}

#scan i: JARs containing vulnerable Log4j code
write-host "====================================================="
write-host "- Scanning for JAR files containing potentially insecure Log4j code..."
$arrFiles | ? {$_ -match '\.jar$'} | % {
    if (select-string -Quiet -Path $_ "JndiLookup.class") {
        write-host "! ALERT: Potentially vulnerable file at $($_)!"
        if (!(test-path "$varProgData\L4Jdetections.txt" -ErrorAction SilentlyContinue)) {set-content -path "$varProgData\L4Jdetections.txt" -Value "! CAUTION !`r`n$(get-date)"}
        Add-Content "$varProgData\L4Jdetections.txt" -Value "POTENTIALLY VULNERABLE JAR: $($_)"
        $script:varDetection=1
    }
}

#scan ii: YARA for logfiles & JARs
write-host "====================================================="
write-host "- Scanning LOGs, TXTs and JARs for common attack strings via YARA scan......"
foreach ($file in $arrFiles) {
    if ($file -match 'CentraStage' -or $file -match 'L4Jdetections\.txt') {
        #do nothing -- this isn't a security threat; we're looking at the pathname of the log, not the contents
    } else {
        #add it to the logfile, with a pause for handling
        try {
            Add-Content "$varProgData\log.txt" -Value $file -ErrorAction Stop
        } catch {
            Start-Sleep -Seconds 1
            Add-Content "$varProgData\log.txt" -Value $file -ErrorAction SilentlyContinue
        }

        #scan it
        clear-variable yaResult -ErrorAction SilentlyContinue
        $yaResult=cmd /c "$varCurrentDir\yara$varch.exe `"yara.yar`" `"$file`" -s"
        if ($yaResult) {
            #sound an alarm
            write-host "====================================================="
            $script:varDetection=1
            write-host "! DETECTION:"
            write-host $yaResult
            #write to a file
            if (!(test-path "$varProgData\L4Jdetections.txt" -ErrorAction SilentlyContinue)) {set-content -path "$varProgData\L4Jdetections.txt" -Value "! INFECTION DETECTION !`r`n$(get-date)"}
            Add-Content "$varProgData\L4Jdetections.txt" -Value $yaResult
        }
    }
}

Add-Content "$varProgData\log.txt" -Value " :: Scan Finished: $(get-date) ::"

if ($script:varDetection -eq 1) {
    #splat a splot
    write-host "====================================================="
    write-host "! Evidence of one or more Log4Shell attack attempts has been found on the system;"
    write-host "  alternatively, a potentially vulnerable JAR file may have been found."
    write-host "  The location of the files demonstrating this are noted in the following log:"
    write-host "  $varProgData\L4Jdetections.txt"
    write-host `r
    #write a UDF
    if ($env:CS_CC_HOST) {
        if ($env:usrUDF -gt 0) {
            Set-ItemProperty "HKLM:\Software\CentraStage" -Name "Custom$env:usrUDF" -Value "L4JBAD :: Evidence of attack attempts (or bad JARs) found. Scrutinise Job log."
            write-host "- Writing a summary to UDF #$env:usrUDF."
        } else {
            write-host "- Not writing a UDF (no field selected)."
        }
    }
} else {
    write-host "- There is no indication that this system has received Log4Shell attack attempts ."
    write-host `r
    #write a UDF
    if ($env:CS_CC_HOST) {
        if ($env:usrUDF -gt 0) {
            Set-ItemProperty "HKLM:\Software\CentraStage" -Name "Custom$env:usrUDF" -Value "L4JGOOD :: No evidence of attack attempts found."
            write-host "- Writing a summary to UDF #$env:usrUDF."
        } else {
            write-host "- Not writing a UDF (no field selected)."
        }
    }
}

write-host `r
write-host "Datto recommends that you follow best practices with your systems by implementing WAF rules,"
write-host "mitigation and remediation recommendations from your vendors. For more information on Datto's"
write-host "response to the Log4j vulnerability, please refer to https://www.datto.com/blog/dattos-response-to-log4shell."