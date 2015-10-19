#requires -Version 3 -Modules SCOrchDev-Exception, SCOrchDev-GitIntegration, SCOrchDev-Utility
<#
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
Function Publish-AzureAutomationRunbookChange
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
        $RepositoryName,

        [Parameter(Mandatory = $True)]
        [PSCredential]
        $Credential,

        [Parameter(Mandatory = $True)]
        [String]
        $AutomationAccountName,

        [Parameter(Mandatory = $True)]
        [String]
        $SubscriptionName,

        [Parameter(Mandatory = $True)]
        [String]
        $ResourceGroupName
    )
    $CompletedParams = Write-StartingMessage -String $FilePath
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    Try
    {
        $Null = Add-AzureRmAccount -Credential $Credential -SubscriptionName $SubscriptionName

        if(Test-FileIsWorkflow -FilePath $FilePath)
        {
            $Name = Get-WorkflowNameFromFile -FilePath $FilePath
            $Type = 'PowerShellWorkflow'
        }
        else
        {
            $Name = Get-ScriptNameFromFileName -FilePath $FilePath
            $Type = 'PowerShell'
        }
        $ErrorActionPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
        $Runbook = Get-AzureRmAutomationRunbook -Name $Name `
                                                -AutomationAccountName $AutomationAccountName `
                                                -ResourceGroupName $ResourceGroupName
        $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

        if($Runbook -as [bool])
        {
            Write-Verbose -Message "[$Name] Update"
            $TagUpdateJSON = New-ChangesetTagLine -TagLine ($Runbook.Tags -join ';') `
                                                  -CurrentCommit $CurrentCommit `
                                                  -RepositoryName $RepositoryName
            $TagUpdate = ConvertFrom-Json -InputObject $TagUpdateJSON
            $TagLine = $TagUpdate.TagLine

            $NewVersion = $TagUpdate.NewVersion
            if(-not ($NewVersion -as [bool]))
            {
                Write-Verbose -Message "[$Name] Already is at commit [$CurrentCommit]"
            }
        }
        else
        {
            Write-Verbose -Message "[$Name] Initial Import"
            
            $TagLine = "RepositoryName:$RepositoryName;CurrentCommit:$CurrentCommit;"
            $Tags = @{}
            Foreach($Tag in $TagLine.Split(';')) { $Null = $Tags.Add($Tag.Split(':')[0],$Tag.Split(':')[1]) }
            $Null = New-AzureRmAutomationRunbook -Name $Name `
                                                     -Tags $Tags `
                                                     -Type $Type `
                                                     -ResourceGroupName $ResourceGroupName `
                                                     -AutomationAccountName $AutomationAccountName
            $NewVersion = $True
        }
        if($NewVersion)
        {
            $Tags = @{}
            Foreach($Tag in $TagLine.Split(';')) { $Null = $Tags.Add($Tag.Split(':')[0],$Tag.Split(':')[1]) }
            $Null = Import-AzureRmAutomationRunbook -Path $FilePath `
                                                    -Tags $Tags `
                                                    -Name $Name `
                                                    -Type $Type `
                                                    -AutomationAccountName $AutomationAccountName `
                                                    -ResourceGroupName $ResourceGroupName
            $Null = Publish-AzureRmAutomationRunbook -Name $Name `
                                                     -AutomationAccountName $AutomationAccountName `
                                                     -ResourceGroupName $ResourceGroupName
        }
    }
    Catch
    {
        $ErrorActionPreference = 'Stop'
        $Exception = $_
        $ExceptionInfo = Get-ExceptionInfo -Exception $Exception
        Switch ($Exception.FullyQualifiedErrorId)
        {
            'Microsoft.Azure.Commands.Automation.Common.ResourceCommonException,Microsoft.Azure.Commands.Automation.Cmdlet.GetAzureAutomationRunbook'
            {
                Write-Verbose -Message "[$Name] Initial Import"
            
                $TagLine = "RepositoryName:$RepositoryName;CurrentCommit:$CurrentCommit;"
                $Tags = @{}
                Foreach($Tag in $TagLine.Split(';')) { $Null = $Tags.Add($Tag.Split(':')[0],$Tag.Split(':')[1]) }
                $Null = New-AzureRmAutomationRunbook -Name $Name `
                                                     -Tags $Tags `
                                                     -Type $Type `
                                                     -ResourceGroupName $ResourceGroupName `
                                                     -AutomationAccountName $AutomationAccountName

                $Null = Import-AzureRmAutomationRunbook -Path $FilePath `
                                                        -Tags $Tags `
                                                        -Name $Name `
                                                        -Type $Type `
                                                        -AutomationAccountName $AutomationAccountName `
                                                        -ResourceGroupName $ResourceGroupName
                
                $Null = Publish-AzureRmAutomationRunbook -Name $Name `
                                                         -AutomationAccountName $AutomationAccountName `
                                                         -ResourceGroupName $ResourceGroupName
            }
            Default
            {
                Write-Exception -Stream Warning -Exception $_
            }
        }
    }

    Write-CompletedMessage @CompletedParams
}
<#
.Synopsis
    Takes a json file and publishes all schedules and variables from it into Azure Automation
    
