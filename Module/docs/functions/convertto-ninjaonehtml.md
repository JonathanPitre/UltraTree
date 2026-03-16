# ConvertTo-NinjaOneHtml

Converts scan results from `Get-FolderSizes` into an HTML report optimized for NinjaOne WYSIWYG custom fields.

## Syntax

```powershell
ConvertTo-NinjaOneHtml [-ScanResults] <PSCustomObject>
```

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| **ScanResults** | PSCustomObject | Yes | Output from `Get-FolderSizes`. Supports pipeline input. |

## Examples

### Basic Usage

```powershell
$results = Get-FolderSizes -DriveLetter C
$html = ConvertTo-NinjaOneHtml -ScanResults $results
```

### Pipeline Usage

```powershell
$html = Get-FolderSizes -AllDrives | ConvertTo-NinjaOneHtml
```

### Full Scan with Duplicates

```powershell
$html = Get-FolderSizes -AllDrives -FindDuplicates | ConvertTo-NinjaOneHtml
```

### Save to File

```powershell
Get-FolderSizes -AllDrives -FindDuplicates |
    ConvertTo-NinjaOneHtml |
    Out-File "DiskReport.html" -Encoding UTF8
```

### Set NinjaOne Custom Field

```powershell
$results = Get-FolderSizes -AllDrives -FindDuplicates
$html = $results | ConvertTo-NinjaOneHtml
$html | Ninja-Property-Set-Piped treesize
```

## Output

Returns a string containing HTML markup with:

### Summary Section

- **Drives Scanned** - Number of drives analyzed
- **Total Items** - Combined folders and files found
- **Duplicates Found** - Number of duplicate file groups (if enabled)
- **Cleanup Potential** - Total size of cleanup suggestions

### Per-Drive Sections

Each scanned drive gets its own section with:

- **Drive Stats** - Used space, free space, health status (Healthy/Warning/Critical)
- **Disk Usage Chart** - Visual bar showing used vs free space
- **Top Folders Chart** - Bar chart of largest folders
- **File Types Table** - Breakdown by extension
- **Cleanup Suggestions** - Categorized cleanup opportunities

### Duplicates Section

If `-FindDuplicates` was used:

- **Duplicate Groups** - Files with identical content
- **Wasted Space** - Reclaimable space from duplicate groups
- **File Paths** - Locations of duplicate files

### Linked Files Section

If linked NTFS files are detected:

- **Linked Files** - Hardlinked paths that reference the same underlying file record
- **Separate from Duplicates** - These are not counted as reclaimable duplicate waste
- **Hardlink Context** - Helps distinguish true duplicated content from shared NTFS file records

### Results Table

- Full sortable table of all items
- Color-coded by size severity
- Shows path, size, type, and last modified date

### Footer

- Scan timestamp
- UltraTree version

## HTML Features

The generated HTML includes:

- **Bootstrap 5** - Responsive grid and components
- **Font Awesome 6** - Icons for status and categories
- **Charts.css** - Lightweight CSS-based charts
- **Dark/Light support** - Respects system preference
- **Mobile-friendly** - Responsive design

## Customization

The HTML output is controlled by the module's configuration. See [Configuration](../configuration.md) for options like:

- `MaxTopFolders` - Number of folders in bar chart
- `MaxFileTypes` - Number of file types shown
- `MaxResults` - Items in results table
- `MaxDuplicateGroups` - Duplicate groups displayed

## Notes

- HTML includes external CDN references for Bootstrap, Font Awesome, and Charts.css
- Best viewed in modern browsers or NinjaOne WYSIWYG fields
- For offline viewing, external resources need internet connectivity
- Duplicate waste in the HTML report excludes NTFS hardlinks, which are shown in a dedicated linked-files section when present
