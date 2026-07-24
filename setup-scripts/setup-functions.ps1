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
        [string]$LogFilePath
    )
    # Ensure the log directory exists
    $logDir = Split-Path -Parent $LogFilePath
    if (!(Test-Path -Path $logDir)) { 
        try {
            New-Item -Path $logDir -ItemType Directory | Out-Null
        }
        catch {
            Write-WarningMessage "Cannot create log directory: $($_.Exception.Message)"
            $LogFilePath = "$env:TEMP\$(Split-Path -Leaf $LogFilePath)"
            Write-WarningMessage "Logging to temporary location: $LogFilePath"
        }
    }
    # Start logging to the specified file
    try {
        Start-Transcript -Path $LogFilePath -ErrorAction Stop
    }
    catch {
        Write-WarningMessage "Cannot start transcript: $($_.Exception.Message)"
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
    $installModuleParams = @{}
    $allUsersScope = if (Test-IsElevated) { 'AllUsers' } else { 'CurrentUser' }
    $wingetScopeArgs = if (Test-IsElevated) { @('--scope', 'machine') } else { @() }
    try {
        # Check if NuGet provider is installed
        if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
            Write-Info "NuGet provider is not installed. Installing now..."
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope $allUsersScope
            Import-PackageProvider -Name NuGet -Force
        } else {
            Write-Info "NuGet provider is already installed, skipping installation."
        }
    } catch {
        Write-ErrorMessage "Failed to check/install NuGet provider: $($_.Exception.Message)"
        return $false
    }

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
                '--accept-source-agreements', '--accept-package-agreements'
            ) + $wingetScopeArgs
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

    # Ensure NuGet and PowerShellGet are up to date
    # Check and update NuGet provider
    try {
        $nugetProvider = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
        if (-not $nugetProvider -or $nugetProvider.Version -lt [Version]'2.8.5.201') {
            Write-Info "Updating NuGet provider..."
            try {
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope $allUsersScope -ErrorAction Stop
                Import-PackageProvider -Name NuGet -Force
            } catch {
                Write-WarningMessage "Failed to update NuGet provider: $_"
            }
        } else {
            Write-Info "NuGet provider is up to date."
        }
    } catch {
        Write-ErrorMessage "Failed to update NuGet provider: $($_.Exception.Message)"
    }

    # Check and update PowerShellGet
    try {
        $psGetModule = Get-Module -ListAvailable PowerShellGet | Sort-Object Version -Descending | Select-Object -First 1
        if (-not $psGetModule -or $psGetModule.Version -lt [Version]'2.2.5') {
            Write-Info "Updating PowerShellGet module..."
            try {
                Install-Module -Name PowerShellGet -Force -Scope $allUsersScope -ErrorAction Stop
                Write-Info "PowerShellGet updated. Please restart PowerShell to use the new version."
            } catch {
                Write-WarningMessage "Failed to update PowerShellGet: $_"
            }
        } else {
            Write-Info "PowerShellGet is up to date."
        }
    } catch {
        Write-ErrorMessage "Failed to install PowerShellGet module: $($_.Exception.Message)"
        return $false
    }

    try {
        # Determine if -AcceptLicense switch is supported
        $psGetModule = Get-Module PowerShellGet -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
        if ($psGetModule -and $psGetModule.Version -ge [Version]"2.0.0") {
            $installModuleParams.AcceptLicense = $true
        }
    } catch {
        Write-WarningMessage "Failed to check PowerShellGet version: $($_.Exception.Message)"
        $installModuleParams = @{}
    }

    # Install Git if not present
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Info "Git not found. Installing Git..."
        $wingetArguments = @(
            'install', '--id', 'Git.Git', '--exact', '--force',
            '--accept-source-agreements', '--accept-package-agreements'
        ) + $wingetScopeArgs
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

    # Ensure the PSGallery repository is registered
    try {
        $psGallery = Get-PSRepository -Name "PSGallery" -ErrorAction Stop
        if ($psGallery -and $psGallery.InstallationPolicy -ne "Trusted") {
            Write-Info "PSGallery repository is not trusted. Setting it to Trusted..."
            Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted
        }
    } catch {
        if ($_.Exception.Message -like '*already exists*') {
            Write-Info "PSGallery repository already exists. Skipping registration."
        } else {
            Write-Info "PSGallery repository not found. Registering it now..."
            try {
                Register-PSRepository -Default -ErrorAction Stop
            } catch {
                Write-ErrorMessage "Failed to register PSGallery repository: $_"
            }
        }
    }

    # Register the default repository if not already registered
    if (-not (Get-PSRepository -Name "PSGallery" -ErrorAction SilentlyContinue)) {
        Write-Info "Registering default PowerShell repository..."
        Register-PSRepository -Default
    }

    # Install the Winget Cmdlet required for enabling Windows features and system-level installation
    Write-Info "Ensuring the Winget Cmdlet is installed..."

    # Only install the module if it isn't already installed
    if (-not (Get-Module -ListAvailable -Name Microsoft.WinGet.Configuration)) {
        Write-Info "Installing the Microsoft.WinGet.Configuration module..."
        try {
            Install-Module -Name Microsoft.WinGet.Configuration -Force -Scope $allUsersScope @installModuleParams
            Write-Info "Microsoft.WinGet.Configuration module installed."
        } catch {
            Write-WarningMessage "Failed to install Microsoft.WinGet.Configuration: $_"
        }
    } else {
        Write-Info "Microsoft.WinGet.Configuration module is already installed, skipping installation."
    }

    return $true
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
    if ((-not $hasInstallPackages) -or $selectedPackages.Count -gt 0) {
        foreach ($entry in $setupConfig.packages) {
            Add-DotfilesSetupPlanItem -Plan $plan -Entry $entry
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
