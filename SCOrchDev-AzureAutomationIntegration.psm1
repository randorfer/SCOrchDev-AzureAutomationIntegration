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
        $SubscriptionName
    )
    
    Write-Verbose -Message "[$FilePath] Starting [Publish-AzureAutomationRunbookChange]"
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    Try
    {
        Connect-AzureAutomationAccount -Credential $Credential `
                                       -SubscriptionName $SubscriptionName `
                                       -AutomationAccountName $AutomationAccountName

        $WorkflowName = Get-WorkflowNameFromFile -FilePath $FilePath
        
        $ErrorActionPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
        $Runbook = Get-AzureAutomationRunbook -Name $WorkflowName `
                                              -AutomationAccountName $AutomationAccountName
        $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

        if($Runbook -as [bool])
        {
            Write-Verbose -Message "[$WorkflowName] Update"
            $TagUpdateJSON = New-ChangesetTagLine -TagLine ($Runbook.Tags -join ';') `
                                                  -CurrentCommit $CurrentCommit `
                                                  -RepositoryName $RepositoryName
            $TagUpdate = ConvertFrom-Json $TagUpdateJSON
            $TagLine = $TagUpdate.TagLine
            $NewVersion = $TagUpdate.NewVersion
            if($NewVersion)
            {
                $Runbook = Set-AzureAutomationRunbookDefinition -Name $WorkflowName `
                                                                -Path $FilePath `
                                                                -Overwrite `
                                                                -AutomationAccountName $AutomationAccountName
                $TagUpdate = Set-AzureAutomationRunbook -Name $WorkflowName `
                                                        -Tags $TagLine.Split(';') `
                                                        -AutomationAccountName $AutomationAccountName
            }
            else
            {
                Write-Verbose -Message "[$WorkflowName] Already is at commit [$CurrentCommit]"
            }
        }
        else
        {
            Write-Verbose -Message "[$WorkflowName] Initial Import"
            
            $TagLine = "RepositoryName:$RepositoryName;CurrentCommit:$CurrentCommit;"
            $Runbook = New-AzureAutomationRunbook -Path $FilePath `
                                                  -Tags $TagLine.Split(';') `
                                                  -AutomationAccountName $AutomationAccountName
            
            $NewVersion = $True
        }
        if($NewVersion)
        {
            $PublishHolder = Publish-AzureAutomationRunbook -Name $WorkflowName `
                                                            -AutomationAccountName $AutomationAccountName
        }
    }
    Catch
    {
        Write-Exception -Stream Warning -Exception $_
    }
    Write-Verbose -Message "[$FilePath] Finished [Publish-AzureAutomationRunbookChange]"
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
        $SubscriptionName
    )
    
    Write-Verbose -Message "[$FilePath] Starting [Publish-AzureAutomationSettingsFileChange]"
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    Try
    {
        Connect-AzureAutomationAccount -Credential $Credential `
                                       -SubscriptionName $SubscriptionName `
                                       -AutomationAccountName $AutomationAccountName

        $VariablesJSON = Get-GlobalFromFile -FilePath $FilePath -GlobalType Variables
        $Variables = $VariablesJSON | ConvertFrom-JSON | ConvertFrom-PSCustomObject
        foreach($VariableName in $Variables.Keys)
        {
            Try
            {
                Write-Verbose -Message "[$VariableName] Updating"
                $Variable = $Variables."$VariableName"
                $ErrorActionPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
                $AzureAutomationVariable = Get-AzureAutomationVariable -Name $VariableName `
                                                                       -AutomationAccountName $AutomationAccountName
                $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
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
                        'Name' = $VariableName ;
                        'Value' = $Variable.Value ;
                        'Encrypted' = $Variable.isEncrypted ;
                        'AutomationAccountName' = $AutomationAccountName
                    }
                    if($NewVariable)
                    {
                        $CreateVariable = New-AzureAutomationVariable @VariableParameters `
                                                                      -Description $VariableDescription
                    }
                    else
                    {
                        $UpdateVariable = Set-AzureAutomationVariable @VariableParameters
                        $UpdateVariable = Set-AzureAutomationVariable -Name $VariableName `
                                                                      -Description $VariableDescription `
                                                                      -AutomationAccountName $AutomationAccountName
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
                                           -Message 'Failed to publish a variable to Azure Automation' `
                                           -Property @{
                    'ErrorMessage' = Convert-ExceptionToString $_ ;
                    'VariableName' = $VariableName ;
                }
                Write-Warning -Message $Exception -WarningAction Continue
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
                $AzureAutomationSchedule = Get-AzureAutomationSchedule -Name $ScheduleName `
                                                                       -AutomationAccountName $AutomationAccountName
                $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
                if($AzureAutomationSchedule -as [bool])
                {
                    Write-Verbose -Message "[$($ScheduleName)] is an existing Schedule"
                    $TagUpdateJSON = New-SmaChangesetTagLine -TagLine $SmaVariable.Description`
                                                         -CurrentCommit $CurrentCommit `
                                                         -RepositoryName $RepositoryName
                    $TagUpdate = ConvertFrom-Json -InputObject $TagUpdateJSON
                    $ScheduleDescription = "$($TagUpdate.TagLine)"
                    $NewVersion = $TagUpdate.NewVersion
                    if($NewVersion)
                    {
                        Write-Verbose -Message "[$($ScheduleName)] is an Updated Schedule. Deleting to re-create"
                        Remove-AzureAutomationSchedule -Name $ScheduleName `
                                                       -Force `
                                                       -AutomationAccountName $AutomationAccountName
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
                    $CreateSchedule = New-AzureAutomationSchedule -Name $ScheduleName `
                                                                  -Description $ScheduleDescription `
                                                                  -DayInterval $Schedule.DayInterval `
                                                                  -StartTime $Schedule.NextRun `
                                                                  -ExpiryTime $Schedule.ExpirationTime `
                                                                  -AutomationAccountName $AutomationAccountName
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
                            'Credential'       = $SMACred.UserName
                        }
                    }
                    try
                    {
                        $Parameters = ConvertFrom-PSCustomObject -InputObject $Schedule.Parameter `
                                                                 -MemberType NoteProperty
                        $Register = Register-AzureAutomationScheduledRunbook -AutomationAccountName $AutomationAccountName `
                                                                             -RunbookName $Schedule.RunbookName `
                                                                             -ScheduleName $ScheduleName `
                                                                             -Parameters $Parameters
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
                        Remove-AzureAutomationSchedule -Name $ScheduleName `
                                                       -Force `
                                                       -AutomationAccountName $AutomationAccountName
                                                       $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Continue
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
    Write-Verbose -Message "[$FilePath] Finished [Publish-AzureAutomationSettingsFileChange]"
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
        
        Write-Verbose -Message "Variable [$VarName / $VarName] = [$($Variables[$VarName])]"
    }
    Return (New-Object -TypeName 'PSObject' -Property $Variables)
}
<#
.Synopsis
    Returns a list of the runbook workers in the target hybrid runbook worker deployment.
