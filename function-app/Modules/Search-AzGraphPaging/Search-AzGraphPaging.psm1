function Search-AzGraphPaging {
    [OutputType([System.Collections.Generic.List[Object]])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [String] $Query,

        [Parameter()]
        [Int] $First = 1000
    )

    begin {
        $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

        $SearchResults = [System.Collections.Generic.List[Object]]::new()
    }

    process {
        $SearchParameters = @{
            ErrorAction    = "Stop"
            First          = $First
            Query          = $Query
            UseTenantScope = $true
        }

        do {
            $SearchParameters["SkipToken"] = $InnerSearchResult.SkipToken
            $SearchResults.Add((Search-AzGraph @SearchParameters -OutVariable InnerSearchResult))
        } while (-not [String]::IsNullOrWhiteSpace($InnerSearchResult.SkipToken))
    }

    end {
        # Return flattened list
        return $SearchResults | ForEach-Object { $PSItem }
    }
}
Export-ModuleMember -Function Search-AzGraphPaging
