# Equivalent PowerShell script for 3.docker.packages.admin.dsc.yaml
# Minimum OS version check
# (No MinVersion specified, just check for OS presence)

# Enable HypervisorPlatform
Enable-WindowsOptionalFeature -Online -FeatureName "HypervisorPlatform" -All -NoRestart

# Enable VirtualMachinePlatform
Enable-WindowsOptionalFeature -Online -FeatureName "VirtualMachinePlatform" -All -NoRestart

# Enable Microsoft-Windows-Subsystem-Linux
Enable-WindowsOptionalFeature -Online -FeatureName "Microsoft-Windows-Subsystem-Linux" -All -NoRestart

# Enable Hyper-V
Enable-WindowsOptionalFeature -Online -FeatureName "Microsoft-Hyper-V-All" -All -NoRestart

# Install WSL
wsl --install --no-distribution

# Install Ubuntu
wsl --install -d Ubuntu

# Install Docker Desktop
winget install --id Docker.DockerDesktop --accept-source-agreements --accept-package-agreements