[CmdletBinding()]
param(
    [string]$Branch = "advanced",
    [int]$TimeoutSeconds = 1800
)

$ErrorActionPreference = "Stop"

function Get-WorkflowRuns {
    param(
        [string]$Repository,
        [string]$Workflow,
        [string]$Commit,
        [string]$TriggerType
    )

    $json = & gh run list --repo $Repository --workflow $Workflow --commit $Commit --event $TriggerType --limit 20 --json databaseId,createdAt,status,url
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to list runs for $Workflow."
    }

    return @($json | ConvertFrom-Json)
}

function Wait-ForWorkflowRun {
    param(
        [string]$Repository,
        [string]$Workflow,
        [string]$Commit,
        [string]$TriggerType,
        [hashtable]$ExistingRunIds,
        [datetimeoffset]$StartedAt,
        [datetimeoffset]$Deadline
    )

    while ([datetimeoffset]::UtcNow -lt $Deadline) {
        $run = Get-WorkflowRuns -Repository $Repository -Workflow $Workflow -Commit $Commit -TriggerType $TriggerType |
            Where-Object {
                -not $ExistingRunIds.ContainsKey([string]$_.databaseId) -and
                ([datetimeoffset]$_.createdAt) -ge $StartedAt
            } |
            Sort-Object { [datetimeoffset]$_.createdAt } -Descending |
            Select-Object -First 1

        if ($null -ne $run) {
            return $run
        }

        Write-Host "Waiting for $Workflow to be created..."
        Start-Sleep -Seconds 3
    }

    throw "Timed out waiting for $Workflow to start."
}

& gh auth status
if ($LASTEXITCODE -ne 0) {
    throw "GitHub CLI is not authenticated. Run 'gh auth login -h github.com' and try again."
}

$repository = & gh repo view --json nameWithOwner --jq ".nameWithOwner"
if ($LASTEXITCODE -ne 0) {
    throw "Unable to determine the GitHub repository from this folder."
}

$commit = & gh api "repos/$repository/commits/$Branch" --jq ".sha"
if ($LASTEXITCODE -ne 0) {
    throw "Unable to find branch '$Branch' in $repository. Push the branch first."
}

$startedAt = [datetimeoffset]::UtcNow
$deadline = $startedAt.AddSeconds($TimeoutSeconds)
$existingCiRunIds = @{}
Get-WorkflowRuns -Repository $repository -Workflow "ci.yml" -Commit $commit -TriggerType "workflow_dispatch" |
    ForEach-Object { $existingCiRunIds[[string]$_.databaseId] = $true }
$existingCdRunIds = @{}
Get-WorkflowRuns -Repository $repository -Workflow "cd.yml" -Commit $commit -TriggerType "workflow_run" |
    ForEach-Object { $existingCdRunIds[[string]$_.databaseId] = $true }

Write-Host "Dispatching CI for $repository at $commit..."
& gh workflow run ci.yml --repo $repository --ref $Branch
if ($LASTEXITCODE -ne 0) {
    throw "CI dispatch failed. Ensure ci.yml is pushed and includes workflow_dispatch."
}

$ciRun = Wait-ForWorkflowRun -Repository $repository -Workflow "ci.yml" -Commit $commit -TriggerType "workflow_dispatch" -ExistingRunIds $existingCiRunIds -StartedAt $startedAt -Deadline $deadline
Write-Host "`nCI run: $($ciRun.url)"
& gh run watch $ciRun.databaseId --repo $repository --exit-status
if ($LASTEXITCODE -ne 0) {
    throw "CI failed. CD will not run because cd.yml only deploys after successful CI."
}

$cdRun = Wait-ForWorkflowRun -Repository $repository -Workflow "cd.yml" -Commit $commit -TriggerType "workflow_run" -ExistingRunIds $existingCdRunIds -StartedAt $startedAt -Deadline $deadline
Write-Host "`nCD run: $($cdRun.url)"
& gh run watch $cdRun.databaseId --repo $repository --exit-status
if ($LASTEXITCODE -ne 0) {
    throw "CD failed. The deployment logs above identify the failed step."
}

Write-Host "`nCI and CD completed successfully."
