function New-HtmlInfoCard {
    <#
    .SYNOPSIS
        Creates an info/alert card with icon and description.
    .DESCRIPTION
        Generates HTML for an information or alert card with appropriate styling.
    .PARAMETER Title
        The card title text.
    .PARAMETER Description
        The description text.
    .PARAMETER Type
        The card type: Info, Warning, Danger, or Success.
    #>
    [CmdletBinding()]
    param (
        [string]$Title,
        [string]$Description,
        [ValidateSet("Info", "Warning", "Danger", "Success")]
        [string]$Type = "Info"
    )

    $style = Get-SeverityStyle -Severity $Type
    $classExtra = if ($Type -eq "Info") { "" } else { " $($Type.ToLower())" }

    # NinjaOne dark mode inherits light page text, but info-card.* keeps light-theme
    # tinted backgrounds in WYSIWYG fields — force readable text on those cards.
    $titleStyle = ' style="color: #333;"'
    $descStyle = ' style="color: #666;"'

    @"
<div class="info-card$classExtra">
  <i class="info-icon $($style.Icon)"></i>
  <div class="info-text">
    <div class="info-title"$titleStyle>$Title</div>
    <div class="info-description"$descStyle>$Description</div>
  </div>
</div>
"@
}
