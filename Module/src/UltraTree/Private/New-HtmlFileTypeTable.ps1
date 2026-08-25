function New-HtmlFileTypeTable {
    <#
    .SYNOPSIS
        Creates a table showing file types by total size.
    .DESCRIPTION
        Generates HTML for a file type statistics table with color coding.
    .PARAMETER FileTypes
        Array of file type objects with Extension, FileCount, and TotalSize properties.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'None')]
    param ([array]$FileTypes)

    if (-not $PSCmdlet.ShouldProcess('file types', 'Generate HTML file type table')) { return '' }

    $colors = @("#FF6B6B", "#4ECDC4", "#45B7D1", "#96CEB4", "#FFEAA7", "#DDA0DD", "#98D8C8", "#F7DC6F", "#BB8FCE", "#85C1E9", "#F8B500", "#00CED1", "#FF7F50", "#9370DB", "#20B2AA")

    $rows = for ($i = 0; $i -lt $FileTypes.Count; $i++) {
        $ft = $FileTypes[$i]
        $color = $colors[$i % $colors.Count]
        $sizeText = Format-ByteSize -Bytes $ft.TotalSize
        @"
    <tr>
      <td><span style="display: inline-block; width: 12px; height: 12px; background-color: $color; border-radius: 2px; margin-right: 8px;"></span>$($ft.Extension)</td>
      <td style="text-align: right;">$($ft.FileCount.ToString("N0"))</td>
      <td style="text-align: right;">$sizeText</td>
    </tr>
"@
    }

    $icon = Get-ThemeIcon -IconName "FileAlt"
    $body = @"
    <table style="width: 100%;">
      <thead>
        <tr>
          <th>Extension</th>
          <th style="text-align: right;">Count</th>
          <th style="text-align: right;">Total Size</th>
        </tr>
      </thead>
      <tbody>
$($rows -join "`n")
      </tbody>
    </table>
"@

    New-HtmlCard -Title "File Types by Size" -Icon $icon -Body $body -BodyStyle "padding: 0;" -CardStyle "margin-bottom: 16px;"
}
