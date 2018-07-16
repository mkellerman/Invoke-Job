Import-Module .\Invoke-Job.ps1

function Invoke-HelloWorld { 
    Write-Warning 'Hello World'
}

(1..5) | Invoke-Job -ScriptBlock { Invoke-HelloWorld } -ImportFunctions -Throttle 2 -PassThru
