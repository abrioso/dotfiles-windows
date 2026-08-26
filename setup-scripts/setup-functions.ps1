# setup-functions.ps1
# Shared PowerShell functions for setup scripts

<#
.SYNOPSIS
    This script contains reusable functions for setup scripts.
.DESCRIPTION
    Import this script in your setup scripts to use the shared functions.
#>

# Example: Import-Module "$PSScriptRoot\setup-functions.ps1"

function Write-Info {
    param (
        [Parameter(Mandatory)]
        [string]$Message
    )
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-WarningMessage {
    param (
        [Parameter(Mandatory)]
        [string]$Message
    )
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-ErrorMessage {
    param (
        [Parameter(Mandatory)]
        [string]$Message
    )
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Start-Logging {
    param (
        [Parameter(Mandatory)]
        [string]$LogFilePath,
        [switch]$PassThru,
        [switch]$RequireRequestedPath
    )

    $actualLogFilePath = $LogFilePath
    try {
        $logDir = Split-Path -Parent $actualLogFilePath
        if (-not (Test-Path -LiteralPath $logDir -PathType Container)) {
            New-Item -Path $logDir -ItemType Directory -ErrorAction Stop | Out-Null
        }
        Start-Transcript -Path $actualLogFilePath -ErrorAction Stop | Out-Null
    }
    catch {
        if ($RequireRequestedPath) {
            throw "Cannot start transcript at '$actualLogFilePath': $($_.Exception.Message)"
        }

        Write-WarningMessage "Cannot start transcript at '$actualLogFilePath': $($_.Exception.Message)"
        $fallbackName = "{0}-{1}.txt" -f [System.IO.Path]::GetFileNameWithoutExtension($LogFilePath), [System.Guid]::NewGuid().ToString('N')
        $actualLogFilePath = Join-Path $env:TEMP $fallbackName
        try {
            Start-Transcript -Path $actualLogFilePath -ErrorAction Stop | Out-Null
            Write-WarningMessage "Logging to temporary location: $actualLogFilePath"
        }
        catch {
            throw "Cannot start transcript at the requested or temporary path: $($_.Exception.Message)"
        }
    }

    if ($PassThru) {
        return $actualLogFilePath
    }
}
 
function Stop-Logging {
    try {
        Stop-Transcript -ErrorAction Stop
    }
    catch {
        Write-WarningMessage "Cannot stop transcript: $($_.Exception.Message)"
    }
}

function Update-DotfilesProcessPath {
    $pathSegments = @(
        [System.Environment]::GetEnvironmentVariable("Path", "Machine")
        [System.Environment]::GetEnvironmentVariable("Path", "User")
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    $env:Path = $pathSegments -join [System.IO.Path]::PathSeparator
}

# Function to install the dotfiles pre-requisites
function Install-DotfilesPrerequisites {
    Write-Info "Installing dotfiles prerequisites..."

    # Check if winget is available
    try {
        $wingetAvailable = Get-Command winget -ErrorAction SilentlyContinue
        if ($wingetAvailable) {
            Write-Info "Winget is available, proceeding with installations."
        } else {
            Write-ErrorMessage "Winget is required to install bootstrap prerequisites. Install App Installer and re-run setup."
            return $false
        }
    } catch {
        Write-ErrorMessage "Failed to check winget availability: $($_.Exception.Message)"
        return $false
    }

    # Install PowerShell if not present
    try {
        if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
            Write-Info "PowerShell is not installed. Installing PowerShell..."
            $wingetArguments = @(
                'install', '--id', 'Microsoft.PowerShell', '--exact', '--force',
                '--source', 'winget', '--scope', 'user',
                '--accept-source-agreements', '--accept-package-agreements',
                '--disable-interactivity'
            )
            & winget @wingetArguments
            if ($LASTEXITCODE -ne 0) {
                Write-ErrorMessage "Winget failed to install PowerShell (exit code $LASTEXITCODE)."
                return $false
            }

            Update-DotfilesProcessPath
            if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
                Write-ErrorMessage "PowerShell was installed but pwsh is not available on PATH."
                return $false
            }
        } else {
            Write-Info "PowerShell 7 is already installed, skipping installation."
        }
    } catch {
        Write-ErrorMessage "Failed to install PowerShell: $($_.Exception.Message)"
        return $false
    }

    # Install Git if not present
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Info "Git not found. Installing Git..."
        $wingetArguments = @(
            'install', '--id', 'Git.Git', '--exact', '--force',
            '--source', 'winget', '--scope', 'user',
            '--accept-source-agreements', '--accept-package-agreements',
            '--disable-interactivity'
        )
        & winget @wingetArguments
        if ($LASTEXITCODE -ne 0) {
            Write-ErrorMessage "Winget failed to install Git (exit code $LASTEXITCODE)."
            return $false
        }

        Update-DotfilesProcessPath
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            Write-ErrorMessage "Git was installed but git is not available on PATH."
            return $false
        }
    } else {
        Write-Info "Git is already installed, skipping installation."
    }

    return $true
}

