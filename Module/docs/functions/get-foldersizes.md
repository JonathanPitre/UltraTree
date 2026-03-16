# Get-FolderSizes

Scans one or more drives and returns detailed disk usage information including folder sizes, file types, cleanup suggestions, and optionally duplicate files.

## Syntax

```powershell
Get-FolderSizes [-DriveLetter] <String> [-MaxDepth <Int32>] [-Top <Int32>]
    [-FolderSize] [-FileSize] [-VerboseOutput] [-FindDuplicates] [-MinDuplicateSize <Int64>]

Get-FolderSizes -AllDrives [-ExcludeDrives <String[]>] [-MaxDepth <Int32>] [-Top <Int32>]
    [-FolderSize] [-FileSize] [-VerboseOutput] [-FindDuplicates] [-MinDuplicateSize <Int64>]
```

## Parameters

| Parameter | Type | Default | Range | Description |
|-----------|------|---------|-------|-------------|
| **DriveLetter** | String | - | - | Drive letter to scan (e.g., "C"). Required unless `-AllDrives` is specified. |
| **AllDrives** | Switch | `$false` | - | Scan all fixed drives on the system. |
| **ExcludeDrives** | String[] | - | - | Array of drive letters to skip when using `-AllDrives`. |
| **MaxDepth** | Int32 | `5` | 1-20 | Maximum folder depth to include in results. |
| **Top** | Int32 | `40` | 1-1000 | Maximum number of items to return per drive. |
| **FolderSize** | Switch | `$false` | - | Show only folders in results (excludes files). |
| **FileSize** | Switch | `$false` | - | Show only large files in results (excludes folders). |
| **FindDuplicates** | Switch | `$false` | - | Enable staged duplicate detection. True duplicate groups are returned in `Duplicates`; NTFS hardlinks are returned separately in `LinkedFiles`. |
| **MinDuplicateSize** | Int64 | `10MB` | 0+ | Minimum on-disk file size to consider for duplicate detection. This uses compressed/allocated size semantics, not sparse logical length. |
| **VerboseOutput** | Switch | `$false` | - | Display progress information during scan. |

## Examples

### Scan a Single Drive

```powershell
$results = Get-FolderSizes -DriveLetter C
```

### Scan with Custom Depth and Results

```powershell
$results = Get-FolderSizes -DriveLetter C -MaxDepth 5 -Top 50
```

### Scan All Drives

```powershell
$results = Get-FolderSizes -AllDrives
```

### Scan All Drives Except D:

```powershell
$results = Get-FolderSizes -AllDrives -ExcludeDrives @("D")
```

### Find Duplicate Files

```powershell
$results = Get-FolderSizes -DriveLetter C -FindDuplicates
```

### Find Large Duplicates Only (50MB+)

```powershell
$results = Get-FolderSizes -DriveLetter C -FindDuplicates -MinDuplicateSize 50MB
```

### Show Only Folders

```powershell
$results = Get-FolderSizes -DriveLetter C -FolderSize -Top 100
```

### Show Only Large Files

```powershell
$results = Get-FolderSizes -DriveLetter C -FileSize -Top 100
```

### Verbose Output for Monitoring

```powershell
$results = Get-FolderSizes -AllDrives -FindDuplicates -VerboseOutput
```

## Return Object

`Get-FolderSizes` returns a `PSCustomObject` with the following properties:

| Property | Type | Description |
|----------|------|-------------|
| **Items** | List | Folders/files sorted by size descending |
| **FileTypes** | List | File extension statistics |
| **CleanupSuggestions** | List | Identified cleanup opportunities |
| **Duplicates** | List | Duplicate file groups (if `-FindDuplicates` specified) |
| **LinkedFiles** | List | NTFS hardlink groups reported separately from duplicate waste |
| **DriveInfo** | List | Drive capacity and usage for each scanned drive |
| **TotalDuplicateWasted** | Int64 | Total reclaimable bytes from duplicate files, excluding hardlinks |
| **TotalFiles** | Int64 | Total files scanned |
| **TotalFolders** | Int64 | Total folders scanned |
| **TotalErrorCount** | Int64 | Count of access errors encountered |

### Items Structure

