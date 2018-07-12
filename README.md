# Invoke-Job

##    .DESCRIPTION
Function to control background job processing exposing additional functionalities.

Added functionalities:
  * ImportFunctions
  * Throttle
  * Tmeout

##    .NOTES
Name: Start-RSJob

Author: Marc R Kellerman (@mkellerman)

Inspired by RamblingCookieMonster's Invoke-Parallel function

https://github.com/RamblingCookieMonster/Invoke-Parallel

##    .EXAMPLE

Example 1: Start 5 background jobs, throttle 2 jobs in parallel, Output result from Job and use a custom function in current session.

        function Invoke-HelloWorld { 
            Write-Warning 'Hello World'
        }
        
        (1..5) | Invoke-Job -ScriptBlock { Invoke-HelloWorld; Start-Sleep 2 } -ImportFunctions -Throttle 2 -PassThru
