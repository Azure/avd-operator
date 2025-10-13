function Write-Log {
    [CmdletBinding()]
    [OutputType([String])]
    param(
        [Parameter(Position = 0, Mandatory)]
        [String] $Message,

        [Parameter(Position = 1)]
        [System.Exception] $Exception,

        [Parameter(Position = 2)]
        [ValidateSet("INFO", "WARN", "VERBOSE", "ERROR", "ERRORSTOP", IgnoreCase = $false)]
        [String] $LogLevel = "INFO"
    )

    $SanitizedMessage = $Message.Trim()
    if (-not ([String]::IsNullOrWhiteSpace($SanitizedMessage))) {
        if ($null -ne $env:LogPrefix) {
            $Message = "$env:LogPrefix - $SanitizedMessage"
        }

        switch ($LogLevel) {
            "INFO" {
                Write-Information $Message
            }

            "WARN" {
                Write-Warning $Message
            }

            "VERBOSE" {
                Write-Verbose $Message
            }

            { (@("ERROR", "ERRORSTOP") -contains $PSItem) } {
                $ErrorParameters = @{
                    Message = $Message
                }
                if ($null -ne $Exception) {
                    $ErrorParameters.Exception = $Exception
                }
                if ($LogLevel -eq "ERRORSTOP") {
                    $ErrorParameters.ErrorAction = "Stop"
                }
                Write-Error @ErrorParameters
            }
        }
    }
}
Export-ModuleMember -Function Write-Log