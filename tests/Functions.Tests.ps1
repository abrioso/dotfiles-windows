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
            $env:PATH | Should -Be 'C:\Start;C:\Existing1;C:\Existing2'
        }
    }

    Context 'Append-EnvPath' {
        It 'places a path at the end of $env:PATH' {
            $env:PATH = 'C:\Existing1;C:\Existing2'
            Append-EnvPath 'C:\End'
            $env:PATH | Should -Be 'C:\Existing1;C:\Existing2;C:\End'
        }
    }
}
