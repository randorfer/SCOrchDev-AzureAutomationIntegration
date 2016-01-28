$here = Split-Path -Parent $MyInvocation.MyCommand.Path

$ModuleRoot = "$here\.."
$manifestPath = "$ModuleRoot\SCOrchDev-AzureAutomationIntegration.psd1"
Import-Module $manifestPath -Force -Scope Local

Describe -Tags 'VersionChecks' 'SCOrchDev-AzureAutomationIntegration' {
    $script:manifest = $null
    It 'has a valid manifest' {
        {
            $script:manifest = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop -WarningAction SilentlyContinue
        } | Should Not Throw
    }

    It 'has a valid name in the manifest' {
        $script:manifest.Name | Should Be SCOrchDev-AzureAutomationIntegration
    }

    It 'has a valid guid in the manifest' {
        $script:manifest.Guid | Should Be '1dafd04a-a2c2-4245-a2ba-69bfcd6bfe0a'
    }

    It 'has a valid version in the manifest' {
        $script:manifest.Version -as [Version] | Should Not BeNullOrEmpty
    }

    if (Get-Command git.exe -ErrorAction SilentlyContinue) {
        $script:tagVersion = $null
        It 'is tagged with a valid version' {
            $cwd = get-location
            Set-Location ($PATH -as [System.IO.FileInfo]).Directory
            $thisCommit = git.exe log --decorate --oneline HEAD~1..HEAD
            Set-Location $cwd
            if ($thisCommit -match 'tag:\s*(\d+(?:\.\d+)*)')
            {
                $script:tagVersion = $matches[1]
            }

            $script:tagVersion                  | Should Not BeNullOrEmpty
            $script:tagVersion -as [Version]    | Should Not BeNullOrEmpty
            
        }

        It 'all versions are the same' {
            $script:manifest.Version -as [Version] | Should be ( $script:tagVersion -as [Version] )
        }

    }

    It 'should have all files listed in the FileList' {
        $ModuleFiles = (Get-ChildItem -Path $ModuleRoot -Recurse -Exclude .git -File).FullName
        #Filter out NUnit
        $ModuleFiles = $ModuleFiles | Where-Object { $_ -notlike '*\NUnitToHTML*' }
        $FileDifferences = Compare-Object -ReferenceObject $ModuleFiles -DifferenceObject $script:manifest.FileList
        
        if (($FileDifferences -as [array]).Count -gt 0)
        {
            Throw-Exception -Type 'MissingFiles' `
                            -Message 'Files missing or not tracked in FileList' `
                            -Property @{
                'Missing Files' = ($FileDifferences | Where-Object {$_.SideIndicator -eq '=>'}).InputObject ;
                'Non Tracked Files' = ($FileDifferences | Where-Object {$_.SideIndicator -eq '<='}).InputObject ;
            }
        }
    }
}

if ($PSVersionTable.PSVersion.Major -ge 3)
{
    $error.Clear()
    Describe 'Clean treatment of the $error variable' {
        It 'Performs a successful test' {
            $true | Should Be $true
        }

        It 'Did not add anything to the $error variable' {
            $error.Count | Should Be 0
        }
    }
}

Describe 'Style rules' {
    $_ModuleBase = (Get-Module SCOrchDev-AzureAutomationIntegration).ModuleBase

    $files = @(
        Get-ChildItem $_ModuleBase -Include *.ps1,*.psm1
    )

    It 'Module source files contain no trailing whitespace' {
        $badLines = @(
            foreach ($file in $files)
            {
                $lines = [System.IO.File]::ReadAllLines($file.FullName)
                $lineCount = $lines.Count

                for ($i = 0; $i -lt $lineCount; $i++)
                {
                    if ($lines[$i] -match '\s+$')
                    {
                        'File: {0}, Line: {1}' -f $file.FullName, ($i + 1)
                    }
                }
            }
        )

        if ($badLines.Count -gt 0)
        {
            throw "The following $($badLines.Count) lines contain trailing whitespace: `r`n`r`n$($badLines -join "`r`n")"
        }
    }

    It 'Module Source Files all end with a newline' {
        $badFiles = @(
            foreach ($file in $files)
            {
                $string = [System.IO.File]::ReadAllText($file.FullName)
                if ($string.Length -gt 0 -and $string[-1] -ne "`n")
                {
                    $file.FullName
                }
            }
        )

        if ($badFiles.Count -gt 0)
        {
            throw "The following files do not end with a newline: `r`n`r`n$($badFiles -join "`r`n")"
        }
    }
}

Describe 'ConvertFrom-AutomationDescriptionTagLine' {
    InModuleScope -ModuleName SCOrchDev-AzureAutomationIntegration {
        Context 'When passed a description string with a tag section' {
            $RepositoryName = 'AAAAAAAAA'
            $CurrentCommit = 'BBBBBBBB'
            $DescriptionString = "__RepositoryName:$RepositoryName;CurrentCommit:$CurrentCommit;__"
            $Return = ConvertFrom-AutomationDescriptionTagLine -InputObject $DescriptionString
            It 'Should return an object with a CurrentCommit property' {
                $Return.ContainsKey('CurrentCommit') | Should Be $True
            }
            It 'Should have the proper value in current commit' {
                $Return.CurrentCommit | Should Match $CurrentCommit
            }
            It 'Should return an object with RepositoryName property' {
                $Return.ContainsKey('RepositoryName') | Should Be $True
            }
            It 'Should have the proper value in Repository Name' {
                $Return.RepositoryName | Should Match $RepositoryName
            }
            It 'Should return an object with Description property' {
                $Return.ContainsKey('Description') | Should Be $True
            }
            It 'Should have the proper value in Description' {
                $Return.Description | Should Match $DescriptionString
            }
        }
    }
}

Describe 'Converting a AutomationDescription Tag Line' {
    InModuleScope -ModuleName SCOrchDev-AzureAutomationIntegration {
        $RepositoryName = 'AAAAAAAAA'
        $CurrentCommit = 'BBBBBBBB'
        $DescriptionString = "__RepositoryName:$RepositoryName;CurrentCommit:$CurrentCommit;__"
        $Return = ConvertFrom-AutomationDescriptionTagLine -InputObject $DescriptionString
        $NewRepositoryName = 'CCCCCCCCC'
        $NewCommit = 'DDDDDDDD'
        $UpdatedString = ConvertTo-AutomationDescriptionTagLine `
            -Description $Return.Description `
            -CurrentCommit $NewCommit `
            -RepositoryName $NewRepositoryName

        Context 'Converting a string to a Description Hashtable' {
            It 'Should return an object with a CurrentCommit property' {
                $Return.ContainsKey('CurrentCommit') | Should Be $True
            }
            It 'Should have the proper value in current commit' {
                $Return.CurrentCommit | Should Match $CurrentCommit
            }
            It 'Should return an object with RepositoryName property' {
                $Return.ContainsKey('RepositoryName') | Should Be $True
            }
            It 'Should have the proper value in Repository Name' {
                $Return.RepositoryName | Should Match $RepositoryName
            }
            It 'Should return an object with Description property' {
                $Return.ContainsKey('Description') | Should Be $True
            }
            It 'Should have the proper value in Description' {
                $Return.Description | Should Match $DescriptionString
            }
        }
        Context 'Converting an updated Description Hashtable' {
            It 'Should have a properly updated Current Commit' {
                $UpdatedString | Should Match "__RepositoryName:$NewRepositoryName;"
            }
            It 'Should have a properly updated RepositoryName' {
                $UpdatedString | Should Match "CurrentCommit:$NewCommit;__"
            }
        }
    }
}