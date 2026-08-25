function New-HtmlTag {
    <#
    .SYNOPSIS
        Creates an inline tag/badge element.
    .DESCRIPTION
        Generates HTML for a small tag or badge with optional type styling.
        Uses inline colors so NinjaOne WYSIWYG fields render badges without wrapper CSS.
    .PARAMETER Text
        The tag text content.
    .PARAMETER Type
        Optional type: empty string (default), "disabled", or "expired".
    #>
    param (
        [string]$Text,
        [ValidateSet("", "disabled", "expired")]
        [string]$Type = ""
    )

    $classExtra = if ($Type) { " $Type" } else { "" }
    $baseStyle = 'display: inline-block; padding: 2px 8px; border-radius: 4px; font-size: 0.75rem; font-weight: 600;'

    switch ($Type) {
        'expired' {
            $bgColor = Get-ThemeColor -Severity 'Danger'
        }
        'disabled' {
            $bgColor = Get-ThemeColor -Severity 'Warning'
        }
        default {
            $bgColor = Get-ThemeColor -Severity 'Success'
        }
    }

    $style = "$baseStyle background-color: $bgColor; color: #fff;"
    "<div class=`"tag$classExtra`" style=`"$style`">$Text</div>"
}
