# ConvertTo-NinjaOneHtml

Converts scan results from `Get-FolderSizes` into an HTML report optimized for NinjaOne WYSIWYG custom fields.

## Syntax

```powershell
ConvertTo-NinjaOneHtml [-ScanResults] <PSCustomObject>
    [[-MaxTopFiles] <int>]
    [[-MaxTopFolders] <int>]
    [[-ShowAllResults] <bool>]
    [[-FooterSuffix] <string>]
```

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| **ScanResults** | PSCustomObject | Yes | Output from `Get-FolderSizes`. Supports pipeline input. |
| **MaxTopFiles** | int | No | Max file rows per drive in Top Files table. Default: 50 (`Display.MaxTopFiles`). |
| **MaxTopFolders** | int | No | Max folder rows per drive in Top Folders table. Default: 25 (`Display.MaxTopFolders`). |
| **ShowAllResults** | bool | No | Include the full "All Results by Size" table. Default: `$true`. |
| **FooterSuffix** | string | No | Text appended after the UltraTree version in the footer (e.g. `", Script v1.4.2"`). |

## Examples

### Basic Usage

```powershell
$results = Get-FolderSizes -DriveLetter C -Top 200
$html = ConvertTo-NinjaOneHtml -ScanResults $results
```

### Pipeline Usage

```powershell
$html = Get-FolderSizes -AllDrives -Top 200 | ConvertTo-NinjaOneHtml
```

### Full Scan with Duplicates

```powershell
$html = Get-FolderSizes -AllDrives -FindDuplicates -Top 200 | ConvertTo-NinjaOneHtml
```

### Compact report (no full results table)

```powershell
$html = Get-FolderSizes -DriveLetter C -Top 200 |
    ConvertTo-NinjaOneHtml -ShowAllResults:$false -FooterSuffix ", Script v1.4.2"
```

### Save to File

```powershell
Get-FolderSizes -AllDrives -FindDuplicates -Top 200 |
    ConvertTo-NinjaOneHtml |
    Out-File "DiskReport.html" -Encoding UTF8
```

### Set NinjaOne Custom Field

```powershell
$results = Get-FolderSizes -AllDrives -FindDuplicates -Top 200
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
- **Top Files** - Ranked table of largest files (path, size, modified)
- **Top Folders** - Ranked table of largest folders
- **Cleanup** and **File Types** - Side-by-side in a two-column row
- **Cleanup Suggestions** - Categorized cleanup opportunities

### Duplicates Section

If `-FindDuplicates` was used:

- **Duplicate Groups** - Files with identical content
- **Wasted Space** - Space that could be recovered
- **File Paths** - Locations of duplicate files

### Results Table

When `-ShowAllResults` is true (default):

- Full sortable table of all items
- Color-coded by size severity
- Shows path, size, type, and last modified date

### Footer

- Scan timestamp
- UltraTree module version (from the loaded module manifest)
- Optional suffix from `-FooterSuffix`

## HTML Features

The generated HTML includes:

- **Bootstrap 5** - Responsive grid and components
- **Font Awesome 6** - Icons for status and categories
- **Inline badge colors** - Readable in NinjaOne WYSIWYG (wrapper CSS is stripped)
- **Dark/Light support** - Uses `stat-desc` for muted text; explicit dark text on info cards
- **Mobile-friendly** - Responsive design

## Customization

The HTML output is controlled by the module's configuration. See [Configuration](../configuration.md) for options like:

- `MaxTopFiles` - Top files in ranked table (default 50)
- `MaxTopFolders` - Top folders in ranked table (default 25)
- `MaxFileTypes` - Number of file types shown
- `MaxResults` - Items in results table
- `MaxDuplicateGroups` - Duplicate groups displayed

### `-Top` interaction

`Get-FolderSizes` returns `Items` as one mixed file/folder list truncated by `-Top` (default 40). Folders usually dominate that list. Use a larger `-Top` (for example `-Top 200`) when you need the Top Files table to fill out — especially with `-AllDrives`.

## Notes

- HTML assumes Bootstrap 5 and Font Awesome 6 are available in the NinjaOne WYSIWYG host page
- For offline viewing, wrap with `New-HtmlWrapper` (loads CDN assets)
- Best viewed in modern browsers or NinjaOne WYSIWYG fields
