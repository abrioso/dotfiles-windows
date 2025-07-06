# 13.docker.ollama.user.stop.ps1
# PowerShell script to stop and remove Docker Compose services for Ollama and recommended services

# Ensure Docker is installed
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Error "Docker is not installed. Please install Docker Desktop first."
    exit 1
}

# Check if docker-compose.yml exists in the current directory
$composeFile = "docker-compose.yml"
if (-not (Test-Path $composeFile)) {
    Write-Error "docker-compose.yml not found in the current directory."
    exit 1
}

Write-Host "Stopping and removing Ollama, Open WebUI, Portainer, and Watchtower containers..."

docker compose down --volumes

Write-Host "All containers stopped and volumes removed."
