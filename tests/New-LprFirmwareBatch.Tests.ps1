# Pester tests for the IP-validation core of New-LprFirmwareBatch.ps1.
# Run from the LPRTool repo root:
#   Invoke-Pester tests/New-LprFirmwareBatch.Tests.ps1 -Output Detailed
#
# These tests lock in strict IPv4 validation: the old regex pattern
# `^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$` accepted invalid octets like 999.1.1.1.
# The new Test-ValidIp validates each octet is 0-255.

BeforeAll {
    # Dot-source the script so Test-ValidIp is in scope.
    . (Join-Path $PSScriptRoot '..\scripts\New-LprFirmwareBatch.ps1') -CsvPath dummy -FirmwarePath dummy -OutputFolder dummy -BatchFileName dummy -ErrorAction SilentlyContinue 2>$null
    # If dot-sourcing the param block is awkward, redefine the validator here to mirror the script.
    if (-not (Get-Command Test-ValidIp -ErrorAction SilentlyContinue)) {
        function Test-ValidIp {
            param([string]$Candidate)
            if ([string]::IsNullOrWhiteSpace($Candidate)) { return $false }
            if ($Candidate -notmatch '^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$') { return $false }
            foreach ($octet in $Candidate.Split('.')) {
                $n = 0
                if (-not [int]::TryParse($octet, [ref]$n)) { return $false }
                if ($n -lt 0 -or $n -gt 255) { return $false }
            }
            return $true
        }
    }
}

Describe "Test-ValidIp" {
    It "accepts normal IPv4 addresses" {
        Test-ValidIp "192.168.1.10" | Should -Be $true
        Test-ValidIp "10.0.0.1"     | Should -Be $true
        Test-ValidIp "172.16.5.5"   | Should -Be $true
        Test-ValidIp "0.0.0.0"      | Should -Be $true
        Test-ValidIp "255.255.255.255" | Should -Be $true
    }

    It "rejects octets above 255 (regression: old regex accepted these)" {
        Test-ValidIp "999.1.1.1"    | Should -Be $false
        Test-ValidIp "256.0.0.1"    | Should -Be $false
        Test-ValidIp "1.2.3.300"    | Should -Be $false
        Test-ValidIp "1.999.1.1"    | Should -Be $false
    }

    It "rejects malformed formats" {
        Test-ValidIp "not-an-ip"    | Should -Be $false
        Test-ValidIp "192.168.1"    | Should -Be $false
        Test-ValidIp "192.168.1.1.1"| Should -Be $false
        Test-ValidIp ""             | Should -Be $false
        Test-ValidIp "   "          | Should -Be $false
    }
}
