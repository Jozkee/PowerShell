# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.
Describe "Get-Process for admin" -Tags @('CI', 'RequireAdminOnWindows') {
    It "Should support -IncludeUserName" {
        (Get-Process -Id $PID -IncludeUserName).UserName | Should -Match $env:USERNAME
    }

    It "Should support -Module" -Pending:$IsMacOS {
        $modules = Get-Process -Id $PID -Module
        $modules.GetType() | Should -BeExactly "System.Object[]"
        foreach ($module in $modules) {
            $module.GetType() | Should -BeExactly "System.Diagnostics.ProcessModule"
        }
    }

    It "Should support -FileVersionInfo" {
        $pwshVersion = Get-Process -Id $PID -FileVersionInfo
        if ($IsWindows) {
            $pwshVersion.FileVersion | Should -Match $PSVersionTable.PSVersion.ToString().Split("-")[0]
            $pwshVersion.FileMajorPart | Should -BeExactly $PSVersionTable.PSVersion.Major
            $pwshVersion.FileMinorPart | Should -BeExactly $PSVersionTable.PSVersion.Minor
            $pwshVersion.FileBuildPart | Should -BeExactly $PSVersionTable.PSVersion.Patch
            $gitCommitId = $PSVersionTable.GitCommitId
            if ($gitCommitId.StartsWith("v")) { $gitCommitId = $gitCommitId.Substring(1) }
            $productVersion = $pwshVersion.ProductVersion.Replace(" Commits: ","-").Replace(" SHA: ","-g")
            $productVersion | Should -Match $gitCommitId
        } else {
            $pwshVersion.FileVersion | Should -BeNullOrEmpty
        }
    }

    It "Run with parameter -FileVersionInfo should not stop responding on non Windows platform also when process' main module is null." -Skip:$IsWindows {
        # Main module for idle process can be null on non-Windows platforms
        { $pwshVersion = Get-Process -Id 0 -FileVersionInfo -ErrorAction Stop } | Should -Not -Throw
    }

    It "Run with parameter -FileVersionInfo for idle process should throw on Windows." -Skip:(!$IsWindows) {
        { $pwshVersion = Get-Process -Id 0 -FileVersionInfo -ErrorAction Stop } | Should -Throw -ErrorId "CouldNotEnumerateFileVer,Microsoft.PowerShell.Commands.GetProcessCommand"
    }
}

Describe "Get-Process" -Tags "CI" {
    # These tests are no good, please replace!
    BeforeAll {
        $ps = Get-Process
        $idleProcessPid = 0
    }
    It "Should return a type of Object[] for Get-Process cmdlet" -Pending:$IsMacOS {
        ,$ps | Should -BeOfType System.Object[]
    }

    It "Should have not empty Name flags set for Get-Process object" -Pending:$IsMacOS {
        $ps | ForEach-Object { $_.Name | Should -Not -BeNullOrEmpty }
    }

    It "Should throw an error for non existing process id." {
        $randomId = 123456789
        { Get-Process -Id $randomId -ErrorAction Stop } | Should -Throw -ErrorId "NoProcessFoundForGivenId,Microsoft.PowerShell.Commands.GetProcessCommand"
    }

    It "Should throw an exception when process id is null." {
        { Get-Process -Id $null } | Should -Throw -ErrorId "ParameterArgumentValidationErrorNullNotAllowed,Microsoft.PowerShell.Commands.GetProcessCommand"
    }

    It "Should throw an exception when -InputObject parameter is null." {
        { Get-Process -InputObject $null } | Should -Throw -ErrorId "ParameterArgumentValidationErrorNullNotAllowed,Microsoft.PowerShell.Commands.GetProcessCommand"
    }

    It "Should not fail to get process name even if it is unavailable." {
        { (Get-Process -Id $idleProcessPid).Name } | Should -Not -Throw
    }

    It "Test for process property = Name" -Pending {
        # Bug in .Net 5.0 Preview4. See https://github.com/PowerShell/PowerShell/pull/12894
        (Get-Process -Id $PID).Name | Should -BeExactly "pwsh"
    }

    It "Test for process property = Id" {
        (Get-Process -Id $PID).Id | Should -BeExactly $PID
    }

    It "Should fail to run Get-Process with -IncludeUserName without admin" -Skip:(!$IsWindows)  {
        { Get-Process -IncludeUserName } | Should -Throw -ErrorId "IncludeUserNameRequiresElevation,Microsoft.PowerShell.Commands.GetProcessCommand"
    }

    It "Should fail to run Get-Process with -Module without admin" -Skip:(!$IsWindows) {
        { Get-Process -Module -ErrorAction Stop } | Should -Throw -ErrorId "CouldNotEnumerateModules,Microsoft.PowerShell.Commands.GetProcessCommand"
    }

    It "Should not fail to stop Get-Process with -Module when piped to Select-Object" {
        Get-Process -Module -Id $PID -ErrorVariable errs | Select-Object -First 1
        $errs | Should -HaveCount 0
    }

    It "Should fail to run Get-Process with -FileVersionInfo without admin" -Skip:(!$IsWindows) {
        { Get-Process -FileVersionInfo -ErrorAction Stop } | Should -Throw -ErrorId "CouldNotEnumerateFileVer,Microsoft.PowerShell.Commands.GetProcessCommand"
    }

    It "Should return CommandLine property" -Skip:($IsMacOS)  {
        $command = "(Get-Process -Id `$pid).CommandLine"
        $result = & "$PSHOME/pwsh" -NoProfile -NonInteractive -Command $command
        $result | Should -BeLike "*$command*"
    }
}

Describe "Get-Process Formatting" -Tags "Feature" {
    BeforeAll {
        $skip = $false
        if ($IsWindows)
        {
            # on Windows skip this test until issue #11016 is resolved
            $skip = $true
        }
    }

    It "Should not have Handle in table format header" -Skip:$skip {
        $types = "System.Diagnostics.Process","System.Diagnostics.Process#IncludeUserName"

        foreach ($type in $types) {
            $formatData = Get-FormatData -TypeName $type -PowerShellVersion $PSVersionTable.PSVersion
            $tableControls = $formatData.FormatViewDefinition | Where-Object {$_.Control -is "System.Management.Automation.TableControl"}
            foreach ($tableControl in $tableControls) {
                $tableControl.Control.Headers.Label -match "Handle*" | Should -BeNullOrEmpty
                # verify that rows without headers isn't the handlecount (as PowerShell will create a header that matches the property name)
                $tableControl.Control.Rows.Columns.DisplayEntry.Value -eq "HandleCount" | Should -BeNullOrEmpty
            }
        }
    }
}

Describe "Process Parent property" -Tags "CI" {
    It "Has Parent process property" -Pending {
        # Bug in .Net 5.0 Preview4. See https://github.com/PowerShell/PowerShell/pull/12894
        $powershellexe = (Get-Process -Id $PID).mainmodule.filename
        & $powershellexe -noprofile -command '(Get-Process -Id $PID).Parent' | Should -Not -BeNullOrEmpty
    }

    It "Has valid parent process ID property" -Pending {
        # Bug. See https://github.com/PowerShell/PowerShell/issues/12908
        $powershellexe = (Get-Process -Id $PID).mainmodule.filename
        & $powershellexe -noprofile -command '(Get-Process -Id $PID).Parent.Id' | Should -Be $PID
    }
}