function ConvertFrom-DotfilesWhoAmIUpnResult {
    param (
        [AllowNull()]
        $Output,
        [int]$ExitCode
    )

    if ($ExitCode -ne 0) {
        return $null
    }

    $outputRecords = @($Output)
    if ($outputRecords.Count -ne 1) {
        return $null
    }

    $upn = ([string]$outputRecords[0]).Trim()
    if ($upn.Contains([char]13) -or $upn.Contains([char]10) -or $upn -notmatch '^[^@\\]+@[^@\\]+$') {
        return $null
    }

    return $upn
}

function Get-DotfilesSignedInUserUpn {
    $whoAmI = Get-Command -Name 'whoami.exe' -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $whoAmI) {
        return $null
    }

    $output = & $whoAmI.Source /upn 2>$null
    return ConvertFrom-DotfilesWhoAmIUpnResult -Output $output -ExitCode $LASTEXITCODE
}

function Test-DotfilesUserHomeAliasLeaf {
    param (
        [AllowNull()]
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $false
    }

    if ($Name -match '[^\x20-\x7E]' -or $Name -match '\s' -or $Name -match '[<>:"/\\|?*]') {
        return $false
    }

    if ($Name -match '^\.+$' -or $Name -match '[. ]$') {
        return $false
    }

    if ($Name -match '^(CON|PRN|AUX|NUL|CLOCK\$|CONIN\$|CONOUT\$|COM[0-9]|LPT[0-9])([. ]|$)') {
        return $false
    }

    return $true
}

function Get-DotfilesUserHomeAliasPreflight {
    param (
        [Parameter(Mandatory)]
        [string]$UserProfile,
        [AllowNull()]
        [string]$AliasName,
        [AllowNull()]
        [string]$CurrentHome
    )

    $hasNonAsciiCharacter = @($UserProfile.ToCharArray() | Where-Object { [int]$_ -gt 127 }).Count -gt 0
    if (-not $hasNonAsciiCharacter) {
        return [pscustomobject]@{
            Action = 'Skip'
            AliasPath = $null
            Message = "Profile path '$UserProfile' is already ASCII-only."
        }
    }

    if (-not (Test-DotfilesUserHomeAliasLeaf -Name $AliasName)) {
        return [pscustomobject]@{
            Action = 'Fail'
            AliasPath = $null
            Message = 'Could not determine a safe user name for the home alias.'
        }
    }

    $aliasRoot = $UserProfile -replace '[\\/][^\\/]+$', ''
    $aliasPath = $aliasRoot + '\' + $AliasName
    try {
        # Unlike Test-Path, Get-Item -Force can expose a dangling reparse-point entry.
        # Recheck the concrete entry here and again in the child before any mutation.
        $existingItem = Get-Item -LiteralPath $aliasPath -Force -ErrorAction Stop
    }
    catch [System.Management.Automation.ItemNotFoundException] {
        return [pscustomobject]@{
            Action = 'Elevate'
            AliasPath = $aliasPath
            Message = "The home alias junction '$aliasPath' must be created."
        }
    }
    catch {
        return [pscustomobject]@{
            Action = 'Fail'
            AliasPath = $aliasPath
            Message = "Cannot inspect home alias path '$aliasPath': $($_.Exception.Message)"
        }
    }

    $targets = @($existingItem.Target)
    $isReparsePoint = [bool]($existingItem.Attributes -band [IO.FileAttributes]::ReparsePoint)
    $isCorrectJunction = $isReparsePoint -and
        $existingItem.LinkType -eq 'Junction' -and
        $targets.Count -eq 1 -and
        ([string]$targets[0] -ieq $UserProfile)
    if (-not $isCorrectJunction) {
        return [pscustomobject]@{
            Action = 'Fail'
            AliasPath = $aliasPath
            Message = "'$aliasPath' exists but is not a junction targeting '$UserProfile'."
        }
    }

    if ($CurrentHome -ieq $aliasPath) {
        return [pscustomobject]@{
            Action = 'Skip'
            AliasPath = $aliasPath
            Message = 'The home alias junction and user HOME are already correct.'
        }
    }

    return [pscustomobject]@{
        Action = 'RunNonElevated'
        AliasPath = $aliasPath
        Message = 'The home alias junction is correct; only user HOME needs an update.'
    }
}

