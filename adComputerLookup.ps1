param([SupportsWildcards()][string]$value, [string]$resultProperty, [string]$queryProperty = "cn", [switch]$allProperties, [switch]$findAll)

if (!$resultProperty) { $defaultProperties = $true }
if (!$value) { 
    Write-Host "ERROR: Missing required parameter value for value" -ForegroundColor Red 
    break
}

if ($value.contains("*")) { $wildcard = $true }
if ($findAll -and $wildcard) {
    Clear-Host
    Write-Host "`n***WARNING***`nYou have chosen both findAll and a wildcard value, which can result in a very intensive query with an excessive volume of results." -ForegroundColor Red
    Write-Host "`nSELECT * FROM theWholeEnterpriseOfLiterallyThousandsOfComputers WHERE $queryProperty = '$value'" -ForegroundColor Cyan

    $title = "Choose wisely:"
    $choices = @(
    ("&Y", "Yes, I am certain that this query will not invoke the wrath of admins, set anything on fire, or otherwise do any sort of great big uh oh. Send it."), #0
    ("&N", "No... on second thought, that's not a good idea. Stop now, and I'll modify the query before trying again.") #1
    ) | ForEach-Object { New-Object System.Management.Automation.Host.ChoiceDescription $_ }

    $message = "Are you certain that you would like to initiate the above query?"

    $userInput = $Host.UI.PromptForChoice($title, $message, $choices, 1)
    if ($userInput -eq 1) { return }
}

$searcher = ([adsisearcher]"(&(objectClass=computer)(objectCategory=computer))")

if ($defaultProperties) {
    $properties = "distinguishedname", "name", "lastlogon", "operatingsystem", "operatingsystemversion", "dnshostname", "memberof", "whencreated"
    foreach ($property in $properties) { $searcher.PropertiesToLoad.Add($property) | out-null }
}

$searcher.Filter = "(&($queryProperty=$value))"
if ($findAll) {
    if ($resultProperty) { $result = $searcher.FindAll().Properties.$resultProperty }
    else { $result = $searcher.FindAll().Properties }
}
else {
    if ($resultProperty) { $result = $searcher.FindOne().Properties.$resultProperty }
    else { $result = $searcher.FindOne().Properties }
}

if (!$result) {
    if ($resultProperty) { Write-Host "$resultProperty not found in current domain for account with $queryProperty = $value" -ForegroundColor Red }
    else { Write-Host "Account with $queryProperty = $value not found in current domain" -ForegroundColor Red }
    break
}

if ($allProperties) { $result | Select-Object Name, Value | Sort-Object Name | Format-Table -AutoSize | Out-File -FilePath $targetFile -Append }
else { $result | ForEach-Object { Write-Output $_ | Format-Table } }