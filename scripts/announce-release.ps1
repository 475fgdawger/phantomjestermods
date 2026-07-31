<#
.SYNOPSIS
  Post a release announcement embed to a Discord channel webhook.

.EXAMPLE
  scripts\announce-release.ps1 -Tag v0.9.2 -Title "Jester Overhaul (Full) — v0.9.2" -DescriptionFile notes.txt

.EXAMPLE
  scripts\announce-release.ps1 -Tag PhantomJesterRadarRwrBfm -Title "Jester Combat Core" -Description "**Radar** ..."

.NOTES
  Webhook is resolved from, in order:
    1. $env:DISCORD_WEBHOOK
    2. scripts\.discord_webhook  (one line; gitignored — never committed)
  The tag is turned into the GitHub release URL automatically.
#>
param(
    [Parameter(Mandatory = $true)][string]$Tag,
    [Parameter(Mandatory = $true)][string]$Title,
    [string]$DescriptionFile,
    [string]$Description
)

$ErrorActionPreference = 'Stop'
$repo = '475fgdawger/phantomjestermods'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- resolve webhook (never printed) ---
$hook = $env:DISCORD_WEBHOOK
if (-not $hook) {
    $wf = Join-Path $here '.discord_webhook'
    if (Test-Path $wf) { $hook = (Get-Content -Raw $wf).Trim() }
}
if (-not $hook) { throw "No webhook. Set `$env:DISCORD_WEBHOOK or create $here\.discord_webhook" }

# --- description (file or inline) ---
if ($DescriptionFile) { $Description = Get-Content -Raw -Encoding UTF8 $DescriptionFile }
if (-not $Description) { throw "Provide -DescriptionFile or -Description" }

$url = "https://github.com/$repo/releases/tag/$Tag"

$payload = @{
    username = 'Phantom Jester Mods'
    embeds   = @(@{
            title       = $Title
            url         = $url
            color       = 3447003
            description = $Description
        })
} | ConvertTo-Json -Depth 6

# Send as UTF-8 bytes so em dashes / emoji survive.
$bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
$null = Invoke-RestMethod -Uri "${hook}?wait=true" -Method Post -ContentType 'application/json' -Body $bytes
Write-Host "Posted OK: $Title"
Write-Host "  -> $url"
