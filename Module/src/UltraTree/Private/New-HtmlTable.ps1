function New-HtmlTable {
    <#
    .SYNOPSIS
        Creates a table of files/folders with size and type information.
    .DESCRIPTION
        Generates HTML for a sortable results table.
    .PARAMETER Items
        Array of item objects with Path, Size, SizeBytes, IsDirectory, and LastModified properties.
    .PARAMETER Title
        The table title.
    .PARAMETER Icon
        Optional FontAwesome icon class for the title.
    #>
    param (
        [array]$Items,
        [string]$Title = "Results",
        [string]$Icon = ""
    )

    if (-not $Icon) { $Icon = Get-ThemeIcon -IconName "Folder" }
    $folderIcon = Get-ThemeIcon -IconName "Folder"
    $fileIcon = Get-ThemeIcon -IconName "File"
    $warningColor = Get-ThemeColor -Severity "Warning"
    $infoColor = Get-ThemeColor -Severity "Info"

    $rows = foreach ($item in $Items) {
        $rowClass = Get-SizeCategory -SizeBytes $item.SizeBytes
        $typeIcon = if ($item.IsDirectory) { "<i class=`"$folderIcon`" style=`"color: $warningColor;`"></i>" } else { "<i class=`"$fileIcon`" style=`"color: $infoColor;`"></i>" }
        $lastMod = if ($item.LastModified) { $item.LastModified } else { "" }
        @"
    <tr class="$rowClass">
      <td>$typeIcon $($item.Path)</td>
      <td style="text-align: right; white-space: nowrap;">$($item.Size)</td>
      <td style="text-align: right; white-space: nowrap;"><span class="stat-desc">$lastMod</span></td>
    </tr>
"@
    }

    $body = @"
    <table style="width: 100%;">
      <thead>
        <tr>
          <th>Path</th>
          <th style="text-align: right;">Size</th>
          <th style="text-align: right;">Modified</th>
        </tr>
      </thead>
      <tbody>
$($rows -join "`n")
      </tbody>
    </table>
"@

    New-HtmlCard -Title $Title -Icon $Icon -Body $body -BodyStyle "padding: 0;" -CardStyle "margin-bottom: 16px;"
}
