# Equivalent PowerShell script for 12.multimedia.packages.user.dsc.yaml
# Minimum OS version check
# (No MinVersion specified, just check for OS presence)

# Install VideoLAN VLC Media Player
winget install --id VideoLAN.VLC --accept-source-agreements --accept-package-agreements

# Install OBS Studio
winget install --id OBSProject.OBSStudio --accept-source-agreements --accept-package-agreements

# Install Audacity (uncomment to enable)
# winget install --id Audacity.Audacity --accept-source-agreements --accept-package-agreements

# Install HandBrake (uncomment to enable)
# winget install --id HandBrake.HandBrake --accept-source-agreements --accept-package-agreements