function Resolve-DotfilesUserHomeAliasName {
    param (
        [AllowNull()]
        [string]$WindowsIdentityName,
        [AllowNull()]
        [string]$UserName
    )

    $upn = Get-DotfilesSignedInUserUpn
    if ($upn -match '^([^@\\]+)@[^@\\]+$' -and (Test-DotfilesUserHomeAliasLeaf -Name $Matches[1])) {
        return $Matches[1]
    }

    if ($WindowsIdentityName -match '^([^@\\]+)@[^@\\]+$' -and (Test-DotfilesUserHomeAliasLeaf -Name $Matches[1])) {
        return $Matches[1]
    }

    if (Test-DotfilesUserHomeAliasLeaf -Name $UserName) {
        return $UserName
    }

    return $null
}

# Function to return the current user
function Get-CurrentUser {
    try {
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        return $currentUser
    } catch {
        Write-ErrorMessage "Failed to get current user: $($_.Exception.Message)"
        return $null
    }
}

# Function to test if this powershell script is run as an administrator
function Test-IsElevated {
    $wid = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $prp = [System.Security.Principal.WindowsPrincipal]::new($wid)
    $adm = [System.Security.Principal.WindowsBuiltInRole]::Administrator
    return $prp.IsInRole($adm)
}


# Function to check if the script is running as Administrator
function Test-RunningAsAdmin {
    return Test-IsElevated
}

# Function to check if the script is running as a normal user
function Test-RunningAsUser {
    return -not (Test-RunningAsAdmin)
}

# Function to check if the script is running as SYSTEM
function Test-RunningAsSystem {
    $wid = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    return $wid.Name -eq "NT AUTHORITY\SYSTEM"
}

# Function to check if the script is running as a service
function Test-RunningAsService {
    $wid = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    return $wid.Name -eq "NT SERVICE\TrustedInstaller"
}

# Function to check if the script is running as a user with administrative privileges
function Test-RunningAsAdminUser {
    return Test-IsElevated
}

# Function to Enable Developer Mode
# This function will attempt to enable Developer Mode by modifying the registry.
function Enable-DeveloperMode {
    Write-Host "Enabling Developer Mode (requires elevation)..."
    $command = 'reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /t REG_DWORD /f /v "AllowDevelopmentWithoutDevLicense" /d "1"'
    Start-Process powershell -ArgumentList "-NoProfile -WindowStyle Hidden -Command $command" -Verb RunAs -Wait
    Write-Host "Developer Mode should now be enabled. Please re-run this script if you still see errors."
}

# Check if Developer Mode is enabled
function Test-DeveloperMode {
    try {
        $reg = Get-ItemProperty -Path "HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\AppModelUnlock" -Name "AllowDevelopmentWithoutDevLicense" -ErrorAction Stop
        return $reg.AllowDevelopmentWithoutDevLicense -eq 1
    } catch {
        return $false
    }
}

function Get-DotfilesConfigDirectory {
    $DotfilesRoot = Split-Path -Parent $PSScriptRoot
    return (Join-Path $DotfilesRoot "dotfiles-configurations")
}

function Get-DotfilesConfigFile {
    return @(
        "dotfiles-bootstrap-variables.json",
        "git-variables.json",
        "env-variables.json",
        "winget-packages.json",
        "windows-features.json",
        "setup-modules.json"
    )
}

function Read-DotfilesJsonFile {
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )

    $content = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($content)) {
        return [pscustomobject]@{}
    }

    return $content | ConvertFrom-Json
}

