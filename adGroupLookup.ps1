param([SupportsWildcards()][string]$groupName)
#Test values
#$groupName = "biso"
#$output = "CSV"

if (!$groupName) {
    Write-Host "ERROR: Missing required parameter value for groupName"
    Write-Host "       PARAMETERS:"
    Write-Host "           groupName  : Required. Name of the AD group to query. Please use wildcards in the groupName for partial lookups: such as 'webfilter_*', '*_cloudfileshare' '*filter_*' and so on"
    Write-Host "Example usage: "
    Write-Host "adGroupLookUp -groupName '*filter_*'"
    Write-Host "adGroupLookUp *splunk*"
    Write-Host "adGroupLookUp webfilter_*"
    Return
}
Write-Host " "
Write-Host "Querying groups matching $groupname..." -ForegroundColor Green
Write-Host " "

###Query the group name(s)
$groupSearch = [adsisearcher]'(&(objectCategory=group))'
$groupSearch.Filter = "(&(name=$groupName)(objectClass=group))"
$groupSearch.PageSize = 200
$groupSearch.Sort.PropertyName = "name"
$groupSearch.Sort.Direction = "ascending"

#List of properties--modify this with any additional properties, in the order you want them to be displayed
$groupProperties = "name", "distinguishedname", "description", "managedby", "msexchcomanagedbylink", "managedobjects", "member", "memberof"
foreach ($property in $groupProperties) { $groupSearch.PropertiesToLoad.Add($property) | out-null }

#Actual query for names and group properties
$colResults = $groupSearch.FindAll()

function Write-Padded ([Int16]$charLength, [string]$leftText, [string]$rightText, [string]$foregroundColor = "White") {
    $numSpaces = $charLength - $leftText.Length
    $paddedText = "$leftText{0,$numSpaces}$rightText" -f ""
    Write-Host $paddedText -ForegroundColor $foregroundColor
}

if ($colResults.Count -gt 0) {
    Write-Host $colResults.Count "match(es) found..." -ForegroundColor Green
    Write-Host " "
    foreach ($objResult in $colResults) {
        foreach ($property in $groupProperties) { 
            #Member just spits out an unformatted list of DNs and is pretty unwieldy here, so it's been replaced with a simple count of members
            #For group member details, use the adGroupMemberLookup script instead of trying to force that info into this script
            $nameList = ""
            $numSpaces = 25
            if ($property -eq "member") { 
                $rightText = ": " + ($objResult.Properties).$property.Count
                Write-Padded $numSpaces "members" $rightText
            }
            elseif ($property -eq "managedobjects" -or $property -eq "memberof" -or $property -eq "managedby" -or $property -eq "msexchcomanagedbylink") { 
                #Managed and co-managed by are both singular; managed objects and member of can be one or more--check the count and format properly
                if (($objResult.Properties).$property.Count -gt 1) {
                    ($objResult.Properties).$property | ForEach-Object {
                        if ($_.Length -gt 1) {
                            $commaPosition = $_.IndexOf(",") - 3
                            $resultString = $_.substring(3, $commaPosition) + "; "
                            $nameList += $resultString
                        }
                        else { $nameList = "N/A" }
                    }
                }    
                else { 
                    [string]$name = ($objResult.Properties).$property
                    if ($name.Length -gt 1) {
                        $commaPosition = $name.IndexOf(",") - 3
                        $nameList = $name.substring(3, $commaPosition)
                    }
                    else { $nameList = "N/A" }
                }  
                $rightText = ": " + $nameList
                if ($property -eq "msexchcomanagedbylink") { $property = "comanagedby" } #that property name is atrocious
                Write-Padded $numSpaces $property $rightText
            }
            else { 
                #Highlight the first row of each result with green text for ease of review
                if ($property -eq "name") { $color = "Green" } else { $color = "White" }
                $rightText = ": " + ($objResult.Properties).$property
                Write-Padded $numSpaces $property $rightText $color
            }
        }
        Write-Host " "
    }
}
else { Write-Host "No matches found." -ForegroundColor Red }