function Invoke-Job {
    <#
    .SYNOPSIS
        Function to control background job processing exposing additional functionalities.

    .DESCRIPTION
        Function to control background job processing exposing additional functionalities.

        Added functionalities:
            -ImportFunctions
            -Throttle
            -Tmeout
            -PassThru

    .NOTES
        Name: Start-RSJob
        Author: Marc R Kellerman (@mkellerman)

        Inspired by Invoke-Parallel by RamblingCookieMonster
        https://github.com/RamblingCookieMonster/Invoke-Parallel

    .PARAMETER ScriptFile
        Specifies a local script that this cmdlet runs as a background job. Enter the path and file name of the script or pipe a script path to Start-Job. The script must be on the local computer or in a folder that the local computer can access.

        When you use this parameter, Windows PowerShell converts the contents of the specified script file to a script block and runs the script block as a background job.


    .PARAMETER ScriptBlock
        Specifies the commands to run in the background job. Enclose the commands in braces ( { } ) to create a script block. This parameter is required.

            You may use $Using:<Variable> language in PowerShell 3 and later.
            Refer to the InputObject as $Input.

    .PARAMETER ArgumentList
        Specifies an array of arguments, or parameter values, for the script that is specified by the FilePath parameter.

        Because all of the values that follow the ArgumentList parameter name are interpreted as being values of ArgumentList, specify this parameter as the last parameter in the command.

    .PARAMETER Authentication
        Specifies the mechanism that is used to authenticate user credentials. The acceptable values for this parameter are:

        Default
        Basic
        Credssp
        Digest
        Kerberos
        Negotiate
        NegotiateWithImplicitCredential
        The default value is Default.

        CredSSP authentication is available only in Windows Vista, Windows Server 2008, and later versions of the Windows operating system.

        For more information about the values of this parameter, see AuthenticationMechanism Enumeration in the MSDN library.

        Caution: Credential Security Support Provider (CredSSP) authentication, in which the user's credentials are passed to a remote computer to be authenticated, is designed for commands that require authentication on more than one resource, such as accessing a remote network share. This mechanism increases the security risk of the remote operation. If the remote computer is compromised, the credentials that are passed to it can be used to control the network session.

    .PARAMETER Credential
        Specifies a user account that has permission to perform this action. The default is the current user.

        Type a user name, such as User01 or Domain01\User01, or enter a PSCredential object, such as one from the Get-Credential cmdlet.

    .PARAMETER InitializationScript
        Specifies commands that run before the job starts. Enclose the commands in braces ( { } ) to create a script block.

        Use this parameter to prepare the session in which the job runs. For example, you can use it to add functions, snap-ins, and modules to the session.

    .PARAMETER InputObject
        Specifies input to the command. Enter a variable that contains the objects, or type a command or expression that generates the objects.

        In the value of the ScriptBlock parameter, use the $Input automatic variable to represent the input objects.

    .PARAMETER PSVersion
        Specifies a version. This cmdlet runs the job with the version of Windows PowerShell. The acceptable values for this parameter are: 2.0 and 3.0.

        This parameter was introduced in Windows PowerShell 3.0.

    .PARAMETER RunAs32
        Indicates that this cmdlet runs the job in a 32-bit process. Use this parameter to force the job to run in a 32-bit process on a 64-bit operating system.

        On 64-bit versions of Windows 7 and Windows Server 2008 R2, when the Start-Job command includes the RunAs32 parameter, you cannot use the Credential parameter to specify the credentials of another user.

    .PARAMETER AutoRemoveJob
        Indicates that this cmdlet deletes the job after it returns the job results. 

    .PARAMETER ImportFunctions
        Import all functions from current session in the background job.

    .PARAMETER Throttle
        Maximum number of background jobs to run at a single time.

    .PARAMETER Timeout
        Specifies the maximum wait time for each background job, in seconds. The default value, the cmdlet waits until the job finishes.

    .PARAMETER PassThru
        Returns the result from the background job. By default, this cmdlet returns the job progress.

    .PARAMETER All
        Returns all background job progress (Start/Stop/Failed/Completed). By default, this cmdlet will returns the job progress when completed.

        This parameter is ignored when -PassThru is used.

    .EXAMPLE

        Example 1: Start 5 background jobs, throttle 2 jobs in parallel, Output result from Job and use a custom function from current session.

        function Invoke-HelloWorld { 
            Write-Warning 'Hello World'
        }
        
        (1..5) | Invoke-Job -ScriptBlock { Invoke-HelloWorld; Start-Sleep 2 } -ImportFunctions -Throttle 2 -PassThru

    .LINK
        https://github.com/mkellerman/Invoke-Job
    #>

    [cmdletbinding(DefaultParameterSetName="ScriptBlock")]
    Param(
        [Parameter(Mandatory=$True, ParameterSetName='FilePath')]
        [string]$FilePath,
        [Parameter(Mandatory=$True, ParameterSetName='ScriptBlock')]
        [scriptblock]$ScriptBlock,
        [object[]]$ArgumentList,
        [System.Management.Automation.Runspaces.AuthenticationMechanism]$Authentication,
        [pscredential]$Credential,
        [scriptblock]$InitializationScript,
        [Parameter(Mandatory=$False,ValueFromPipeline=$true)]
        [Alias('CN','__Server','IPAddress','Server','ComputerName')]
        [psobject]$InputObject,
        [version]$PSVersion,
        [switch]$RunAs32,
        [switch]$AutoRemoveJob,
        [switch]$ImportFunctions,
        [int]$Throttle,
        [int]$Timeout,
        [switch]$PassThru,
        [switch]$All
    )
    Begin {

        $JobName = 'Invoke-Job'

        $JobQueue = New-Object System.Collections.Queue

        # Collect any previously created jobs and marked them as Received already.
        $Script:JobReceived = @()
        Get-Job -Name $JobName -ErrorAction SilentlyContinue | ForEach-Object { $Script:JobReceived += $PSItem.Id }

        # Create InitializationScript
        $InitializationScripts = @()
        If ($ImportFunctions) {

            $PSDefaults = Start-Job -ScriptBlock {

                #Get modules, snapins, functions in this clean runspace
                $Modules = Try { Get-Module | Select-Object -ExpandProperty Name } Catch { $Null }
                $Snapins = Try { Get-PSSnapin | Select-Object -ExpandProperty Name } Catch { $Null }
                $Functions = Try { Get-ChildItem function:\ | Select-Object -ExpandProperty Name } Catch { $Null }

                #Get variables in this clean runspace
                #Called last to get vars like $? into session
                $Variables = Try { Get-Variable | Select-Object -ExpandProperty Name } Catch { $Null }

                #Return a hashtable where we can access each.
                [PSCustomObject]@{
                    Modules     = $Modules
                    Snapins     = $Snapins
                    Functions   = $Functions
                    Variables   = $Variables
                }

            } | Receive-Job -Wait -AutoRemoveJob

            $FunctionsFileName  = [System.IO.Path]::GetTempFileName() | ForEach-Object { Move-Item -Path $PSItem -Destination "$($PSItem -Replace "\.tmp", ".ps1")" -PassThru }
            $UsingFunctions = Get-ChildItem function:\ | Where-Object { $_.ScriptBlock.Ast.GetType().Name -eq 'FunctionDefinitionAst' } | Where-Object { -not ($PSDefaults.Functions -contains $_.Name ) } | ForEach-Object { $_.ScriptBlock.Ast.Extent.Text }
            $UsingFunctions -Join "`r`n`r`n" | Set-Content $FunctionsFileName
            $InitializationScripts += "Try { Import-Module '$FunctionsFileName' -ErrorAction SilentlyContinue -NoClobber -Force } Catch { }"

        }
        If ($InitializationScript) { $InitializationScripts += $InitializationScript.ToString() }
        $InitializationScript = [scriptblock]::Create($InitializationScripts -Join "`r`n")

        function Invoke-GetJob ([switch]$First) {
            Get-Job -Name $JobName -ErrorAction SilentlyContinue | Where-Object { $Script:JobReceived -notcontains $_.Id }
        }
        function Invoke-StartJob {
            
            $JobParams = @{}
            If ($ScriptBlock)     { $JobParams['ScriptBlock'] = $ScriptBlock }
            If ($FilePath)        { $JobParams['FilePath'] = $FilePath }
            If ($Credential)      { $JobParams['Credential'] = $Credential }
            If ($Authentication ) { $JobParams['Authentication '] = $Authentication  }
            If ($RunAs32)         { $JobParams['RunAs32'] = $RunAs32 }
            If ($PSVersion )      { $JobParams['PSVersion '] = $PSVersion  }
            If ($ArgumentList)    { $JobParams['ArgumentList'] = $ArgumentList }

            # Bring Parent scope variable into current scope
            # Fix to using $Using variable that uses the same name than a parameter of this function.

            Get-Variable -Name ScriptBlock -Scope 2 -ErrorAction SilentlyContinue    | % { Set-Variable -Scope 0 -Name $_.Name -Value $_.Value }
            Get-Variable -Name FilePath -Scope 2 -ErrorAction SilentlyContinue       | % { Set-Variable -Scope 0 -Name $_.Name -Value $_.Value }
            Get-Variable -Name Credential -Scope 2 -ErrorAction SilentlyContinue     | % { Set-Variable -Scope 0 -Name $_.Name -Value $_.Value }
            Get-Variable -Name Authentication -Scope 2 -ErrorAction SilentlyContinue | % { Set-Variable -Scope 0 -Name $_.Name -Value $_.Value }
            Get-Variable -Name RunAs32 -Scope 2 -ErrorAction SilentlyContinue        | % { Set-Variable -Scope 0 -Name $_.Name -Value $_.Value }
            Get-Variable -Name PSVersion -Scope 2 -ErrorAction SilentlyContinue      | % { Set-Variable -Scope 0 -Name $_.Name -Value $_.Value }
            Get-Variable -Name ArgumentList -Scope 2 -ErrorAction SilentlyContinue   | % { Set-Variable -Scope 0 -Name $_.Name -Value $_.Value }

            If ($JobQueue.Count) {
                $Job = $JobQueue.Dequeue() | Start-Job -Name $JobName -InitializationScript $InitializationScript @JobParams
                If (-Not($PassThru) -and ($All)) { Return $Job }
            }
        }

        function Invoke-ReceiveJob {

            If ($Job = Invoke-GetJob | Select-Object -First 1) {

                $Script:JobReceived += $Job.Id

                While ($Job | Where-Object State -eq 'Running') {
                    If ($Timeout) {
                        $Timespan = (Get-Date) - $Job.PSBeginTime
                        If ($Timespan.TotalSeconds -ge $Timeout) { 
                            $Job | Stop-Job -Confirm:$False -EA 0 | Out-Null
                        }
                    }
                    If ($PassThru) { $Job | Receive-Job -EA 0 }
                }

                If ($PassThru) { $Job | Receive-Job -Wait -EA 0 }
                          Else { $Job | Wait-Job -EA 0 }

                If ($AutoRemoveJob) { $Job | Remove-Job -Force -EA 0 }

                If ($Job.State -eq 'Stopped') { Write-Error "This Job was stopped because execution time exceeded Timeout value ($Timeout)."}

            }

        }

    }

    Process {

        # Add each inputobjects into the JobQueue
        $InputObject | ForEach-Object { $JobQueue.Enqueue($PSItem) }

    }

    End {

        If (-Not($Timeout -gt 0)) { $Timeout = [int]::MaxValue }
        If (-Not($Throttle -gt 0)) { $Throttle = [int]::MaxValue }

        # While there is jobs in queue and jobs are running
        While (($JobQueue.Count -gt 0) -or ((Invoke-GetJob | Measure-Object).Count -gt 0))  {

            # While there is jobs in queue and jobs are running
            While (($JobQueue.Count -gt 0) -and ((Invoke-GetJob | Measure-Object).Count -lt $Throttle)) {
                Invoke-StartJob
            }

            Try {
                Invoke-ReceiveJob
            } Catch {
                
                # If -ErrorAction is set to Stop, then force stop all jobs that are running
                If ($ErrorActionPreference -eq 'Stop') { 
                    Invoke-GetJob | Stop-Job -EA 0 
                }

                Write-Error $_.Exception.Message
            }
            Start-Sleep -Milliseconds 200

        }

    }

}
