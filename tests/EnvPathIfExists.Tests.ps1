Describe 'EnvPath *-IfExists functions' {
    BeforeAll {
        $script:originalPath = $env:PATH
        . "$PSScriptRoot/../powershell-scripts/functions.ps1"
    }
    BeforeEach {
        $env:PATH = $script:originalPath
    }
    AfterAll {
        $env:PATH = $script:originalPath
    }

    Context 'Prepend-EnvPathIfExists' {
        It 'updates $env:PATH when directory exists' {
            $tempDir = Join-Path $env:TEMP ([System.Guid]::NewGuid())
            New-Item -ItemType Directory -Path $tempDir | Out-Null
            $env:PATH = 'C:\Existing1;C:\Existing2'
            Prepend-EnvPathIfExists $tempDir
            $expectedPath = "$tempDir;C:\Existing1;C:\Existing2"
            if ($env:PATH -ne $expectedPath) {
                throw "Expected PATH '$expectedPath', got '$env:PATH'."
            }
            Remove-Item -Recurse -Force $tempDir
        }
        It 'does not update $env:PATH when directory does not exist' {
            $tempDir = Join-Path $env:TEMP ([System.Guid]::NewGuid())
            $env:PATH = 'C:\Existing1;C:\Existing2'
            Prepend-EnvPathIfExists $tempDir
            if ($env:PATH -ne 'C:\Existing1;C:\Existing2') {
                throw "Expected PATH to remain unchanged, got '$env:PATH'."
            }
        }
    }

    Context 'Append-EnvPathIfExists' {
        It 'updates $env:PATH when directory exists' {
            $tempDir = Join-Path $env:TEMP ([System.Guid]::NewGuid())
            New-Item -ItemType Directory -Path $tempDir | Out-Null
            $env:PATH = 'C:\Existing1;C:\Existing2'
            Append-EnvPathIfExists $tempDir
            $expectedPath = "C:\Existing1;C:\Existing2;$tempDir"
            if ($env:PATH -ne $expectedPath) {
                throw "Expected PATH '$expectedPath', got '$env:PATH'."
            }
            Remove-Item -Recurse -Force $tempDir
        }
        It 'does not update $env:PATH when directory does not exist' {
            $tempDir = Join-Path $env:TEMP ([System.Guid]::NewGuid())
            $env:PATH = 'C:\Existing1;C:\Existing2'
            Append-EnvPathIfExists $tempDir
            if ($env:PATH -ne 'C:\Existing1;C:\Existing2') {
                throw "Expected PATH to remain unchanged, got '$env:PATH'."
            }
        }
    }
}