Each item in the `Items` collection:

```powershell
[PSCustomObject]@{
    Drive        = "C:"           # Drive letter
    Path         = "C:\Users"     # Full path
    Size         = "15.20 GB"     # Human-readable size
    SizeBytes    = 16324567890    # Size in bytes
    IsDirectory  = $true          # True for folders
    LastModified = "2024-01-15"   # Last modified date
}
```

### DriveInfo Structure

Each item in the `DriveInfo` collection:

```powershell
[PSCustomObject]@{
    Drive       = "C:"            # Drive letter
    TotalSize   = 500107862016    # Total capacity in bytes
    UsedSpace   = 350075703296    # Used space in bytes
    FreeSpace   = 150032158720    # Free space in bytes
    UsedPercent = 70.0            # Usage percentage
}
```

### Duplicates Structure

Each item in the `Duplicates` collection (when `-FindDuplicates` is used):

```powershell
[PSCustomObject]@{
    Drive       = "C:"            # Drive letter
    Hash        = "a1b2c3d4..."   # xxHash64 hash
    FileSize    = 104857600       # Size of each file in bytes
    Files       = @(              # Array of duplicate paths
        "C:\path1\file.exe",
        "C:\path2\file.exe"
    )
    WastedSpace = 104857600       # Wasted bytes (FileSize × (Count-1))
}
```

### LinkedFiles Structure

Each item in the `LinkedFiles` collection:

```powershell
[PSCustomObject]@{
    Drive         = "C:"                                # Drive letter
    Identity      = "A6E7F19B:008600000004173F"        # NTFS file identity
    FileSize      = 2371584                            # On-disk size of the shared file
    Files         = @("C:\path1\file.bin", "C:\path2\file.bin")
    IsLinkedGroup = $true
}
```

## Duplicate and Linked-File Semantics

- `Duplicates` contains separate files with identical content.
- `LinkedFiles` contains NTFS hardlinks, which are multiple paths to the same underlying file record.
- `TotalDuplicateWasted` reports reclaimable bytes from duplicate groups only.
- Hardlinks are excluded from duplicate waste totals.
- `MinDuplicateSize` uses on-disk size semantics. Sparse files can have a logical length larger than the threshold used for duplicate candidate filtering.

### FileTypes Structure

Each item in the `FileTypes` collection:

```powershell
[PSCustomObject]@{
    Drive     = "C:"              # Drive letter
    Extension = ".exe"            # File extension
    TotalSize = 5368709120        # Combined size in bytes
    FileCount = 1250              # Number of files
}
```

### CleanupSuggestions Structure

Each item in the `CleanupSuggestions` collection:

```powershell
[PSCustomObject]@{
    Drive       = "C:"            # Drive letter
    Path        = "C:\Windows\Temp"  # Path to cleanup target
    Category    = "temp"          # Cleanup category
    Size        = 1073741824      # Size in bytes
    Description = "Temporary files that can be safely deleted"
}
```

## Working with Results

### Get Top 10 Largest Folders

```powershell
$results = Get-FolderSizes -DriveLetter C
$results.Items | Where-Object { $_.IsDirectory } | Select-Object -First 10
```

### Calculate Total Wasted Space from Duplicates

```powershell
$results = Get-FolderSizes -DriveLetter C -FindDuplicates
$wastedGB = [math]::Round($results.TotalDuplicateWasted / 1GB, 2)
Write-Output "Total wasted: ${wastedGB} GB"
```

### Find Drives Over 80% Full

```powershell
$results = Get-FolderSizes -AllDrives
$results.DriveInfo | Where-Object { $_.UsedPercent -gt 80 }
```

### Export Results to CSV

```powershell
$results = Get-FolderSizes -DriveLetter C
$results.Items | Export-Csv -Path "DiskUsage.csv" -NoTypeInformation
```

## Notes

- Requires Administrator privileges for full access to all folders
- Uses NTFS MFT enumeration for maximum performance
- Duplicate detection uses xxHash64 for fast, reliable hashing
- Hardlinks are reported separately in `LinkedFiles` and do not contribute to `TotalDuplicateWasted`
- Access errors are tracked but don't stop the scan
