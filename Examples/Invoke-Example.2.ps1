Import-Module .\Invoke-Job.ps1

# Load a script in this user session
# https://gallery.technet.microsoft.com/scriptcenter/Get-PendingReboot-Query-bdb79542
Import-Module .\Get-PendingReboot.ps1

# Make a simple ScriptBlock that will receive the computername from the pipeline and execute the script against the remote computer. In this case, Get-PendingReboot that we've loaded in this current session.

$ScriptBlock = {
  Process {
    
    # Collect the InputObject sent through the Pipeline.
    $ComputerName = $_
    
    Try   { 
    
      # Because Get-PendingReboot has been imported into this session, I can call the function directly.
      # I'm also $Using variables from the parent session. Everything works as expected.
      
      Invoke-Command -ComputerName $ComputerName -Credential $Using:Credential -ScriptBlock ${function:Get-PendingReboot} 
    
    } Catch { 
    
      Write-Error $_.Exception.Message 
    
    }
  
  }
}

# Get list of computers and set the credential used for the remote execution.

$Computers = Get-Content -Path '.\computers.txt'
$Credential = Get-Credential

# Start-Job 4 jobs at a time, with a timeout of 30 seconds, and return the results (not the Job object). And beautify it by presenting the results in a table.

$Computers | Invoke-Job -ScriptBlock $ScriptBlock -Throttle 4 -Timeout 30 -ImportFunctions -PassThru | Format-Table
