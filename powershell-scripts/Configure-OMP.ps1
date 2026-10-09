# Setup OMP
oh-my-posh font install --user CascadiaCode
Install-Module -Name Terminal-Icons -Repository PSGallery -Force
Import-Module -Name Terminal-Icons

# NOTE: Theme deployment is handled without elevation by setup-modules\Install-OmpConfig.ps1.
# It creates hard links when possible and falls back to regular copies across volumes.
