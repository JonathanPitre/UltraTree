# NinjaOne Integration

UltraTree is designed for seamless integration with NinjaOne RMM. The HTML output is optimized for WYSIWYG custom fields with responsive design, charts, and color-coded status indicators.

## Overview

The integration allows you to:

- Automatically scan disk usage on all managed devices
- Display beautiful HTML reports in NinjaOne device details
- Schedule scans on a recurring basis

## Prerequisites

- NinjaOne agent installed on target devices
- UltraTree module installed system-wide (see [Installation](installation.md))
- Custom field configured (WYSIWYG/HTML type)

## Step 1: Create the Custom Field

1. Log into NinjaOne
2. Go to **Administration** → **Devices** → **Role Custom Fields**
3. Click **Add** to create a new field
4. Configure the field:
   - **Label**: `TreeSize` (or your preferred display name)
   - **Name**: `treesize` (this is the script reference name)
   - **Type**: **WYSIWYG** (HTML)
   - **Scripts**: Read/Write
5. Click **Save**
6. Assign the field to appropriate device roles

!!! warning "Important"
    The field type **must** be WYSIWYG (HTML). Plain text fields will show raw HTML code instead of the rendered report.

## Step 2: Create the Script

### Basic Script

Minimal script for quick deployment:

```powershell
# UltraTree NinjaOne Script - non-interactive safe install, then run
$ProgressPreference = 'SilentlyContinue'
$ConfirmPreference = 'None'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
    Install-PackageProvider -Name NuGet -Force -Scope AllUsers -Confirm:$false
}

if ((Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue).InstallationPolicy -ne 'Trusted') {
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
}

if (-not (Get-Module -ListAvailable -Name UltraTree -ErrorAction SilentlyContinue)) {
    Install-Module -Name UltraTree -Repository PSGallery -Scope AllUsers -Force -AllowClobber -Confirm:$false
}
Import-Module UltraTree -Force

$results = Get-FolderSizes -AllDrives -FindDuplicates -MaxDepth 5 -Top 50
$html = $results | ConvertTo-NinjaOneHtml

# Set the custom field (change 'treesize' to match your field name)
$html | Ninja-Property-Set-Piped treesize
```

### Production Script (With Error Handling)

Production-ready script with error handling and logging:

```powershell
#Requires -Version 5.1
#Requires -RunAsAdministrator

try {
    $ProgressPreference = 'SilentlyContinue'
    $ConfirmPreference = 'None'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
        Install-PackageProvider -Name NuGet -Force -Scope AllUsers -Confirm:$false
    }

    if ((Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue).InstallationPolicy -ne 'Trusted') {
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    }

    # Install module if not present
    if (-not (Get-Module -ListAvailable -Name UltraTree -ErrorAction SilentlyContinue)) {
        Write-Output "Installing UltraTree from PowerShell Gallery..."
        Install-Module -Name UltraTree -Repository PSGallery -Scope AllUsers -Force -AllowClobber -Confirm:$false
    }
    Import-Module UltraTree -Force -ErrorAction Stop

    # Run the scan and set custom field
    $results = Get-FolderSizes -AllDrives -FindDuplicates -MaxDepth 5 -Top 50
    $results | ConvertTo-NinjaOneHtml | Ninja-Property-Set-Piped treesize

    # Log summary
    Write-Output "Scan complete: $($results.TotalFiles) files, $($results.TotalFolders) folders"
    if ($results.TotalDuplicateWasted -gt 0) {
        $wastedGB = [math]::Round($results.TotalDuplicateWasted / 1GB, 2)
        Write-Output "Duplicate waste: ${wastedGB} GB"
    }
    exit 0
}
catch {
    Write-Error "UltraTree failed: $_"
    exit 1
}
```

### Production Script (With Auto-Update)

Automatically updates to the latest version from PowerShell Gallery:

```powershell
#Requires -Version 5.1
#Requires -RunAsAdministrator

try {
    $ProgressPreference = 'SilentlyContinue'
    $ConfirmPreference = 'None'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
        Install-PackageProvider -Name NuGet -Force -Scope AllUsers -Confirm:$false
    }

    if ((Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue).InstallationPolicy -ne 'Trusted') {
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    }

    $moduleName = "UltraTree"
    $installed = Get-Module -ListAvailable -Name $moduleName -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1

    if (-not $installed) {
        # First-time install
        Write-Output "Installing $moduleName from PowerShell Gallery..."
        Install-Module -Name $moduleName -Repository PSGallery -Scope AllUsers -Force -AllowClobber -Confirm:$false
    }
    else {
        # Check for updates
        $latest = Find-Module -Name $moduleName -ErrorAction SilentlyContinue
        if ($latest -and $latest.Version -gt $installed.Version) {
            Write-Output "Updating $moduleName from $($installed.Version) to $($latest.Version)..."
            Update-Module -Name $moduleName -Force -Confirm:$false
        }
    }

    Import-Module $moduleName -Force -ErrorAction Stop

    # Run the scan and set custom field
    $results = Get-FolderSizes -AllDrives -FindDuplicates -MaxDepth 5 -Top 50
    $results | ConvertTo-NinjaOneHtml | Ninja-Property-Set-Piped treesize

    # Log summary
    Write-Output "Scan complete: $($results.TotalFiles) files, $($results.TotalFolders) folders"
    if ($results.TotalDuplicateWasted -gt 0) {
        $wastedGB = [math]::Round($results.TotalDuplicateWasted / 1GB, 2)
        Write-Output "Duplicate waste: ${wastedGB} GB"
    }
    exit 0
}
catch {
    Write-Error "UltraTree failed: $_"
    exit 1
}
```

