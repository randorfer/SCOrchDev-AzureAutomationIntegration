﻿<#
    .Synopsis
        Takes a ps1 file and publishes it to the current Azure Automation environment.
    
    .Parameter FilePath
        The full path to the script file

    .Parameter CurrentCommit
        The current commit to store this version under

    .Parameter RepositoryName
        The name of the repository that will be listed as the 'owner' of this
        runbook
#>
Function Publish-SMARunbookChange
{
    Param(
        [Parameter(Mandatory=$True)]
        [String]
        $FilePath,

        [Parameter(Mandatory=$True)]
        [String]
        $CurrentCommit,

        [Parameter(Mandatory=$True)]
        [String]
        $RepositoryName,

        [Parameter(Mandatory=$True)]
        [PSCredential]
        $Credential
    )
    
    Write-Verbose -Message "[$FilePath] Starting [$WorkflowCommandName]"
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    $CIVariables = Get-BatchAutomationVariable -Name @(
                                                    'WebserviceEndpoint'
                                                    'WebservicePort'
                                                    ) `
                                               -Prefix 'SMAContinuousIntegration'

    Try
    {
        $WorkflowName = Get-SmaWorkflowNameFromFile -FilePath $FilePath
        
        $ErrorActionPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
        $Runbook = Get-SmaRunbook -Name $WorkflowName `
                                  -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                  -Port $CIVariables.WebservicePort `
                                  -Credential $SMACred
        $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

        if(Test-IsNullOrEmpty $Runbook.RunbookID.Guid)
        {
            Write-Verbose -Message "[$WorkflowName] Initial Import"
            
            $Runbook = Import-SmaRunbook -Path $FilePath `
                                         -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                         -Port $CIVariables.WebservicePort `
                                         -Credential $SMACred
            
            $TagLine = "RepositoryName:$RepositoryName;CurrentCommit:$CurrentCommit;"
            $NewVersion = $True
        }
        else
        {
            Write-Verbose -Message "[$WorkflowName] Update"
            $TagUpdateJSON = New-SmaChangesetTagLine -TagLine $Runbook.Tags `
                                                     -CurrentCommit $CurrentCommit `
                                                     -RepositoryName $RepositoryName
            $TagUpdate = ConvertFrom-Json $TagUpdateJSON
            $TagLine = $TagUpdate.TagLine
            $NewVersion = $TagUpdate.NewVersion
            if($NewVersion)
            {
                $EditStatus = Edit-SmaRunbook -Overwrite `
                                              -Path $FilePath `
                                              -Name $WorkflowName `
                                              -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                              -Port $CIVariables.WebservicePort `
                                              -Credential $SMACred                
            }
            else
            {
                Write-Verbose -Message "[$WorkflowName] Already is at commit [$CurrentCommit]"
            }
        }
        if($NewVersion)
        {
            $PublishHolder = Publish-SmaRunbook -Name $WorkflowName `
                                                -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                                -Port $CIVariables.WebservicePort `
                                                -Credential $SMACred

            Set-SmaRunbookTags -RunbookID $Runbook.RunbookID.Guid `
                               -Tags $TagLine `
                               -WebserviceEndpoint $CIVariables.WebserviceEndpoint `
                               -Port $CIVariables.WebservicePort `
                               -Credential $SMACred
        }
    }
    Catch
    {
        Write-Exception -Stream Warning -Exception $_
    }
    Write-Verbose -Message "[$FilePath] Finished [$WorkflowCommandName]"
}
<#
.Synopsis
    Takes a json file and publishes all schedules and variables from it into SMA
    
.Parameter FilePath
    The path to the settings file to process

.Parameter CurrentCommit
    The current commit to tag the variables and schedules with

.Parameter RepositoryName
    The Repository Name that will 'own' the variables and schedules
#>
Function Publish-SMASettingsFileChange
{
    Param( 
        [Parameter(Mandatory = $True)]
        [String] 
        $FilePath,
        
        [Parameter(Mandatory = $True)]
        [String]
        $CurrentCommit,

        [Parameter(Mandatory = $True)]
        [String]
        $RepositoryName
    )
    
    Write-Verbose -Message "[$FilePath] Starting [$WorkflowCommandName]"
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    $CIVariables = Get-BatchAutomationVariable -Name @('SMACredName', 
                                                       'WebserviceEndpoint'
                                                       'WebservicePort') `
                                               -Prefix 'SMAContinuousIntegration'
    $SMACred = Get-AutomationPSCredential -Name $CIVariables.SMACredName

    Try
    {
        $VariablesJSON = Get-SmaGlobalFromFile -FilePath $FilePath -GlobalType Variables
        $Variables = ConvertFrom-PSCustomObject -InputObject (ConvertFrom-Json -InputObject $VariablesJSON)
        foreach($VariableName in $Variables.Keys)
        {
            Try
            {
                Write-Verbose -Message "[$VariableName] Updating"
                $Variable = $Variables."$VariableName"
                $ErrorActionPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
                $SmaVariable = Get-SmaVariable -Name $VariableName `
                                               -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                               -Port $CIVariables.WebservicePort `
                                               -Credential $SMACred
                $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
                if(Test-IsNullOrEmpty -String $SmaVariable.VariableId.Guid)
                {
                    Write-Verbose -Message "[$($VariableName)] is a New Variable"
                    $VariableDescription = "$($Variable.Description)`n`r__RepositoryName:$($RepositoryName);CurrentCommit:$($CurrentCommit);__"
                    $NewVersion = $True
                }
                else
                {
                    Write-Verbose -Message "[$($VariableName)] is an existing Variable"
                    $TagUpdateJSON = New-SmaChangesetTagLine -TagLine $SmaVariable.Description`
                                                             -CurrentCommit $CurrentCommit `
                                                             -RepositoryName $RepositoryName
                    $TagUpdate = ConvertFrom-Json -InputObject $TagUpdateJSON
                    $VariableDescription = "$($TagUpdate.TagLine)"
                    $NewVersion = $TagUpdate.NewVersion
                }
                if($NewVersion)
                {
                    $SmaVariableParameters = @{
                        'Name' = $VariableName ;
                        'Value' = $Variable.Value ;
                        'Description' = $VariableDescription ;
                        'WebServiceEndpoint' = $CIVariables.WebserviceEndpoint ;
                        'Port' = $CIVariables.WebservicePort ;
                        'Credential' = $SMACred ;
                        'Force' = $True ;
                    }
                    if(ConvertTo-Boolean -InputString $Variable.isEncrypted)
                    {
                        $CreateEncryptedVariable = Set-SmaVariable @SmaVariableParameters `
                                                                   -Encrypted
                    }
                    else
                    {
                        $CreateEncryptedVariable = Set-SmaVariable @SmaVariableParameters
                    }
                }
                else
                {
                    Write-Verbose -Message "[$($VariableName)] Is not a new version. Skipping"
                }
                Write-Verbose -Message "[$($VariableName)] Finished Updating"
            }
            Catch
            {
                $Exception = New-Exception -Type 'VariablePublishFailure' `
                                           -Message 'Failed to publish a variable to SMA' `
                                           -Property @{
                    'ErrorMessage' = Convert-ExceptionToString $_ ;
                    'VariableName' = $VariableName ;
                }
                Write-Warning -Message $Exception -WarningAction Continue
            }
        }
        $SchedulesJSON = Get-SmaGlobalFromFile -FilePath $FilePath -GlobalType Schedules
        $Schedules = ConvertFrom-PSCustomObject -InputObject (ConvertFrom-Json -InputObject $SchedulesJSON)
        foreach($ScheduleName in $Schedules.Keys)
        {
            Write-Verbose -Message "[$ScheduleName] Updating"
            try
            {
                $Schedule = $Schedules."$ScheduleName"
                $ErrorActionPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
                $SmaSchedule = Get-SmaSchedule -Name $ScheduleName `
                                               -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                               -Port $CIVariables.WebservicePort `
                                               -Credential $SMACred
                $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
                if(Test-IsNullOrEmpty -String $SmaSchedule.ScheduleId.Guid)
                {
                    Write-Verbose -Message "[$($ScheduleName)] is a New Schedule"
                    $ScheduleDescription = "$($Schedule.Description)`n`r__RepositoryName:$($RepositoryName);CurrentCommit:$($CurrentCommit);__"
                    $NewVersion = $True
                }
                else
                {
                    Write-Verbose -Message "[$($ScheduleName)] is an existing Schedule"
                    $TagUpdateJSON = New-SmaChangesetTagLine -TagLine $SmaVariable.Description`
                                                         -CurrentCommit $CurrentCommit `
                                                         -RepositoryName $RepositoryName
                    $TagUpdate = ConvertFrom-Json -InputObject $TagUpdateJSON
                    $ScheduleDescription = "$($TagUpdate.TagLine)"
                    $NewVersion = $TagUpdate.NewVersion
                }
                if($NewVersion)
                {
                    $CreateSchedule = Set-SmaSchedule -Name $ScheduleName `
                                                      -Description $ScheduleDescription `
                                                      -ScheduleType DailySchedule `
                                                      -DayInterval $Schedule.DayInterval `
                                                      -StartTime $Schedule.NextRun `
                                                      -ExpiryTime $Schedule.ExpirationTime `
                                                      -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                                      -Port $CIVariables.WebservicePort `
                                                      -Credential $SMACred

                    if(Test-IsNullOrEmpty -String $CreateSchedule)
                    {
                        Throw-Exception -Type 'ScheduleFailedToCreate' `
                                        -Message 'Failed to create the schedule' `
                                        -Property @{
                            'ScheduleName'     = $ScheduleName
                            'Description'      = $ScheduleDescription
                            'ScheduleType'     = 'DailySchedule'
                            'DayInterval'      = $Schedule.DayInterval
                            'StartTime'        = $Schedule.NextRun
                            'ExpiryTime'       = $Schedule.ExpirationTime
                            'WebServiceEndpoint' = $CIVariables.WebserviceEndpoint
                            'Port'             = $CIVariables.WebservicePort
                            'Credential'       = $SMACred.UserName
                        }
                    }
                    try
                    {
                        $Parameters   = ConvertFrom-PSCustomObject -InputObject $Schedule.Parameter `
                                                                   -MemberType NoteProperty `
                        $RunbookStart = Start-SmaRunbook -Name $Schedule.RunbookName `
                                                         -ScheduleName $ScheduleName `
                                                         -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                                         -Port $CIVariables.WebservicePort `
                                                         -Parameters $Parameters `
                                                         -Credential $SMACred
                        if(Test-IsNullOrEmpty -String $RunbookStart)
                        {
                            Throw-Exception -Type 'ScheduleFailedToSet' `
                                            -Message 'Failed to set the schedule on the target runbook' `
                                            -Property @{
                                'ScheduleName' = $ScheduleName
                                'RunbookName' = $Schedule.RunbookName
                                'Parameters' = $(ConvertTo-Json -InputObject $Parameters)
                            }
                        }
                    }
                    catch
                    {
                        Remove-SmaSchedule -Name $ScheduleName `
                                           -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                           -Port $CIVariables.WebservicePort `
                                           -Credential $SMACred `
                                           -Force
                        Write-Exception -Exception $_ -Stream Warning
                    }
                }
            }
            catch
            {
                Write-Exception -Exception $_ -Stream Warning
            }
            Write-Verbose -Message "[$($ScheduleName)] Finished Updating"
        }
    }
    Catch
    {
        Write-Exception -Stream Warning -Exception $_
    }
    Write-Verbose -Message "[$FilePath] Finished [$WorkflowCommandName]"
}
<#
.Synopsis
    Checks a SMA environment and removes any global assets tagged
    with the current repository that are no longer found in
    the repository

.Parameter RepositoryName
    The name of the repository
#>
Function Remove-SmaOrphanAsset
{
    Param($RepositoryName)

    Write-Verbose -Message "Starting [$WorkflowCommandName]"
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    Try
    {
        $CIVariables = Get-BatchAutomationVariable -Name @('RepositoryInformation', 
                                                       'SMACredName', 
                                                       'WebserviceEndpoint'
                                                       'WebservicePort') `
                                                   -Prefix 'SMAContinuousIntegration'
        $SMACred = Get-AutomationPSCredential -Name $CIVariables.SMACredName

        $RepositoryInformation = (ConvertFrom-Json -InputObject $CIVariables.RepositoryInformation)."$RepositoryName"

        $SmaVariables = Get-SmaVariable -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                        -Port $CIVariables.WebservicePort `
                                        -Credential $SMACred
        if($SmaVariables) 
        {
            $SmaVariableTable = Group-SmaAssetsByRepository -InputObject $SmaVariables 
        }

        $SmaSchedules = Get-SmaSchedule -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                        -Port $CIVariables.WebservicePort `
                                        -Credential $SMACred
        if($SmaSchedules) 
        {
            $SmaScheduleTable = Group-SmaAssetsByRepository -InputObject $SmaSchedules 
        }

        $RepositoryAssets = Get-GitRepositoryAssetName -Path "$($RepositoryInformation.Path)\$($RepositoryInformation.RunbookFolder)"

        if($SmaVariableTable."$RepositoryName")
        {
            $VariableDifferences = Compare-Object -ReferenceObject $SmaVariableTable."$RepositoryName".Name `
                                                  -DifferenceObject $RepositoryAssets.Variable
            Foreach($Difference in $VariableDifferences)
            {
                Try
                {
                    if($Difference.SideIndicator -eq '<=')
                    {
                        Write-Verbose -Message "[$($Difference.InputObject)] Does not exist in Source Control"
                        Remove-SmaVariable -Name $Difference.InputObject `
                                           -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                           -Port $CIVariables.WebservicePort `
                                           -Credential $SMACred
                        Write-Verbose -Message "[$($Difference.InputObject)] Removed from SMA"
                    }
                }
                Catch
                {
                    $Exception = New-Exception -Type 'RemoveSmaAssetFailure' `
                                                -Message 'Failed to remove a Sma Asset' `
                                                -Property @{
                        'ErrorMessage' = (Convert-ExceptionToString $_) ;
                        'AssetName' = $Difference.InputObject ;
                        'AssetType' = 'Variable' ;
                        'WebserviceEnpoint' = $CIVariables.WebserviceEndpoint ;
                        'Port' = $CIVariables.WebservicePort ;
                        'Credential' = $SMACred.UserName ;
                    }
                    Write-Warning -Message $Exception -WarningAction Continue
                }
            }
        }
        else
        {
            Write-Warning -Message "[$RepositoryName] No Variables found in environment for this repository" `
                          -WarningAction Continue
        }

        if($SmaScheduleTable."$RepositoryName")
        {
            $ScheduleDifferences = Compare-Object -ReferenceObject $SmaScheduleTable."$RepositoryName".Name `
                                                  -DifferenceObject $RepositoryAssets.Schedule
            Foreach($Difference in $ScheduleDifferences)
            {
                Try
                {
                    if($Difference.SideIndicator -eq '<=')
                    {
                        Write-Verbose -Message "[$($Difference.InputObject)] Does not exist in Source Control"
                        Remove-SmaSchedule -Name $Difference.InputObject `
                                           -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                           -Port $CIVariables.WebservicePort `
                                           -Credential $SMACred
                        Write-Verbose -Message "[$($Difference.InputObject)] Removed from SMA"
                    }
                }
                Catch
                {
                    $Exception = New-Exception -Type 'RemoveSmaAssetFailure' `
                                                -Message 'Failed to remove a Sma Asset' `
                                                -Property @{
                        'ErrorMessage' = (Convert-ExceptionToString $_) ;
                        'AssetName' = $Difference.InputObject ;
                        'AssetType' = 'Schedule' ;
                        'WebserviceEnpoint' = $CIVariables.WebserviceEndpoint ;
                        'Port' = $CIVariables.WebservicePort ;
                        'Credential' = $SMACred.UserName ;
                    }
                    Write-Exception -Exception $Exception -Stream Warning
                }
            }
        }
        else
        {
            Write-Warning -Message "[$RepositoryName] No Schedules found in environment for this repository" `
                          -WarningAction Continue
        }
    }
    Catch
    {
        $Exception = New-Exception -Type 'RemoveSmaOrphanAssetWorkflowFailure' `
                                   -Message 'Unexpected error encountered in the Remove-SmaOrphanAsset workflow' `
                                   -Property @{
            'ErrorMessage' = (Convert-ExceptionToString $_) ;
            'RepositoryName' = $RepositoryName ;
        }
        Write-Exception -Exception $Exception -Stream Warning
    }
    Write-Verbose -Message "Finished [$WorkflowCommandName]"
}
<#
    .Synopsis
        Checks a SMA environment and removes any modules that are not found
        in the local psmodulepath
#>
Function Remove-SmaOrphanModule
{
    Write-Verbose -Message "Starting [$WorkflowCommandName]"
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    Try
    {
        $CIVariables = Get-BatchAutomationVariable -Name @('SMACredName',
                                                       'WebserviceEndpoint'
                                                       'WebservicePort') `
                                               -Prefix 'SMAContinuousIntegration'
        $SMACred = Get-AutomationPSCredential -Name $CIVariables.SMACredName

        $SmaModule = Get-SmaModule -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                   -Port $CIVariables.WebservicePort `
                                   -Credential $SMACred

        $LocalModule = Get-Module -ListAvailable -Refresh -Verbose:$false

        if(-not ($SmaModule -and $LocalModule))
        {
            if(-not $SmaModule)   { Write-Warning -Message 'No modules found in SMA. Not cleaning orphan modules' }
            if(-not $LocalModule) { Write-Warning -Message 'No modules found in local PSModule Path. Not cleaning orphan modules' }
        }
        else
        {
            $ModuleDifference = Compare-Object -ReferenceObject  $SmaModule.ModuleName `
                                               -DifferenceObject $LocalModule.Name
            Foreach($Difference in $ModuleDifference)
            {
                if($Difference.SideIndicator -eq '<=')
                {
                    Try
                    {
                        Write-Verbose -Message "[$($Difference.InputObject)] Does not exist in Source Control"
                        <#
                        TODO: Investigate / Test before uncommenting. Potential to brick an environment

                        Remove-SmaModule -Name $Difference.InputObject `
                                         -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                         -Port $CIVariables.WebservicePort `
                                         -Credential $SMACred
                        #>
                        Write-Verbose -Message "[$($Difference.InputObject)] Removed from SMA"
                    }
                    Catch
                    {
                        $Exception = New-Exception -Type 'RemoveSmaModuleFailure' `
                                                   -Message 'Failed to remove a Sma Module' `
                                                   -Property @{
                            'ErrorMessage' = (Convert-ExceptionToString $_) ;
                            'RunbookName' = $Difference.InputObject ;
                            'WebserviceEnpoint' = $CIVariables.WebserviceEndpoint ;
                            'Port' = $CIVariables.WebservicePort ;
                            'Credential' = $SMACred.UserName ;
                        }
                        Write-Warning -Message $Exception -WarningAction Continue
                    }
                }
            }
        }
    }
    Catch
    {
        $Exception = New-Exception -Type 'RemoveSmaOrphanModuleWorkflowFailure' `
                                   -Message 'Unexpected error encountered in the Remove-SmaOrphanModule workflow' `
                                   -Property @{
            'ErrorMessage' = (Convert-ExceptionToString $_) ;
            'RepositoryName' = $RepositoryName ;
        }
        Write-Exception -Exception $Exception -Stream Warning
    }
    
    Write-Verbose -Message "Finished [$WorkflowCommandName]"
}
<#
    .Synopsis
        Checks a SMA environment and removes any runbooks tagged
        with the current repository that are no longer found in
        the repository

    .Parameter RepositoryName
        The name of the repository
#>
Function Remove-SmaOrphanRunbook
{
    Param($RepositoryName)

    Write-Verbose -Message "Starting [$WorkflowCommandName]"
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    Try
    {
        $CIVariables = Get-BatchAutomationVariable -Name @('RepositoryInformation',
                                                           'SMACredName',
                                                           'WebserviceEndpoint'
                                                           'WebservicePort') `
                                                   -Prefix 'SMAContinuousIntegration'
        $SMACred = Get-AutomationPSCredential -Name $CIVariables.SMACredName

        $RepositoryInformation = (ConvertFrom-JSON -InputObject $CIVariables.RepositoryInformation)."$RepositoryName"

        $SmaRunbooks = Get-SMARunbookPaged -WebserviceEndpoint $CIVariables.WebserviceEndpoint `
                                           -Port $CIVariables.WebservicePort `
                                           -Credential $SMACred
        if($SmaRunbooks) { $SmaRunbookTable = Group-SmaRunbooksByRepository -InputObject $SmaRunbooks }
        $RepositoryWorkflows = Get-GitRepositoryWorkflowName -Path "$($RepositoryInformation.Path)\$($RepositoryInformation.RunbookFolder)"
        $Differences = Compare-Object -ReferenceObject $SmaRunbookTable.$RepositoryName.RunbookName `
                                      -DifferenceObject $RepositoryWorkflows
    
        Foreach($Difference in $Differences)
        {
            if($Difference.SideIndicator -eq '<=')
            {
                Try
                {
                    Write-Verbose -Message "[$($Difference.InputObject)] Does not exist in Source Control"
                    Remove-SmaRunbook -Name $Difference.InputObject `
                                      -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                      -Port $CIVariables.WebservicePort `
                                      -Credential $SMACred
                    Write-Verbose -Message "[$($Difference.InputObject)] Removed from SMA"
                }
                Catch
                {
                    $Exception = New-Exception -Type 'RemoveSmaRunbookFailure' `
                                               -Message 'Failed to remove a Sma Runbook' `
                                               -Property @{
                        'ErrorMessage' = (Convert-ExceptionToString $_) ;
                        'RunbookName' = $Difference.InputObject ;
                        'WebserviceEnpoint' = $CIVariables.WebserviceEndpoint ;
                        'Port' = $CIVariables.WebservicePort ;
                        'Credential' = $SMACred.UserName ;
                    }
                    Write-Warning -Message $Exception -WarningAction Continue
                }
            }
        }
    }
    Catch
    {
        $Exception = New-Exception -Type 'RemoveSmaOrphanRunbookWorkflowFailure' `
                                   -Message 'Unexpected error encountered in the Remove-SmaOrphanRunbook workflow' `
                                   -Property @{
            'ErrorMessage' = (Convert-ExceptionToString $_) ;
            'RepositoryName' = $RepositoryName ;
        }
        Write-Exception -Exception $Exception -Stream Warning
    }
    Write-Verbose -Message "Finished [$WorkflowCommandName]"
}

<#
    .SYNOPSIS
    Returns $true if working in a local development environment, $false otherwise.
#>
function Test-LocalDevelopment
{
    $LocalDevModule = Get-Module -ListAvailable -Name 'LocalDev' -Verbose:$False -ErrorAction 'SilentlyContinue' -WarningAction 'SilentlyContinue'
    if($LocalDevModule -ne $Null)
    {
        return $True
    }
    return $False
}

Function Get-BatchAutomationVariable
{
    Param(
        [Parameter(Mandatory = $True)]
        [String[]]
        $Name,

        [Parameter(Mandatory = $False)]
        [AllowNull()]
        [String]
        $Prefix = $Null
    )
    $Variables = @{}
    
    ForEach($VarName in $Name)
    {
        If(-not [String]::IsNullOrEmpty($Prefix))
        {
            $Variables[$VarName] = (Get-AutomationVariable -Name "$Prefix-$VarName").Value
        }
        Else
        {
            $Variables[$VarName] = (Get-AutomationVariable -Name $VarName).Value
        }
        
        Write-Verbose -Message "Variable [$VarName / $SMAVarName] = [$($Variables[$VarName])]"
    }
    Return (New-Object -TypeName 'PSObject' -Property $Variables)
}

Function Get-AzureAutomationHybridRunbookWorker
{
    Param(
        [Parameter(Mandatory = $True)]
        [String[]]
        $Name
    )
    
    Return @($Env:ComputerName) -as [array]
}
Export-ModuleMember -Function * -Verbose:$false