#>
Function Get-AzureAutomationHybridRunbookWorker
{
    Param(
        [Parameter(Mandatory = $True)]
        [String[]]
        $Name
    )
    
    Return @($Env:ComputerName) -as [array]
}

<#
.Synopsis
    Connects to an Azure Automation Account
#>
Function Connect-AzureAutomationAccount
{
    Param(
        [Parameter(Mandatory = $True)]
        [PSCredential]
        $Credential,

        [Parameter(Mandatory = $True)]
        [string]
        $SubscriptionName,

        [Parameter(Mandatory = $True)]
        [string]
        $AutomationAccountName
    )

    Import-AzurePSModule

    $AzureAccount = Get-AzureAccount
    if($AzureAccount.Id -ne $Credential.UserName)
    {
        $AzureAccount | ForEach-Object { Remove-AzureAccount -Name $_.Id -Force }
        Add-AzureAccount -Credential $Credential
    }
    
    $AzureAccountAccessible = (Get-AzureAutomationAccount -Name $AutomationAccountName) -as [bool]
    if(-not $AzureAccountAccessible)
    {
        Throw-Exception -Type 'AzureAutomationAccountNotAccessible' `
                        -Message 'Could not access the target Azure Automation Account' `
                        -Property @{
                            'Credential' = $Credential ;
                            'SubscriptionName' = $SubscriptionName ;
                            'AutomationAccountName' = $AutomationAccountName ;
                        }
    }
}

<#
.Synopsis
    Imports the Azure PowerShell module
