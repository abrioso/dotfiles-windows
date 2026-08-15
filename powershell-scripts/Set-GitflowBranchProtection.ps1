<#
.SYNOPSIS
    Applies GitHub branch protection (require PR, block direct pushes) to main/develop for a set of repos.

.DESCRIPTION
    Requires an authenticated `gh` CLI session (gh auth login). For each "owner/repo" passed in,
    protects the 'main' branch, and the 'develop' branch if it exists, so changes must come in via PR.
    Idempotent: safe to re-run.

.PARAMETER Repos
    List of repos in "owner/repo" format.

.EXAMPLE
    ./Set-GitflowBranchProtection.ps1 -Repos 'abrioso/dotfiles-windows','abrioso/dotfiles'
#>
param (
    [Parameter(Mandatory = $true)]
    [string[]]$Repos
)

$protectionPayload = @{
    required_status_checks        = $null
    enforce_admins                 = $true
    required_pull_request_reviews  = @{ required_approving_review_count = 0 }
    restrictions                    = $null
    allow_force_pushes              = $false
    allow_deletions                  = $false
} | ConvertTo-Json -Depth 5

foreach ($repo in $Repos) {
    Write-Host "`n=== $repo ===" -ForegroundColor Cyan

    $branches = (gh api "repos/$repo/branches" --paginate --jq '.[].name' 2>$null)
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Could not read branches for '$repo'. Skipping."
        continue
    }

    $targetBranches = @('main') + ($branches -contains 'develop' ? @('develop') : @())

    foreach ($branch in $targetBranches) {
        Write-Host "Protecting '$branch'..."
        $protectionPayload | gh api --method PUT "repos/$repo/branches/$branch/protection" --input - 1>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Protected '$branch' (PR required, direct pushes blocked)." -ForegroundColor Green
        } else {
            Write-Warning "  Failed to protect '$branch' on '$repo'."
        }
    }
}
