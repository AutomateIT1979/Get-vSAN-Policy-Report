BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot .. "*.ps1"
    $scriptFiles = Get-ChildItem $scriptPath -File | Where-Object { $_.Name -notmatch "\.Tests\.ps1$" }
}

Describe "Get-vSAN-Policy-Report" {
    
    It "should have at least one PowerShell script" {
        $scriptFiles | Should -Not -BeNullOrEmpty
    }
    
    It "scripts should have documentation" {
        foreach ($script in $scriptFiles) {
            $content = Get-Content $script -Raw
            $content | Should -Match "#"
        }
    }
    
    It "scripts should not have hardcoded credentials" {
        foreach ($script in $scriptFiles) {
            $content = Get-Content $script -Raw
            $content | Should -Not -Match "password\s*="
        }
    }
    
    It "should have proper structure" {
        $scriptFiles.Count | Should -BeGreaterThan 0
    }
    
    It "scripts should have reasonable size" {
        foreach ($script in $scriptFiles) {
            (Get-Content $script | Measure-Object -Line).Lines | Should -BeGreaterThan 5
        }
    }
}
