# UltraTree

**Lightning-Fast Disk Space Analysis for Windows**

UltraTree is a PowerShell module that provides ultra-fast disk space analysis by directly reading the NTFS Master File Table (MFT). It's designed for system administrators and MSPs who need quick insights into disk usage, duplicate files, and cleanup opportunities—with beautiful HTML reports optimized for NinjaOne RMM.

## Why UltraTree?

| Feature | UltraTree | TreeSize | WinDirStat |
|---------|-----------|----------|------------|
| Speed | **10-100x faster** (MFT) | Slow (recursive) | Slow (recursive) |
| Duplicate Detection | 3-stage xxHash64 | Limited | No |
| RMM Integration | NinjaOne ready | No | No |
| Cleanup Suggestions | Automatic | Manual | No |
| PowerShell Native | Yes | No | No |

## Features

- **Ultra-fast scanning** using USN Journal / MFT enumeration
- **Smart 3-stage duplicate detection** (Size → xxHash64 → Full Compare)
- **Intelligent cleanup suggestions** (temp files, logs, cache, node_modules)
- **Beautiful HTML reports** with interactive charts
- **NinjaOne RMM integration** with WYSIWYG custom field support
- **Multi-drive scanning** with exclusion support
- **Dynamic memory management** for massive filesystems
- **Configurable thresholds** and display limits

## Quick Example

```powershell
# Scan all drives with duplicate detection
$results = Get-FolderSizes -AllDrives -FindDuplicates

# Generate HTML report
$html = $results | ConvertTo-NinjaOneHtml

# For NinjaOne - set custom field
$html | Ninja-Property-Set-Piped treesize
```

## Getting Started

- [Installation](installation.md) - Install from PowerShell Gallery or manually
- [Get-FolderSizes](functions/get-foldersizes.md) - Main scanning function
- [ConvertTo-NinjaOneHtml](functions/convertto-ninjaonehtml.md) - HTML report generation
- [NinjaOne Integration](ninjaone-integration.md) - Complete RMM setup guide
- [Configuration](configuration.md) - Thresholds and display options
- [Refactor Review Plan](refactor-review-plan.md) - Architecture and performance review with phased refactor roadmap

## Requirements

- PowerShell 5.1 or later
- Windows (NTFS drives only)
- Administrator privileges for full access
- .NET Framework 4.5+ (included with Windows 10/11)

## Version

Current version: **1.0.0**

## Author

Jan Scholte

## License

MIT License
