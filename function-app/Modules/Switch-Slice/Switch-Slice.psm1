function Switch-Slice {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [String] $HostPoolName
    )

    $poolSuffix = $HostPoolName.Substring($HostPoolName.Length - 3, 3)

    # Regex to check the last three chars in the pool name and only continue if it matches e.g. 'A-4'
    if ($poolSuffix -notmatch '[A|B]-\d') {
        return $HostPoolName
    }

    $nameCharArray = $HostPoolName.ToCharArray()
    $currentSlice = $nameCharArray[-3]

    if ($currentSlice -ieq "A") {
        $nameCharArray[-3] = "B"
        return $nameCharArray -join ''
    } else {
        $nameCharArray[-3] = "A"
        return $nameCharArray -join ''
    }
}
Export-ModuleMember -Function Switch-Slice