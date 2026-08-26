function New-HtmlRankedStack {
    <#
    .SYNOPSIS
        Stacks ranked table cards full-width for NinjaOne WYSIWYG layout.
    .DESCRIPTION
        Wraps one or more HTML card fragments in a full-width Bootstrap row so
        Top Files and Top Folders tables stack vertically in NinjaOne WYSIWYG fields.
    .PARAMETER Sections
        HTML card fragments (e.g. from New-HtmlTable).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [string[]]$Sections
    )

    $parts = @($Sections | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($parts.Count -eq 0) { return '' }

    $cards = for ($i = 0; $i -lt $parts.Count; $i++) {
        $card = $parts[$i] -replace '<div class="card flex-grow-1"', '<div class="card"'
        $card = $card -replace 'style="margin-bottom: 16px;"', 'style="width: 100%; margin-bottom: 16px;"'
        if ($i -eq ($parts.Count - 1)) {
            $card = $card -replace 'margin-bottom: 16px;', ''
        }
        $card
    }

    @"
<div class="row g-3" style="margin-bottom: 16px;">
<div class="col-xl-12 col-lg-12 col-md-12 d-flex flex-column">
$($cards -join "`n")
</div>
</div>
"@
}
