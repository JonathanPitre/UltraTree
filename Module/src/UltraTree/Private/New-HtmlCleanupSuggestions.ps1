function New-HtmlCleanupSuggestions {
    <#
    .SYNOPSIS
        Creates cleanup suggestions display with categorization.
    .DESCRIPTION
        Generates HTML for cleanup opportunities with icons and size information.
    .PARAMETER Suggestions
        Array of suggestion objects with Category, Size, and optionally Description properties.
    .PARAMETER Compact
        Switch to use compact list format instead of full cards.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'None')]
    param (
        [array]$Suggestions,
        [switch]$Compact
    )

    if ($null -eq $Suggestions -or $Suggestions.Count -eq 0) { return '' }
    if (-not $PSCmdlet.ShouldProcess('cleanup suggestions', 'Generate HTML cleanup suggestions')) { return '' }

    $broomIcon = Get-ThemeIcon -IconName 'Broom'

    if ($Compact) {
        $items = foreach ($sug in $Suggestions) {
            $sizeText = Format-ByteSize -Bytes $sug.Size
            $catInfo = Get-CleanupCategoryInfo -CategoryName $sug.Category
            $category = $script:CleanupCategories | Where-Object { $_.Name -eq $sug.Category }
            $displayName = if ($category) { $category.DisplayName } else { $sug.Path }

            "<li style=`"margin-bottom: 8px;`"><i class=`"$($catInfo.Icon)`" style=`"color: $($catInfo.Color); margin-right: 8px;`"></i><strong>$displayName</strong><br><span class=`"stat-desc`" style=`"font-size: 0.9em;`">$sizeText</span></li>"
        }

        $body = @"
    <ul style="list-style: none; padding: 0; margin: 0;">
      $($items -join "`n      ")
    </ul>
"@
        New-HtmlCard -Title 'Cleanup' -Icon $broomIcon -Body $body -BodyStyle 'padding: 12px;'
    } else {
        $cards = foreach ($sug in $Suggestions) {
            $sizeText = Format-ByteSize -Bytes $sug.Size
            $category = $script:CleanupCategories | Where-Object { $_.Name -eq $sug.Category }
            $displayName = if ($category) { $category.DisplayName } else { $sug.Path }
            $description = if ($category) { $category.Description } else { $sug.Description }
            $severity = if ($category) { $category.Severity } else { 'Info' }

            New-HtmlInfoCard -Title "$displayName`: $sizeText" -Description $description -Type $severity
        }

        $body = $cards -join "`n    "
        New-HtmlCard -Title 'Cleanup Suggestions' -Icon $broomIcon -Body $body -CardStyle 'margin-bottom: 16px;'
    }
}
