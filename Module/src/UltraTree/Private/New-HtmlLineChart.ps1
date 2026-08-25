function New-HtmlLineChart {
    <#
    .SYNOPSIS
        Creates a line/segment chart showing disk usage.
    .DESCRIPTION
        Generates HTML for a horizontal segmented chart (like a stacked bar).
    .PARAMETER Segments
        Array of segment objects with Label, Value, and Color properties.
    .PARAMETER Total
        The total value for calculating percentages.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'None')]
    param (
        [array]$Segments,
        [long]$Total
    )

    if (-not $PSCmdlet.ShouldProcess('disk usage chart', 'Generate HTML line chart')) { return '' }

    if ($Total -eq 0) { $Total = 1 }

    $bars = foreach ($seg in $Segments) {
        $width = [math]::Round(($seg.Value / $Total) * 100, 2)
        "<div style=`"width: $width%; background-color: $($seg.Color);`"></div>"
    }

    $legendItems = foreach ($seg in $Segments) {
        $sizeText = Format-ByteSize -Bytes $seg.Value
        "<li><span class=`"chart-key`" style=`"background-color: $($seg.Color);`"></span><span>$($seg.Label) ($sizeText)</span></li>"
    }

    @"
<div class="p-3 linechart">
  $($bars -join "`n  ")
</div>
<ul class="unstyled p-3" style="display: flex; justify-content: space-between; flex-wrap: wrap;">
  $($legendItems -join "`n  ")
</ul>
"@
}
