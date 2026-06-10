[CmdletBinding()]
param(
    [string]$Version,
    [ValidateSet("x86", "arm", "loongarch", "risc-v", "all")]
    [string]$Platform,
    [string]$OsMinVersion,
    [string]$WebBuildPath = "build/web",
    [string]$OutputRoot = "dist/fnos"
)

$ErrorActionPreference = "Stop"

function Get-RepoRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

function Get-PubspecVersion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PubspecPath
    )

    $match = Select-String -Path $PubspecPath -Pattern '^\s*version:\s*(.+?)\s*$' | Select-Object -First 1
    if (-not $match) {
        throw "Unable to find version in $PubspecPath"
    }

    return $match.Matches[0].Groups[1].Value.Trim()
}

function Get-PackageVersion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RawVersion
    )

    $normalized = $RawVersion.Trim()
    if ($normalized.StartsWith("v")) {
        $normalized = $normalized.Substring(1)
    }

    if ($normalized -match '^(.+?)\+(.+)$') {
        return "$($Matches[1])-$($Matches[2])"
    }

    return $normalized
}

function Get-ArtifactVersion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RawVersion
    )

    return ($RawVersion.Trim() -replace '\+', '-')
}

function Ensure-Directory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Get-TargetPlatforms {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequestedPlatform
    )

    if ($RequestedPlatform -eq "all") {
        return @("x86", "arm")
    }

    return @($RequestedPlatform)
}

function Write-Utf8File {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $parent = Split-Path -Parent $Path
    if ($parent) {
        Ensure-Directory -Path $parent
    }

    Set-Content -Path $Path -Value $Content -Encoding utf8NoBOM
}

$repoRoot = Get-RepoRoot
$packageConfigPath = Join-Path $repoRoot "packaging/fnos/package.json"
$packageConfig = Get-Content -Path $packageConfigPath -Raw | ConvertFrom-Json

if (-not $Version) {
    $Version = Get-PubspecVersion -PubspecPath (Join-Path $repoRoot "pubspec.yaml")
}

$packageVersion = Get-PackageVersion -RawVersion $Version
$artifactVersion = Get-ArtifactVersion -RawVersion $Version

$resolvedPlatform = if ($Platform) { $Platform } else { [string]$packageConfig.platform }
$resolvedOsMinVersion = if ($OsMinVersion) { $OsMinVersion } else { [string]$packageConfig.osMinVersion }
$targetPlatforms = Get-TargetPlatforms -RequestedPlatform $resolvedPlatform

$webBuildFullPath = (Resolve-Path (Join-Path $repoRoot $WebBuildPath)).Path
if (-not (Test-Path (Join-Path $webBuildFullPath "index.html"))) {
    throw "Web build output not found at $webBuildFullPath. Run 'flutter build web --release' first."
}

if ($resolvedPlatform -eq "all") {
    Write-Host "platform=all in package config will be expanded into separate fnOS source packages for: $($targetPlatforms -join ', ')"
}

$outputFullPath = Join-Path $repoRoot $OutputRoot
Ensure-Directory -Path $outputFullPath

$legacyStagingDir = Join-Path $outputFullPath $packageConfig.packageRootName
$legacyArchivePath = Join-Path $outputFullPath ("{0}-{1}.zip" -f $packageConfig.archiveNamePrefix, $artifactVersion)
if (Test-Path $legacyStagingDir) {
    Remove-Item -LiteralPath $legacyStagingDir -Recurse -Force
}
if (Test-Path $legacyArchivePath) {
    Remove-Item -LiteralPath $legacyArchivePath -Force
}

$privilegeObject = [ordered]@{
    defaults = [ordered]@{
        "run-as" = "package"
    }
}

$resourceObject = [ordered]@{
    "docker-project" = [ordered]@{
        projects = @(
            [ordered]@{
                name = $packageConfig.dockerProjectName
                path = $packageConfig.dockerComposePath
            }
        )
    }
}

$dockerCompose = @"
version: '3.8'

services:
  web:
    container_name: $($packageConfig.containerName)
    image: $($packageConfig.containerImage)
    restart: unless-stopped
    ports:
      - "$($packageConfig.servicePort):$($packageConfig.containerPort)"
    volumes:
      - ./site:/usr/share/nginx/html:ro
      - ./nginx/default.conf:/etc/nginx/conf.d/default.conf:ro
"@

$cmdMain = @'
#!/bin/bash
set -eu

FILE_PATH="${TRIM_APPDEST}/docker/docker-compose.yaml"

get_container_name() {
    if [ -f "$FILE_PATH" ]; then
        awk '/container_name:/ { print $2; exit }' "$FILE_PATH"
    fi
}

is_docker_running() {
    DOCKER_NAME="$(get_container_name)"

    if [ -n "$DOCKER_NAME" ]; then
        docker inspect "$DOCKER_NAME" 2>/dev/null | grep -q '"Status": "running"' || return 1
        return 0
    fi

    return 1
}

case "${1:-}" in
start)
    exit 0
    ;;
stop)
    exit 0
    ;;