function Set-DotfilesBootstrapBranch {
    param (
        [Parameter(Mandatory)]
        [string]$ConfigPath,
        [Parameter(Mandatory)]
        [string]$Branch
    )

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw "Bootstrap configuration file not found: $ConfigPath"
    }

    $config = Read-DotfilesJsonFile -Path $ConfigPath
    if (Test-DotfilesObjectProperty -InputObject $config -Name "GITHUB_DOTFILES_BRANCH") {
        $config.GITHUB_DOTFILES_BRANCH = $Branch
    } else {
        $config | Add-Member -NotePropertyName "GITHUB_DOTFILES_BRANCH" -NotePropertyValue $Branch
    }

    $config | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
}

function ConvertTo-DotfilesStringArray {
    param (
        [AllowNull()]
        $Value
    )

    if ($null -eq $Value) {
        return @()
    }

    return @($Value) |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
        ForEach-Object { [string]$_ }
}

function Test-DotfilesObjectProperty {
    param (
        [AllowNull()]
        $InputObject,
        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($null -eq $InputObject) {
        return $false
    }

    return ($InputObject.PSObject.Properties.Name -contains $Name)
}

function Add-DotfilesSetupPlanItem {
    param (
        [Parameter(Mandatory)]
        $Plan,
        [Parameter(Mandatory)]
        $Entry
    )

    if ([string]::IsNullOrWhiteSpace($Entry.script)) {
        throw "Setup module entry is missing a script value."
    }

    $scriptName = [string]$Entry.script
    $alreadyAdded = $Plan | Where-Object { $_.Script -eq $scriptName } | Select-Object -First 1
    if ($alreadyAdded) {
        return
    }

    $Plan.Add([pscustomobject]@{
        Name = if ([string]::IsNullOrWhiteSpace($Entry.name)) { [System.IO.Path]::GetFileNameWithoutExtension($scriptName) } else { [string]$Entry.name }
        Script = $scriptName
        RequiresAdmin = [bool]$Entry.requiresAdmin
    })
}

function Resolve-DotfilesWindowsFeature {
    param (
        [string]$ConfigPath = (Join-Path (Get-DotfilesConfigDirectory) "windows-features.json"),
        [string]$BootstrapPath = (Join-Path (Get-DotfilesConfigDirectory) "dotfiles-bootstrap-variables.json"),
        [string[]]$Groups = @(),
        [switch]$GroupsSpecified
    )

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw "Windows feature configuration file not found: $ConfigPath"
    }

    $config = Read-DotfilesJsonFile -Path $ConfigPath
    $bootstrapHasInstallFeatures = $false

    if (-not $GroupsSpecified -and (Test-Path -LiteralPath $BootstrapPath)) {
        $bootstrap = Read-DotfilesJsonFile -Path $BootstrapPath
        $bootstrapHasInstallFeatures = Test-DotfilesObjectProperty -InputObject $bootstrap -Name "INSTALL_FEATURES"
        if ($bootstrapHasInstallFeatures) {
            $Groups = ConvertTo-DotfilesStringArray -Value $bootstrap.INSTALL_FEATURES
            if ($Groups.Count -eq 0) {
                return @()
            }
        }
    }

    $installAllGroups = (-not $GroupsSpecified) -and (-not $bootstrapHasInstallFeatures) -and ($Groups.Count -eq 0)
    $features = [System.Collections.Generic.List[string]]::new()

    foreach ($property in $config.PSObject.Properties) {
        $includeGroup = $installAllGroups -or ($Groups -contains $property.Name)
        if (-not $includeGroup) {
            continue
        }

        foreach ($featureName in (ConvertTo-DotfilesStringArray -Value $property.Value)) {
            if ($features -notcontains $featureName) {
                $features.Add($featureName)
            }
        }
    }

    return $features.ToArray()
}

function Test-DotfilesWindowsFeaturesEnabled {
    param([Parameter(Mandatory)][string[]]$FeatureName)

    if ($FeatureName.Count -eq 0) {
        return $true
    }

    try {
        $featureStates = @(Get-CimInstance -ClassName Win32_OptionalFeature -ErrorAction Stop)
    }
    catch {
        Write-WarningMessage "Could not query Windows optional feature state without elevation: $($_.Exception.Message)"
        return $false
    }

    foreach ($requestedFeature in $FeatureName) {
        $matches = @($featureStates | Where-Object { $_.Name -ieq $requestedFeature })
        if ($matches.Count -ne 1 -or [uint32]$matches[0].InstallState -ne 1) {
            return $false
        }
    }

    return $true
}

