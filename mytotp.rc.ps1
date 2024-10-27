#!/usr/bin/env pwsh

# mytotp.rc.ps1

# before all we check if there is installed pwsh core, if not we exit with message about

$isPwshInstalled = Get-Command pwsh -ErrorAction SilentlyContinue
if (-not $isPwshInstalled) {
    Write-Host "PowerShell Core is not installed. Please install it first."
    Write-Host "You can install it with: brew install --cask powershell, see more on site https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-core-on-macos"
    Write-Host "Then you can run this script again."
    exit 1
}
# Define constants
$KEYDIR = "$HOME/.config/mytotp"
$KEYEXT = ".gpg"

# Check the operating system and set the paste command
if ($IsMacOS) {
    $PASTECOMMAND = "pbpaste"
    $pwshVersion = $PSVersionTable.PSVersion
    if ($pwshVersion.Major -eq 6 -and $pwshVersion.Minor -eq 0 -and $pwshVersion.Build -lt 2) {
        Write-Host "Your MacOS PowerShell Core version is too old, please upgrade it to 7.0.3 with brew, following these steps"
        Write-Host "brew install --cask powershell"
        Write-Host "sudo ln -s /usr/local/bin/pwsh /usr/local/bin/pwsh"
        Write-Host "sudo bash -c 'echo /usr/local/bin/pwsh >> /etc/shells'"
        Write-Host "optional step to change default shell to pwsh, not really needed: chsh -s /usr/local/bin/pwsh"
        exit 1
    }
} elseif ($IsLinux) {
    if (-not (Get-Command xclip -ErrorAction SilentlyContinue)) {
        Write-Host "xclip could not be found. It is an optional tool for reading the initial key from the clipboard."
        Write-Host "If you want to use this optional feature, please install it with: sudo apt-get install xclip"
        $yn = Read-Host "Do you want to continue without xclip? (y/n)"
        if ($yn -ne 'y') { exit 1 }
    }
    $PASTECOMMAND = "xclip -o"
}

function mytotp {
    param (
        [string]$SERVID
    )

    if (-not (Get-Command oathtool -ErrorAction SilentlyContinue)) {
        Write-Host "oathtool could not be found"
        Write-Host "Please install it with: brew install oath-toolkit"
        Write-Host "or check further https://launchpad.net/oath-toolkit/+packages && https://www.nongnu.org/oath-toolkit/"
        return 1
    }

    if (-not $SERVID) {
        Write-Host "mytotp version 1.0.1.rc"
        Write-Host "Usage: mytotp SERVID"
        Write-Host "SERVID is a service ID, abbreviated, that you provided for mytotpadd before, check all with mytotplist command"
        return 1
    }

    $keyFile = "$KEYDIR/$SERVID$KEYEXT"
    if (-not (Test-Path $keyFile)) {
        Write-Host "No key for $keyFile"
        return 1
    }

    $SKEY = gpg -d --quiet $keyFile

    $NOWS = (Get-Date).Second
    $WAIT = 60 - $NOWS
    if ($WAIT -gt 30) {
        $WAIT -= 30
    }
    Write-Host "Seconds :$NOWS (we need to wait $WAIT) ... "
    Start-Sleep -Seconds $WAIT

    $TOTP = $SKEY | oathtool -b --totp -
    Write-Host $TOTP
    $SKEY = "none"
    return 0
}

function mytotpdel {
    param (
        [string]$SERVID
    )

    if (-not $SERVID) {
        Write-Host "Usage: mytotpdel SERVID"
        Write-Host "SERVID is a service ID, abbreviated, w/o ext:"
        return 1
    }

    $keyFile = "$KEYDIR/$SERVID$KEYEXT"
    if (-not (Test-Path $keyFile)) {
        Write-Host "No key for $keyFile"
        return 1
    }

    Remove-Item $keyFile
    Write-Host "Key for $SERVID deleted."
}

function mytotpadd {
    param (
        [string]$SERVID
    )

    if (-not (gpg --list-keys "My TOTP" -ErrorAction SilentlyContinue)) {
        Write-Host "GPG key 'My TOTP' does not exist. Please create it first."
        $yn = Read-Host "Do you want to create the key 'My TOTP' now ? (y/n)"
        if ($yn -eq 'y') {
            Write-Host "Write and remember the password for 'My TOTP' gpg key in the next line:"
            gpg --yes --batch --passphrase-fd 0 --quick-generate-key 'My TOTP'
        } else {
            return 1
        }
        Write-Host "get back with further usage: mytotpadd <SERVID>"
        return
    }

    if (-not $SERVID) {
        Write-Host "Usage: mytotpadd SERVID"
        Write-Host "SERVID is a service ID, abbreviated, w/o ext:"
        return 1
    }

    Write-Host "Paste the key in the prompt, press enter, and then press control-D to stop gpg"
    gpg -e -r "My TOTP" > "$KEYDIR/$SERVID$KEYEXT"

    $byn = Read-Host "Do you want to store the initial service key in .key.asc? Warn: it is unsafe (y/n)"
    if ($byn -eq 'y') {
        & $PASTECOMMAND >> "$KEYDIR/$SERVID.key.asc"
    }
}

function mytotplist {
    if (-not (Test-Path $KEYDIR)) {
        $yn = Read-Host "Directory $KEYDIR does not exist. Do you want to create it? (y/n)"
        if ($yn -eq 'y') {
            New-Item -ItemType Directory -Path $KEYDIR
        } else {
            return
        }
    }

    $ENTRIES = Get-ChildItem "$KEYDIR/*$KEYEXT" -ErrorAction SilentlyContinue | ForEach-Object {
        $_.Name -replace '\.gpg$', ''
    }

    if (-not $ENTRIES) {
        Write-Host "Warning: No SERVID entries found."
    } else {
        Write-Host $ENTRIES
    }
}

# Function to get the list of .gpg files in $KEYDIR
function Get-GpgFiles {
    $files = Get-ChildItem -Path $KEYDIR -Filter "*$KEYEXT" -ErrorAction SilentlyContinue
    if ($files) {
        $files | ForEach-Object { $_.BaseName }
    } else {
        @()  # Return an empty array if no files are found
    }
}

# Register argument completer for mytotpdel function
Register-ArgumentCompleter -Native -CommandName mytotpdel -ParameterName SERVID -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameter)
    $gpgFiles = Get-GpgFiles
    if ($gpgFiles) {
        $gpgFiles | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }
}

# Register argument completer for mytotp function (for SERVID parameter) just the same as totpdel
Register-ArgumentCompleter -Native -CommandName mytotp -ParameterName SERVID -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameter)
    $gpgFiles = Get-GpgFiles
    if ($gpgFiles) {
        $gpgFiles | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }
}