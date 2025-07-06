# 13.docker.ollama.user.ps1
# PowerShell script to set up Docker Compose for Ollama and recommended services

# Ensure Docker is installed and running
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Error "Docker is not installed. Please install Docker Desktop first."
    exit 1
}

# Define the docker-compose.yml content
$composeContent = @"
version: '3.8'
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
      - "11434:11434"
    volumes:
      - ollama_data:/root/.ollama
    restart: unless-stopped

  # Recommended: Portainer for Docker management
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    ports:
      - "9000:9000"
    volumes:
      - portainer_data:/data
      - /var/run/docker.sock:/var/run/docker.sock
    restart: unless-stopped

  # Recommended: Watchtower for automatic updates
  watchtower:
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
      - "3000:8080"
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

# Write docker-compose.yml to current directory
$composeFile = "docker-compose.yml"
Set-Content -Path $composeFile -Value $composeContent -Encoding UTF8

Write-Host "docker-compose.yml created."

# Start the containers
docker compose up -d

Write-Host "Ollama and recommended Docker services are starting."
Write-Host "Ollama API: http://localhost:11434"
Write-Host "Portainer UI: http://localhost:9000"