#>
Function Import-AzurePSModule
{
    Param(
    )
    $ModuleLoaded = (Get-Module 'Azure') -as [bool]

    if(-not $ModuleLoaded)
    {
        $64BitPath = 'C:\Program Files (x86)\Microsoft SDKs\Azure\PowerShell\ServiceManagement\Azure'
        $32BitPath = 'C:\Program Files\Microsoft SDKs\Azure\PowerShell\ServiceManagement\Azure'
        if(Test-Path -Path $64BitPath)
        {
            Import-Module $64BitPath -Force
        }
        elseif(Test-Path -Path $32BitPath)
        {
            Import-Module $32BitPath -Force
        }
        else
        {
            Throw-Exception -Type 'ModuleNotFound' `
                            -Message 'Could not load the azure module. Please install from https://github.com/Azure/azure-powershell/releases'
        }
    }
}
<#
.Synopsis
    Imports a PowerShell module into Azure Automation.
    
.Parameter ModulePath
    The path to the PSD1 file

.Parameter Credential
    A credential object to use for the request. If not passed this method will use
    the default credential
#>
Function Publish-AzureAutomationPowerShellModule
{
    Param(
        [Parameter(Mandatory = $True)]
        [string]
        $ModulePath,

        [Parameter(Mandatory = $True)]
        [string]
        $SubscriptionName,

        [Parameter(Mandatory = $True)]
        [string]
        $AutomationAccountName,

        [Parameter(Mandatory = $False)]
        [pscredential]
        $Credential,

        [Parameter(Mandatory = $True)]
        [String]
        $CurrentCommit,

        [Parameter(Mandatory = $True)]
        [String]
        $RepositoryName
    )
    
    Write-Verbose -Message 'Starting [Publish-AzureAutomationPowershellModule]'

    $Module = Get-Item -Path $ModulePath
    $ModuleFolderPath = $Module.Directory.FullName
    $ModuleName = $Module.Directory.Name
    $TempDirectory = New-TempDirectory

    try
    {
        Connect-AzureAutomationAccount -Credential $Credential `
                                       -SubscriptionName $SubscriptionName `
                                       -AutomationAccountName $AutomationAccountName

        $ErrorActionPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
        $Module = Get-AzureAutomationModule -Name $ModuleName `
                                            -AutomationAccountName $AutomationAccountName
        $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

        $ZipFile = "$($TempDirectory.FullName)\$($ModuleName).zip"
        New-ZipFile -SourceDir $ModuleFolderPath `
                    -ZipFilePath $ZipFile `
                    -OverwriteExisting $True

        if($Module -as [bool])
        {
            Write-Verbose -Message "[$ModuleName] Update"
            $TagLine = ($Module.Tags.Keys | ForEach-Object { (@($_, $Module.Tags.$_) -join ':') } ) -join ';'
            $TagUpdateJSON = New-ChangesetTagLine -TagLine $TagLine `
                                                  -CurrentCommit $CurrentCommit `
                                                  -RepositoryName $RepositoryName
            $TagUpdate = ConvertFrom-Json $TagUpdateJSON
            $TagLine = $TagUpdate.TagLine
            $NewVersion = $TagUpdate.NewVersion
            if($NewVersion)
            {
                $Tags = @{}
                $TagLine -split ';' | ForEach-Object { $KVPair = $_ -split ':' ; $Tags.Add($KVPair[0], $KVPair[1]) | Out-Null }
                $ModuleImport = Set-AzureAutomationModule -Name $ModuleName `
                                                          -ContentLinkUri $ZipFile `
                                                          -Tags $Tags `
                                                          -AutomationAccountName $AutomationAccountName
            }
            else
            {
                Write-Verbose -Message "[$ModuleName] Already is at commit [$CurrentCommit]"
            }
        }
        else
        {
            $Tags = @{
                'CurrentCommit' = $CurrentCommit ;
                'RepositoryName' = $RepositoryName
            }
            $ModuleImport = New-AzureAutomationModule -Name $ModuleName `
                                                      -ContentLink $ZipFile `
                                                      -AutomationAccountName $AutomationAccountName `
                                                      -Tags $Tags
        }
    }
    finally
    {
        Remove-Item $TempDirectory -Force -Recurse
    }

    Write-Verbose -Message 'Finished [Publish-AzureAutomationPowershellModule]'
}
Export-ModuleMember -Function * -Verbose:$false