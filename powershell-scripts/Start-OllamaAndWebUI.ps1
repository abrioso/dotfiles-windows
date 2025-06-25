# Start-OllamaAndWebUI.ps1
# This script manages Ollama and Open WebUI Docker containers with checks and cleanup.

function Remove-ExistingContainer {
    param(
        [string]$Name
    )
    $exists = docker ps -a --format '{{.Names}}' | Where-Object { $_ -eq $Name }
    if ($exists) {
        Write-Host "Stopping and removing existing container: $Name"
        docker stop $Name | Out-Null
        docker rm $Name | Out-Null
    }
}

# Ollama
Remove-ExistingContainer -Name "ollama"
docker run --gpus=all -d -v ollama:/root/.ollama -p 11434:11434 --name ollama ollama/ollama

# Open WebUI
Remove-ExistingContainer -Name "open-webui"
docker run -d -p 3000:8080 --gpus all --add-host=host.docker.internal:host-gateway -v open-webui:/app/backend/data --name open-webui --restart always ghcr.io/open-webui/open-webui:cuda

Write-Host "Both containers started successfully."
