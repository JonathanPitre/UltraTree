function Get-FolderSizes {
    <#
    .SYNOPSIS
        Ultra-fast folder size calculation using USN Journal / MFT enumeration.
    .DESCRIPTION
        Scans one or more drives to calculate folder sizes, identify large files,
        detect duplicates, and suggest cleanup opportunities. Uses NTFS MFT for
        high-speed enumeration when available, with automatic fallback for non-NTFS drives.
    .PARAMETER DriveLetter
        The drive letter to scan (e.g., "C"). Required unless -AllDrives is specified.
    .PARAMETER MaxDepth
        Maximum folder depth to include in results (default: 5, range: 1-20).
    .PARAMETER Top
        Maximum number of items returned in ScanResults.Items (default: 40, range: 1-1000).
        Items is a single list of files and folders mixed together, sorted by size globally
        (across all drives when using -AllDrives). Folders usually dominate this list.
        For ranked Top Files tables in ConvertTo-NinjaOneHtml, use a larger -Top value
        (for example -Top 200) so enough file rows remain after truncation.
    .PARAMETER FolderSize
        Show only folders in results (excludes individual files).
    .PARAMETER FileSize
        Show only large files in results (excludes folders).
    .PARAMETER VerboseOutput
        Display progress information during scan.
    .PARAMETER AllDrives
        Scan all fixed drives on the system.
    .PARAMETER ExcludeDrives
        Array of drive letters to exclude when using -AllDrives.
    .PARAMETER FindDuplicates
        Enable duplicate file detection using xxHash64.
    .PARAMETER MinDuplicateSize
        Minimum file size for duplicate detection (default: from config, typically 10MB).
    .OUTPUTS
        PSCustomObject with properties:
        - Items: List of folders/files with size information
        - FileTypes: File type statistics by extension
        - CleanupSuggestions: Identified cleanup opportunities
        - Duplicates: Duplicate file groups (if -FindDuplicates specified)
        - DriveInfo: Drive capacity and usage information
        - TotalDuplicateWasted: Total wasted space from duplicates
        - TotalFiles: Count of files scanned
        - TotalFolders: Count of folders scanned
        - TotalErrorCount: Count of access errors encountered
    .EXAMPLE
        Get-FolderSizes -DriveLetter C -MaxDepth 3 -Top 20
        Scans the C: drive to depth 3 and returns top 20 largest items.
    .EXAMPLE
        Get-FolderSizes -AllDrives -FindDuplicates -VerboseOutput
        Scans all drives with duplicate detection and progress output.
    .EXAMPLE
        Get-FolderSizes -AllDrives -ExcludeDrives @("D", "E") -FolderSize
        Scans all drives except D: and E:, showing only folder sizes.
    .NOTES
        Requires administrator privileges for MFT-based scanning.
        Falls back to standard enumeration if MFT access is unavailable.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$DriveLetter,

        [Parameter()]
        [ValidateRange(1, 20)]
        [int]$MaxDepth = 5,

        [Parameter()]
        [ValidateRange(1, 1000)]
        [int]$Top = 40,

        [Parameter()]
        [Switch]$FolderSize,

        [Parameter()]
        [Switch]$FileSize,

        [Parameter()]
        [Switch]$VerboseOutput,

        [Parameter()]
        [Switch]$AllDrives,

        [Parameter()]
        [string[]]$ExcludeDrives,

        [Parameter()]
        [Switch]$FindDuplicates,

        [Parameter()]
        [long]$MinDuplicateSize = 0
    )

    # Use config default if not specified
    if ($MinDuplicateSize -eq 0) {
        $MinDuplicateSize = $script:Config.Thresholds.DuplicateMin
    }

    # Validate parameters
    Test-ScanParameters -DriveLetter $DriveLetter -MaxDepth $MaxDepth -Top $Top -MinDuplicateSize $MinDuplicateSize -AllDrives:$AllDrives

    if (-not $AllDrives -and -not $DriveLetter) {
        throw "You must specify either -DriveLetter or -AllDrives."
    }

    # Clear error log for new scan
    Clear-ErrorLog

    $drivesToProcess = if ($AllDrives) {
        $allFixed = (Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 }).DeviceID
        if ($ExcludeDrives.Count -gt 0) {
            $excludeNormalized = $ExcludeDrives | ForEach-Object { $_.TrimEnd(':').ToUpper() + ':' }
            $allFixed | Where-Object { $_ -notin $excludeNormalized }
        }
        else {
            $allFixed
        }
    }
    else {
        @("$DriveLetter`:")
    }

    # Prepare category patterns for C#
    $categoryPatterns = $script:CleanupCategories | ForEach-Object { , $_.Patterns }
    $categoryNames = $script:CleanupCategories | ForEach-Object { $_.Name }

    $allResults = [PSCustomObject]@{
        Items                = [System.Collections.Generic.List[object]]::new()
        FileTypes            = [System.Collections.Generic.List[object]]::new()
        CleanupSuggestions   = [System.Collections.Generic.List[object]]::new()
        Duplicates           = [System.Collections.Generic.List[object]]::new()
        DriveInfo            = [System.Collections.Generic.List[object]]::new()
        TotalDuplicateWasted = 0
        TotalFiles           = 0
        TotalFolders         = 0
        TotalErrorCount      = 0
    }

    foreach ($drive in $drivesToProcess) {
        if ($VerboseOutput) { Write-Output "Processing drive $drive" }
        $driveLetterOnly = $drive.TrimEnd(':')
        $includeFiles = $FileSize -or (-not $FolderSize -and -not $FileSize)

        try {
            $scanResult = [MftTreeSizeV8.MftScanner]::ScanWithAnalysis(
                $driveLetterOnly,
                $MaxDepth,
                $Top,
                $includeFiles,
                [bool]$VerboseOutput,
                [bool]$FindDuplicates,
                $MinDuplicateSize,
                $script:Config.Thresholds.LargeFile,
                $script:Config.Thresholds.CleanupMin,
                $categoryPatterns,
                $categoryNames
            )
        }
        catch {
            Add-ScanError -Path $drive -Category "io" -Message $_.Exception.Message
            Write-Warning "Failed to scan drive $drive`: $_"
            continue
        }

        # Add drive info
        $allResults.DriveInfo.Add([PSCustomObject]@{
                Drive       = $drive
                TotalSize   = $scanResult.TotalDriveSize
                UsedSpace   = $scanResult.TotalUsedSpace
                FreeSpace   = $scanResult.TotalFreeSpace
                UsedPercent = [math]::Round(($scanResult.TotalUsedSpace / $scanResult.TotalDriveSize) * 100, 1)
            })

        # Aggregate totals
        $allResults.TotalFiles += $scanResult.TotalFiles
        $allResults.TotalFolders += $scanResult.TotalFolders
        $allResults.TotalErrorCount += $scanResult.ErrorCount

        # Add items
        foreach ($item in $scanResult.Items) {
            $minValidDate = [DateTime]::new(1980, 1, 1)
            $lastMod = if ($item.LastModified -gt $minValidDate) { $item.LastModified.ToString("yyyy-MM-dd") } else { "" }
            $allResults.Items.Add([PSCustomObject]@{
                    Drive        = $drive
                    Path         = $item.Path
                    Size         = Format-ByteSize -Bytes $item.Size
                    SizeBytes    = $item.Size
                    IsDirectory  = $item.IsDirectory
                    LastModified = $lastMod
                })
        }

        # Add file types
        foreach ($ft in $scanResult.FileTypes) {
            $allResults.FileTypes.Add([PSCustomObject]@{
                    Drive     = $drive
                    Extension = $ft.Extension
                    TotalSize = $ft.TotalSize
                    FileCount = $ft.FileCount
                })
        }

        # Add cleanup suggestions
        foreach ($sug in $scanResult.CleanupSuggestions) {
            $allResults.CleanupSuggestions.Add([PSCustomObject]@{
                    Drive       = $drive
                    Path        = $sug.Path
                    Category    = $sug.Category
                    Size        = $sug.Size
                    Description = $sug.Description
                })
        }

        # Add duplicates
        if ($FindDuplicates -and $scanResult.Duplicates -and $scanResult.Duplicates.Groups) {
            foreach ($group in $scanResult.Duplicates.Groups) {
                $allResults.Duplicates.Add([PSCustomObject]@{
                        Drive       = $drive
                        Hash        = $group.Hash
                        FileSize    = $group.FileSize
                        Files       = $group.Files
                        WastedSpace = $group.WastedSpace
                    })
            }
            $allResults.TotalDuplicateWasted += $scanResult.Duplicates.TotalWastedSpace
        }
    }

    # Filter items
    if ($FolderSize -and -not $FileSize) {
        $allResults.Items = $allResults.Items | Where-Object { $_.IsDirectory }
    }
    elseif ($FileSize -and -not $FolderSize) {
        $allResults.Items = $allResults.Items | Where-Object { -not $_.IsDirectory }
    }

    # Sort and limit
    $allResults.Items = $allResults.Items | Sort-Object -Property SizeBytes -Descending | Select-Object -First $Top
    $allResults.Duplicates = $allResults.Duplicates | Sort-Object -Property WastedSpace -Descending

    return $allResults
}
