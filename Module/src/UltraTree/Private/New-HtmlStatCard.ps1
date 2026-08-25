function New-HtmlStatCard {
    <#
    .SYNOPSIS
        Creates a stat card with value, description, and optional icon.
    .DESCRIPTION
        Generates HTML for a statistics display card.
    .PARAMETER Value
        The main value to display.
    .PARAMETER Description
        The description text below the value.
    .PARAMETER Color
        Optional hex color for the value text.
    .PARAMETER Icon
        Optional FontAwesome icon class.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'None')]
    param (
        [string]$Value,
        [string]$Description,
        [string]$Color = "",
        [string]$Icon = ""
    )

    if (-not $PSCmdlet.ShouldProcess($Description, 'Generate HTML stat card')) { return '' }

    if (-not $Color) { $Color = Get-ThemeColor -Severity "Primary" }
    $iconHtml = if ($Icon) { "<i class=`"$Icon`" style=`"margin-right: 8px;`"></i>" } else { "" }

    @"
<div class="stat-card">
  <div class="stat-value" style="color: $Color;">$iconHtml$Value</div>
  <div class="stat-desc">$Description</div>
</div>
"@
}