status)
    if is_docker_running; then
        exit 0
    else
        exit 3
    fi
    ;;
*)
    exit 1
    ;;
esac
'@

$buildResults = @()

foreach ($targetPlatform in $targetPlatforms) {
    $packageRootName = "{0}-{1}" -f $packageConfig.packageRootName, $targetPlatform
    $stagingDir = Join-Path $outputFullPath $packageRootName
    $archivePath = Join-Path $outputFullPath ("{0}-{1}-{2}.zip" -f $packageConfig.archiveNamePrefix, $artifactVersion, $targetPlatform)

    if (Test-Path $stagingDir) {
        Remove-Item -LiteralPath $stagingDir -Recurse -Force
    }

    if (Test-Path $archivePath) {
        Remove-Item -LiteralPath $archivePath -Force
    }

    Ensure-Directory -Path $stagingDir
    Ensure-Directory -Path (Join-Path $stagingDir "app/docker/site")
    Ensure-Directory -Path (Join-Path $stagingDir "app/docker/nginx")
    Ensure-Directory -Path (Join-Path $stagingDir "app/ui/images")
    Ensure-Directory -Path (Join-Path $stagingDir "cmd")
    Ensure-Directory -Path (Join-Path $stagingDir "config")

    $manifest = @"
appname=$($packageConfig.appname)
version=$packageVersion
display_name=$($packageConfig.displayName)
desc=$($packageConfig.description)
platform=$targetPlatform
source=$($packageConfig.source)
maintainer=$($packageConfig.maintainer)
maintainer_url=$($packageConfig.maintainerUrl)
distributor=$($packageConfig.distributor)
distributor_url=$($packageConfig.distributorUrl)
os_min_version=$resolvedOsMinVersion
desktop_uidir=ui
desktop_applaunchname=$($packageConfig.entryId)
service_port=$($packageConfig.servicePort)
checkport=true
disable_authorization_path=true
"@

    $uiConfigObject = [ordered]@{
        ".url" = [ordered]@{
            ($packageConfig.entryId) = [ordered]@{
                title = $packageConfig.entryTitle
                icon = "images/lserial-{0}.png"
                type = $packageConfig.entryType
                protocol = $packageConfig.protocol
                port = [string]$packageConfig.servicePort
                url = $packageConfig.entryPath
                allUsers = [bool]$packageConfig.allUsers
                control = [ordered]@{
                    accessPerm = "readonly"
                }
            }
        }
    }

    Write-Utf8File -Path (Join-Path $stagingDir "manifest") -Content $manifest.Trim()
    Write-Utf8File -Path (Join-Path $stagingDir "app/ui/config") -Content ($uiConfigObject | ConvertTo-Json -Depth 10)
    Write-Utf8File -Path (Join-Path $stagingDir "config/privilege") -Content ($privilegeObject | ConvertTo-Json -Depth 10)
    Write-Utf8File -Path (Join-Path $stagingDir "config/resource") -Content ($resourceObject | ConvertTo-Json -Depth 10)
    Write-Utf8File -Path (Join-Path $stagingDir "app/docker/docker-compose.yaml") -Content $dockerCompose.Trim()
    Write-Utf8File -Path (Join-Path $stagingDir "cmd/main") -Content $cmdMain.Trim()

    Copy-Item -LiteralPath (Join-Path $repoRoot "packaging/fnos/docker/default.conf") -Destination (Join-Path $stagingDir "app/docker/nginx/default.conf") -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot "packaging/fnos/LICENSE") -Destination (Join-Path $stagingDir "LICENSE") -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot "packaging/fnos/README.md") -Destination (Join-Path $stagingDir "README.md") -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot "packaging/fnos/assets/ICON.PNG") -Destination (Join-Path $stagingDir "ICON.PNG") -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot "packaging/fnos/assets/ICON_256.PNG") -Destination (Join-Path $stagingDir "ICON_256.PNG") -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot "packaging/fnos/assets/ICON.PNG") -Destination (Join-Path $stagingDir "app/ui/images/lserial-64.png") -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot "packaging/fnos/assets/ICON_256.PNG") -Destination (Join-Path $stagingDir "app/ui/images/lserial-256.png") -Force
    Copy-Item -Path (Join-Path $webBuildFullPath "*") -Destination (Join-Path $stagingDir "app/docker/site") -Recurse -Force

    Push-Location $outputFullPath
    try {
        Compress-Archive -Path $packageRootName -DestinationPath $archivePath -Force
    }
    finally {
        Pop-Location
    }

    $buildResults += [pscustomobject]@{
        Platform   = $targetPlatform
        PackageDir = $stagingDir
        Archive    = $archivePath
    }
}

foreach ($buildResult in $buildResults) {
    Write-Host "FNOS package directory [$($buildResult.Platform)]: $($buildResult.PackageDir)"
    Write-Host "FNOS package archive   [$($buildResult.Platform)]: $($buildResult.Archive)"
}
Write-Host "FNOS min system ver: $resolvedOsMinVersion"