!!! note "Auto-Update Notes"
    - Requires internet access to check PowerShell Gallery
    - If offline, script continues with installed version
    - Updates are applied before the scan runs

!!! warning "Non-Interactive PowerShell"
    NinjaOne commonly runs PowerShell in a non-interactive `SYSTEM` context. The bootstrap above avoids NuGet and repository trust prompts that would otherwise fail with `ShouldContinue` errors.

### Lightweight Script (No Duplicates)

Faster scan without duplicate detection:

```powershell
if (-not (Get-Module -ListAvailable -Name UltraTree)) {
    Install-Module -Name UltraTree -Scope AllUsers -Force -AllowClobber
}
Import-Module UltraTree -Force

$results = Get-FolderSizes -AllDrives -MaxDepth 3 -Top 30
$html = $results | ConvertTo-NinjaOneHtml

$html | Ninja-Property-Set-Piped treesize
```

## Step 3: Deploy the Script

1. In NinjaOne, go to **Administration** → **Library** → **Automation**
2. Click **Add** → **New Script**
3. Configure:
   - **Name**: `UltraTree Disk Analysis`
   - **Language**: PowerShell
   - **OS**: Windows
   - **Architecture**: All
4. Paste the script content
5. Save the script

## Step 4: Schedule the Script

1. Go to **Administration** → **Policies**
2. Select the appropriate policy (or create a new one)
3. Navigate to **Scheduled Scripts**
4. Add the UltraTree script with:
   - **Schedule**: Weekly (recommended) or Daily
   - **Run As**: System (required for full disk access)
   - **Time**: Off-peak hours recommended
5. Apply the policy to target devices

!!! tip "Scheduling Recommendations"
    - **Weekly** - Sufficient for most environments
    - **Daily** - For servers or high-activity machines
    - **Monthly** - For stable workstations with little change

## Viewing Results

1. Navigate to any device running the script
2. Go to the **Details** or **Custom Fields** tab
3. Find the **TreeSize** field
4. The HTML report displays:
   - Summary statistics
   - Per-drive breakdown with charts
   - Top folders by size
   - File type analysis
   - Cleanup suggestions
   - Duplicate files (if enabled)

## Troubleshooting

### Module Not Found

If the script fails with "Module not found":

```powershell
# Verify module is installed system-wide
Get-Module -Name UltraTree -ListAvailable

# If not found, install as Administrator
Install-Module -Name UltraTree -Scope AllUsers
```

### HTML Shows as Raw Code

- Verify the custom field type is **WYSIWYG**, not Text
- Re-create the field if needed

### Scan Taking Too Long

Reduce scope for faster scans:

```powershell
# Reduce depth and disable duplicates
$results = Get-FolderSizes -AllDrives -MaxDepth 3 -Top 25
```

### Access Denied Errors

- Ensure script runs as **System**
- Check that UltraTree is installed in `$env:ProgramFiles\WindowsPowerShell\Modules`

### Empty Report

- Verify the device has fixed NTFS drives
- Check script output for errors
- Run manually on the device to debug

## Example Output

The HTML report in NinjaOne displays:

```
┌─────────────────────────────────────────────┐
│  ULTRATREE DISK ANALYSIS                    │
├─────────────────────────────────────────────┤
│  📊 2 Drives  │  📁 1,234 Items  │  🔍 15   │
│               │                  │  Dupes   │
├─────────────────────────────────────────────┤
│  DRIVE C: - 75% Used (Warning)              │
│  ████████████████░░░░░░  375GB / 500GB      │
│                                             │
│  Top Folders:                               │
│  ▓▓▓▓▓▓▓▓▓▓ Windows      45 GB             │
│  ▓▓▓▓▓▓▓▓   Users        38 GB             │
│  ▓▓▓▓▓▓     Program Files 25 GB            │
│                                             │
│  Cleanup Suggestions:                       │
│  🗑️ Recycle Bin         2.5 GB             │
│  ⏰ Temp Files           1.2 GB             │
│  📦 node_modules         5.8 GB             │
└─────────────────────────────────────────────┘
```

## Best Practices

1. **Start with weekly scans** - Adjust frequency based on needs
2. **Use alerts** - Don't just collect data, act on it
3. **Review cleanup suggestions** - Automate where safe
4. **Monitor duplicates** - Significant space savings possible
5. **Test first** - Run manually before deploying widely
