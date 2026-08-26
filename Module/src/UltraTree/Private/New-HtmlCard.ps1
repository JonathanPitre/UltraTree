function New-HtmlCard {
    <#
    .SYNOPSIS
        Base card template - other card functions should use this.
    .DESCRIPTION
        Creates a Bootstrap-style card with title, icon, and body content.
    .PARAMETER Title
        The card title text.
    .PARAMETER Icon
        Optional FontAwesome icon class.
    .PARAMETER Body
        The HTML content for the card body.
    .PARAMETER BodyStyle
        Optional inline CSS for the body element.
    .PARAMETER CardStyle
        Optional inline CSS for the card element.
    #>
    [CmdletBinding()]
    param (
        [string]$Title,
        [string]$Icon = "",
        [string]$Body,
        [string]$BodyStyle = "",
        [string]$CardStyle = ""
    )

    $iconHtml = if ($Icon) { "<i class=`"$Icon`"></i>&nbsp;&nbsp;" } else { "" }
    $bodyStyleAttr = if ($BodyStyle) { " style=`"$BodyStyle`"" } else { "" }
    $cardStyleAttr = if ($CardStyle) { " style=`"$CardStyle`"" } else { "" }

    @"
<div class="card flex-grow-1"$cardStyleAttr>
  <div class="card-title-box">
    <div class="card-title">$iconHtml$Title</div>
  </div>
  <div class="card-body"$bodyStyleAttr>$Body</div>
</div>
"@
}
