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

Describe "Commit pinning and archive URLs (issue #11)" {
    # The one-liner still downloads and runs code as admin, which no amount of
    # scripting makes safe on its own. What it can do is stop being a moving
    # target: resolve a commit, fetch that exact revision, and refuse anything
    # the caller did not ask for.

    Context "Get-RepositoryArchiveUrl" {
        It "Should download a specific commit when one is known" {
            $url = Get-RepositoryArchiveUrl -CommitSha "0123456789abcdef0123456789abcdef01234567"
            $url | Should -BeLike "*/archive/0123456789abcdef0123456789abcdef01234567.zip"
        }

        It "Should fall back to the branch tip when no commit was resolved" {
            Get-RepositoryArchiveUrl -CommitSha "" | Should -BeLike "*/archive/refs/heads/main.zip"
        }

        It "Should stay on github.com either way" {
            (Get-RepositoryArchiveUrl -CommitSha "abc1234") | Should -BeLike "https://github.com/*"
            (Get-RepositoryArchiveUrl -CommitSha $null)     | Should -BeLike "https://github.com/*"
        }
    }

    Context "Test-CommitMatch" {
        It "Should pass when nothing was pinned" {
            Test-CommitMatch -Expected "" -Actual "abcdef1234567890" | Should -BeTrue
        }

        It "Should accept the short SHA GitHub displays" {
            Test-CommitMatch -Expected "abcdef1" -Actual "abcdef1234567890" | Should -BeTrue
        }

        It "Should ignore case" {
            Test-CommitMatch -Expected "ABCDEF1" -Actual "abcdef1234567890" | Should -BeTrue
        }

        It "Should reject a different commit" {
            Test-CommitMatch -Expected "9999999" -Actual "abcdef1234567890" | Should -BeFalse
        }

        It "Should fail closed when the commit could not be resolved" {
            Test-CommitMatch -Expected "abcdef1" -Actual $null | Should -BeFalse
        }

        It "Should refuse a prefix too short to mean anything" {
            Test-CommitMatch -Expected "ab" -Actual "abcdef1234567890" | Should -BeFalse
        }
    }

    Context "Get-FileSha256" {
        It "Should hash a file that exists" {
            $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("uwso_hash_" + [Guid]::NewGuid().ToString('N'))
            Set-Content -LiteralPath $tmp -Value 'uwso' -NoNewline
            try {
                Get-FileSha256 -Path $tmp | Should -Match '^[0-9A-F]{64}$'
            } finally {
                Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should return nothing for a path that is not there" {
            $missing = Join-Path ([System.IO.Path]::GetTempPath()) ("uwso_nohash_" + [Guid]::NewGuid().ToString('N'))
            Get-FileSha256 -Path $missing | Should -BeNullOrEmpty
        }
    }

    Context "carrying the pin through elevation" {
        It "Should pass the commit to the elevated -File relaunch" {
            $localCopy = Join-Path ([System.IO.Path]::GetTempPath()) ("uwso_run_" + [Guid]::NewGuid().ToString('N') + ".ps1")
            Set-Content -LiteralPath $localCopy -Value '# stand-in for run.ps1'
            try {
                $result = Get-ElevationArgumentString -LocalScriptPath $localCopy -ExpectedCommit "abcdef1"
                $result | Should -BeLike "*-ExpectedCommit `"abcdef1`"*"
            } finally {
                Remove-Item -LiteralPath $localCopy -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should encode the commit into the piped fallback" {
            $result = Get-ElevationArgumentString -LocalScriptPath "" -ExpectedCommit "abcdef1"
            $encoded = ($result -split '-EncodedCommand ')[-1].Trim()
            $decoded = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($encoded))
            $decoded | Should -BeLike "*UWSO_COMMIT = 'abcdef1'*"
        }

        It "Should leave both opt-ins out when neither was asked for" {
            $localCopy = Join-Path ([System.IO.Path]::GetTempPath()) ("uwso_run_" + [Guid]::NewGuid().ToString('N') + ".ps1")
            Set-Content -LiteralPath $localCopy -Value '# stand-in for run.ps1'
            try {
                $result = Get-ElevationArgumentString -LocalScriptPath $localCopy
                $result | Should -Not -BeLike "*-ExpectedCommit*"
                $result | Should -Not -BeLike "*-Auto*"
            } finally {
                Remove-Item -LiteralPath $localCopy -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