function Test-DotfilesProfileSymlinksCorrect {
    # Returns $true when every .ps1 file in the repo's powershell-profiles directory
    # already exists as a symlink pointing at its source file. Used by setup.ps1 to
    # skip relaunching Create-PowerShellProfileSymlink.ps1 elevated when nothing
    # needs to change. Returns $false on any uncertainty so setup still runs the module.
    param([Parameter(Mandatory)][string]$ProfilesSourceDirectory)

    if (-not (Test-Path -LiteralPath $ProfilesSourceDirectory -PathType Container)) {
        return $false
    }

    $profileFiles = @(Get-ChildItem -Path $ProfilesSourceDirectory -Filter '*.ps1' -ErrorAction SilentlyContinue)
    if ($profileFiles.Count -eq 0) {
        return $false
    }

    $profileDirectory = Split-Path -Parent $PROFILE
    foreach ($profileFile in $profileFiles) {
        $symlinkPath = Join-Path $profileDirectory $profileFile.Name

        if (-not (Test-Path -LiteralPath $symlinkPath)) {
            return $false
        }

        $existingItem = Get-Item -LiteralPath $symlinkPath -Force -ErrorAction SilentlyContinue
        if (-not $existingItem -or -not ($existingItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            return $false
        }

        if ($existingItem.Target -ne $profileFile.FullName) {
            return $false
        }
    }

    return $true
}

function Get-DotfilesSetupPlan {
    param (
        [Parameter(Mandatory)]
        $DotfilesVariables,
        [string]$ConfigDirectory = (Get-DotfilesConfigDirectory)
    )

    $setupModulesPath = Join-Path $ConfigDirectory "setup-modules.json"
    if (-not (Test-Path -LiteralPath $setupModulesPath)) {
        throw "Setup module configuration file not found: $setupModulesPath"
    }

    $setupConfig = Read-DotfilesJsonFile -Path $setupModulesPath
    $plan = [System.Collections.Generic.List[object]]::new()

    $hasInstallFeatures = Test-DotfilesObjectProperty -InputObject $DotfilesVariables -Name "INSTALL_FEATURES"
    $selectedFeatures = if ($hasInstallFeatures) { ConvertTo-DotfilesStringArray -Value $DotfilesVariables.INSTALL_FEATURES } else { @() }
    $runAllFeatureModules = -not $hasInstallFeatures

    foreach ($entry in $setupConfig.features) {
        $matched = $runAllFeatureModules
        if (-not $matched -and $selectedFeatures.Count -gt 0) {
            $selectors = ConvertTo-DotfilesStringArray -Value $entry.whenSelected
            $matched = $null -ne ($selectors | Where-Object { $selectedFeatures -contains $_ } | Select-Object -First 1)
        }

        if ($matched) {
            Add-DotfilesSetupPlanItem -Plan $plan -Entry $entry
        }
    }

    $hasInstallPackages = Test-DotfilesObjectProperty -InputObject $DotfilesVariables -Name "INSTALL_PACKAGES"
    $selectedPackages = if ($hasInstallPackages) { ConvertTo-DotfilesStringArray -Value $DotfilesVariables.INSTALL_PACKAGES } else { @() }
    $runAllPackageModules = -not $hasInstallPackages
    if ($runAllPackageModules -or $selectedPackages.Count -gt 0) {
        foreach ($entry in $setupConfig.packages) {
            $selectors = ConvertTo-DotfilesStringArray -Value $entry.whenSelected
            $matched = $runAllPackageModules -or $selectors.Count -eq 0
            if (-not $matched) {
                $matched = $null -ne ($selectors | Where-Object { $selectedPackages -contains $_ } | Select-Object -First 1)
            }

            if ($matched) {
                Add-DotfilesSetupPlanItem -Plan $plan -Entry $entry
            }
        }
    }

    $hasInstallSettings = Test-DotfilesObjectProperty -InputObject $DotfilesVariables -Name "INSTALL_SETTINGS"
    $selectedSettings = if ($hasInstallSettings) { ConvertTo-DotfilesStringArray -Value $DotfilesVariables.INSTALL_SETTINGS } else { @() }
    $runAllSettings = -not $hasInstallSettings

    $settingGroups = if ($setupConfig.settings) { $setupConfig.settings.PSObject.Properties } else { @() }
    foreach ($group in $settingGroups) {
        if ($runAllSettings -or ($selectedSettings -contains $group.Name)) {
            foreach ($entry in $group.Value) {
                Add-DotfilesSetupPlanItem -Plan $plan -Entry $entry
            }
        }
    }

    return $plan.ToArray()
}

function Get-DotfilesRequiredPackageGroup {
    param (
        [Parameter(Mandatory)]
        $SetupConfig,
        [string[]]$SelectedSettings = @()
    )

    $requiredGroups = [System.Collections.Generic.List[string]]::new()
    $settingGroups = if ($SetupConfig.settings) { $SetupConfig.settings.PSObject.Properties } else { @() }

    foreach ($group in $settingGroups) {
        if ($SelectedSettings -notcontains $group.Name) {
            continue
        }

        foreach ($entry in $group.Value) {
            foreach ($packageGroup in (ConvertTo-DotfilesStringArray -Value $entry.requiresPackageGroups)) {
                if ($requiredGroups -notcontains $packageGroup) {
                    $requiredGroups.Add($packageGroup)
                }
            }
        }
    }

    return $requiredGroups.ToArray()
}

function Assert-DotfilesSetupDependencies {
    param (
        [Parameter(Mandatory)]
        $DotfilesVariables,
        [string]$ConfigDirectory = (Get-DotfilesConfigDirectory)
    )

    if (-not (Test-DotfilesObjectProperty -InputObject $DotfilesVariables -Name "INSTALL_PACKAGES")) {
        return
    }

    $setupModulesPath = Join-Path $ConfigDirectory "setup-modules.json"
    if (-not (Test-Path -LiteralPath $setupModulesPath)) {
        throw "Setup module configuration file not found: $setupModulesPath"
    }

    $setupConfig = Read-DotfilesJsonFile -Path $setupModulesPath
    $selectedPackages = ConvertTo-DotfilesStringArray -Value $DotfilesVariables.INSTALL_PACKAGES
    $selectedSettings = if (Test-DotfilesObjectProperty -InputObject $DotfilesVariables -Name "INSTALL_SETTINGS") {
        ConvertTo-DotfilesStringArray -Value $DotfilesVariables.INSTALL_SETTINGS
    } else {
        @($setupConfig.settings.PSObject.Properties.Name)
    }

    $requiredPackages = Get-DotfilesRequiredPackageGroup -SetupConfig $setupConfig -SelectedSettings $selectedSettings
    $missingPackages = @($requiredPackages | Where-Object { $selectedPackages -notcontains $_ })

    if ($missingPackages.Count -gt 0) {
        throw "Selected settings require missing package group(s): $($missingPackages -join ', ')"
    }
}

function Initialize-DotfilesConfiguration {
    param (
        [switch]$NonInteractive
    )

    $DotfilesRoot = Split-Path -Parent $PSScriptRoot
    $ConfigScript = Join-Path (Join-Path $DotfilesRoot "setup-scripts") "configure.ps1"

    if (-not (Test-Path -LiteralPath $ConfigScript)) {
        throw "Configuration script not found: $ConfigScript"
    }

    $ConfigDirectory = Get-DotfilesConfigDirectory
    $RequiredConfigFiles = Get-DotfilesConfigFile

    $MissingConfigFiles = @($RequiredConfigFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path $ConfigDirectory $_)) })
    if ($MissingConfigFiles.Count -eq 0) {
        return
    }

    Write-WarningMessage "Missing local configuration files: $($MissingConfigFiles -join ', ')"
    Write-Info "Launching dotfiles configuration TUI to create local configuration from .example templates..."

    if ($NonInteractive) {
        & $ConfigScript -NonInteractive
    } else {
        & $ConfigScript
    }

    if (-not $?) {
        throw "Configuration TUI failed."
    }
}

