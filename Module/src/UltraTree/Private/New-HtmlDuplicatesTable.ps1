function New-HtmlDuplicatesTable {
    <#
    .SYNOPSIS
        Creates a table displaying duplicate file groups.
    .DESCRIPTION
        Generates HTML for duplicate files with wasted space information.
    .PARAMETER DuplicateGroups
        Array of duplicate group objects with FileSize, WastedSpace, and Files properties.
    .PARAMETER TotalWasted
        Total wasted space across all duplicate groups.
    #>
    param (
        [array]$DuplicateGroups,
        [long]$TotalWasted
    )

    if ($null -eq $DuplicateGroups -or $DuplicateGroups.Count -eq 0) { return "" }

    $totalWastedText = Format-ByteSize -Bytes $TotalWasted
    $cfg = $script:Config.Display
    $maxGroups = $cfg.MaxDuplicateGroups
    $maxPaths = $cfg.MaxPathsPerGroup
    $maxPathLen = $cfg.MaxPathLength
    $copyIcon = Get-ThemeIcon -IconName "Copy"

    $rows = foreach ($group in $DuplicateGroups | Select-Object -First $maxGroups) {
        $sizeText = Format-ByteSize -Bytes $group.FileSize
        $wastedText = Format-ByteSize -Bytes $group.WastedSpace
        $fileCount = $group.Files.Count
        $filesToShow = $group.Files | Select-Object -First $maxPaths
        $remaining = $group.Files.Count - $maxPaths

        $fileName = Split-Path $group.Files[0] -Leaf

        $pathList = ($filesToShow | ForEach-Object {
                $parentPath = Split-Path $_ -Parent
                if ($parentPath.Length -gt $maxPathLen) { "..." + $parentPath.Substring($parentPath.Length - ($maxPathLen - 3)) } else { $parentPath }
            }) -join "<br>"

        if ($remaining -gt 0) {
            $pathList += "<br><span class=`"stat-desc`">+$remaining more</span>"
        }

        $severity = Get-WastedSpaceSeverity -WastedBytes $group.WastedSpace
        $rowClass = $severity.ToLower()
        $borderColor = Get-ThemeColor -Severity $severity

        @"
    <tr class="$rowClass" style="border-left: 3px solid $borderColor;">
      <td style="padding: 1px 3px; font-size: 0.7em; white-space: nowrap; vertical-align: top;"><strong>$fileName</strong><br><span class="stat-desc">$fileCount &times; $sizeText</span></td>
      <td class="stat-desc" style="padding: 1px 3px; font-size: 0.65em; line-height: 1.0;">$pathList</td>
      <td style="padding: 1px 3px; font-size: 0.7em; text-align: right; vertical-align: top;">$wastedText</td>
    </tr>
"@
    }

    @"
<h4 style="margin: 16px 0 8px 0;"><i class="$copyIcon"></i> Duplicate Files <span class="stat-desc" style="font-weight: normal; font-size: 0.85em;">(Wasted: $totalWastedText)</span></h4>
<table style="width: 100%; border-collapse: collapse; border-spacing: 0;">
  <thead>
    <tr>
      <th style="padding: 1px 3px; font-size: 0.7em; text-align: left;">File</th>
      <th style="padding: 1px 3px; font-size: 0.7em; text-align: left;">Locations</th>
      <th style="padding: 1px 3px; font-size: 0.7em; text-align: right;">Wasted</th>
    </tr>
  </thead>
  <tbody>
$($rows -join "`n")
  </tbody>
</table>
"@
}
