Describe 'Setup configuration resolution' {
    BeforeAll {
        . "$PSScriptRoot/../setup-scripts/setup-functions.ps1"
    }

    function New-TestConfigDirectory {
        [CmdletBinding(SupportsShouldProcess)]
        param()

        $path = Join-Path $env:TEMP ([System.Guid]::NewGuid())
        if ($PSCmdlet.ShouldProcess($path, 'Create test configuration directory')) {
            New-Item -ItemType Directory -Path $path | Out-Null
        }
        return $path
    }

    function Write-TestJson {
        param(
            [Parameter(Mandatory)][string]$Path,
            [Parameter(Mandatory)][string]$Json
        )

        Set-Content -LiteralPath $Path -Value $Json -Encoding UTF8
    }

    Context 'Resolve-DotfilesWindowsFeature' {
        It 'returns only features selected by INSTALL_FEATURES' {
            $configDir = New-TestConfigDirectory
            try {
                $featuresPath = Join-Path $configDir 'windows-features.json'
                $bootstrapPath = Join-Path $configDir 'dotfiles-bootstrap-variables.json'

                Write-TestJson -Path $featuresPath -Json '{"hyperv":["HypervisorPlatform","Microsoft-Hyper-V-All"],"wsl":["VirtualMachinePlatform"]}'
                Write-TestJson -Path $bootstrapPath -Json '{"INSTALL_FEATURES":["wsl"]}'

                $features = Resolve-DotfilesWindowsFeature -ConfigPath $featuresPath -BootstrapPath $bootstrapPath
                if (($features -join ',') -ne 'VirtualMachinePlatform') {
                    throw "Expected only the WSL feature, got '$($features -join ',')'."
                }
            }
            finally {
                Remove-Item -LiteralPath $configDir -Recurse -Force
            }
        }

        It 'returns no features when INSTALL_FEATURES is explicitly empty' {
            $configDir = New-TestConfigDirectory
            try {
                $featuresPath = Join-Path $configDir 'windows-features.json'
                $bootstrapPath = Join-Path $configDir 'dotfiles-bootstrap-variables.json'

                Write-TestJson -Path $featuresPath -Json '{"hyperv":["HypervisorPlatform"],"wsl":["VirtualMachinePlatform"]}'
                Write-TestJson -Path $bootstrapPath -Json '{"INSTALL_FEATURES":[]}'

                $features = Resolve-DotfilesWindowsFeature -ConfigPath $featuresPath -BootstrapPath $bootstrapPath
                if ($features.Count -ne 0) {
                    throw "Expected no features, got '$($features -join ',')'."
                }
            }
            finally {
                Remove-Item -LiteralPath $configDir -Recurse -Force
            }
        }
    }

    Context 'Get-DotfilesSetupPlan' {
        It 'builds a module plan from selected feature, package, and setting groups' {
            $configDir = New-TestConfigDirectory
            try {
                $setupModulesPath = Join-Path $configDir 'setup-modules.json'
                Write-TestJson -Path $setupModulesPath -Json @'
{
  "features": [
    { "name": "windows-features", "script": "Configure-WindowsFeatures.ps1", "requiresAdmin": true, "whenSelected": [ "hyperv", "wsl" ] }
  ],
  "packages": [
    { "name": "winget-packages", "script": "Install-WingetPackages.ps1" }
  ],
  "settings": {
    "base": [
      { "script": "Set-EnvironmentVariables.ps1" }
    ],
    "developer": [
      { "script": "Apply-GitConfig.ps1" }
    ]
  }
}
'@
                $bootstrap = '{"INSTALL_FEATURES":["wsl"],"INSTALL_PACKAGES":["base"],"INSTALL_SETTINGS":["developer"]}' | ConvertFrom-Json

                $plan = Get-DotfilesSetupPlan -DotfilesVariables $bootstrap -ConfigDirectory $configDir
                $scripts = @($plan | ForEach-Object { $_.Script })
                $expected = @('Configure-WindowsFeatures.ps1', 'Install-WingetPackages.ps1', 'Apply-GitConfig.ps1')

                if (($scripts -join ',') -ne ($expected -join ',')) {
                    throw "Expected scripts '$($expected -join ',')', got '$($scripts -join ',')'."
                }

                $featureModule = $plan | Where-Object { $_.Script -eq 'Configure-WindowsFeatures.ps1' } | Select-Object -First 1
                if (-not $featureModule.RequiresAdmin) {
                    throw 'Expected Configure-WindowsFeatures.ps1 to require admin.'
                }
            }
            finally {
                Remove-Item -LiteralPath $configDir -Recurse -Force
            }
        }

        It 'skips package and setting modules for explicit empty selections' {
            $configDir = New-TestConfigDirectory
            try {
                $setupModulesPath = Join-Path $configDir 'setup-modules.json'
                Write-TestJson -Path $setupModulesPath -Json @'
{
  "features": [
    { "name": "windows-features", "script": "Configure-WindowsFeatures.ps1", "requiresAdmin": true, "whenSelected": [ "hyperv", "wsl" ] }
  ],
  "packages": [
    { "name": "winget-packages", "script": "Install-WingetPackages.ps1" }
  ],
  "settings": {
    "base": [
      { "script": "Set-EnvironmentVariables.ps1" }
    ]
  }
}
'@
                $bootstrap = '{"INSTALL_FEATURES":[],"INSTALL_PACKAGES":[],"INSTALL_SETTINGS":[]}' | ConvertFrom-Json

                $plan = Get-DotfilesSetupPlan -DotfilesVariables $bootstrap -ConfigDirectory $configDir
                if ($plan.Count -ne 0) {
                    throw "Expected empty module plan, got '$(@($plan | ForEach-Object { $_.Script }) -join ',')'."
                }
            }
            finally {
                Remove-Item -LiteralPath $configDir -Recurse -Force
            }
        }
    }

    Context 'JSON templates' {
        It 'contains valid JSON in all dotfiles configuration templates' {
            $templateFiles = Get-ChildItem -LiteralPath "$PSScriptRoot/../dotfiles-configurations" -Filter '*.json.example'
            foreach ($file in $templateFiles) {
                try {
                    Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json | Out-Null
                }
                catch {
                    throw "Invalid JSON template '$($file.Name)': $($_.Exception.Message)"
                }
            }
        }
    }
}
