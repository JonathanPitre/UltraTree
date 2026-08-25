# UltraTree Module Configuration
# Centralized configuration with nested theme/thresholds

$script:Config = @{
    Version        = "1.0.2"

    # Size thresholds
    Thresholds     = @{
        CleanupMin    = 100MB     # Minimum size for cleanup suggestions
        DuplicateMin  = 10MB      # Minimum file size for duplicate detection
        LargeFile     = 100MB     # Files above this shown in results
        DangerWasted  = 500MB     # Wasted space threshold for "danger" severity
        WarningWasted = 100MB     # Wasted space threshold for "warning" severity
        ErrorWarning  = 50        # Show warning if more than X files couldn't be read
    }

    # Display limits
    Display        = @{
        MaxDuplicateGroups = 20     # Max duplicate groups to display
        MaxPathsPerGroup   = 5      # Max paths shown per duplicate group
        MaxTopFolders      = 25     # Top folders in ranked table
        MaxTopFiles        = 50     # Top files in ranked table
        MaxFileTypes       = 10     # Top file types to show
        MaxResults         = 40     # Max items in results table
        MaxPathLength      = 50     # Truncate paths longer than this
        MaxLabelLength     = 12     # Truncate chart labels longer than this
    }

    # Disk health thresholds (percent)
    DiskHealth     = @{
        CriticalPercent = 90
        WarningPercent  = 75
    }

    # Size category thresholds for row styling
    SizeCategories = @{
        Danger  = 100GB
        Warning = 50GB
        Other   = 10GB
        Unknown = 1GB
    }

    # Theme: centralized colors and icons
    Theme          = @{
        Colors = @{
            Danger   = "#d9534f"
            Warning  = "#f0ad4e"
            Info     = "#5bc0de"
            Success  = "#4ECDC4"
            Primary  = "#337ab7"
            Muted    = "#999999"
            Critical = "#FF6B6B"
            Free     = "#95a5a6"
        }
        Icons  = @{
            # Status icons
            Info        = "fa-solid fa-circle-info"
            Warning     = "fa-solid fa-triangle-exclamation"
            Error       = "fa-solid fa-circle-exclamation"
            Success     = "fa-solid fa-circle-check"
            # Object icons
            Folder      = "fas fa-folder"
            File        = "fas fa-file"
            FileAlt     = "fas fa-file-alt"
            Drive       = "fas fa-hdd"
            List        = "fas fa-list"
            Chart       = "fas fa-chart-bar"
            Copy        = "fas fa-copy"
            Broom       = "fas fa-broom"
            Search      = "fas fa-search"
            CheckCircle = "fas fa-check-circle"
            # Category icons
            Trash       = "fas fa-trash"
            Clock       = "fas fa-clock"
            Database    = "fas fa-database"
            Code        = "fas fa-code"
            CodeBranch  = "fas fa-code-branch"
            Download    = "fas fa-download"
            Cog         = "fas fa-cog"
        }
    }
}

# Data-driven cleanup categories
$script:CleanupCategories = @(
    @{
        Name        = "recycleBin"
        DisplayName = "Recycle Bin"
        Patterns    = @('$Recycle.Bin', '\RECYCLER')
        Icon        = "Trash"
        Severity    = "Warning"
        Description = "Empty recycle bin to reclaim space"
    }
    @{
        Name        = "temp"
        DisplayName = "Temp Files"
        Patterns    = @('\Temp\', '\tmp\', '\AppData\Local\Temp')
        Icon        = "Clock"
        Severity    = "Info"
        Description = "Temporary files that can be safely deleted"
    }
    @{
        Name        = "cache"
        DisplayName = "Cache Files"
        Patterns    = @('\Cache\', '\cache\', '\.cache\', '\CachedData')
        Icon        = "Database"
        Severity    = "Info"
        Description = "Application cache files"
    }
    @{
        Name        = "nodeModules"
        DisplayName = "node_modules"
        Patterns    = @('\node_modules\')
        Icon        = "Code"
        Severity    = "Info"
        Description = "Node.js dependencies - run 'npm install' to restore"
    }
    @{
        Name        = "git"
        DisplayName = ".git folders"
        Patterns    = @('\.git\')
        Icon        = "CodeBranch"
        Severity    = "Info"
        Description = "Git repository data"
    }
    @{
        Name        = "downloads"
        DisplayName = "Downloads"
        Patterns    = @('\Downloads\')
        Icon        = "Download"
        Severity    = "Warning"
        Description = "Review and clean old downloads"
    }
    @{
        Name        = "installer"
        DisplayName = "Windows Installer"
        Patterns    = @('\Windows\Installer\')
        Icon        = "Cog"
        Severity    = "Danger"
        Description = "Windows Installer cache (use Disk Cleanup)"
    }
)

# Error tracking collection
$script:ErrorLog = [System.Collections.Generic.List[PSCustomObject]]::new()