function Resolve-DotfilesRepositoryUrl {
    param (
        [Parameter(Mandatory)]
        $DotfilesVariables
    )

    $endpointType = $DotfilesVariables.REPOSITORY_ENDPOINT_TYPE
    if ([string]::IsNullOrWhiteSpace($endpointType)) {
        $endpointType = "github-https"
    }

    switch ($endpointType) {
        "github-https" {
            return "https://github.com/$($DotfilesVariables.GITHUB_ACCOUNT)/$($DotfilesVariables.GITHUB_DOTFILES_REPO).git"
        }
        "github-ssh" {
            return "git@github.com:$($DotfilesVariables.GITHUB_ACCOUNT)/$($DotfilesVariables.GITHUB_DOTFILES_REPO).git"
        }
        "custom" {
            if ([string]::IsNullOrWhiteSpace($DotfilesVariables.CUSTOM_REPOSITORY_URL)) {
                throw "CUSTOM_REPOSITORY_URL must be set when REPOSITORY_ENDPOINT_TYPE is 'custom'."
            }
            return $DotfilesVariables.CUSTOM_REPOSITORY_URL
        }
        default {
            throw "Unsupported REPOSITORY_ENDPOINT_TYPE '$endpointType'. Supported values: github-https, github-ssh, custom."
        }
    }
}

