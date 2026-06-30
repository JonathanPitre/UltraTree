BeforeAll {
    Set-Location -Path $PSScriptRoot
    $ModuleName = 'UltraTree'
    $PathToManifest = [System.IO.Path]::Combine('..', '..', '..', $ModuleName, "$ModuleName.psd1")
    Get-Module $ModuleName -ErrorAction SilentlyContinue | Remove-Module -Force
    Import-Module $PathToManifest -Force
}

Describe 'HTML Generation Functions' -Tag Unit {

    Context 'New-HtmlStatCard' {
        It 'Generates valid stat card HTML' {
            InModuleScope UltraTree {
                $html = New-HtmlStatCard -Value "100 GB" -Description "Test Desc" -Color "#ff0000"
                $html | Should -Match 'class="stat-card"'
                $html | Should -Match 'class="stat-value"'
                $html | Should -Match 'class="stat-desc"'
                $html | Should -Match '100 GB'
                $html | Should -Match 'Test Desc'
                $html | Should -Match '#ff0000'
            }
        }

        It 'Includes icon when provided' {
            InModuleScope UltraTree {
                $html = New-HtmlStatCard -Value "5" -Description "Items" -Icon "fas fa-folder"
                $html | Should -Match 'fas fa-folder'
            }
        }

        It 'Uses default color when not provided' {
            InModuleScope UltraTree {
                $html = New-HtmlStatCard -Value "5" -Description "Items"
                $html | Should -Match '#337ab7'
            }
        }
    }

    Context 'New-HtmlInfoCard' {
        It 'Generates info card with Warning type' {
            InModuleScope UltraTree {
                $html = New-HtmlInfoCard -Title "Test" -Description "Desc" -Type "Warning"
                $html | Should -Match 'class="info-card warning"'
                $html | Should -Match 'fa-solid fa-triangle-exclamation'
                $html | Should -Match 'info-title" style="color: #333;"'
                $html | Should -Match 'info-description" style="color: #666;"'
            }
        }

        It 'Generates info card with Danger type' {
            InModuleScope UltraTree {
                $html = New-HtmlInfoCard -Title "Test" -Description "Desc" -Type "Danger"
                $html | Should -Match 'class="info-card danger"'
            }
        }

        It 'Info type has no extra class' {
            InModuleScope UltraTree {
                $html = New-HtmlInfoCard -Title "Test" -Description "Desc" -Type "Info"
                $html | Should -Match 'class="info-card"'
                $html | Should -Not -Match 'class="info-card info"'
            }
        }
    }

    Context 'New-HtmlTag' {
        It 'Generates basic tag' {
            InModuleScope UltraTree {
                $html = New-HtmlTag -Text "Healthy"
                $html | Should -Match 'class="tag"'
                $html | Should -Match 'Healthy'
            }
        }

        It 'Adds expired type class' {
            InModuleScope UltraTree {
                $html = New-HtmlTag -Text "Critical" -Type "expired"
                $html | Should -Match 'class="tag expired"'
            }
        }

        It 'Adds disabled type class' {
            InModuleScope UltraTree {
                $html = New-HtmlTag -Text "Warning" -Type "disabled"
                $html | Should -Match 'class="tag disabled"'
            }
        }
    }

    Context 'New-HtmlCard' {
        It 'Generates card with title and body' {
            InModuleScope UltraTree {
                $html = New-HtmlCard -Title "Test Card" -Body "<p>Content</p>"
                $html | Should -Match 'class="card flex-grow-1"'
                $html | Should -Match 'class="card-title-box"'
                $html | Should -Match 'Test Card'
                $html | Should -Match '<p>Content</p>'
            }
        }

        It 'Includes icon when provided' {
            InModuleScope UltraTree {
                $html = New-HtmlCard -Title "Test" -Icon "fas fa-folder" -Body "Content"
                $html | Should -Match 'fas fa-folder'
            }
        }

        It 'Applies body style' {
            InModuleScope UltraTree {
                $html = New-HtmlCard -Title "Test" -Body "Content" -BodyStyle "padding: 0;"
                $html | Should -Match 'style="padding: 0;"'
            }
        }
    }

    Context 'New-HtmlBarChart' {
        It 'Returns empty string for null items' {
            InModuleScope UltraTree { New-HtmlBarChart -Items $null | Should -Be "" }
        }

        It 'Returns empty string for empty array' {
            InModuleScope UltraTree { New-HtmlBarChart -Items @() | Should -Be "" }
        }

        It 'Generates chart with items' {
            InModuleScope UltraTree {
                $items = @(
                    @{ Label = "Folder1"; Value = 1GB }
                    @{ Label = "Folder2"; Value = 500MB }
                )
                $html = New-HtmlBarChart -Items $items -Title "Test Chart"
                $html | Should -Match 'charts-css bar'
                $html | Should -Match 'Test Chart'
                $html | Should -Match 'Folder1'
                $html | Should -Match 'Folder2'
            }
        }
    }

    Context 'New-HtmlDuplicatesTable' {
        It 'Returns empty string for null groups' {
            InModuleScope UltraTree { New-HtmlDuplicatesTable -DuplicateGroups $null -TotalWasted 0 | Should -Be "" }
        }

        It 'Returns empty string for empty groups' {
            InModuleScope UltraTree { New-HtmlDuplicatesTable -DuplicateGroups @() -TotalWasted 0 | Should -Be "" }
        }

        It 'Generates table with duplicate groups' {
            InModuleScope UltraTree {
                $groups = @(
                    [PSCustomObject]@{
                        FileSize = 100MB
                        WastedSpace = 100MB
                        Files = @("C:\path1\file.exe", "C:\path2\file.exe")
                    }
                )
                $html = New-HtmlDuplicatesTable -DuplicateGroups $groups -TotalWasted 100MB
                $html | Should -Match 'Duplicate Files'
                $html | Should -Match 'file.exe'
                $html | Should -Match 'Wasted'
            }
        }
    }
}
