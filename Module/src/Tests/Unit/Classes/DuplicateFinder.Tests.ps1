BeforeAll {
    Set-Location -Path $PSScriptRoot
    $ModuleName = 'UltraTree'
    $PathToManifest = [System.IO.Path]::Combine('..', '..', '..', $ModuleName, "$ModuleName.psd1")
    Get-Module $ModuleName -ErrorAction SilentlyContinue | Remove-Module -Force
    Import-Module $PathToManifest -Force
}

Describe 'DuplicateFinder' -Tag Unit {
    It 'Groups duplicates correctly when candidate sizes are interleaved' {
        $testRoot = Join-Path $TestDrive 'dedupe-interleaved'
        $null = New-Item -Path $testRoot -ItemType Directory -Force

        $alpha1 = Join-Path $testRoot 'alpha-1.bin'
        $alpha2 = Join-Path $testRoot 'alpha-2.bin'
        $beta1 = Join-Path $testRoot 'beta-1.bin'
        $beta2 = Join-Path $testRoot 'beta-2.bin'
        $unique = Join-Path $testRoot 'unique.bin'

        [System.IO.File]::WriteAllText($alpha1, ('A' * 1024))
        [System.IO.File]::WriteAllText($alpha2, ('A' * 1024))
        [System.IO.File]::WriteAllText($beta1, ('B' * 2048))
        [System.IO.File]::WriteAllText($beta2, ('B' * 2048))
        [System.IO.File]::WriteAllText($unique, ('C' * 1536))

        $alpha1Candidate = [MftTreeSizeV8.DuplicateCandidate]::new()
        $alpha1Candidate.Path = $alpha1
        $alpha1Candidate.Size = ([System.IO.FileInfo]$alpha1).Length

        $beta1Candidate = [MftTreeSizeV8.DuplicateCandidate]::new()
        $beta1Candidate.Path = $beta1
        $beta1Candidate.Size = ([System.IO.FileInfo]$beta1).Length

        $uniqueCandidate = [MftTreeSizeV8.DuplicateCandidate]::new()
        $uniqueCandidate.Path = $unique
        $uniqueCandidate.Size = ([System.IO.FileInfo]$unique).Length

        $alpha2Candidate = [MftTreeSizeV8.DuplicateCandidate]::new()
        $alpha2Candidate.Path = $alpha2
        $alpha2Candidate.Size = ([System.IO.FileInfo]$alpha2).Length

        $beta2Candidate = [MftTreeSizeV8.DuplicateCandidate]::new()
        $beta2Candidate.Path = $beta2
        $beta2Candidate.Size = ([System.IO.FileInfo]$beta2).Length

        $candidates = @(
            $alpha1Candidate
            $beta1Candidate
            $uniqueCandidate
            $alpha2Candidate
            $beta2Candidate
        )

        $result = [MftTreeSizeV8.DuplicateFinder]::FindDuplicates($candidates, 0, $false)

        $result.Groups.Count | Should -Be 2

        $alphaGroup = $result.Groups | Where-Object { $_.Files -contains $alpha1 }
        $betaGroup = $result.Groups | Where-Object { $_.Files -contains $beta1 }

        $alphaGroup | Should -Not -BeNullOrEmpty
        $betaGroup | Should -Not -BeNullOrEmpty

        @($alphaGroup.Files) | Should -Contain $alpha2
        @($betaGroup.Files) | Should -Contain $beta2

        $expectedWasted = ([System.IO.FileInfo]$alpha1).Length + ([System.IO.FileInfo]$beta1).Length
        $result.TotalWastedSpace | Should -Be $expectedWasted
    }

    It 'Honors MinFileSize when filtering duplicate candidates' {
        $testRoot = Join-Path $TestDrive 'dedupe-min-size'
        $null = New-Item -Path $testRoot -ItemType Directory -Force

        $small1 = Join-Path $testRoot 'small-1.bin'
        $small2 = Join-Path $testRoot 'small-2.bin'
        $large1 = Join-Path $testRoot 'large-1.bin'
        $large2 = Join-Path $testRoot 'large-2.bin'

        [System.IO.File]::WriteAllText($small1, ('S' * 128))
        [System.IO.File]::WriteAllText($small2, ('S' * 128))
        [System.IO.File]::WriteAllText($large1, ('L' * 4096))
        [System.IO.File]::WriteAllText($large2, ('L' * 4096))

        $small1Candidate = [MftTreeSizeV8.DuplicateCandidate]::new()
        $small1Candidate.Path = $small1
        $small1Candidate.Size = ([System.IO.FileInfo]$small1).Length

        $small2Candidate = [MftTreeSizeV8.DuplicateCandidate]::new()
        $small2Candidate.Path = $small2
        $small2Candidate.Size = ([System.IO.FileInfo]$small2).Length

        $large1Candidate = [MftTreeSizeV8.DuplicateCandidate]::new()
        $large1Candidate.Path = $large1
        $large1Candidate.Size = ([System.IO.FileInfo]$large1).Length

        $large2Candidate = [MftTreeSizeV8.DuplicateCandidate]::new()
        $large2Candidate.Path = $large2
        $large2Candidate.Size = ([System.IO.FileInfo]$large2).Length

        $candidates = @(
            $small1Candidate
            $small2Candidate
            $large1Candidate
            $large2Candidate
        )

        $result = [MftTreeSizeV8.DuplicateFinder]::FindDuplicates($candidates, 1024, $false)

        $result.Groups.Count | Should -Be 1
        @($result.Groups[0].Files) | Should -Contain $large1
        @($result.Groups[0].Files) | Should -Contain $large2
        @($result.Groups[0].Files) | Should -Not -Contain $small1
        @($result.Groups[0].Files) | Should -Not -Contain $small2
    }
}
