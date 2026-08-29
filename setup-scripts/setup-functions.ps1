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

    $aliasRoot = Split-Path -Path $UserProfile -Parent
    try {
        $aliasPath = Join-Path -Path $aliasRoot -ChildPath $AliasName -ErrorAction Stop
    }
    catch [System.Management.Automation.DriveNotFoundException] {
        $combinedAliasPath = [IO.Path]::Combine($aliasRoot, $AliasName)
        if ($combinedAliasPath.StartsWith('\\') -or $combinedAliasPath.StartsWith('//')) {
            $aliasPath = '\\' + $combinedAliasPath.TrimStart('\', '/').Replace('/', '\')
        }
        else {
            $aliasPath = $combinedAliasPath.Replace('/', '\')
        }
    }
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
    if (-not $isReparsePoint) {
        return [pscustomobject]@{
            Action = 'Fail'
            AliasPath = $aliasPath
            Message = "'$aliasPath' already exists as a regular path."
        }
    }

    $isCorrectJunction = $existingItem.LinkType -eq 'Junction' -and
        $targets.Count -eq 1 -and
        ([string]$targets[0] -ieq $UserProfile)
    if (-not $isCorrectJunction) {
        $observedLinkType = if ([string]::IsNullOrEmpty([string]$existingItem.LinkType)) { '<none>' } else { [string]$existingItem.LinkType }
        $observedTarget = if ($targets.Count -eq 0) { '<none>' } else { ($targets | ForEach-Object { "'$([string]$_)'" }) -join ', ' }
        return [pscustomobject]@{
            Action = 'Fail'
            AliasPath = $aliasPath
            Message = "'$aliasPath' exists but has LinkType '$observedLinkType' and Target $observedTarget; expected a junction targeting '$UserProfile'."
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

function Get-DotfilesUserHomeAliasJunctionPreflight {
    param (
        [Parameter(Mandatory)]
        [string]$UserProfile,
        [Parameter(Mandatory)]
        [string]$AliasPath
    )

    $aliasName = Split-Path -Path $AliasPath -Leaf
    $aliasRoot = Split-Path -Path $UserProfile -Parent
    try {
        $expectedAliasPath = Join-Path -Path $aliasRoot -ChildPath $aliasName -ErrorAction Stop
    }
    catch [System.Management.Automation.DriveNotFoundException] {
        $combinedAliasPath = [IO.Path]::Combine($aliasRoot, $aliasName)
        if ($combinedAliasPath.StartsWith('\\') -or $combinedAliasPath.StartsWith('//')) {
            $expectedAliasPath = '\\' + $combinedAliasPath.TrimStart('\', '/').Replace('/', '\')
        }
        else {
            $expectedAliasPath = $combinedAliasPath.Replace('/', '\')
        }
    }

    if (-not [string]::Equals($expectedAliasPath, $AliasPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        return [pscustomobject]@{
            Action = 'Fail'
            AliasPath = $AliasPath
            Message = "Supplied alias path '$AliasPath' does not match expected alias path '$expectedAliasPath'."
        }
    }

    return Get-DotfilesUserHomeAliasPreflight `
        -UserProfile $UserProfile `
        -AliasName $aliasName `
        -CurrentHome $AliasPath
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

function Invoke-DotfilesGitCommand {
    param (
        [Parameter(Mandatory)]
        [string]$RepositoryRoot,
        [Parameter(Mandatory)]
        [string[]]$ArgumentList
    )

    $gitCommand = Get-Command -Name 'git' -CommandType Application -ErrorAction Stop |
        Select-Object -First 1
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $gitCommand.Source
    $startInfo.WorkingDirectory = $RepositoryRoot
    $startInfo.Arguments = $ArgumentList -join ' '
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        throw "Failed to start Git in '$RepositoryRoot'."
    }
    $output = $process.StandardOutput.ReadToEnd()
    $errorOutput = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        Output = $output
        Error = $errorOutput
    }
}

function Get-DotfilesGitBlobBytes {
    param (
        [Parameter(Mandatory)]
        [string]$RepositoryRoot,
        [Parameter(Mandatory)]
        [string]$ObjectId
    )

    $gitCommand = Get-Command -Name 'git' -CommandType Application -ErrorAction Stop |
        Select-Object -First 1
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $gitCommand.Source
    $startInfo.WorkingDirectory = $RepositoryRoot
    $startInfo.Arguments = "cat-file blob $ObjectId"
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        throw "Failed to start Git while reading blob '$ObjectId'."
    }
    $memory = [IO.MemoryStream]::new()
    $process.StandardOutput.BaseStream.CopyTo($memory)
    $errorOutput = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) {
        throw "Cannot read Git blob '$ObjectId': $($errorOutput.Trim())"
    }

    return $memory.ToArray()
}

function Test-DotfilesJsonBytes {
    param (
        [Parameter(Mandatory)]
        [byte[]]$Bytes
    )

    try {
        $stream = [IO.MemoryStream]::new($Bytes, $false)
        $encoding = [Text.UTF8Encoding]::new($false, $true)
        $reader = [IO.StreamReader]::new($stream, $encoding, $true)
        $content = $reader.ReadToEnd()
        if ([string]::IsNullOrWhiteSpace($content)) {
            return $false
        }
        $content | ConvertFrom-Json -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        return $false
    }
    finally {
        if ($reader) { $reader.Dispose() }
        if ($stream) { $stream.Dispose() }
    }
}

function Get-DotfilesSha256Hex {
    param (
        [Parameter(Mandatory)]
        [byte[]]$Bytes
    )

    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha256.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
}

function Get-DotfilesLegacyCanonicalPath {
    param ([Parameter(Mandatory)][string]$Path)

    $normalizedInput = $Path.Replace('/', '\')
    if ($normalizedInput.StartsWith('\\?\', [StringComparison]::Ordinal) -or
        $normalizedInput.StartsWith('\\.\', [StringComparison]::Ordinal)) {
        throw "Windows device namespace paths are not allowed: $Path"
    }
    $fullPath = [IO.Path]::GetFullPath($Path)
    $normalizedFullPath = $fullPath.Replace('/', '\')
    if ($normalizedFullPath.StartsWith('\\?\', [StringComparison]::Ordinal) -or
        $normalizedFullPath.StartsWith('\\.\', [StringComparison]::Ordinal)) {
        throw "Windows device namespace paths are not allowed: $fullPath"
    }
    return $fullPath
}

function Get-DotfilesLegacyPathComparison {
    if ([IO.Path]::DirectorySeparatorChar -eq '\') {
        return [StringComparison]::OrdinalIgnoreCase
    }
    return [StringComparison]::Ordinal
}

function Test-DotfilesLegacyPathWithinRoot {
    param (
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Root
    )

    $fullPath = Get-DotfilesLegacyCanonicalPath -Path $Path
    $fullRoot = Get-DotfilesLegacyCanonicalPath -Path $Root
    $comparison = Get-DotfilesLegacyPathComparison
    if ($fullPath.Equals($fullRoot, $comparison)) { return $true }
    $rootPrefix = $fullRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    return $fullPath.StartsWith($rootPrefix, $comparison)
}

function Assert-DotfilesLegacyPathHasNoReparsePoint {
    param ([Parameter(Mandatory)][string]$Path)

    $current = Get-DotfilesLegacyCanonicalPath -Path $Path
    while (-not [string]::IsNullOrWhiteSpace($current)) {
        $item = $null
        try {
            $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
        }
        catch [Management.Automation.ItemNotFoundException] {
            $item = $null
        }
        catch {
            throw "Could not inspect migration path component '$current': $_"
        }
        if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Reparse points are not allowed in migration paths: $current"
        }
        $parent = Split-Path -Parent $current
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $current) { break }
        $current = $parent
    }
}

function ConvertFrom-DotfilesLegacyJsonBytes {
    param (
        [Parameter(Mandatory)][byte[]]$Bytes,
        [Parameter(Mandatory)][string]$Description
    )

    try {
        $text = [Text.UTF8Encoding]::new($false, $true).GetString($Bytes)
        return ($text | ConvertFrom-Json -ErrorAction Stop)
    }
    catch {
        throw "$Description must contain valid UTF-8 JSON. $($_.Exception.Message)"
    }
}

function Read-DotfilesMigrationTemplate {
    param (
        [Parameter(Mandatory)][string]$ConfigDirectory,
        [Parameter(Mandatory)][string]$Name
    )

    $path = Join-Path $ConfigDirectory "$Name.example"
    try {
        $value = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Current migration template '$path' must contain valid JSON. $($_.Exception.Message)"
    }
    if ($value -isnot [pscustomobject]) {
        throw "Current migration template '$path' must be a JSON object."
    }
    return $value
}

function Copy-DotfilesJsonObject {
    param ([Parameter(Mandatory)]$InputObject)
    return ($InputObject | ConvertTo-Json -Depth 100 | ConvertFrom-Json)
}

function Get-DotfilesCurrentWingetEntry {
    param (
        [Parameter(Mandatory)]$WingetTemplate,
        [Parameter(Mandatory)][string]$LegacyId
    )

    $aliases = @{
        'Google.Chrome' = 'Google.Chrome.EXE'
        'Microsoft.WindowsSubsystemForLinux' = 'Microsoft.WSL'
    }
    $lookupId = if ($aliases.ContainsKey($LegacyId)) { $aliases[$LegacyId] } else { $LegacyId }
    $allEntries = @($WingetTemplate.PSObject.Properties | ForEach-Object { @($_.Value) })
    $match = $allEntries | Where-Object { $_.id -ceq $lookupId } | Select-Object -First 1
    if (-not $match) {
        $match = $allEntries | Where-Object { $_.id -ieq $lookupId } | Select-Object -First 1
    }
    if ($match) { return Copy-DotfilesJsonObject -InputObject $match }
    return [pscustomobject][ordered]@{ id = $LegacyId }
}

function New-DotfilesLegacyMigrationCandidates {
    param (
        [Parameter(Mandatory)][string]$ConfigDirectory,
        [Parameter(Mandatory)][hashtable]$LegacyBlobs
    )

    $bootstrapTemplate = Read-DotfilesMigrationTemplate -ConfigDirectory $ConfigDirectory -Name 'dotfiles-bootstrap-variables.json'
    $gitTemplate = Read-DotfilesMigrationTemplate -ConfigDirectory $ConfigDirectory -Name 'git-variables.json'
    $envTemplate = Read-DotfilesMigrationTemplate -ConfigDirectory $ConfigDirectory -Name 'env-variables.json'
    $wingetTemplate = Read-DotfilesMigrationTemplate -ConfigDirectory $ConfigDirectory -Name 'winget-packages.json'
    $setupTemplate = Read-DotfilesMigrationTemplate -ConfigDirectory $ConfigDirectory -Name 'setup-modules.json'
    $featureTemplate = Read-DotfilesMigrationTemplate -ConfigDirectory $ConfigDirectory -Name 'windows-features.json'

    $legacyBootstrap = ConvertFrom-DotfilesLegacyJsonBytes -Bytes $LegacyBlobs['dotfiles-configurations/dotfiles-bootstrap-variables.json'] -Description 'Legacy bootstrap configuration'
    $legacyGit = ConvertFrom-DotfilesLegacyJsonBytes -Bytes $LegacyBlobs['dotfiles-configurations/git-variables.json'] -Description 'Legacy Git configuration'
    $legacyEnv = ConvertFrom-DotfilesLegacyJsonBytes -Bytes $LegacyBlobs['dotfiles-configurations/env-variables.json'] -Description 'Legacy environment configuration'
    $legacyWinget = ConvertFrom-DotfilesLegacyJsonBytes -Bytes $LegacyBlobs['dotfiles-configurations/winget-packages.json'] -Description 'Legacy winget configuration'
    foreach ($item in @(
        @{ Value = $legacyBootstrap; Name = 'bootstrap' },
        @{ Value = $legacyGit; Name = 'Git' },
        @{ Value = $legacyWinget; Name = 'winget' }
    )) {
        if ($item.Value -isnot [pscustomobject]) { throw "Legacy $($item.Name) configuration must be a JSON object." }
    }
    if ($null -eq $legacyEnv -or $legacyEnv -isnot [pscustomobject]) { throw 'The generated environment candidate must be a JSON object.' }

    $warnings = [Collections.Generic.List[string]]::new()
    $bootstrap = Copy-DotfilesJsonObject -InputObject $bootstrapTemplate
    foreach ($name in @('GITHUB_ACCOUNT', 'GITHUB_DOTFILES_REPO', 'GITHUB_DOTFILES_BRANCH', 'WORKSPACE_FOLDER')) {
        if ($legacyBootstrap.PSObject.Properties.Name -contains $name) { $bootstrap.$name = $legacyBootstrap.$name }
    }
    foreach ($property in $legacyBootstrap.PSObject.Properties) {
        if ($bootstrapTemplate.PSObject.Properties.Name -notcontains $property.Name) {
            $warnings.Add("Removed legacy bootstrap field '$($property.Name)' was not copied to the candidate.")
        }
    }

    $featureGroups = @($featureTemplate.PSObject.Properties.Name)
    $settingGroups = @($setupTemplate.settings.PSObject.Properties.Name)
    $packageGroups = @($wingetTemplate.PSObject.Properties.Name)
    $legacyFeatureSelections = @(ConvertTo-DotfilesStringArray -Value $legacyBootstrap.INSTALL_FEATURES)
    $legacySettingSelections = @(ConvertTo-DotfilesStringArray -Value $legacyBootstrap.INSTALL_SETTINGS)
    $bootstrap.INSTALL_FEATURES = @($legacyFeatureSelections | Where-Object { $featureGroups -contains $_ })
    $bootstrap.INSTALL_SETTINGS = @($legacySettingSelections | Where-Object { $settingGroups -contains $_ })
    foreach ($group in $legacyFeatureSelections) {
        if ($featureGroups -notcontains $group) { $warnings.Add("Unsupported legacy feature selection '$group' was not copied to the candidate.") }
    }
    foreach ($group in $legacySettingSelections) {
        if ($settingGroups -notcontains $group) { $warnings.Add("Unsupported legacy setting selection '$group' was not copied to the candidate.") }
    }
    $selectedPackages = [Collections.Generic.List[string]]::new()
    foreach ($group in (ConvertTo-DotfilesStringArray -Value $legacyBootstrap.INSTALL_PACKAGES)) {
        if ($packageGroups -contains $group) {
            if (-not $selectedPackages.Contains($group)) { $selectedPackages.Add($group) }
        } else {
            $warnings.Add("Unsupported legacy package selection '$group' was not copied to the candidate.")
        }
    }
    $legacyProductivityIds = if ($legacyWinget.PSObject.Properties.Name -contains 'productivity') {
        @(ConvertTo-DotfilesStringArray -Value $legacyWinget.productivity)
    } else { @() }
    if ($selectedPackages.Contains('productivity') -and $legacyProductivityIds -icontains 'Microsoft.PowerBI' -and -not $selectedPackages.Contains('PowerBI')) {
        $selectedPackages.Add('PowerBI')
    }
    if ($selectedPackages.Contains('docker') -and $legacyWinget.PSObject.Properties.Name -contains 'wsl' -and -not $selectedPackages.Contains('wsl')) {
        $selectedPackages.Add('wsl')
    }
    foreach ($requiredGroup in (Get-DotfilesRequiredPackageGroup -SetupConfig $setupTemplate -SelectedSettings $bootstrap.INSTALL_SETTINGS)) {
        if ($packageGroups -contains $requiredGroup -and -not $selectedPackages.Contains($requiredGroup)) { $selectedPackages.Add($requiredGroup) }
    }
    $bootstrap.INSTALL_PACKAGES = $selectedPackages.ToArray()

    $gitCandidate = Copy-DotfilesJsonObject -InputObject $gitTemplate
    foreach ($property in $legacyGit.PSObject.Properties) {
        $gitCandidate | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value -Force
    }
    if ($legacyEnv.PSObject.Properties.Name -contains 'EnvironmentVariables' -and $legacyEnv.PSObject.Properties.Count -eq 1) {
        $environmentVariables = @($legacyEnv.EnvironmentVariables | ForEach-Object { Copy-DotfilesJsonObject -InputObject $_ })
    } else {
        $environmentVariables = [Collections.Generic.List[object]]::new()
        foreach ($property in $legacyEnv.PSObject.Properties) {
            $value = if ($null -eq $property.Value) {
                ''
            } elseif ($property.Value -is [string] -or $property.Value -is [ValueType]) {
                [string]$property.Value
            } else {
                $warnings.Add("Complex legacy environment value '$($property.Name)' was serialized as JSON for review.")
                $property.Value | ConvertTo-Json -Depth 100 -Compress
            }
            $environmentVariables.Add([pscustomobject][ordered]@{
                Name = $property.Name
                Value = $value
                Scope = 'User'
            })
        }
        $environmentVariables = $environmentVariables.ToArray()
    }
    $envCandidate = [pscustomobject][ordered]@{ EnvironmentVariables = $environmentVariables }

    $wingetCandidate = [pscustomobject][ordered]@{}
    foreach ($group in $legacyWinget.PSObject.Properties) {
        $entries = [Collections.Generic.List[object]]::new()
        foreach ($legacyEntry in @($group.Value)) {
            $legacyId = if ($legacyEntry -is [string]) { $legacyEntry } elseif ($legacyEntry.id) { [string]$legacyEntry.id } else { '' }
            if ([string]::IsNullOrWhiteSpace($legacyId)) { throw "Legacy winget group '$($group.Name)' contains an entry without an id." }
            $entries.Add((Get-DotfilesCurrentWingetEntry -WingetTemplate $wingetTemplate -LegacyId $legacyId))
        }
        $wingetCandidate | Add-Member -NotePropertyName $group.Name -NotePropertyValue $entries.ToArray()
        if ($group.Name -ceq 'Packages') { $warnings.Add("Legacy winget group 'Packages' has no current template equivalent and was preserved for review.") }
    }
    foreach ($group in $bootstrap.INSTALL_PACKAGES) {
        if ($wingetCandidate.PSObject.Properties.Name -notcontains $group) {
            $templateGroup = $wingetTemplate.PSObject.Properties[$group]
            if ($templateGroup) {
                $wingetCandidate | Add-Member -NotePropertyName $group -NotePropertyValue @($templateGroup.Value | ForEach-Object { Copy-DotfilesJsonObject -InputObject $_ })
            }
        }
    }

    foreach ($name in @('GITHUB_ACCOUNT', 'GITHUB_DOTFILES_REPO', 'GITHUB_DOTFILES_BRANCH', 'WORKSPACE_FOLDER')) {
        if ($bootstrap.PSObject.Properties.Name -notcontains $name -or [string]::IsNullOrWhiteSpace([string]$bootstrap.$name)) { throw "Generated bootstrap candidate requires nonempty '$name'." }
    }
    foreach ($name in @('INSTALL_FEATURES', 'INSTALL_PACKAGES', 'INSTALL_SETTINGS')) {
        if ($bootstrap.$name -is [string] -or $null -eq $bootstrap.$name) { throw "Generated bootstrap candidate requires array '$name'." }
    }
    foreach ($group in $bootstrap.INSTALL_FEATURES) { if ($featureGroups -notcontains $group) { throw "Generated bootstrap candidate selects unknown feature group '$group'." } }
    foreach ($group in $bootstrap.INSTALL_SETTINGS) { if ($settingGroups -notcontains $group) { throw "Generated bootstrap candidate selects unknown setting group '$group'." } }
    foreach ($group in $bootstrap.INSTALL_PACKAGES) {
        if ($packageGroups -notcontains $group -or $wingetCandidate.PSObject.Properties.Name -notcontains $group) { throw "Generated bootstrap candidate selects missing package group '$group'." }
    }
    $requiredGroups = Get-DotfilesRequiredPackageGroup -SetupConfig $setupTemplate -SelectedSettings $bootstrap.INSTALL_SETTINGS
    foreach ($group in $requiredGroups) { if ($bootstrap.INSTALL_PACKAGES -notcontains $group) { throw "Generated bootstrap candidate is missing required package group '$group'." } }
    foreach ($group in $wingetCandidate.PSObject.Properties) {
        foreach ($entry in @($group.Value)) {
            if ($entry -isnot [pscustomobject] -or [string]::IsNullOrWhiteSpace([string]$entry.id)) { throw "Generated winget candidate group '$($group.Name)' contains an invalid entry." }
        }
    }
    if ($envCandidate.EnvironmentVariables -is [string] -or $null -eq $envCandidate.EnvironmentVariables) {
        throw "Generated environment candidate requires an 'EnvironmentVariables' array."
    }
    foreach ($variable in @($envCandidate.EnvironmentVariables)) {
        if ($variable -isnot [pscustomobject] -or [string]::IsNullOrWhiteSpace([string]$variable.Name) -or $null -eq $variable.Value -or $variable.Scope -notin @('User', 'Machine')) {
            throw 'Generated environment candidate contains an invalid variable entry.'
        }
    }

    return [pscustomobject]@{
        Values = [ordered]@{
            'dotfiles-bootstrap-variables.json' = $bootstrap
            'git-variables.json' = $gitCandidate
            'env-variables.json' = $envCandidate
            'winget-packages.json' = $wingetCandidate
        }
        Warnings = $warnings.ToArray()
    }
}

function Get-DotfilesLegacyMigrationRoot {
    param ([string]$MigrationRoot)

    if ([string]::IsNullOrWhiteSpace($MigrationRoot)) {
        $migrationBase = $env:LOCALAPPDATA
        if ([string]::IsNullOrWhiteSpace($migrationBase)) { $migrationBase = $env:TEMP }
        if ([string]::IsNullOrWhiteSpace($migrationBase)) {
            throw 'Neither LOCALAPPDATA nor TEMP is available for external migration state.'
        }
        $MigrationRoot = Join-Path $migrationBase 'dotfiles/migrations'
    }
    return (Get-DotfilesLegacyCanonicalPath -Path $MigrationRoot)
}

function Get-DotfilesLegacyRepositoryBinding {
    param (
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$ConfigDirectory,
        [string]$MigrationRoot
    )

    $canonicalResult = Invoke-DotfilesGitCommand -RepositoryRoot $RepositoryRoot -ArgumentList @('rev-parse', '--show-toplevel')
    if ($canonicalResult.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($canonicalResult.Output)) {
        throw "Cannot resolve the repository canonical path: $($canonicalResult.Error.Trim())"
    }
    $repository = Get-DotfilesLegacyCanonicalPath -Path $canonicalResult.Output.Trim()
    $configuration = Get-DotfilesLegacyCanonicalPath -Path $ConfigDirectory
    $expectedConfiguration = Get-DotfilesLegacyCanonicalPath -Path (Join-Path $repository 'dotfiles-configurations')
    $comparison = Get-DotfilesLegacyPathComparison
    if (-not $configuration.Equals($expectedConfiguration, $comparison)) {
        throw "Configuration directory must be the repository's dotfiles-configurations directory: $expectedConfiguration"
    }
    $root = Get-DotfilesLegacyMigrationRoot -MigrationRoot $MigrationRoot
    if (Test-DotfilesLegacyPathWithinRoot -Path $root -Root $repository) {
        throw 'Migration directory must be outside the dotfiles repository.'
    }
    Assert-DotfilesLegacyPathHasNoReparsePoint -Path $repository
    Assert-DotfilesLegacyPathHasNoReparsePoint -Path $configuration
    Assert-DotfilesLegacyPathHasNoReparsePoint -Path $root

    $identity = Get-DotfilesSha256Hex -Bytes ([Text.UTF8Encoding]::new($false).GetBytes($repository))
    $repositoryState = Join-Path $root $identity
    return [pscustomobject]@{
        Repository = $repository
        Configuration = $configuration
        MigrationRoot = $root
        RepositoryState = $repositoryState
        ManifestPath = Join-Path $repositoryState 'pending.json'
    }
}

function Get-DotfilesLegacyMigrationState {
    param (
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$ConfigDirectory,
        [string]$MigrationRoot
    )

    $binding = Get-DotfilesLegacyRepositoryBinding -RepositoryRoot $RepositoryRoot -ConfigDirectory $ConfigDirectory -MigrationRoot $MigrationRoot
    if (-not (Test-Path -LiteralPath $binding.ManifestPath -PathType Leaf)) { return $null }
    Assert-DotfilesLegacyPathHasNoReparsePoint -Path $binding.ManifestPath
    try {
        $manifest = [IO.File]::ReadAllText($binding.ManifestPath) | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Migration manifest '$($binding.ManifestPath)' must contain valid JSON. $($_.Exception.Message)"
    }
    if ($manifest -isnot [pscustomobject] -or $manifest.status -cnotin @('pending', 'applied')) {
        throw "Migration manifest '$($binding.ManifestPath)' has an unexpected status."
    }
    if ($manifest.status -ceq 'applied') {
        Assert-DotfilesLegacyAppliedManifest -Manifest $manifest -Binding $binding
    }
    return [pscustomobject]@{
        Status = [string]$manifest.status
        ManifestPath = $binding.ManifestPath
        MigrationDirectory = [string]$manifest.migrationDirectory
        Repository = $binding.Repository
        Configuration = $binding.Configuration
        MigrationRoot = $binding.MigrationRoot
        RepositoryState = $binding.RepositoryState
        Manifest = $manifest
    }
}

function Assert-DotfilesLegacyEntrySet {
    param (
        [Parameter(Mandatory)][object[]]$Entries,
        [Parameter(Mandatory)][string[]]$ExpectedPaths,
        [Parameter(Mandatory)][string]$Description
    )

    if ($Entries.Count -ne $ExpectedPaths.Count) { throw "$Description must contain exactly four entries." }
    $observed = @($Entries | ForEach-Object { [string]$_.path })
    if (@($observed | Select-Object -Unique).Count -ne $ExpectedPaths.Count) { throw "$Description must contain exactly four unique entries." }
    for ($index = 0; $index -lt $ExpectedPaths.Count; $index++) {
        if ($observed[$index] -cne $ExpectedPaths[$index]) { throw "$Description contains an unexpected path '$($observed[$index])'." }
        if ([string]$Entries[$index].sha256 -notmatch '^[0-9a-f]{64}$') { throw "$Description contains an invalid SHA-256 value." }
    }
}

function Assert-DotfilesLegacyAppliedManifest {
    param (
        [Parameter(Mandatory)][pscustomobject]$Manifest,
        [Parameter(Mandatory)]$Binding
    )

    $requiredProperties = @(
        'status', 'repositoryPath', 'configurationPath', 'sourceCommit', 'migrationDirectory',
        'files', 'candidates', 'migrationWarnings', 'backupDirectory', 'backups', 'installed'
    )
    foreach ($property in $requiredProperties) {
        if ($Manifest.PSObject.Properties.Name -cnotcontains $property) {
            throw "Applied migration manifest is missing required field '$property'."
        }
    }
    if ($Manifest.migrationWarnings -isnot [array]) {
        throw 'Applied migration manifest migration warnings must be a JSON array.'
    }
    if ([string]$Manifest.repositoryPath -cne $Binding.Repository) {
        throw 'Applied migration manifest repository identity is stale or unexpected.'
    }
    if ([string]$Manifest.configurationPath -cne $Binding.Configuration) {
        throw 'Applied migration manifest configuration identity is stale or unexpected.'
    }
    if ([string]$Manifest.sourceCommit -cnotmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$') {
        throw 'Applied migration manifest source commit is malformed.'
    }
    $sourceCommitResult = Invoke-DotfilesGitCommand `
        -RepositoryRoot $Binding.Repository `
        -ArgumentList @('cat-file', '-e', "$($Manifest.sourceCommit)^{commit}")
    if ($sourceCommitResult.ExitCode -ne 0 -or
        -not [string]::IsNullOrWhiteSpace($sourceCommitResult.Output) -or
        -not [string]::IsNullOrWhiteSpace($sourceCommitResult.Error)) {
        throw 'Applied migration manifest source commit does not resolve to an existing commit.'
    }

    $migrationDirectory = Get-DotfilesLegacyCanonicalPath -Path ([string]$Manifest.migrationDirectory)
    if ([string]$Manifest.migrationDirectory -cne $migrationDirectory -or
        -not (Test-DotfilesLegacyPathWithinRoot -Path $migrationDirectory -Root $Binding.RepositoryState) -or
        $migrationDirectory.Equals($Binding.RepositoryState, (Get-DotfilesLegacyPathComparison))) {
        throw 'Applied migration directory is outside the exact repository migration state.'
    }
    if (-not (Test-Path -LiteralPath $migrationDirectory -PathType Container)) {
        throw 'Applied migration directory does not exist.'
    }
    Assert-DotfilesLegacyPathHasNoReparsePoint -Path $migrationDirectory

    $names = @('dotfiles-bootstrap-variables.json', 'git-variables.json', 'env-variables.json', 'winget-packages.json')
    $originalPaths = @($names | ForEach-Object { "dotfiles-configurations/$_" })
    $candidatePaths = @($names | ForEach-Object { "candidates/$_" })
    Assert-DotfilesLegacyEntrySet -Entries @($Manifest.files) -ExpectedPaths $originalPaths -Description 'Applied migration original list'
    Assert-DotfilesLegacyEntrySet -Entries @($Manifest.candidates) -ExpectedPaths $candidatePaths -Description 'Applied migration candidate list'

    foreach ($set in @(
        @{ Entries = @($Manifest.files); Paths = $originalPaths; Description = 'original' },
        @{ Entries = @($Manifest.candidates); Paths = $candidatePaths; Description = 'candidate' }
    )) {
        for ($index = 0; $index -lt $set.Paths.Count; $index++) {
            $path = Get-DotfilesLegacyCanonicalPath -Path (Join-Path $migrationDirectory $set.Paths[$index])
            if (-not (Test-DotfilesLegacyPathWithinRoot -Path $path -Root $migrationDirectory) -or
                -not (Test-Path -LiteralPath $path -PathType Leaf)) {
                throw "Applied migration $($set.Description) file is missing or outside the migration directory: '$($set.Paths[$index])'."
            }
            Assert-DotfilesLegacyPathHasNoReparsePoint -Path $path
            $bytes = [IO.File]::ReadAllBytes($path)
            if ((Get-DotfilesSha256Hex -Bytes $bytes) -cne [string]$set.Entries[$index].sha256) {
                throw "Applied migration $($set.Description) hash mismatch for '$($set.Paths[$index])'."
            }
            if (-not (Test-DotfilesJsonBytes -Bytes $bytes)) {
                throw "Applied migration $($set.Description) '$($set.Paths[$index])' must contain valid JSON."
            }
        }
    }

    Assert-DotfilesLegacyEntrySet -Entries @($Manifest.installed) -ExpectedPaths $names -Description 'Applied migration installed list'
    for ($index = 0; $index -lt $names.Count; $index++) {
        $target = Get-DotfilesLegacyCanonicalPath -Path (Join-Path $Binding.Configuration $names[$index])
        if (-not (Test-DotfilesLegacyPathWithinRoot -Path $target -Root $Binding.Configuration) -or
            -not (Test-Path -LiteralPath $target -PathType Leaf)) {
            throw "Applied migration installed target is missing or outside the configuration directory: '$($names[$index])'."
        }
        Assert-DotfilesLegacyPathHasNoReparsePoint -Path $target
        if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$Manifest.installed[$index].sha256) {
            throw "Applied migration installed target hash mismatch for '$($names[$index])'."
        }
    }

    $backupDirectory = Get-DotfilesLegacyCanonicalPath -Path ([string]$Manifest.backupDirectory)
    if ([string]$Manifest.backupDirectory -cne $backupDirectory -or
        -not (Test-DotfilesLegacyPathWithinRoot -Path $backupDirectory -Root $migrationDirectory) -or
        $backupDirectory.Equals($migrationDirectory, (Get-DotfilesLegacyPathComparison)) -or
        -not (Test-Path -LiteralPath $backupDirectory -PathType Container)) {
        throw 'Applied migration backup directory is missing or outside the migration directory.'
    }
    Assert-DotfilesLegacyPathHasNoReparsePoint -Path $backupDirectory

    $backups = @($Manifest.backups)
    if ($backups.Count -ne $names.Count) { throw 'Applied migration backup list must contain exactly four entries.' }
    $backupNames = @($backups | ForEach-Object { [string]$_.path })
    if (@($backupNames | Select-Object -Unique).Count -ne $names.Count) { throw 'Applied migration backup list must contain exactly four unique entries.' }
    for ($index = 0; $index -lt $names.Count; $index++) {
        $backup = $backups[$index]
        if ($backup -isnot [pscustomobject] -or $backupNames[$index] -cne $names[$index]) {
            throw "Applied migration backup list contains an unexpected path '$($backupNames[$index])'."
        }
        foreach ($property in @('path', 'existed', 'backupPath', 'sha256')) {
            if ($backup.PSObject.Properties.Name -cnotcontains $property) { throw "Applied migration backup entry is missing '$property'." }
        }
        if ($backup.existed -isnot [bool]) { throw 'Applied migration backup existed value must be boolean.' }
        if (-not $backup.existed) {
            if ($null -ne $backup.backupPath -or $null -ne $backup.sha256) {
                throw "Applied migration non-existing backup metadata must be null for '$($names[$index])'."
            }
            continue
        }
        $expectedBackupPath = Get-DotfilesLegacyCanonicalPath -Path (Join-Path $backupDirectory $names[$index])
        if ([string]$backup.backupPath -cne $expectedBackupPath -or
            -not (Test-Path -LiteralPath $expectedBackupPath -PathType Leaf)) {
            throw "Applied migration backup path is missing or unexpected for '$($names[$index])'."
        }
        if ([string]$backup.sha256 -cnotmatch '^[0-9a-f]{64}$') {
            throw "Applied migration backup hash is malformed for '$($names[$index])'."
        }
        Assert-DotfilesLegacyPathHasNoReparsePoint -Path $expectedBackupPath
        if ((Get-FileHash -LiteralPath $expectedBackupPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$backup.sha256) {
            throw "Applied migration backup hash mismatch for '$($names[$index])'."
        }
    }
}

function Assert-DotfilesLegacyCandidateSemantics {
    param (
        [Parameter(Mandatory)][hashtable]$Candidates,
        [Parameter(Mandatory)][string]$ConfigDirectory
    )

    $bootstrap = $Candidates['dotfiles-bootstrap-variables.json']
    $git = $Candidates['git-variables.json']
    $environment = $Candidates['env-variables.json']
    $winget = $Candidates['winget-packages.json']
    if ($bootstrap -isnot [pscustomobject]) { throw 'Bootstrap candidate must be a JSON object.' }
    foreach ($name in @('GITHUB_ACCOUNT', 'GITHUB_DOTFILES_REPO', 'GITHUB_DOTFILES_BRANCH', 'WORKSPACE_FOLDER')) {
        if ($bootstrap.PSObject.Properties.Name -notcontains $name -or [string]::IsNullOrWhiteSpace([string]$bootstrap.$name)) {
            throw "Bootstrap candidate requires nonempty '$name'."
        }
    }
    foreach ($name in @('INSTALL_FEATURES', 'INSTALL_PACKAGES', 'INSTALL_SETTINGS')) {
        if ($bootstrap.PSObject.Properties.Name -notcontains $name -or $bootstrap.$name -isnot [array]) {
            throw "Bootstrap candidate requires array '$name'."
        }
    }
    if ($git -isnot [pscustomobject]) { throw 'Git candidate must be a JSON object.' }
    if ($winget -isnot [pscustomobject]) { throw 'Winget candidate must be a JSON object.' }
    if ($environment -isnot [pscustomobject] -or $environment.PSObject.Properties.Name -notcontains 'EnvironmentVariables' -or $environment.EnvironmentVariables -isnot [array]) {
        throw "Environment candidate requires an 'EnvironmentVariables' array."
    }

    $featureTemplate = Read-DotfilesMigrationTemplate -ConfigDirectory $ConfigDirectory -Name 'windows-features.json'
    $setupTemplate = Read-DotfilesMigrationTemplate -ConfigDirectory $ConfigDirectory -Name 'setup-modules.json'
    $wingetTemplate = Read-DotfilesMigrationTemplate -ConfigDirectory $ConfigDirectory -Name 'winget-packages.json'
    $featureGroups = @($featureTemplate.PSObject.Properties.Name)
    $settingGroups = @($setupTemplate.settings.PSObject.Properties.Name)
    $templatePackageGroups = @($wingetTemplate.PSObject.Properties.Name)
    foreach ($group in @($bootstrap.INSTALL_FEATURES)) {
        if ([string]::IsNullOrWhiteSpace([string]$group) -or $featureGroups -notcontains $group) { throw "Bootstrap candidate selects unknown feature group '$group'." }
    }
    foreach ($group in @($bootstrap.INSTALL_SETTINGS)) {
        if ([string]::IsNullOrWhiteSpace([string]$group) -or $settingGroups -notcontains $group) { throw "Bootstrap candidate selects unknown setting group '$group'." }
    }
    foreach ($group in @($bootstrap.INSTALL_PACKAGES)) {
        if ([string]::IsNullOrWhiteSpace([string]$group) -or $templatePackageGroups -notcontains $group -or $winget.PSObject.Properties.Name -notcontains $group) {
            throw "Bootstrap candidate selects missing package group '$group'."
        }
    }
    foreach ($group in (Get-DotfilesRequiredPackageGroup -SetupConfig $setupTemplate -SelectedSettings $bootstrap.INSTALL_SETTINGS)) {
        if ($bootstrap.INSTALL_PACKAGES -notcontains $group) { throw "Bootstrap candidate is missing required package group '$group'." }
    }
    foreach ($property in $winget.PSObject.Properties) {
        if ($property.Value -isnot [array]) { throw "Winget candidate group '$($property.Name)' must be an array." }
        foreach ($entry in @($property.Value)) {
            if ($entry -isnot [pscustomobject] -or [string]::IsNullOrWhiteSpace([string]$entry.id)) { throw "Winget candidate group '$($property.Name)' contains an invalid entry." }
        }
    }
    foreach ($variable in @($environment.EnvironmentVariables)) {
        if ($variable -isnot [pscustomobject] -or [string]::IsNullOrWhiteSpace([string]$variable.Name) -or
            $variable.PSObject.Properties.Name -notcontains 'Value' -or $null -eq $variable.Value -or $variable.Scope -notin @('User', 'Machine')) {
            throw 'Environment candidate contains an invalid variable entry.'
        }
    }
}

function Test-DotfilesLegacyJsonSemanticEquality {
    param ([Parameter(Mandatory)][string]$FirstPath, [Parameter(Mandatory)][string]$SecondPath)
    try {
        $first = Get-Content -LiteralPath $FirstPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop | ConvertTo-Json -Depth 100 -Compress
        $second = Get-Content -LiteralPath $SecondPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop | ConvertTo-Json -Depth 100 -Compress
        return $first -ceq $second
    }
    catch {
        throw "Could not compare current configuration with its template. $($_.Exception.Message)"
    }
}

function Assert-DotfilesLegacyCurrentTargets {
    param ([Parameter(Mandatory)][string]$ConfigDirectory, [Parameter(Mandatory)][string[]]$Names)

    $present = @($Names | Where-Object { Test-Path -LiteralPath (Join-Path $ConfigDirectory $_) -PathType Leaf })
    if ($present.Count -ne 0 -and $present.Count -ne $Names.Count) { throw 'The current configuration set is partial; apply was rejected.' }
    foreach ($name in $present) {
        $target = Join-Path $ConfigDirectory $name
        Assert-DotfilesLegacyPathHasNoReparsePoint -Path $target
        if (-not (Test-DotfilesLegacyJsonSemanticEquality -FirstPath $target -SecondPath (Join-Path $ConfigDirectory "$name.example"))) {
            throw "Current configuration '$name' is user-owned and must not be overwritten."
        }
    }
    return $present.Count
}

function Write-DotfilesLegacyCreateNewBytes {
    param ([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][byte[]]$Bytes)
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($Bytes, 0, $Bytes.Length); $stream.Flush() }
    finally { $stream.Dispose() }
}

function Install-DotfilesLegacyAtomicFile {
    param ([Parameter(Mandatory)][string]$TemporaryPath, [Parameter(Mandatory)][string]$TargetPath)
    if (Test-Path -LiteralPath $TargetPath -PathType Leaf) { [IO.File]::Move($TemporaryPath, $TargetPath, $true) }
    else { [IO.File]::Move($TemporaryPath, $TargetPath) }
}

function Invoke-DotfilesLegacyMigrationApply {
    param (
        [Parameter(Mandatory)]$MigrationState,
        [scriptblock]$BeforeInstall,
        [scriptblock]$BeforeManifestPublish
    )

    $binding = Get-DotfilesLegacyRepositoryBinding -RepositoryRoot $MigrationState.Repository -ConfigDirectory $MigrationState.Configuration -MigrationRoot $MigrationState.MigrationRoot
    if (-not $binding.ManifestPath.Equals([string]$MigrationState.ManifestPath, (Get-DotfilesLegacyPathComparison))) { throw 'Migration manifest is not at the exact expected location.' }
    $state = Get-DotfilesLegacyMigrationState -RepositoryRoot $binding.Repository -ConfigDirectory $binding.Configuration -MigrationRoot $binding.MigrationRoot
    if (-not $state -or $state.Status -ne 'pending') { throw 'Migration manifest status must be pending before apply.' }
    $manifest = $state.Manifest
    if ([string]$manifest.repositoryPath -cne $binding.Repository) { throw 'Migration manifest repository identity is stale or unexpected.' }
    if ([string]$manifest.configurationPath -cne $binding.Configuration) { throw 'Migration manifest configuration identity is stale or unexpected.' }
    $migrationDirectory = Get-DotfilesLegacyCanonicalPath -Path ([string]$manifest.migrationDirectory)
    if (-not (Test-DotfilesLegacyPathWithinRoot -Path $migrationDirectory -Root $binding.RepositoryState) -or
        $migrationDirectory.Equals($binding.RepositoryState, (Get-DotfilesLegacyPathComparison))) {
        throw 'Migration directory is outside the approved repository migration state.'
    }
    Assert-DotfilesLegacyPathHasNoReparsePoint -Path $migrationDirectory

    $names = @('dotfiles-bootstrap-variables.json', 'git-variables.json', 'env-variables.json', 'winget-packages.json')
    $sourcePaths = @($names | ForEach-Object { "dotfiles-configurations/$_" })
    $candidatePaths = @($names | ForEach-Object { "candidates/$_" })
    Assert-DotfilesLegacyEntrySet -Entries @($manifest.files) -ExpectedPaths $sourcePaths -Description 'Migration original list'
    Assert-DotfilesLegacyEntrySet -Entries @($manifest.candidates) -ExpectedPaths $candidatePaths -Description 'Migration candidate list'

    $candidateBytes = @{}
    $candidateValues = @{}
    foreach ($set in @(@{ Entries = @($manifest.files); Expected = $sourcePaths; Candidate = $false }, @{ Entries = @($manifest.candidates); Expected = $candidatePaths; Candidate = $true })) {
        for ($index = 0; $index -lt $set.Expected.Count; $index++) {
            $path = Get-DotfilesLegacyCanonicalPath -Path (Join-Path $migrationDirectory $set.Expected[$index])
            if (-not (Test-DotfilesLegacyPathWithinRoot -Path $path -Root $migrationDirectory)) { throw "Migration entry escaped the migration directory: $path" }
            Assert-DotfilesLegacyPathHasNoReparsePoint -Path $path
            $bytes = [IO.File]::ReadAllBytes($path)
            if ((Get-DotfilesSha256Hex -Bytes $bytes) -cne [string]$set.Entries[$index].sha256) { throw "Migration entry hash mismatch for '$($set.Expected[$index])'." }
            if (-not (Test-DotfilesJsonBytes -Bytes $bytes)) { throw "Migration entry '$($set.Expected[$index])' must contain valid JSON." }
            if ($set.Candidate) {
                $candidateBytes[$names[$index]] = $bytes
                $candidateValues[$names[$index]] = ConvertFrom-DotfilesLegacyJsonBytes -Bytes $bytes -Description "Migration candidate '$($names[$index])'"
            }
        }
    }
    Assert-DotfilesLegacyCandidateSemantics -Candidates $candidateValues -ConfigDirectory $binding.Configuration
    Assert-DotfilesLegacyCurrentTargets -ConfigDirectory $binding.Configuration -Names $names | Out-Null

    # A malicious concurrent process running as this same user is outside this migration's threat model.
    $backupDirectory = Join-Path $migrationDirectory ('.apply-backup-{0}' -f [Guid]::NewGuid().ToString('N'))
    $backupEntries = [Collections.Generic.List[object]]::new()
    $temporaryPaths = [Collections.Generic.List[string]]::new()
    $results = [Collections.Generic.List[object]]::new()
    $rollbackFailures = [Collections.Generic.List[string]]::new()
    $backupCreated = $false
    $rollbackSucceeded = $false
    try {
        Assert-DotfilesLegacyCurrentTargets -ConfigDirectory $binding.Configuration -Names $names | Out-Null
        Assert-DotfilesLegacyPathHasNoReparsePoint -Path $backupDirectory
        New-Item -ItemType Directory -Path $backupDirectory -ErrorAction Stop | Out-Null
        $backupCreated = $true
        Assert-DotfilesLegacyPathHasNoReparsePoint -Path $backupDirectory

        foreach ($name in $names) {
            $target = Join-Path $binding.Configuration $name
            if (Test-Path -LiteralPath $target -PathType Leaf) {
                $bytes = [IO.File]::ReadAllBytes($target)
                $backup = Join-Path $backupDirectory $name
                Write-DotfilesLegacyCreateNewBytes -Path $backup -Bytes $bytes
                $backupEntries.Add([pscustomobject][ordered]@{ path = $name; existed = $true; backupPath = $backup; sha256 = Get-DotfilesSha256Hex -Bytes $bytes })
            } else {
                $backupEntries.Add([pscustomobject][ordered]@{ path = $name; existed = $false; backupPath = $null; sha256 = $null })
            }
        }
        for ($index = 0; $index -lt $names.Count; $index++) {
            $target = Join-Path $binding.Configuration $names[$index]
            $temporary = Join-Path $binding.Configuration ('.{0}.{1}.migration.tmp' -f $names[$index], [Guid]::NewGuid().ToString('N'))
            Write-DotfilesLegacyCreateNewBytes -Path $temporary -Bytes ([byte[]]$candidateBytes[$names[$index]])
            $temporaryPaths.Add($temporary)
        }

        for ($index = 0; $index -lt $names.Count; $index++) {
            if ($BeforeInstall) { & $BeforeInstall $index }
            $target = Join-Path $binding.Configuration $names[$index]
            Assert-DotfilesLegacyPathHasNoReparsePoint -Path $target
            $expectedCandidateHash = Get-DotfilesSha256Hex -Bytes ([byte[]]$candidateBytes[$names[$index]])
            $candidatePath = Join-Path $migrationDirectory $candidatePaths[$index]
            if ((Get-FileHash -LiteralPath $candidatePath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expectedCandidateHash) { throw "Candidate hash changed immediately before mutation for '$($names[$index])'." }
            Install-DotfilesLegacyAtomicFile -TemporaryPath $temporaryPaths[$index] -TargetPath $target
            $results.Add([pscustomobject][ordered]@{ Path = $names[$index]; Action = if ($backupEntries[$index].existed) { 'Replaced' } else { 'Created' }; Sha256 = $expectedCandidateHash })
        }
        foreach ($result in $results) {
            $target = Join-Path $binding.Configuration $result.Path
            if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -cne $result.Sha256) { throw "Installed target hash mismatch for '$($result.Path)'." }
        }

        $manifest.status = 'applied'
        $manifest | Add-Member -NotePropertyName backupDirectory -NotePropertyValue $backupDirectory -Force
        $manifest | Add-Member -NotePropertyName backups -NotePropertyValue $backupEntries.ToArray() -Force
        $manifest | Add-Member -NotePropertyName installed -NotePropertyValue @($results | ForEach-Object { [ordered]@{ path = $_.Path; sha256 = $_.Sha256 } }) -Force
        $manifestBytes = [Text.UTF8Encoding]::new($false).GetBytes(($manifest | ConvertTo-Json -Depth 20))
        $manifestTemporary = Join-Path $binding.RepositoryState ('.pending.{0}.tmp' -f [Guid]::NewGuid().ToString('N'))
        $temporaryPaths.Add($manifestTemporary)
        if ($BeforeManifestPublish) { & $BeforeManifestPublish }
        Write-DotfilesLegacyCreateNewBytes -Path $manifestTemporary -Bytes $manifestBytes
        Install-DotfilesLegacyAtomicFile -TemporaryPath $manifestTemporary -TargetPath $binding.ManifestPath
        return [pscustomobject]@{ Applied = $true; Results = $results.ToArray(); BackupDirectory = $backupDirectory }
    }
    catch {
        $primary = $_.Exception.Message
        for ($index = $results.Count - 1; $index -ge 0; $index--) {
            $result = $results[$index]
            $target = Join-Path $binding.Configuration $result.Path
            try {
                Assert-DotfilesLegacyPathHasNoReparsePoint -Path $target
                if ($result.Action -eq 'Created') {
                    Remove-Item -LiteralPath $target -Force -ErrorAction Stop
                } else {
                    $backup = $backupEntries[$index]
                    Assert-DotfilesLegacyPathHasNoReparsePoint -Path $backup.backupPath
                    $bytes = [IO.File]::ReadAllBytes($backup.backupPath)
                    if ((Get-DotfilesSha256Hex -Bytes $bytes) -cne $backup.sha256) { throw 'Backup hash mismatch.' }
                    $restoreTemporary = Join-Path $binding.Configuration ('.{0}.{1}.rollback.tmp' -f $result.Path, [Guid]::NewGuid().ToString('N'))
                    $temporaryPaths.Add($restoreTemporary)
                    Write-DotfilesLegacyCreateNewBytes -Path $restoreTemporary -Bytes $bytes
                    Install-DotfilesLegacyAtomicFile -TemporaryPath $restoreTemporary -TargetPath $target
                }
            }
            catch { $rollbackFailures.Add("$($result.Path): $($_.Exception.Message)") }
        }
        $rollbackSucceeded = $rollbackFailures.Count -eq 0
        if ($rollbackSucceeded) { throw "$primary Configuration changes were rolled back." }
        throw "$primary Rollback was incomplete: $($rollbackFailures -join '; ')"
    }
    finally {
        foreach ($temporary in $temporaryPaths) {
            try { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction Stop } } catch { }
        }
        if ($backupCreated -and $rollbackSucceeded) {
            try { if (Test-Path -LiteralPath $backupDirectory) { Remove-Item -LiteralPath $backupDirectory -Recurse -Force -ErrorAction Stop } } catch { }
        }
    }
}

function Invoke-DotfilesLegacyMigrationPrompt {
    param (
        [Parameter(Mandatory)]$MigrationState,
        [scriptblock]$ReadConfirmation = { Read-Host 'Apply these four migration candidates? [y/N]' }
    )

    if ($MigrationState.Status -eq 'applied') { return [pscustomobject]@{ Applied = $false; AlreadyApplied = $true } }
    if ($MigrationState.Status -ne 'pending') { throw "Unexpected migration status '$($MigrationState.Status)'." }
    Write-WarningMessage 'A pending legacy configuration migration is ready for explicit review.'
    Write-Host "Manifest: $($MigrationState.ManifestPath)"
    Write-Host "Migration directory: $($MigrationState.MigrationDirectory)"
    Write-Host 'Candidates:'
    foreach ($entry in @($MigrationState.Manifest.candidates)) { Write-Host "  - $(Join-Path $MigrationState.MigrationDirectory $entry.path)" }
    foreach ($warning in @($MigrationState.Manifest.migrationWarnings)) { Write-WarningMessage ([string]$warning) }
    $answer = [string](& $ReadConfirmation)
    if ($answer.Trim().ToLowerInvariant() -notin @('y', 'yes')) {
        Write-Host 'Legacy configuration migration declined; the pending stage was not changed.'
        return [pscustomobject]@{ Applied = $false; Declined = $true }
    }
    return Invoke-DotfilesLegacyMigrationApply -MigrationState $MigrationState
}

function Invoke-DotfilesLegacyConfigurationStage {
    param (
        [Parameter(Mandatory)]
        [string]$RepositoryRoot,
        [Parameter(Mandatory)]
        [string]$ConfigDirectory,
        [string]$MigrationRoot
    )

    $legacyNames = @(
        'dotfiles-bootstrap-variables.json',
        'git-variables.json',
        'env-variables.json',
        'winget-packages.json'
    )
    $relativePaths = @($legacyNames | ForEach-Object { "dotfiles-configurations/$_" })

    $currentPaths = @($legacyNames | ForEach-Object { Join-Path $ConfigDirectory $_ })
    $presentPaths = @($currentPaths | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
    if ($presentPaths.Count -ne 0 -and $presentPaths.Count -ne $legacyNames.Count) {
        throw 'The current legacy configuration set is partial; no files were changed.'
    }
    foreach ($currentPath in $presentPaths) {
        try {
            $content = [IO.File]::ReadAllText($currentPath)
            if ([string]::IsNullOrWhiteSpace($content)) { throw 'JSON is empty.' }
            $content | ConvertFrom-Json -ErrorAction Stop | Out-Null
        }
        catch {
            throw "Current configuration '$currentPath' must contain valid JSON; no files were changed. $($_.Exception.Message)"
        }
    }

    $canonicalResult = Invoke-DotfilesGitCommand -RepositoryRoot $RepositoryRoot -ArgumentList @('rev-parse', '--show-toplevel')
    if ($canonicalResult.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($canonicalResult.Output)) {
        throw "Cannot resolve the repository canonical path: $($canonicalResult.Error.Trim())"
    }
    $canonicalRepository = Get-DotfilesLegacyCanonicalPath -Path $canonicalResult.Output.Trim()
    $canonicalConfig = Get-DotfilesLegacyCanonicalPath -Path $ConfigDirectory
    $expectedConfig = Get-DotfilesLegacyCanonicalPath -Path (Join-Path $canonicalRepository 'dotfiles-configurations')
    $pathComparison = Get-DotfilesLegacyPathComparison
    if (-not $canonicalConfig.Equals($expectedConfig, $pathComparison)) {
        throw "Configuration directory must be the repository's dotfiles-configurations directory: $expectedConfig"
    }
    Assert-DotfilesLegacyPathHasNoReparsePoint -Path $canonicalRepository
    Assert-DotfilesLegacyPathHasNoReparsePoint -Path $canonicalConfig

    if ($presentPaths.Count -eq $legacyNames.Count) {
        $allCurrentFilesMatchTemplates = $true
        foreach ($name in $legacyNames) {
            try {
                $currentValue = Get-Content -LiteralPath (Join-Path $canonicalConfig $name) -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                $templateValue = Read-DotfilesMigrationTemplate -ConfigDirectory $canonicalConfig -Name $name
                $currentJson = $currentValue | ConvertTo-Json -Depth 100 -Compress -ErrorAction Stop
                $templateJson = $templateValue | ConvertTo-Json -Depth 100 -Compress -ErrorAction Stop
            }
            catch {
                throw "Could not compare current configuration '$name' with its template; no files were changed. $($_.Exception.Message)"
            }
            if ($currentJson -cne $templateJson) {
                $allCurrentFilesMatchTemplates = $false
                break
            }
        }
        if (-not $allCurrentFilesMatchTemplates) {
            return [pscustomobject]@{
                Staged = $false
                CurrentConfigurationPreserved = $true
            }
        }
    }

    $headResult = Invoke-DotfilesGitCommand -RepositoryRoot $canonicalRepository -ArgumentList @('rev-parse', 'HEAD')
    if ($headResult.ExitCode -ne 0) {
        throw "Cannot resolve repository HEAD: $($headResult.Error.Trim())"
    }
    $currentCommit = $headResult.Output.Trim()
    $reflogResult = Invoke-DotfilesGitCommand -RepositoryRoot $canonicalRepository -ArgumentList @('reflog', 'show', 'HEAD', '--format=%H')
    if ($reflogResult.ExitCode -ne 0) {
        throw "Cannot inspect the checkout reflog: $($reflogResult.Error.Trim())"
    }

    $priorCommits = [Collections.Generic.List[string]]::new()
    foreach ($line in ($reflogResult.Output -split "`r?`n")) {
        $commit = $line.Trim()
        if ($commit -and $commit -ne $currentCommit -and -not $priorCommits.Contains($commit)) {
            $priorCommits.Add($commit)
        }
    }

    $sawLegacyPath = $false
    $candidate = $null
    foreach ($commit in $priorCommits) {
        $blobIds = [Collections.Generic.List[string]]::new()
        $blobBytes = @{}
        foreach ($relativePath in $relativePaths) {
            $objectResult = Invoke-DotfilesGitCommand `
                -RepositoryRoot $canonicalRepository `
                -ArgumentList @('rev-parse', "$commit`:$relativePath")
            if ($objectResult.ExitCode -ne 0) { continue }
            $sawLegacyPath = $true
            $objectId = $objectResult.Output.Trim()
            if ([string]::IsNullOrWhiteSpace($objectId)) { continue }
            $blobIds.Add($objectId)
            $blobBytes[$relativePath] = Get-DotfilesGitBlobBytes `
                -RepositoryRoot $canonicalRepository `
                -ObjectId $objectId
        }

        if ($blobIds.Count -eq 0) { continue }
        if ($blobIds.Count -ne $relativePaths.Count) {
            throw "Legacy checkout '$commit' is incomplete; all four blobs must come from the nearest qualifying reflog commit."
        }
        foreach ($relativePath in $relativePaths) {
            if (-not (Test-DotfilesJsonBytes -Bytes $blobBytes[$relativePath])) {
                throw "Legacy blob '$commit`:$relativePath' must contain valid JSON; no files were changed."
            }
        }
        $candidate = [pscustomobject]@{
            Commit = $commit
            Blobs = $blobBytes
        }
        break
    }

    if (-not $candidate) {
        if ($sawLegacyPath) {
            throw 'Legacy checkout evidence is incomplete; all four blobs must come from one reflog commit.'
        }
        return [pscustomobject]@{ Staged = $false }
    }

    if ([string]::IsNullOrWhiteSpace($MigrationRoot)) {
        $migrationBase = $env:LOCALAPPDATA
        if ([string]::IsNullOrWhiteSpace($migrationBase)) {
            $migrationBase = $env:TEMP
        }
        if ([string]::IsNullOrWhiteSpace($migrationBase)) {
            throw 'Neither LOCALAPPDATA nor TEMP is available for external migration staging.'
        }
        $MigrationRoot = Join-Path $migrationBase 'dotfiles/migrations'
    }
    $MigrationRoot = Get-DotfilesLegacyCanonicalPath -Path $MigrationRoot
    if (Test-DotfilesLegacyPathWithinRoot -Path $MigrationRoot -Root $canonicalRepository) {
        throw 'Migration directory must be outside the dotfiles repository.'
    }
    Assert-DotfilesLegacyPathHasNoReparsePoint -Path $MigrationRoot

    $migrationCandidates = New-DotfilesLegacyMigrationCandidates -ConfigDirectory $canonicalConfig -LegacyBlobs $candidate.Blobs
    $candidateBytes = [ordered]@{}
    foreach ($entry in $migrationCandidates.Values.GetEnumerator()) {
        try {
            $json = $entry.Value | ConvertTo-Json -Depth 100 -ErrorAction Stop
            $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json)
            if (-not (Test-DotfilesJsonBytes -Bytes $bytes)) { throw 'Serialized JSON did not parse.' }
            $candidateBytes[$entry.Key] = $bytes
        }
        catch {
            throw "Could not serialize generated migration candidate '$($entry.Key)'. $($_.Exception.Message)"
        }
    }

    $repositoryIdentityBytes = [Text.UTF8Encoding]::new($false).GetBytes($canonicalRepository)
    $repositoryIdentity = Get-DotfilesSha256Hex -Bytes $repositoryIdentityBytes
    $repositoryMigrationRoot = Join-Path $MigrationRoot $repositoryIdentity
    $manifestPath = Join-Path $repositoryMigrationRoot 'pending.json'

    if (Test-Path -LiteralPath $repositoryMigrationRoot) {
        $existingArtifacts = @(Get-ChildItem -LiteralPath $repositoryMigrationRoot -Force -ErrorAction Stop)
        if ($existingArtifacts.Count -ne 0) {
            throw "A stale or pending manifest conflict exists at '$manifestPath'; no files were changed."
        }
    }

    $createdMigrationRoot = $false
    $createdRepositoryRoot = $false
    $createdMigrationDirectory = $false
    $migrationDirectory = $null
    $manifestCreated = $false
    try {
        if (-not (Test-Path -LiteralPath $MigrationRoot)) {
            New-Item -ItemType Directory -Path $MigrationRoot -ErrorAction Stop | Out-Null
            $createdMigrationRoot = $true
        }
        if (-not (Test-Path -LiteralPath $repositoryMigrationRoot)) {
            New-Item -ItemType Directory -Path $repositoryMigrationRoot -ErrorAction Stop | Out-Null
            $createdRepositoryRoot = $true
        }
        $migrationDirectory = Join-Path $repositoryMigrationRoot ([Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $migrationDirectory -ErrorAction Stop | Out-Null
        $createdMigrationDirectory = $true

        $manifestFiles = [Collections.Generic.List[object]]::new()
        foreach ($relativePath in $relativePaths) {
            $destination = Join-Path $migrationDirectory $relativePath
            $destinationDirectory = Split-Path -Parent $destination
            if (-not (Test-Path -LiteralPath $destinationDirectory)) {
                New-Item -ItemType Directory -Path $destinationDirectory -ErrorAction Stop | Out-Null
            }
            $bytes = [byte[]]$candidate.Blobs[$relativePath]
            $stream = [IO.File]::Open($destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try {
                $stream.Write($bytes, 0, $bytes.Length)
                $stream.Flush()
            }
            finally {
                $stream.Dispose()
            }
            $manifestFiles.Add([ordered]@{
                path = $relativePath
                sha256 = Get-DotfilesSha256Hex -Bytes $bytes
            })
        }

        $candidateDirectory = Join-Path $migrationDirectory 'candidates'
        New-Item -ItemType Directory -Path $candidateDirectory -ErrorAction Stop | Out-Null
        $manifestCandidates = [Collections.Generic.List[object]]::new()
        foreach ($entry in $candidateBytes.GetEnumerator()) {
            $candidateRelativePath = "candidates/$($entry.Key)"
            $destination = Join-Path $migrationDirectory $candidateRelativePath
            $bytes = [byte[]]$entry.Value
            $stream = [IO.File]::Open($destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try {
                $stream.Write($bytes, 0, $bytes.Length)
                $stream.Flush()
            }
            finally {
                $stream.Dispose()
            }
            $manifestCandidates.Add([ordered]@{
                path = $candidateRelativePath
                sha256 = Get-DotfilesSha256Hex -Bytes $bytes
            })
        }

        $manifest = [ordered]@{
            status = 'pending'
            repositoryPath = $canonicalRepository
            configurationPath = $canonicalConfig
            sourceCommit = $candidate.Commit
            migrationDirectory = $migrationDirectory
            files = $manifestFiles.ToArray()
            candidates = $manifestCandidates.ToArray()
            migrationWarnings = @($migrationCandidates.Warnings)
        }
        $manifestBytes = [Text.UTF8Encoding]::new($false).GetBytes(($manifest | ConvertTo-Json -Depth 10))
        $manifestStream = [IO.File]::Open($manifestPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $manifestCreated = $true
        try {
            $manifestStream.Write($manifestBytes, 0, $manifestBytes.Length)
            $manifestStream.Flush()
        }
        finally {
            $manifestStream.Dispose()
        }

        return [pscustomobject]@{
            Staged = $true
            MigrationDirectory = $migrationDirectory
            ManifestPath = $manifestPath
            SourceCommit = $candidate.Commit
        }
    }
    catch {
        $primaryError = $_
        if ($manifestCreated) {
            Remove-Item -LiteralPath $manifestPath -Force -ErrorAction SilentlyContinue
        }
        if ($createdMigrationDirectory) {
            Remove-Item -LiteralPath $migrationDirectory -Recurse -Force -ErrorAction SilentlyContinue
        }
        if ($createdRepositoryRoot) {
            Remove-Item -LiteralPath $repositoryMigrationRoot -Force -ErrorAction SilentlyContinue
        }
        if ($createdMigrationRoot) {
            Remove-Item -LiteralPath $MigrationRoot -Force -ErrorAction SilentlyContinue
        }
        throw $primaryError
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