function Sync-DotfilesLocalConfiguration {
    param (
        [Parameter(Mandatory)]
        [string]$SourceRoot,
        [Parameter(Mandatory)]
        [string]$TargetRoot
    )

    $sourceConfigDirectory = Join-Path $SourceRoot "dotfiles-configurations"
    $targetConfigDirectory = Join-Path $TargetRoot "dotfiles-configurations"

    if (-not (Test-Path -LiteralPath $sourceConfigDirectory)) { return }
    if (-not (Test-Path -LiteralPath $targetConfigDirectory)) {
        New-Item -ItemType Directory -Path $targetConfigDirectory -Force | Out-Null
    }

    $sourcePath = (Get-Item -LiteralPath $sourceConfigDirectory).FullName
    $targetPath = (Get-Item -LiteralPath $targetConfigDirectory).FullName
    if ($sourcePath -eq $targetPath) { return }

    Get-ChildItem -LiteralPath $sourceConfigDirectory -Filter "*.json" -File | ForEach-Object {
        $targetFile = Join-Path $targetConfigDirectory $_.Name
        Copy-Item -LiteralPath $_.FullName -Destination $targetFile -Force
        Write-Info "Copied local configuration '$($_.Name)' to cloned repository."
    }
}

# Function to get the dotfiles bootstrap variables
function Get-DotfilesBootstrapVariables {
    param (
        [switch]$NonInteractive
    )

    try {
        Initialize-DotfilesConfiguration -NonInteractive:$NonInteractive

        $DotfilesConfigFolder = Get-DotfilesConfigDirectory
        $DotfilesVariablesFile = Get-ChildItem -LiteralPath $DotfilesConfigFolder -Filter "dotfiles-bootstrap-variables.json" -ErrorAction Stop

        if ($DotfilesVariablesFile) {
            $DotfilesVariables = Get-Content -LiteralPath $DotfilesVariablesFile.FullName | ConvertFrom-Json
        } else {
            throw "The dotfiles-bootstrap-variables.json file was not found in $DotfilesConfigFolder"
        }
    } catch {
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host "Please run setup-scripts\configure.ps1 and try again."
        Stop-Logging
        Exit 1
    }

    Write-Host "Dotfiles Bootstrap Variables to be applied:"
    foreach ($kv in $DotfilesVariables.PSObject.Properties) {
        if ($kv.Name -eq "REPOSITORY_ENDPOINTS") { continue }
        if ($kv.Value -is [System.Collections.IEnumerable] -and $kv.Value -isnot [string]) {
            Write-Host ("{0,-25}:" -f $kv.Name)
            foreach ($item in $kv.Value) {
                Write-Host ("  - {0}" -f $item)
            }
        } else {
            Write-Host ("{0,-25}: {1}" -f $kv.Name, $kv.Value)
        }
    }
    return $DotfilesVariables
}

# Function to check if script is running in a VM environment
function Test-RunningInVM {
    $vmTypes = @("VirtualBox", "VMware", "Hyper-V", "Parallels", "QEMU")
    $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
    Write-Host "Checking if the machine is running in a VM environment..."
    foreach ($vmType in $vmTypes) {
        if ($computerSystem | Where-Object { $_.Manufacturer -like "*$vmType*" }) {
            return $true
        }
    }
    if ($computerSystem | Where-Object { $_.Model -like "*Virtual Machine*" }) {
        return $true
    }
    Write-Host "This machine is not running in a recognized VM environment."
    return $false
}