.Parameter FilePath
    The path to the settings file to process

.Parameter CurrentCommit
    The current commit to tag the variables and schedules with

.Parameter RepositoryName
    The Repository Name that will 'own' the variables and schedules
#>
Function Publish-AzureAutomationSettingsFileChange
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
        $RepositoryName,

        [Parameter(Mandatory = $True)]
        [PSCredential]
        $Credential,

        [Parameter(Mandatory = $True)]
        [String]
        $AutomationAccountName,

        [Parameter(Mandatory = $True)]
        [String]
        $SubscriptionName,

        [Parameter(Mandatory = $True)]
        [String]
        $ResourceGroupName
    )
    
    $CompletedParams = Write-StartingMessage -String $FilePath
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    Try
    {
        $Null = Add-AzureRmAccount -Credential $Credential -SubscriptionName $SubscriptionName

        $VariablesJSON = Get-GlobalFromFile -FilePath $FilePath -GlobalType Variables
        $Variables = $VariablesJSON | ConvertFrom-JSON | ConvertFrom-PSCustomObject
        foreach($VariableName in $Variables.Keys)
        {
            Try
            {
                Write-Verbose -Message "[$VariableName] Updating"
                $Variable = $Variables."$VariableName"
                $AzureAutomationVariable = Get-AzureRmAutomationVariable -Name $VariableName `
                                                                         -AutomationAccountName $AutomationAccountName `
                                                                         -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
                if($AzureAutomationVariable -as [bool])
                {
                    Write-Verbose -Message "[$($VariableName)] is an existing Variable"
                    $TagUpdateJSON = New-ChangesetTagLine -TagLine $AzureAutomationVariable.Description`
                                                          -CurrentCommit $CurrentCommit `
                                                          -RepositoryName $RepositoryName
                    $TagUpdate = $TagUpdateJSON | ConvertFrom-Json
                    $VariableDescription = "$($TagUpdate.TagLine)"
                    $NewVersion = $TagUpdate.NewVersion
                    $NewVariable = $False
                }
                else
                {
                    Write-Verbose -Message "[$($VariableName)] is a New Variable"
                    $VariableDescription = "$($Variable.Description)`n`r__RepositoryName:$($RepositoryName);CurrentCommit:$($CurrentCommit);__"
                    $NewVersion = $True
                    $NewVariable = $True
                }
                if($NewVersion)
                {
                    $VariableParameters = @{
                        'Name' = $VariableName
                        'Value' = $Variable.Value
                        'Encrypted' = $Variable.isEncrypted
                        'AutomationAccountName' = $AutomationAccountName
                        'ResourceGroupName' = $ResourceGroupName
                        'Description' = $VariableDescription
                    }
                    if($NewVariable)
                    {
                        $Null = New-AzureRmAutomationVariable @VariableParameters
                    }
                    else
                    {
                        $Null = Set-AzureRmAutomationVariable @VariableParameters
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
                $Exception = $_
                $ExceptionInfo = Get-ExceptionInfo -Exception $Exception
                Switch ($ExceptionInfo.FullyQualifiedErrorId)
                {
                    'Microsoft.Azure.Commands.Automation.Common.ResourceNotFoundException,Microsoft.Azure.Commands.Automation.Cmdlet.GetAzureAutomationVariable'
                    {
                        Write-Verbose -Message "[$($VariableName)] is a New Variable"
                        $VariableDescription = "$($Variable.Description)`n`r__RepositoryName:$($RepositoryName);CurrentCommit:$($CurrentCommit);__"
                        $VariableParameters = @{
                            'Name' = $VariableName
                            'Value' = $Variable.Value
                            'Encrypted' = $Variable.isEncrypted
                            'AutomationAccountName' = $AutomationAccountName
                            'ResourceGroupName' = $ResourceGroupName
                            'Description' = $VariableDescription
                        }
                        $Null = New-AzureRmAutomationVariable @VariableParameters
                    }
                    Default
                    {
                        Write-Exception -Exception $Exception -Stream Warning
                    }
                }
            }
        }
        $SchedulesJSON = Get-GlobalFromFile -FilePath $FilePath -GlobalType Schedules
        $Schedules = $SchedulesJSON | ConvertFrom-JSON | ConvertFrom-PSCustomObject
        foreach($ScheduleName in $Schedules.Keys)
        {
            Write-Verbose -Message "[$ScheduleName] Updating"
            try
            {
                $Schedule = $Schedules."$ScheduleName"
                $ErrorActionPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
                $AzureAutomationSchedule = Get-AzureRmAutomationSchedule -Name $ScheduleName `
                                                                        -AutomationAccountName $AutomationAccountName `
                                                                        -ResourceGroupName $ResourceGroupName
                $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
                if($AzureAutomationSchedule -as [bool])
                {
                    Write-Verbose -Message "[$($ScheduleName)] is an existing Schedule"
                    $TagUpdateJSON = New-ChangesetTagLine -TagLine $Schedule.Description`
                                                          -CurrentCommit $CurrentCommit `
                                                          -RepositoryName $RepositoryName
                    $TagUpdate = ConvertFrom-Json -InputObject $TagUpdateJSON
                    $ScheduleDescription = "$($TagUpdate.TagLine)"
                    $NewVersion = $TagUpdate.NewVersion
                    if($NewVersion)
                    {
                        Write-Verbose -Message "[$($ScheduleName)] is an Updated Schedule. Deleting to re-create"
                        Remove-AzureRmAutomationSchedule -Name $ScheduleName `
                                                         -Force `
                                                         -AutomationAccountName $AutomationAccountName `
                                                         -ResourceGroupName $ResourceGroupName
                    }
                }
                else
                {
                    Write-Verbose -Message "[$($ScheduleName)] is a New Schedule"
                    $ScheduleDescription = "$($Schedule.Description)`n`r__RepositoryName:$($RepositoryName);CurrentCommit:$($CurrentCommit);__"
                    
                    $NewVersion = $True
                }
                if($NewVersion)
                {
                    $CreateSchedule = New-AzureRmAutomationSchedule -Name $ScheduleName `
                                                                    -Description $ScheduleDescription `
                                                                    -DayInterval $Schedule.DayInterval `
                                                                    -StartTime $Schedule.NextRun `
                                                                    -ExpiryTime $Schedule.ExpirationTime `
                                                                    -AutomationAccountName $AutomationAccountName `
                                                                    -ResourceGroupName $ResourceGroupName
                    if(-not ($CreateSchedule -as [bool]))
                    {
                        Throw-Exception -Type 'ScheduleFailedToCreate' `
                                        -Message 'Failed to create the schedule' `
                                        -Property @{
                            'ScheduleName'     = $ScheduleName
                            'Description'      = $ScheduleDescription
                            'DayInterval'      = $Schedule.DayInterval
                            'StartTime'        = $Schedule.NextRun
                            'ExpiryTime'       = $Schedule.ExpirationTime
                            'AutomationAccountName' = $AutomationAccountName
                        }
                    }
                }
            }
            catch
            {
                $Exception = $_
                $ExceptionInfo = Get-ExceptionInfo -Exception $Exception
                Switch ($Exception.FullyQualifiedErrorId)
                {
                    'Microsoft.Azure.Commands.Automation.Common.ResourceNotFoundException,Microsoft.Azure.Commands.Automation.Cmdlet.GetAzureAutomationVariable'
                    {
                        Write-Verbose -Message "[$Name] Initial Import"
            
                        Write-Verbose -Message "[$($ScheduleName)] is a New Schedule"
                        $ScheduleDescription = "$($Schedule.Description)`n`r__RepositoryName:$($RepositoryName);CurrentCommit:$($CurrentCommit);__"
                    
                        $NewVersion = $True
                    }
                    Default
                    {
                        Write-Exception -Stream Warning -Exception $_
                    }
                }
                Write-Exception -Exception $_ -Stream Warning
            }
            try
            {
                $Parameters = ConvertFrom-PSCustomObject -InputObject $Schedule.Parameter `
                                                            -MemberType NoteProperty
                $Register = Register-AzureRmAutomationScheduledRunbook -AutomationAccountName $AutomationAccountName `
                                                                        -RunbookName $Schedule.RunbookName `
                                                                        -ScheduleName $ScheduleName `
                                                                        -Parameters $Parameters `
                                                                        -ResourceGroupName $ResourceGroupName
                if(-not($Register -as [bool]))
                {
                    Throw-Exception -Type 'ScheduleFailedToSet' `
                                    -Message 'Failed to set the schedule on the target runbook' `
                                    -Property @{
                        'ScheduleName' = $ScheduleName ;
                        'RunbookName' = $Schedule.RunbookName ;
                        'Parameters' = $(ConvertTo-Json -InputObject $Parameters) ;
                        'AutomationAccountName' = $AutomationAccountName
                    }
                }
            }
            catch
            {
                $ErrorActionPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
                Remove-AzureRmAutomationSchedule -Name $ScheduleName `
                                                    -Force `
                                                    -AutomationAccountName $AutomationAccountName `
                                                    -ResourceGroupName $ResourceGroupName
                $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
                Write-Exception -Exception $_ -Stream Warning
            }
            Write-Verbose -Message "[$($ScheduleName)] Finished Updating"
        }
    }
    Catch
    {
        Write-Exception -Stream Warning -Exception $_
    }
    Write-CompletedMessage @CompletedParams
}
<#
.Synopsis
    Checks an Azure Automation environment and removes any global assets tagged
    with the current repository that are no longer found in
    the repository

.Parameter RepositoryName
    The name of the repository
#>
Function Remove-AzureAutomationOrphanAsset
{
    Param(
        [Parameter(Mandatory = $True)]
        [String]
        $RepositoryName,

        [Parameter(Mandatory = $True)]
        [PSCredential]
        $Credential,

        [Parameter(Mandatory = $True)]
        [String]
        $AutomationAccountName,

        [Parameter(Mandatory = $True)]
        [String]
        $ResourceGroupName,

        [Parameter(Mandatory = $True)]
        [String]
        $SubscriptionName,

        [Parameter(Mandatory = $True)]
        [PSCustomObject] 
        $RepositoryInformation
    )

    $CompletedParams = Write-StartingMessage
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    Try
    {
        $Null = Add-AzureRmAccount -Credential $Credential -SubscriptionName $SubscriptionName

        $AzureAutomationVariables = Get-AzureRmAutomationVariable -AutomationAccountName $AutomationAccountName `
                                                                  -ResourceGroupName $ResourceGroupName
        if($AzureAutomationVariables) 
        {
            $AzureAutomationVariables = Group-AssetsByRepository -InputObject $AzureAutomationVariables 
        }

        $RepositoryAssets = Get-GitRepositoryAssetName -Path "$($RepositoryInformation.Path)\$($RepositoryInformation.GlobalsFolder)"

        if($AzureAutomationVariables."$RepositoryName")
        {
            $VariableDifferences = Compare-Object -ReferenceObject $AzureAutomationVariables."$RepositoryName".Name `
                                                  -DifferenceObject $RepositoryAssets.Variable
            Foreach($Difference in $VariableDifferences)
            {
                Try
                {
                    if($Difference.SideIndicator -eq '<=')
                    {
                        Write-Verbose -Message "[$($Difference.InputObject)] Does not exist in Source Control"
                        Remove-AzureRmAutomationVariable -Name $Difference.InputObject `
                                                         -AutomationAccountName $AutomationAccountName `
                                                         -ResourceGroupName $ResourceGroupName `
                                                         -Force
                        Write-Verbose -Message "[$($Difference.InputObject)] Removed from Azure Automation"
                    }
                }
                Catch
                {
                    $Exception = New-Exception -Type 'RemoveAzureAutomationAssetFailure' `
                                                -Message 'Failed to remove an Azure Automation Asset' `
                                                -Property @{
                        'ErrorMessage' = (Convert-ExceptionToString -Exception $_) ;
                        'AssetName' = $Difference.InputObject ;
                        'AssetType' = 'Variable' ;
                        'AutomationAccountName' = $AutomationAccountName ;
                        'RepositoryName' = $RepositoryName ;
                    }
                    Write-Warning -Message $Exception -WarningAction Continue
                }
            }
        }
        else
        {
            Write-Verbose -Message "[$RepositoryName] No Variables found in environment for this repository"
        }

        $AzureAutomationSchedules = Get-AzureRmAutomationSchedule -AutomationAccountName $AutomationAccountName `
                                                                  -ResourceGroupName $ResourceGroupName
        if($AzureAutomationSchedules) 
        {
            $AzureAutomationSchedules = Group-AssetsByRepository -InputObject $AzureAutomationSchedules 
        }

        if($AzureAutomationSchedules."$RepositoryName")
        {
            $ScheduleDifferences = Compare-Object -ReferenceObject $AzureAutomationSchedules."$RepositoryName".Name `
                                                  -DifferenceObject $RepositoryAssets.Schedule
            Foreach($Difference in $ScheduleDifferences)
            {
                Try
                {
                    if($Difference.SideIndicator -eq '<=')
                    {
                        Write-Verbose -Message "[$($Difference.InputObject)] Does not exist in Source Control"
                        Remove-AzureRmAutomationSchedule -Name $Difference.InputObject `
                                                         -AutomationAccountName $AutomationAccountName `
                                                         -ResourceGroupName $ResourceGroupName `
                                                         -Force
                        Write-Verbose -Message "[$($Difference.InputObject)] Removed from Azure Automation"
                    }
                }
                Catch
                {
                    $Exception = New-Exception -Type 'RemoveAzureAutomationAssetFailure' `
                                                -Message 'Failed to remove an Azure Automation Asset' `
                                                -Property @{
                        'ErrorMessage' = (Convert-ExceptionToString -Exception $_) ;
                        'AssetName' = $Difference.InputObject ;
                        'AssetType' = 'Schedule' ;
                        'AutomationAccountName' = $AutomationAccountName ;
                        'RepositoryName' = $RepositoryName ;
                    }
                    Write-Warning -Message $Exception -WarningAction Continue
                }
            }
        }
        else
        {
            Write-Verbose -Message "[$RepositoryName] No Schedules found in environment for this repository"
        }
    }
    Catch
    {
        $Exception = New-Exception -Type 'RemoveAzureAutomationOrphanAssetWorkflowFailure' `
                                   -Message 'Unexpected error encountered in the Remove-AzureAutomationOrphanAsset workflow' `
                                   -Property @{
            'ErrorMessage' = (Convert-ExceptionToString -Exception $_) ;
            'RepositoryName' = $RepositoryName ;
        }
        Write-Exception -Exception $Exception -Stream Warning
    }
    Write-CompletedMessage @CompletedParams
}

<#
    .Synopsis
        Checks an Azure Automation environment and removes any runbooks tagged
        with the current repository that are no longer found in
        the repository

    .Parameter RepositoryName
        The name of the repository
#>
Function Remove-AzureAutomationOrphanRunbook
{
    Param(
        [Parameter(Mandatory = $True)]
        [String]
        $RepositoryName,

        [Parameter(Mandatory = $True)]
        [PSCredential]
        $Credential,

        [Parameter(Mandatory = $True)]
        [String]
        $AutomationAccountName,

        [Parameter(Mandatory = $True)]
        [String]
        $ResourceGroupName,

        [Parameter(Mandatory = $True)]
        [String]
        $SubscriptionName,

        [Parameter(Mandatory = $True)]
        [PSCustomObject] 
        $RepositoryInformation
    )

    $CompletedParams = Write-StartingMessage
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    Try
    {
        $Null = Add-AzureRmAccount -Credential $Credential -SubscriptionName $SubscriptionName

        $AzureAutomationRunbooks = Get-AzureRmAutomationRunbook -AutomationAccountName $AutomationAccountName `
                                                                -ResourceGroupName $ResourceGroupName
        if($AzureAutomationRunbooks) 
        {
            $AzureAutomationRunbooks = Group-RunbooksByRepository -InputObject $AzureAutomationRunbooks 
        }

        $RepositoryWorkflows = Get-GitRepositoryWorkflowName -Path "$($RepositoryInformation.Path)\$($RepositoryInformation.RunbookFolder)"
        $Differences = Compare-Object -ReferenceObject $AzureAutomationRunbooks.$RepositoryName.Name `
                                      -DifferenceObject $RepositoryWorkflows
    
        Foreach($Difference in $Differences)
        {
            if($Difference.SideIndicator -eq '<=')
            {
                Try
                {
                    Write-Verbose -Message "[$($Difference.InputObject)] Does not exist in Source Control"
                    Remove-AzureRmAutomationRunbook -Name $Difference.InputObject `
                                                    -AutomationAccountName $AutomationAccountName `
                                                    -ResourceGroupName $ResourceGroupName `
                                                    -Force
                    Write-Verbose -Message "[$($Difference.InputObject)] Removed from Azure Automation"
                }
                Catch
                {
                    $Exception = New-Exception -Type 'RemoveAzureAutomationRunbookFailure' `
                                                -Message 'Failed to remove a Azure Automation Runbook' `
                                                -Property @{
                        'ErrorMessage' = (Convert-ExceptionToString -Exception $_) ;
                        'Name' = $Difference.InputObject ;
                        'AutomationAccount' = $AutomationAccountName ;
                    }
                    Write-Warning -Message $Exception -WarningAction Continue
                }
            }
        }
    }
    Catch
    {
        $Exception = New-Exception -Type 'RemoveAzureAutomationOrphanRunbookWorkflowFailure' `
                                   -Message 'Unexpected error encountered in the Remove-AzureAutomationOrphanRunbook workflow' `
                                   -Property @{
            'ErrorMessage' = (Convert-ExceptionToString -Exception $_) ;
            'RepositoryName' = $RepositoryName ;
        }
        Write-Exception -Exception $Exception -Stream Warning
    }
    Write-CompletedMessage @CompletedParams
}

<#
    .SYNOPSIS
    Returns $true if working in a local development environment, $false otherwise.
#>
function Test-LocalDevelopment
{
    $LocalDevModule = Get-Module -ListAvailable -Name 'LocalDev' -Verbose:$False -ErrorAction 'SilentlyContinue' -WarningAction 'SilentlyContinue'
    if($Null -ne $LocalDevModule -and ($env:LocalAuthoring -ne $False))
    {
        return $True
    }
    return $False
}

<#
.SYNOPSIS
    Gets one or more automation variable values from the given web service endpoint.

.DESCRIPTION
    Get-BatchAutomationVariable gets the value of each variable given in $Name.
    If $Prefix is set, "$Prefix-$Name" is looked up in (helps keep the
    list of variables in $Name concise).

.PARAMETER Name
    A list of variable values to retrieve.
    
.PARAMETER Prefix
    A prefix to be applied to each variable name when performing the lookup. 
    A '-' is added to the end of $Prefix automatically.
#>
Function Get-BatchAutomationVariable
{
    [OutputType([hashtable])]
    Param(
        [Parameter(Mandatory = $True)]
        [String[]]
        $Name,

        [Parameter(Mandatory = $False)]
        [AllowNull()]
        [String]
        $Prefix = $Null
    )
    $CompletedParams = Write-StartingMessage -Stream Debug
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    $Variables = @{}
    
    ForEach($VarName in $Name)
    {
        If(-not [String]::IsNullOrEmpty($Prefix))
        {
            $_VarName =  "$Prefix-$VarName"
        }
        Else
        {
            $_VarName = $VarName
        }
        $Result = Get-AutomationVariable -Name "$_VarName"
        $Variables[$VarName] = $Result
        Write-Verbose -Message "Variable [$Prefix / $VarName] = [$($Variables[$VarName])]"
    }
    Write-CompletedMessage @CompletedParams
    Return ($Variables -as [hashtable])
}
<#
.Synopsis
    Returns a list of the runbook workers in the target hybrid runbook worker deployment.
#>
Function Get-AzureAutomationHybridRunbookWorker
{
    Param(
        [Parameter(Mandatory = $False)]
        [String[]]
        $Name
    )
    
    Return @($env:COMPUTERNAME) -as [array]
}

<#
.Synopsis
    Top level function for syncing a target git Repository to Azure Automation
#>
Function Sync-GitRepositoryToAzureAutomation
{
    Param(
        [Parameter(Mandatory = $True)]
        [pscredential]
        $SubscriptionAccessCredential,

        [Parameter(Mandatory = $True)]
        [pscredential]
        $RunbookWorkerAccessCredenial,
        
        [Parameter(Mandatory = $True)]
        [string]
        $RepositoryInformationJSON,

        [Parameter(Mandatory = $True)]
        [string]
        $AutomationAccountName,
        
        [Parameter(Mandatory = $True)]
        [string]
        $SubscriptionName,

        [Parameter(Mandatory = $True)]
        [string]
        $ResourceGroupName
    )
    
    $CompletedParams = Write-StartingMessage -String $RepositoryName
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    $RepositoryInformation = $RepositoryInformationJSON | ConvertFrom-Json | ConvertFrom-PSCustomObject
    Foreach($RepositoryName in $RepositoryInformation.Keys -as [array])
    {
        Try
        {
            $_RepositoryInformation = $RepositoryInformation.$RepositoryName
            $RunbookWorker = Get-AzureAutomationHybridRunbookWorker -Name $_RepositoryInformation.HybridWorkerGroup
        
            # Update the repository on all Workers
            Invoke-Command -ComputerName $RunbookWorker -Credential $RunbookWorkerAccessCredenial -ScriptBlock {
                $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
                    
                $_RepositoryInformation = $Using:_RepositoryInformation
                Update-GitRepository -RepositoryPath $_RepositoryInformation.RepositoryPath `
                                     -Path $_RepositoryInformation.Path `
                                     -Branch $_RepositoryInformation.Branch
            }

            $RepositoryChangeJSON = Find-GitRepositoryChange -Path $_RepositoryInformation.Path `
                                                             -StartCommit $_RepositoryInformation.CurrentCommit
            $RepositoryChange = ConvertFrom-Json -InputObject $RepositoryChangeJSON
            if($RepositoryChange.CurrentCommit -as [string] -ne $_RepositoryInformation.CurrentCommit -as [string])
            {
                Write-Verbose -Message "Processing [$($RepositoryInformation.CurrentCommit)..$($RepositoryChange.CurrentCommit)]"
                Write-Verbose -Message "RepositoryChange [$RepositoryChangeJSON]"
                $ReturnInformationJSON = Group-RepositoryFile -File $RepositoryChange.Files `
                                                              -Path $_RepositoryInformation.Path `
                                                              -RunbookFolder $_RepositoryInformation.RunbookFolder `
                                                              -GlobalsFolder $_RepositoryInformation.GlobalsFolder `
                                                              -PowerShellModuleFolder $_RepositoryInformation.PowerShellModuleFolder
                $ReturnInformation = ConvertFrom-Json -InputObject $ReturnInformationJSON
                Write-Verbose -Message "ReturnInformation [$ReturnInformationJSON]"
            
                Foreach($SettingsFilePath in $ReturnInformation.SettingsFiles)
                {
                    Publish-AzureAutomationSettingsFileChange -FilePath $SettingsFilePath `
                                                              -CurrentCommit $RepositoryChange.CurrentCommit `
                                                              -RepositoryName $RepositoryName `
                                                              -Credential $SubscriptionAccessCredential `
                                                              -AutomationAccountName $AutomationAccountName `
                                                              -SubscriptionName $SubscriptionName `
                                                              -ResourceGroupName $ResourceGroupName
                }
                Foreach($RunbookFilePath in $ReturnInformation.ScriptFiles)
                {
                    Publish-AzureAutomationRunbookChange -FilePath $RunbookFilePath `
                                                         -CurrentCommit $RepositoryChange.CurrentCommit `
                                                         -RepositoryName $RepositoryName `
                                                         -Credential $SubscriptionAccessCredential `
                                                         -AutomationAccountName $AutomationAccountName `
                                                         -SubscriptionName $SubscriptionName `
                                                         -ResourceGroupName $ResourceGroupName
                }
            
                if($ReturnInformation.CleanRunbooks)
                {
                    Remove-AzureAutomationOrphanRunbook -RepositoryName $RepositoryName `
                                                        -SubscriptionName $SubscriptionName `
                                                        -AutomationAccountName $AutomationAccountName `
                                                        -Credential $SubscriptionAccessCredential `
                                                        -RepositoryInformation $_RepositoryInformation `
                                                        -ResourceGroupName $ResourceGroupName
                }
                if($ReturnInformation.CleanAssets)
                {
                    Remove-AzureAutomationOrphanAsset -RepositoryName $RepositoryName `
                                                      -SubscriptionName $SubscriptionName `
                                                      -AutomationAccountName $AutomationAccountName `
                                                      -Credential $SubscriptionAccessCredential `
                                                      -RepositoryInformation $_RepositoryInformation `
                                                      -ResourceGroupName $ResourceGroupName
                }
                if($ReturnInformation.ModuleFiles)
                {
                    Try
                    {
                        Write-Verbose -Message 'Validating Module Path on Runbook Wokers'
                        $RepositoryModulePath = "$($_RepositoryInformation.Path)\$($_RepositoryInformation.PowerShellModuleFolder)"
                        Invoke-Command -ComputerName $RunbookWorker -Credential $RunbookWorkerAccessCredenial -ScriptBlock {
                            $RepositoryModulePath = $Using:RepositoryModulePath
                            Try
                            {
                                Add-PSEnvironmentPathLocation -Path $RepositoryModulePath
                            }
                            Catch
                            {
                                $Exception = New-Exception -Type 'PowerShellModulePathValidationError' `
                                                   -Message 'Failed to set PSModulePath' `
                                                   -Property @{
                                    'ErrorMessage' = (Convert-ExceptionToString -String $_) ;
                                    'RepositoryModulePath' = $RepositoryModulePath ;
                                    'RunbookWorker' = $env:COMPUTERNAME ;
                                }
                                Write-Warning -Message $Exception -WarningAction Continue
                            }
                        }
                        Write-Verbose -Message 'Finished Validating Module Path on Runbook Wokers'
                    }
                    Catch
                    {
                        Write-Exception -Exception $_ -Stream Warning
                    }
                }
                $UpdatedRepositoryInformation = (Update-RepositoryInformationCommitVersion -RepositoryInformationJSON $RepositoryInformationJSON `
                                                                                           -RepositoryName $RepositoryName `
                                                                                           -Commit $RepositoryChange.CurrentCommit) -as [string]
                Write-Verbose -Message "Finished Processing [$($RepositoryInformation.CurrentCommit)..$($RepositoryChange.CurrentCommit)]"
            }
        }
        Catch
        {
            Write-Exception -Stream Warning -Exception $_
        }
    }

    Write-CompletedMessage @CompletedParams
    Return (Select-FirstValid -Value @($UpdatedRepositoryInformation, $RepositoryInformationJSON))
}

<#
    .Synopsis
        Invokes test suites on the Runbooks and PowerShell modules
#>
Function Invoke-IntegrationTest
{
    Param(
        [Parameter(
            Mandatory = $True,
            Position = 0,
            ValueFromPipeline = $True
        )]
        [string]
        $Path
    )
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    $CompletedParams = Write-StartingMessage
    $Result = @{ 'Pester' = $null ; 'PSScriptAnalyzer'  = $null }
    Try
    {
        if((Get-Module -Name Pester -ListAvailable) -as [bool])
        {
            $ChildItem = Get-ChildItem -Path $Path -Recurse -Include *.ps1,*.psm1 -Exclude *.tests.ps1
            $Result.Pester = Invoke-Pester $Path -CodeCoverage $ChildItem.FullName -Quiet -PassThru
        }
        if((Get-Module -Name PSScriptAnalyzer -ListAvailable) -as [bool])
        {
            $Result.PSScriptAnalyzer = New-Object -TypeName System.Collections.ArrayList
            $ChildItem = Get-ChildItem -Path $Path -Recurse -Include *.ps1,*.psm1 -Exclude *.tests.ps1
            $ChildItem | ForEach-Object {
                $AnalyzerResult = Invoke-ScriptAnalyzer -Path $_.FullName
                $Null = $Result.PSScriptAnalyzer.Add(@{'FileName' = $_.FullName ; 'AnalyzerResult' = $AnalyzerResult })
            }
        }
    }
    Catch
    {
        Write-Exception -Exception $_ -Stream Warning
    }

    Write-CompletedMessage @CompletedParams
    Return $Result
}
Export-ModuleMember -Function * -Verbose:$false