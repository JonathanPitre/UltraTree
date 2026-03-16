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
                LinkedFiles = [System.Collections.Generic.List[object]]::new()
                DriveInfo = [System.Collections.Generic.List[object]]::new()
                TotalDuplicateWasted = 0
                TotalFiles = 100
                TotalFolders = 20
                TotalErrorCount = 0
            }

            # Add mock drive info
            $mockScanResults.DriveInfo.Add([PSCustomObject]@{
                Drive = "C:"
                TotalSize = 500GB
                UsedSpace = 250GB
                FreeSpace = 250GB
                UsedPercent = 50.0
            })

            # Add mock items
            $mockScanResults.Items.Add([PSCustomObject]@{
                Drive = "C:"
                Path = "C:\Windows"
                Size = "25.00 GB"
                SizeBytes = 25GB
                IsDirectory = $true
                LastModified = "2024-01-01"
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

        It 'Contains linked files section when present' {
            $mockScanResults.LinkedFiles.Add([PSCustomObject]@{
                Drive = 'C:'
                Identity = 'ABCD'
                FileSize = 11MB
                Files = @('C:\Temp\UltraTree-Hardlink-Test\source.bin', 'C:\Temp\UltraTree-Hardlink-Test\link-1.bin')
                IsLinkedGroup = $true
            })

            $html = ConvertTo-NinjaOneHtml -ScanResults $mockScanResults
            $html | Should -Match 'Linked Files'
            $html | Should -Match 'hardlinks'
        }

        It 'Contains version footer' {
            $html = ConvertTo-NinjaOneHtml -ScanResults $mockScanResults
            $html | Should -Match 'TreeSize v1.0.0'
        }

        It 'Accepts pipeline input' {
            $html = $mockScanResults | ConvertTo-NinjaOneHtml
            $html | Should -BeOfType [string]
            $html.Length | Should -BeGreaterThan 0
        }
    }
}
