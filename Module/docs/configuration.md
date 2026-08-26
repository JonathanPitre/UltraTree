# Configuration

UltraTree uses internal configuration settings that control thresholds, display limits, and visual styling. These are defined in the module and can be customized if needed.

## Thresholds

Control what gets flagged and displayed:

| Setting | Default | Description |
|---------|---------|-------------|
| `CleanupMin` | 100MB | Minimum size for items to appear in cleanup suggestions |
| `DuplicateMin` | 10MB | Minimum file size for duplicate detection |
| `LargeFile` | 100MB | Files above this size are included in results |
| `DangerWasted` | 500MB | Wasted space threshold for "Danger" severity |
| `WarningWasted` | 100MB | Wasted space threshold for "Warning" severity |
| `ErrorWarning` | 50 | Show warning if more than N files couldn't be read |

## Display Limits

Control how much data appears in HTML reports:

| Setting | Default | Description |
|---------|---------|-------------|
| `MaxDuplicateGroups` | 20 | Maximum duplicate groups shown in report |
| `MaxPathsPerGroup` | 5 | Maximum file paths shown per duplicate group |
| `MaxTopFolders` | 25 | Top folders in ranked table per drive |
| `MaxTopFiles` | 50 | Top files in ranked table per drive |
| `MaxFileTypes` | 10 | Number of file types in the table |
| `MaxResults` | 40 | Maximum items in the full results table |
| `MaxPathLength` | 50 | Truncate paths longer than this in display |
| `MaxLabelLength` | 12 | Truncate chart labels longer than this |

### Top Files / Top Folders and `-Top`

`ConvertTo-NinjaOneHtml` builds per-drive Top Files and Top Folders tables from `Get-FolderSizes` output. `Items` is a **single mixed list** of files and folders, sorted by size and truncated by `-Top` (default 40) across all drives. Folders usually fill most of that list, so raise `-Top` when you need more file rows (for example `-Top 200`).

## Disk Health Thresholds

Control health status indicators:

| Setting | Default | Description |
|---------|---------|-------------|
| `CriticalPercent` | 90 | Disk usage % marked as Critical (red) |
| `WarningPercent` | 75 | Disk usage % marked as Warning (orange) |

Below 75% is marked as Healthy (green).

## Size Categories

Control row coloring in the results table:

| Category | Threshold | Color |
|----------|-----------|-------|
| Danger | > 100GB | Red |
| Warning | > 50GB | Orange |
| Other | > 10GB | Light blue |
| Unknown | > 1GB | Gray |
| Success | < 1GB | Default |

## Theme Colors

The HTML report uses these colors:

| Name | Hex | Usage |
|------|-----|-------|
| Danger | `#d9534f` | Critical items, errors |
| Warning | `#f0ad4e` | Warning items |
| Info | `#5bc0de` | Informational items |
| Success | `#4ECDC4` | Healthy status |
| Primary | `#337ab7` | Headers, links |
| Muted | `#999999` | Secondary text |
| Critical | `#FF6B6B` | Critical disk status |
| Free | `#95a5a6` | Free space in charts |

## Cleanup Categories

Built-in cleanup detection categories:

| Category | Display Name | Patterns | Icon |
|----------|--------------|----------|------|
| `recycleBin` | Recycle Bin | `$Recycle.Bin`, `RECYCLER` | Trash |
| `temp` | Temp Files | `\Temp\`, `\tmp\`, `AppData\Local\Temp` | Clock |
| `cache` | Cache Files | `\Cache\`, `.cache\`, `CachedData` | Database |
| `nodeModules` | node_modules | `\node_modules\` | Code |
| `git` | .git folders | `\.git\` | Code Branch |
| `downloads` | Downloads | `\Downloads\` | Download |
| `installer` | Windows Installer | `\Windows\Installer\` | Cog |

## Customizing Configuration

To customize settings, modify `Private/Configuration.ps1` in the module folder:

```powershell
# Example: Change thresholds
$script:Config = @{
    Thresholds = @{
        CleanupMin   = 50MB    # Lower threshold
        DuplicateMin = 5MB     # Catch smaller duplicates
        LargeFile    = 50MB    # Show more files
        # ...
    }
    # ...
}
```

After modifying, re-import the module:

```powershell
Import-Module UltraTree -Force
```

!!! warning "Module Updates"
    Custom configuration changes will be lost when updating the module. Consider keeping a backup of your customizations.

## Parameter Validation

The module validates parameters at runtime:

| Parameter | Validation |
|-----------|------------|
| MaxDepth | Must be 1-20 |
| Top | Must be 1-1000 |
| MinDuplicateSize | Cannot be negative |
| DriveLetter | Must be valid drive letter |

Invalid parameters will throw an error before scanning begins.
