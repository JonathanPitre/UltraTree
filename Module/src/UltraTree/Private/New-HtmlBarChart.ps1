function New-HtmlBarChart {
    <#
    .SYNOPSIS
        Creates a horizontal bar chart using Charts.css.
    .DESCRIPTION
        Generates HTML for a bar chart from an array of items with Label and Value properties.
    .PARAMETER Items
        Array of objects with Label and Value properties.
    .PARAMETER Title
        The chart title.
    #>
    [CmdletBinding()]
    param (
        [array]$Items,
        [string]$Title = "Top Items"
    )

    if ($null -eq $Items -or $Items.Count -eq 0) { return "" }

    # Find max value (can't use Measure-Object with hashtables)
    $maxValue = 0
    foreach ($item in $Items) {
        if ($item.Value -gt $maxValue) { $maxValue = $item.Value }
    }
    if ($maxValue -eq 0) { $maxValue = 1 }

    $maxLabel = $script:Config.Display.MaxLabelLength

    $rows = foreach ($item in $Items) {
        $percentage = [math]::Round(($item.Value / $maxValue), 4)
        $sizeText = Format-ByteSize -Bytes $item.Value
        $fullLabel = "$($item.Label)"
        $label = if ($fullLabel.Length -gt $maxLabel) { $fullLabel.Substring(0, $maxLabel - 2) + ".." } else { $fullLabel }
        @"
        <tr>
          <th scope="row" title="$fullLabel" style="font-size: 0.85em;">$label</th>
          <td style="--size: $percentage;"><span class="data">$sizeText</span></td>
        </tr>
"@
    }

    $icon = Get-ThemeIcon -IconName "Chart"
    $body = @"
    <table class="charts-css bar show-labels show-data-on-hover" style="height: 180px; width: 100%; --labels-size: 100px;">
      <tbody>
$($rows -join "`n")
      </tbody>
    </table>
"@

    New-HtmlCard -Title $Title -Icon $icon -Body $body -BodyStyle "padding: 8px;"
}
