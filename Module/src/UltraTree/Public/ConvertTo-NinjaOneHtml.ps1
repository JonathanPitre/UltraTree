function ConvertTo-NinjaOneHtml {
    <#
    .SYNOPSIS
        Converts scan results to NinjaOne-compatible HTML report.
    .DESCRIPTION
        Transforms the output from Get-FolderSizes into a formatted HTML report
        suitable for display in NinjaOne WYSIWYG custom fields. Includes statistics
        cards, charts, tables, and cleanup recommendations.
    .PARAMETER ScanResults
        The PSCustomObject output from Get-FolderSizes containing Items, FileTypes,
        CleanupSuggestions, Duplicates, LinkedFiles, DriveInfo, and statistics.
    .OUTPUTS
        String containing HTML markup for the report.
    .EXAMPLE
        $results = Get-FolderSizes -AllDrives -FindDuplicates
        $html = ConvertTo-NinjaOneHtml -ScanResults $results
        $html | Ninja-Property-Set-Piped treesize
    .EXAMPLE
        $results = Get-FolderSizes -DriveLetter C
        $html = ConvertTo-NinjaOneHtml -ScanResults $results
        $wrappedHtml = New-HtmlWrapper -Content $html -Title "Disk Report"
        $wrappedHtml | Out-File "report.html"
    .NOTES
        The output HTML assumes Bootstrap 5, Font Awesome 6, and Charts.css are
        available. For standalone viewing, wrap with New-HtmlWrapper.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSCustomObject]$ScanResults
    )

    process {
        $html = [System.Text.StringBuilder]::new()
        $cfg = $script:Config

        # === TOTAL SUMMARY STAT CARDS ===
        $driveCount = $ScanResults.DriveInfo.Count
        $totalScanned = "{0:N0}" -f ($ScanResults.TotalFiles + $ScanResults.TotalFolders)
        $duplicateWastedText = if ($ScanResults.TotalDuplicateWasted -gt 0) { Format-ByteSize -Bytes $ScanResults.TotalDuplicateWasted } else { "0 B" }
        $cleanupPotential = ($ScanResults.CleanupSuggestions | Measure-Object -Property Size -Sum).Sum
        $cleanupPotentialText = if ($cleanupPotential -gt 0) { Format-ByteSize -Bytes $cleanupPotential } else { "0 B" }

        $primaryColor = Get-ThemeColor -Severity "Primary"
        $warningColor = Get-ThemeColor -Severity "Warning"
        $infoColor = Get-ThemeColor -Severity "Info"
        $driveIcon = Get-ThemeIcon -IconName "Drive"
        $searchIcon = Get-ThemeIcon -IconName "Search"
        $copyIcon = Get-ThemeIcon -IconName "Copy"
        $broomIcon = Get-ThemeIcon -IconName "Broom"

        [void]$html.AppendLine('<div class="row g-3" style="margin-bottom: 16px;">')
        [void]$html.AppendLine('<div class="col-xl-3 col-lg-3 col-md-6 col-sm-6">')
        [void]$html.AppendLine((New-HtmlStatCard -Value $driveCount -Description "Drives Scanned" -Color $primaryColor -Icon $driveIcon))
        [void]$html.AppendLine('</div>')
        [void]$html.AppendLine('<div class="col-xl-3 col-lg-3 col-md-6 col-sm-6">')
        [void]$html.AppendLine((New-HtmlStatCard -Value $totalScanned -Description "Items (All Drives)" -Color $primaryColor -Icon $searchIcon))
        [void]$html.AppendLine('</div>')
        [void]$html.AppendLine('<div class="col-xl-3 col-lg-3 col-md-6 col-sm-6">')
        [void]$html.AppendLine((New-HtmlStatCard -Value $duplicateWastedText -Description "Duplicates (All Drives)" -Color $warningColor -Icon $copyIcon))
        [void]$html.AppendLine('</div>')
        [void]$html.AppendLine('<div class="col-xl-3 col-lg-3 col-md-6 col-sm-6">')
        [void]$html.AppendLine((New-HtmlStatCard -Value $cleanupPotentialText -Description "Cleanup Potential" -Color $infoColor -Icon $broomIcon))
        [void]$html.AppendLine('</div>')
        [void]$html.AppendLine('</div>')

        # === ERROR WARNING ===
        if ($ScanResults.TotalErrorCount -gt $cfg.Thresholds.ErrorWarning) {
            [void]$html.AppendLine((New-HtmlInfoCard -Title "Access Errors" -Description "$($ScanResults.TotalErrorCount) files could not be read (access denied or in use)" -Type "Warning"))
        }

        # === PER-DRIVE SECTIONS ===
        foreach ($drive in $ScanResults.DriveInfo) {
            $usedText = Format-ByteSize -Bytes $drive.UsedSpace
            $freeText = Format-ByteSize -Bytes $drive.FreeSpace
            $healthTag = Get-DiskHealthTag -UsedPercent $drive.UsedPercent
            $usedColor = Get-DiskUsedColor -UsedPercent $drive.UsedPercent
            $successColor = Get-ThemeColor -Severity "Success"
            $freeColor = Get-ThemeColor -Severity "Free"

            $driveCleanup = @($ScanResults.CleanupSuggestions | Where-Object { $_.Drive -eq $drive.Drive })
            $driveFolders = @($ScanResults.Items | Where-Object { $_.Drive -eq $drive.Drive -and $_.IsDirectory } | Select-Object -First $cfg.Display.MaxTopFolders)
            $driveFileTypes = @($ScanResults.FileTypes | Where-Object { $_.Drive -eq $drive.Drive } | Select-Object -First $cfg.Display.MaxFileTypes)

            # Row 1: Stat cards
            [void]$html.AppendLine('<div class="row g-3" style="margin-bottom: 8px;">')

            [void]$html.AppendLine('<div class="col-xl-3 col-lg-3 col-md-6 col-sm-6">')
            [void]$html.AppendLine((New-HtmlStatCard -Value "$($drive.Drive)" -Description "Drive" -Color $primaryColor -Icon $driveIcon))
            [void]$html.AppendLine('</div>')

            [void]$html.AppendLine('<div class="col-xl-3 col-lg-3 col-md-6 col-sm-6">')
            [void]$html.AppendLine((New-HtmlStatCard -Value $usedText -Description "Used ($($drive.UsedPercent)%)" -Color $usedColor))
            [void]$html.AppendLine('</div>')

            [void]$html.AppendLine('<div class="col-xl-3 col-lg-3 col-md-6 col-sm-6">')
            [void]$html.AppendLine((New-HtmlStatCard -Value $freeText -Description "Free" -Color $successColor))
            [void]$html.AppendLine('</div>')

            [void]$html.AppendLine('<div class="col-xl-3 col-lg-3 col-md-6 col-sm-6">')
            [void]$html.AppendLine("<div class=`"stat-card`"><div class=`"stat-value`">$(New-HtmlTag -Text $healthTag.Text -Type $healthTag.Class)</div><div class=`"stat-desc`">Status</div></div>")
            [void]$html.AppendLine('</div>')

            # Row 2: Line chart
            [void]$html.AppendLine('<div class="col-12">')
            $segments = @(
                @{ Label = "Used"; Value = $drive.UsedSpace; Color = $usedColor }
                @{ Label = "Free"; Value = $drive.FreeSpace; Color = $freeColor }
            )
            [void]$html.AppendLine((New-HtmlLineChart -Segments $segments -Total $drive.TotalSize))
            [void]$html.AppendLine('</div>')

            [void]$html.AppendLine('</div>')

            # Row 3: Three-column layout
            [void]$html.AppendLine('<div class="row g-3" style="margin-bottom: 16px;">')

            [void]$html.AppendLine('<div class="col-xl-4 col-lg-4 col-md-12 d-flex">')
            if ($driveCleanup.Count -gt 0) {
                [void]$html.AppendLine((New-HtmlCleanupSuggestions -Suggestions $driveCleanup -Compact))
            }
            else {
                $checkIcon = Get-ThemeIcon -IconName "CheckCircle"
                [void]$html.AppendLine("<div class=`"card flex-grow-1`"><div class=`"card-title-box`"><div class=`"card-title`"><i class=`"$checkIcon`" style=`"color: $successColor;`"></i>&nbsp;&nbsp;No Cleanup Needed</div></div><div class=`"card-body`"><p style=`"color: #666;`">No significant cleanup opportunities found.</p></div></div>")
            }
            [void]$html.AppendLine('</div>')

            [void]$html.AppendLine('<div class="col-xl-4 col-lg-4 col-md-12 d-flex">')
            if ($driveFolders.Count -gt 0) {
                $chartItems = $driveFolders | ForEach-Object {
                    $label = Split-Path $_.Path -Leaf
                    if ([string]::IsNullOrEmpty($label)) { $label = $_.Path }
                    @{ Label = $label; Value = $_.SizeBytes }
                }
                [void]$html.AppendLine((New-HtmlBarChart -Items $chartItems -Title "Top Folders"))
            }
            [void]$html.AppendLine('</div>')

            [void]$html.AppendLine('<div class="col-xl-4 col-lg-4 col-md-12 d-flex">')
            if ($driveFileTypes.Count -gt 0) {
                [void]$html.AppendLine((New-HtmlFileTypeTable -FileTypes $driveFileTypes))
            }
            [void]$html.AppendLine('</div>')

            [void]$html.AppendLine('</div>')
        }

        # === DUPLICATES TABLE ===
        if ($ScanResults.Duplicates.Count -gt 0) {
            [void]$html.AppendLine((New-HtmlDuplicatesTable -DuplicateGroups $ScanResults.Duplicates -TotalWasted $ScanResults.TotalDuplicateWasted))
        }

        if ($ScanResults.LinkedFiles.Count -gt 0) {
            [void]$html.AppendLine((New-HtmlLinkedFilesTable -LinkedGroups $ScanResults.LinkedFiles))
        }

        # === FULL RESULTS TABLE ===
        $listIcon = Get-ThemeIcon -IconName "List"
        [void]$html.AppendLine((New-HtmlTable -Items $ScanResults.Items -Title "All Results by Size" -Icon $listIcon))

        # === FOOTER ===
        $scanTime = Get-Date -Format "yyyy-MM-dd HH:mm"
        $mutedColor = Get-ThemeColor -Severity "Muted"
        [void]$html.AppendLine("<p style=`"font-size: 0.7em; color: $mutedColor; text-align: right; margin-top: 16px;`">TreeSize v$($cfg.Version) | Scanned: $scanTime</p>")

        return $html.ToString()
    }
}
