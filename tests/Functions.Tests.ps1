Describe 'EnvPath functions' {
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

    Context 'Prepend-EnvPath' {
        It 'places a path at the start of $env:PATH' {
            $env:PATH = 'C:\Existing1;C:\Existing2'
            Prepend-EnvPath 'C:\Start'
            if ($env:PATH -ne 'C:\Start;C:\Existing1;C:\Existing2') {
                throw "Expected PATH to start with C:\Start, got '$env:PATH'."
            }
        }
    }

    Context 'Append-EnvPath' {
        It 'places a path at the end of $env:PATH' {
            $env:PATH = 'C:\Existing1;C:\Existing2'
            Append-EnvPath 'C:\End'
            if ($env:PATH -ne 'C:\Existing1;C:\Existing2;C:\End') {
                throw "Expected PATH to end with C:\End, got '$env:PATH'."
            }
        }
    }
}
