BeforeAll {
    Set-Location -Path $PSScriptRoot
    $ModuleName = 'UltraTree'
    $PathToManifest = [System.IO.Path]::Combine('..', '..', '..', $ModuleName, "$ModuleName.psd1")
    Get-Module $ModuleName -ErrorAction SilentlyContinue | Remove-Module -Force
    Import-Module $PathToManifest -Force
}

Describe 'ConvertTo-NinjaOneHtml' -Tag Unit {

    Context 'Parameter validation' {
        It 'Has mandatory ScanResults parameter' {
            $command = Get-Command ConvertTo-NinjaOneHtml
            $command.Parameters['ScanResults'].Attributes.Mandatory | Should -Contain $true
        }

        It 'Accepts pipeline input' {
            $command = Get-Command ConvertTo-NinjaOneHtml
            $command.Parameters['ScanResults'].Attributes.ValueFromPipeline | Should -Contain $true
        }

        It 'Has optional MaxTopFiles, MaxTopFolders, ShowAllResults, and FooterSuffix parameters' {
            $command = Get-Command ConvertTo-NinjaOneHtml
            $command.Parameters.ContainsKey('MaxTopFiles') | Should -Be $true
            $command.Parameters.ContainsKey('MaxTopFolders') | Should -Be $true
            $command.Parameters.ContainsKey('ShowAllResults') | Should -Be $true
            $command.Parameters.ContainsKey('FooterSuffix') | Should -Be $true
        }
    }

    Context 'Help documentation' {
        BeforeAll {
            $help = Get-Help ConvertTo-NinjaOneHtml -Full
        }

        It 'Has synopsis' {
            $help.Synopsis | Should -Not -BeNullOrEmpty
        }

        It 'Has description' {
            $help.Description | Should -Not -BeNullOrEmpty
        }

        It 'Has at least one example' {
            $help.Examples.Example.Count | Should -BeGreaterOrEqual 1
        }

        It 'Documents ScanResults parameter' {
            ($help.Parameters.Parameter | Where-Object { $_.Name -eq 'ScanResults' }).Description.Text | Should -Not -BeNullOrEmpty
        }
    }

    Context 'HTML generation' {
        BeforeAll {
            # Create mock scan results
            $mockScanResults = [PSCustomObject]@{
                Items = [System.Collections.Generic.List[object]]::new()
                FileTypes = [System.Collections.Generic.List[object]]::new()
                CleanupSuggestions = [System.Collections.Generic.List[object]]::new()
                Duplicates = [System.Collections.Generic.List[object]]::new()
                DriveInfo = [System.Collections.Generic.List[object]]::new()
                TotalDuplicateWasted = 0
                TotalFiles = 100
                TotalFolders = 20
                TotalErrorCount = 0
            }

            # Add mock drive info
            $mockScanResults.DriveInfo.Add([PSCustomObject]@{
                    Drive = 'C:'
                    TotalSize = 500GB
                    UsedSpace = 250GB
                    FreeSpace = 250GB
                    UsedPercent = 50.0
                })

            # Add mock items
            $mockScanResults.Items.Add([PSCustomObject]@{
                    Drive = 'C:'
                    Path = 'C:\Windows'
                    Size = '25.00 GB'
                    SizeBytes = 25GB
                    IsDirectory = $true
                    LastModified = '2024-01-01'
                })

            $mockScanResults.Items.Add([PSCustomObject]@{
                    Drive = 'C:'
                    Path = 'C:\pagefile.sys'
                    Size = '8.00 GB'
                    SizeBytes = 8GB
                    IsDirectory = $false
                    LastModified = '2024-01-01'
                })
        }

        It 'Returns string output' {
            $html = ConvertTo-NinjaOneHtml -ScanResults $mockScanResults
            $html | Should -BeOfType [string]
        }

        It 'Contains stat cards' {
            $html = ConvertTo-NinjaOneHtml -ScanResults $mockScanResults
            $html | Should -Match 'stat-card'
        }

        It 'Contains drive count' {
            $html = ConvertTo-NinjaOneHtml -ScanResults $mockScanResults
            $html | Should -Match 'Drives Scanned'
        }

        It 'Contains items count' {
            $html = ConvertTo-NinjaOneHtml -ScanResults $mockScanResults
            $html | Should -Match 'Items'
        }

        It 'Contains cleanup potential' {
            $html = ConvertTo-NinjaOneHtml -ScanResults $mockScanResults
            $html | Should -Match 'Cleanup Potential'
        }

        It 'Contains UltraTree version footer' {
            $html = ConvertTo-NinjaOneHtml -ScanResults $mockScanResults
            $html | Should -Match 'UltraTree v1.0.2'
            $html | Should -Not -Match 'TreeSize v'
        }

        It 'Contains Top Files ranked table when file items exist' {
            $html = ConvertTo-NinjaOneHtml -ScanResults $mockScanResults
            $html | Should -Match 'Top Files'
            $html | Should -Match '<table style="width: 100%;">'
        }

        It 'Contains Top Folders ranked table when folder items exist' {
            $html = ConvertTo-NinjaOneHtml -ScanResults $mockScanResults
            $html | Should -Match 'Top Folders'
        }

        It 'Uses two-column Cleanup and File Types layout' {
            $html = ConvertTo-NinjaOneHtml -ScanResults $mockScanResults
            $html | Should -Match 'col-xl-6 col-lg-6 col-md-12 d-flex flex-column'
            $html | Should -Not -Match 'col-xl-4 col-lg-4 col-md-12 d-flex'
        }

        It 'Does not use hardcoded muted text outside info cards' {
            $html = ConvertTo-NinjaOneHtml -ScanResults $mockScanResults
            $htmlWithoutInfoCards = ($html -split '<div class="info-card')[0]
            if ($htmlWithoutInfoCards) {
                $htmlWithoutInfoCards | Should -Not -Match 'color: #666'
                $htmlWithoutInfoCards | Should -Not -Match 'color: #888'
            }
        }

        It 'Uses explicit dark text on warning info cards' {
            $mockWithErrors = [PSCustomObject]@{
                Items = $mockScanResults.Items
                FileTypes = $mockScanResults.FileTypes
                CleanupSuggestions = $mockScanResults.CleanupSuggestions
                Duplicates = $mockScanResults.Duplicates
                DriveInfo = $mockScanResults.DriveInfo
                TotalDuplicateWasted = 0
                TotalFiles = 100
                TotalFolders = 20
                TotalErrorCount = 100
            }

            $html = ConvertTo-NinjaOneHtml -ScanResults $mockWithErrors
            $html | Should -Match 'info-card warning'
            $html | Should -Match 'Access Errors'
            $html | Should -Match 'info-title" style="color: #333;"'
            $html | Should -Match 'info-description" style="color: #666;"'
        }

        It 'Omits All Results by Size when ShowAllResults is false' {
            $html = ConvertTo-NinjaOneHtml -ScanResults $mockScanResults -ShowAllResults:$false
            $html | Should -Not -Match 'All Results by Size'
        }

        It 'Includes All Results by Size by default' {
            $html = ConvertTo-NinjaOneHtml -ScanResults $mockScanResults
            $html | Should -Match 'All Results by Size'
        }

        It 'Appends FooterSuffix to footer' {
            $html = ConvertTo-NinjaOneHtml -ScanResults $mockScanResults -FooterSuffix ', Script v1.4.2'
            $html | Should -Match 'UltraTree v1.0.2, Script v1.4.2'
        }

        It 'Accepts pipeline input' {
            $html = $mockScanResults | ConvertTo-NinjaOneHtml
            $html | Should -BeOfType [string]
            $html.Length | Should -BeGreaterThan 0
        }
    }
}
