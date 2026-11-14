[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$ComposePath,
    [ValidatePattern('^[a-z0-9][a-z0-9_-]*$')][string]$ProjectName
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/docker-compose-functions.ps1"

# Define the docker-compose.yml content
$composeContent = @"
# dotfiles-managed ollama compose v1
services:
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
    environment:
      - NVIDIA_VISIBLE_DEVICES=all
    ports:
      - "127.0.0.1:11434:11434"
    volumes:
      - ollama_data:/root/.ollama
    restart: unless-stopped

  # Recommended: Portainer for Docker management
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    ports:
      - "127.0.0.1:9000:9000"
    volumes:
      - portainer_data:/data
      - /var/run/docker.sock:/var/run/docker.sock
    restart: unless-stopped

  # Recommended: Watchtower for automatic updates
  watchtower:
    profiles: [automatic-updates]
    image: containrrr/watchtower:latest
    container_name: watchtower
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    restart: unless-stopped

  # Open WebUI for Ollama
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: open-webui
    ports:
      - "127.0.0.1:3000:8080"
    environment:
      - OLLAMA_API_BASE_URL=http://ollama:11434
    volumes:
      - openwebui_data:/app/backend/data
    depends_on:
      - ollama
    restart: unless-stopped

volumes:
  ollama_data:
  portainer_data:
  openwebui_data:
"@

try {
    $composeFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ComposePath)
    if (-not $PSCmdlet.ShouldProcess($composeFile, 'Create missing Compose file and start services')) { return }
    if (-not (Test-Path -LiteralPath $composeFile)) {
        $parent = Split-Path -Parent $composeFile
        $null = New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop
        # CreateNew refuses to overwrite a file that appears between the existence check and write.
        $stream = [IO.File]::Open($composeFile, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
        try {
            $bytes = [Text.UTF8Encoding]::new($false).GetBytes($composeContent)
            $stream.Write($bytes, 0, $bytes.Length)
        } finally { $stream.Dispose() }
        Write-Host "Created Compose file: $composeFile"
    }
    $composeArguments = @(Get-DotfilesComposeArguments -ComposePath $composeFile -ProjectName $ProjectName)
    Invoke-DotfilesDocker -Arguments ($composeArguments + @('config', '--quiet'))
    Invoke-DotfilesDocker -Arguments ($composeArguments + @('up', '-d', '--wait', '--wait-timeout', '120'))
    Write-Host 'Compose services reached running/healthy state. Persistent volumes were preserved.'
    Write-Host 'Ollama: http://localhost:11434 | Portainer: http://localhost:9000 | Open WebUI: http://localhost:3000'
} catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
}
