function New-HtmlLinkedFilesTable {
    <#
    .SYNOPSIS
        Creates a table displaying hardlinked file groups.
    .DESCRIPTION
        Generates HTML for NTFS hardlinks that share the same file record and
        therefore do not count as reclaimable duplicate waste.
    .PARAMETER LinkedGroups
        Array of linked file group objects with FileSize and Files properties.
    #>
    param (
        [array]$LinkedGroups
    )

    if ($null -eq $LinkedGroups -or $LinkedGroups.Count -eq 0) { return "" }

    $cfg = $script:Config.Display
    $maxGroups = $cfg.MaxDuplicateGroups
    $maxPaths = $cfg.MaxPathsPerGroup
    $maxPathLen = $cfg.MaxPathLength
    $linkIcon = Get-ThemeIcon -IconName "Link"
    $infoColor = Get-ThemeColor -Severity "Info"
    $mutedColor = Get-ThemeColor -Severity "Muted"

    $rows = foreach ($group in $LinkedGroups | Select-Object -First $maxGroups) {
        $sizeText = Format-ByteSize -Bytes $group.FileSize
        $fileCount = $group.Files.Count
        $filesToShow = $group.Files | Select-Object -First $maxPaths
        $remaining = $group.Files.Count - $maxPaths
        $fileName = Split-Path $group.Files[0] -Leaf

        $pathList = ($filesToShow | ForEach-Object {
                $parentPath = Split-Path $_ -Parent
                if ($parentPath.Length -gt $maxPathLen) { "..." + $parentPath.Substring($parentPath.Length - ($maxPathLen - 3)) } else { $parentPath }
            }) -join "<br>"

        if ($remaining -gt 0) {
            $pathList += "<br><span style=`"color: $mutedColor;`">+$remaining more</span>"
        }

        @"
    <tr style="border-left: 3px solid $infoColor;">
      <td style="padding: 1px 3px; font-size: 0.7em; white-space: nowrap; vertical-align: top;"><strong>$fileName</strong><br><span style="color: #888;">$fileCount &times; $sizeText</span></td>
      <td style="padding: 1px 3px; font-size: 0.65em; color: #666; line-height: 1.0;">$pathList</td>
      <td style="padding: 1px 3px; font-size: 0.7em; text-align: right; vertical-align: top; color: $mutedColor;">Shared file record</td>
    </tr>
"@
    }

    @"
<h4 style="margin: 16px 0 8px 0;"><i class="$linkIcon"></i> Linked Files <span style="font-weight: normal; font-size: 0.85em; color: #666;">(NTFS hardlinks, not counted as duplicate waste)</span></h4>
<table style="width: 100%; border-collapse: collapse; border-spacing: 0;">
  <thead>
    <tr>
      <th style="padding: 1px 3px; font-size: 0.7em; text-align: left;">File</th>
      <th style="padding: 1px 3px; font-size: 0.7em; text-align: left;">Locations</th>
      <th style="padding: 1px 3px; font-size: 0.7em; text-align: right;">Notes</th>
    </tr>
  </thead>
  <tbody>
$($rows -join "`n")
  </tbody>
</table>
"@
}
