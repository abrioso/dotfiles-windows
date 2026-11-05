function Invoke-DotfilesDocker {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $PSNativeCommandUseErrorActionPreference = $false
    & docker @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Docker command failed (exit $LASTEXITCODE): $($Arguments[0])." }
}

function Get-DotfilesComposeArguments {
    param([Parameter(Mandatory)][string]$ComposePath, [string]$ProjectName)
    $path = (Resolve-Path -LiteralPath $ComposePath -ErrorAction Stop).ProviderPath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'ComposePath must be a file.' }
    if ((Get-Content -LiteralPath $path -TotalCount 1) -ne '# dotfiles-managed ollama compose v1') {
        throw 'Unrecognized Compose file. Review the migration instructions in powershell-scripts/README.md before using this tool.'
    }
    $arguments = @('compose', '--file', $path, '--project-directory', (Split-Path -Parent $path))
    if ($ProjectName) { $arguments += @('--project-name', $ProjectName) }
    $arguments
}
