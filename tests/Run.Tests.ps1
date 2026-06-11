BeforeAll {
    # Dot-source the installer so Get-ElevationArgumentString is in scope. run.ps1's
    # dot-source guard keeps the self-elevate/download body from running here.
    . (Join-Path $PSScriptRoot "..\run.ps1")
}

Describe "Get-ElevationArgumentString" {
    # Issue #10: when run.ps1 already lives on disk, elevating should re-run that
    # exact file instead of pulling a fresh copy off the network, so the elevated
    # process runs the same code the user inspected.

    Context "when run.ps1 exists on disk" {
        BeforeEach {
            $script:localCopy = Join-Path ([System.IO.Path]::GetTempPath()) ("uwso_run_" + [Guid]::NewGuid().ToString('N') + ".ps1")
            Set-Content -LiteralPath $script:localCopy -Value '# stand-in for run.ps1'
        }
        AfterEach {
            Remove-Item -LiteralPath $script:localCopy -Force -ErrorAction SilentlyContinue
        }

        It "Should relaunch the local file with -File and not re-download" {
            $result = Get-ElevationArgumentString -LocalScriptPath $script:localCopy
            $result | Should -BeLike "*-File*"
            $result | Should -Not -BeLike "*-EncodedCommand*"
        }

        It "Should quote the script path so spaces survive" {
            $result = Get-ElevationArgumentString -LocalScriptPath $script:localCopy
            $result | Should -BeLike "*-File `"$($script:localCopy)`"*"
        }

        It "Should carry -Auto through when requested" {
            $result = Get-ElevationArgumentString -LocalScriptPath $script:localCopy -Auto
            $result | Should -BeLike "*-Auto*"
        }

        It "Should leave -Auto off by default" {
            $result = Get-ElevationArgumentString -LocalScriptPath $script:localCopy
            $result | Should -Not -BeLike "*-Auto*"
        }
    }

    Context "when there is no local copy (piped via irm | iex)" {
        It "Should fall back to an encoded re-download command for an empty path" {
            $result = Get-ElevationArgumentString -LocalScriptPath ""
            $result | Should -BeLike "*-EncodedCommand*"
            $result | Should -Not -BeLike "*-File*"
        }

        It "Should fall back when the path does not point at a real file" {
            $missing = Join-Path ([System.IO.Path]::GetTempPath()) ("uwso_missing_" + [Guid]::NewGuid().ToString('N') + ".ps1")
            $result = Get-ElevationArgumentString -LocalScriptPath $missing
            $result | Should -BeLike "*-EncodedCommand*"
            $result | Should -Not -BeLike "*-File*"
        }

        It "Should still encode the unattended opt-in in the fallback command" {
            # The fallback sets UWSO_AUTO so the re-downloaded run keeps running
            # hands-off. Decode the base64 payload back and check for it.
            $result = Get-ElevationArgumentString -LocalScriptPath "" -Auto
            $encoded = ($result -split '-EncodedCommand ')[-1].Trim()
            $decoded = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($encoded))
            $decoded | Should -BeLike "*UWSO_AUTO*"
        }
    }
}
