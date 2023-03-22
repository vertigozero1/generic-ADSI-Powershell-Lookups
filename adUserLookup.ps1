param([SupportsWildcards()][string]$value, [string]$resultProperty, [string]$queryProperty = "samAccountName", [string]$targetPath, [switch]$findAll, [switch]$allProperties, [switch]$export)
#Test values for simplified debugging in IDE
#$value = "p0018192"
#$queryProperty = "userPrincipalName"
#$resultProperty = "distinguishedname"
#$targetPath = "c:\devtemp\vsCode"
#$findAll = $true
#$allProperties = $true
#$export = $true

###
### Initialization and input validation
###
BEGIN {
    if (!$value) {
        Write-Host "ERROR: Missing required parameter value for value" -ForegroundColor Red
        Write-Host "       PARAMETERS:"
        Write-Host "           value            : Required. The user account value to use for the query. Supports asterisk * wildcarding"
        Write-Host "                              USE CAUTION IF WILDCARDING. There are many thousands of user accounts on the domain, and you could craft a query which would produce enormous results." -ForegroundColor Red
        Write-Host "           queryProperty    : Optional, defaults to samAccountName (employeeID # - p00XXXXX). Uses standard AD property names, with a few custom aliases for common items"
        Write-Host "                              Some examples of the standard property names which have aliases: userprincipalname (alias - email), distinguishedname (alias - dn) "
        Write-Host "           resultProperty   : Optional. Use this to specify a certain single property value to return on the user account. Defaults to userprincipalname (which is email)"
        Write-Host "           targetPath       : Optional. Specifies a destination directory for the output TXT."
        Write-Host "                              If a value is provided for this parameter, the script will automatically export; there is no need to use both input parameters"
        Write-Host "           -findAll         : Optional, switch parameter. Use this to find any user accounts matching your query. Can return a high volume of results."
        Write-Host "                              USE CAUTION WITH THIS. There are many thousands of user accounts on the domain, and you could craft a query which would produce enormous results." -ForegroundColor Red
        Write-Host "           -allProperties   : Optional, switch parameter. Adding this argument will return all AD properties for the user(s) matching your query."
        Write-Host "                              Selecting a combination of -findAll and -allProperties will result in the script ignoring the -allProperties flag." -ForegroundColor Cyan
        Write-Host "                              USE CAUTION WITH THIS. Active Directory user accounts contain a large number of parameters, most of which will not be useful to you." -ForegroundColor Red
        Write-Host "           -export          : Optional, switch parameter. Adding -export will save the results to a file in the current working directory (or in the targetPath, if set)"
        Write-Host " "
        Write-Host "**NOTE** - Any input which would result in a combination of -findAll and wildcard search being used simultaneously will pause and throw a warning." -ForegroundColor Yellow
        Write-Host "           The intended query will be displayed on screen, and confirmation will be required prior to continuing. No other checks are performed to prevent intensive searches." -ForegroundColor Yellow
        Write-Host "           For any bulk queries, please consider using adUserBulkLookup with a constrained list of input parameters, as it will run individual lookups and can therefore be stopped at any time." -ForegroundColor Yellow
        Write-Host " "
        Write-Host "Example usage:" -ForegroundColor Green
        Write-Host "    adUserLookup p0018192" -ForegroundColor Cyan
        Write-Host "           RESULT: Displays the email address on screen" -ForegroundColor Gray
        Write-Host "    adUserLookup p0018192 -resultProperty telephonenumber" -ForegroundColor Cyan
        Write-Host "           RESULT: Displays the phone number on screen" -ForegroundColor Gray
        Write-Host "    adUserLookup p0018192 -allProperties" -ForegroundColor Cyan
        Write-Host "           RESULT: Displays all account property names and values on screen" -ForegroundColor Gray
        Write-Host "    adUserLookup p0018192 -allProperties -export" -ForegroundColor Cyan
        Write-Host "           RESULT: Exports all account property names and values to `"[current folder]\[date/timestamp] allPropertiesFor samAccountName p0018192.txt`"" -ForegroundColor Gray
        Write-Host "    adUserLookup -queryProperty name -value `"Jason Stiles`" directreports" -ForegroundColor Cyan
        Write-Host "           RESULT: Displays a table of standard properties for all direct reports of the specified FM" -ForegroundColor Gray
        Write-Host "    adUserLookup -queryProperty `"Jason Stiles`" orgchart name" -ForegroundColor Cyan
        Write-Host "           RESULT: Displays a table of standard properties for all users above the specified user" -ForegroundColor Gray
        Write-Host "           NOTE: This is also an example of using positional arguments instead of specifying each individually" -ForegroundColor Gray
        Write-Host "    adUserLookup -queryProperty email -value `"jason.stiles@parsons.com`" orgchart" -ForegroundColor Cyan
        Write-Host "           RESULT: Displays a table of the chain of command above the employee with the specified email address" -ForegroundColor Gray
        Write-Host "    adUserLookup -queryProperty name -value `"Eric Schlesinger`" asset" -ForegroundColor Cyan
        Write-Host "           RESULT: Displays a set of properties for any asset(s) assigned to the specified user" -ForegroundColor Gray
        Write-Host "           NOTE: At time of writing, only Parsons-issued Windows PCs are tagged to the user in AD; Macs are not." -ForegroundColor Yellow
        Write-Host "    adUserLookup -queryProperty postalcode -value 75080 -findAll" -ForegroundColor Cyan
        Write-Host "           RESULT: Displays the email addresses of all direct reports" -ForegroundColor Gray
        Write-Host "           WARNING: This is an example of a potentially-intensive query that can take some time to complete." -ForegroundColor Red
        Break
    }

    Remove-Variable result -ErrorAction SilentlyContinue

    #Set some operational flags based on input values to simplify later checks.
    $returnOrgChart = $false
    $returnManager = $false
    $returnAsset = $false
    $wildcard = $false
    $resultIsDNList = $false
        
    if ($queryProperty) {
        #Establish some quick aliases for simplicity of querying--these could all be switch/case blocks, but it just felt better to combine items with multiple aliases into an if/then
        $queryProperty = $queryProperty.ToLower()

        if ($queryProperty.contains("asset") -or 
            $queryProperty.contains("workstation") -or 
            $queryProperty.contains("computer")) 
        { $queryByAsset = $true }

        if ($queryProperty -eq "id" -or 
            $queryProperty -eq "empid" -or 
            $queryProperty -eq "employeeid") 
        { $queryProperty = "samaccountname" }

        switch ($queryProperty) {
            "email" { $queryProperty = "userprincipalname" }
            "dn" { $queryProperty = "distinguishedname" }
            "phone" { $queryProperty = "telephonenumber" }
            "cell" { $queryProperty = "othermobile" }
            "mobile" { $queryProperty = "othermobile" }
            "office" { $queryProperty = "physicaldeliveryofficename" }
            "manager" { 
                #It's possible to query someone's direct reports in "reverse" by using -queryProperty manager -value "[NAME]" (effectively asking "which users
                #have [NAME] listed as their manager," instead of the better "who are the direct reports of [NAME]"), but that performs the basic query and
                #only returns the name of the first direct report to be listed, which is not the intended behavior. Since the best approach would be not to
                #do this, and instead use the -queryProperty "[NAME]" -resultProperty "directreports" (custom functionality), force this outcome instead
                $queryProperty = "name"
                $resultProperty = "directreports"
            }
        }
    }

    #If we're not pulling ALL properties, then run through some overhead to simplify user experience for other queries
    if ($allProperties) {
        #Both result properties set, ignore one
        if ($resultProperty) {
            Write-Host "Conflicting parameters provided: resultProperty = '$resultProperty' and -allProperties" -ForegroundColor Yellow
            Write-Host "Ignoring -allProperties switch, and returning the provided property value instead." -ForegroundColor Yellow
            $allProperties = $false
        }
        if ($findAll) {
            Write-Host "FindAll and AllProperties are mutually exclusive--the output of all properties on multiple users is extremely unwieldy.`nFor multiple lookups, use adUserBulkLookup instead."
            Write-Host "Ignoring the AllProperties argument..."
            $allProperties = $false
        }
    }
    #If no results are specified, just pull a standard set
    $defaultProperties = $false

    if (!$resultProperty -and !$allProperties) { 
        Write-Host "No result property specified; using default property list for results." -ForegroundColor Cyan
        $defaultProperties = $true 
    }
    else {
        $resultProperty = $resultProperty.ToLower()

        if ($resultProperty -eq "id" -or 
            $resultProperty -eq "empid" -or 
            $resultProperty -eq "employeeid") 
        { $resultProperty = "samaccountname" }

        switch ($resultProperty) {
            "email" { $resultProperty = "userprincipalname" }
            "dn" { $resultProperty = "distinguishedname" }
            "phone" { $resultProperty = "telephonenumber" }
            "cell" { $resultProperty = "othermobile" }
            "mobile" { $resultProperty = "othermobile" }
            "office" { $resultProperty = "physicaldeliveryofficename" }
        }

        if ($resultProperty -eq "manager") { $returnManager = $true }

        if ($resultProperty -eq "orgchart") {
            $returnOrgChart = $true
            $resultProperty = "distinguishedname"
        }

        if ($resultProperty -eq "asset" -or $resultProperty -eq "assets" -or
            $resultProperty -eq "workstation" -or $resultProperty -eq "workstations" -or
            $resultProperty -eq "computer" -or $resultProperty -eq "computers" ) 
        { $returnAsset = $true }
    }
    
    if ($value.contains("*")) { $wildcard = $true }

    #Don't break things, and prevent troublesome combinations of arguments

    if (($returnOrgChart -and $findAll) -or ($returnOrgChart -and $allProperties)) {
        Write-Host "Querying the org chart is mutually exclusive with the FindAll and AllProperties arguments.`nThe org chart result returns a pre-defined table of properties for a single user's line of management."
        $findAll = $false
        $allProperties = $false
    }

    if ($returnOrgChart -and $wildcard) {
        Write-Host "Querying the org chart cannot be done with a wildcard search, as it is intended to return pre-defined`nproperties for a single user's line of management. Please perform an individual wildcard query for the`nnecessary user ID, then return orgchart for that individual user account." -ForegroundColor Red
        Break        
    }

    if ($findAll -and $wildcard) {
        Clear-Host
        Write-Host "`n***WARNING***`nYou have chosen both findAll and a wildcard value, which can result in a very intensive query with an excessive volume of results." -ForegroundColor Red
        Write-Host "`nSELECT * FROM theWholeEnterpriseOfLiterallyTensOfThousandsOfUsers WHERE $queryProperty = '$value'" -ForegroundColor Cyan
    
        $title = "Choose wisely:"
        $choices = @(
        ("&Y", "Yes, I am certain that this query will not invoke the wrath of admins, set anything on fire, or otherwise do any sort of great big uh oh. Send it."), #0
        ("&N", "No... on second thought, that's not a good idea. Stop now, and I'll modify the query before trying again.") #1
        ) | ForEach-Object { New-Object System.Management.Automation.Host.ChoiceDescription $_ }

        $message = "Are you certain that you would like to initiate the above query?"

        $userInput = $Host.UI.PromptForChoice($title, $message, $choices, 1)
        if ($userInput -eq 1) { return }
    }

    #Automatically set script to export results to file if a path is specified
    if ($targetPath) { $export = $true }

    #If we're exporting results to file, establish the full destination file path
    if ($export) {
        if (!$targetPath) { $targetPath = (Get-Location).Path }
        else {
            $pathValid = Test-Path $targetPath
            if (!$pathValid) {
                Write-Host "ERROR: Invalid targetPath: $targetPath" -ForegroundColor Red
                return
            }
        }
        $dateTime = $((Get-Date -Format "yyyyMMdd-HHmm").ToString())

        if (!$allProperties) { $resultType = "$resultProperty for $queryProperty $value" }
        else { $resultType = "allProperties for $queryProperty $value" }
        $targetFile = $targetPath + "\$dateTime $resultType.txt"
    }
}

###
### Query processing and special lookup handling
###
PROCESS {
    function Expand-UserList($userDNList) {

        $output = $userDNList | Sort-Object | ForEach-Object {
            $searcher.Filter = "(&(distinguishedname=$_))"
            $eulResult = $searcher.FindOne().Properties
    
            $employeeCount = $eulResult.directreports.count
            $tempObj = [pscustomobject] @{
                ID        = $eulResult.employeeid -join ";"
                Name      = $eulResult.name -join ";"
                Status    = $eulResult.employeetype -join ";"
                USPerson  = $eulResult.usperson -join ";"
                BU        = $eulResult.company -join ";"
                Title     = $eulResult.title -join ";"
                Email     = $eulResult.userprincipalname -join ";"
                Office    = $eulResult.physicaldeliveryofficename -join ";"
                StartDate = $eulResult.firstworkingday -join ";"
                Reports   = $employeeCount
                ManagerDN = $eulResult.manager -join ";"
            }
            $tempObj | Sort-Object Name
        }
        return $output
    }

    function Get-FunctionalManager([string]$employeeDN, [switch]$recursive = $false) {
        #Get property values for the specified user
        $user = Expand-UserList($employeeDN)
        $fmDN = $user.ManagerDN
        #Ensure that they're not their own FM (should only apply to CEO)
        if ($fmDN -eq $employeeDN) { return }

        if ($fmDN) {  
            $functionalManager = Expand-UserList($fmDN)
            $grandBossDN = $functionalManager.ManagerDN        
            if ($recursive) { 
                #Add the current user and their FM to the output list
                $global:fmList += $user
                $global:fmList += $functionalManager
                #If we haven't reached the top, kick it off for the boss's boss
                if ($grandBossDN -and ($grandBossDN -ne $fmDN)) { Get-FunctionalManager($grandBossDN) -recursive }
                else { return }
            }
            else { return $functionalManager }
        }
    }

    #Asset lookups are slightly different--we can query the user by the contents of their "managedobjects" property, but that's unwieldy for this specific lookup
    #instead, query the asset, then return the user ID for the main query, so it can return the requested property value
    if ($queryByAsset) {
        [string]$assetOwnerDN = ([adsisearcher]"(&(objectClass=computer)(objectCategory=computer)(cn=$value))").FindOne().Properties.managedby
        if ($assetOwnerDN) {
            Write-Host "Asset found." -ForegroundColor Green
            $assetOwnerID = ([adsisearcher]"(&(objectCategory=Person)(objectClass=User)(distinguishedname=$assetOwnerDN))").FindOne().Properties.samaccountname
            if ($assetOwnerID) {
                $queryProperty = "samaccountname"
                $value = $assetOwnerID
            }
            else {
                Write-Host "Asset owner with distinguishedname - $assetOwnerDN not found in current domain" -ForegroundColor Red
                return
            }
        }
        else {
            Write-Host "$queryProperty - $value not found in current domain" -ForegroundColor Red
            return
        }
    }

    #Prepare and execute primary query
    $searcher = ([adsisearcher]"(&(objectCategory=Person)(objectClass=User))")
    if ($defaultProperties) {
        $properties = "samaccountname", "name", "employeetype", "usperson", "company", "title", "manager", "userprincipalname", "co", "physicaldeliveryofficename", "firstworkingday", "whencreated", "pwdlastset", "directreports", "memberof"
        foreach ($property in $properties) { $searcher.PropertiesToLoad.Add($property) | out-null }
    }

    $standardQuery = $true
    if ($returnOrgChart -or $returnAsset -or $returnManager) { $standardQuery = $false }

    if ($standardQuery) {
        $searcher.Filter = "(&($queryProperty=$value))"
        if ($findAll) {
            if ($resultProperty) { $result = $searcher.FindAll().Properties.$resultProperty }
            else { $result = $searcher.FindAll().Properties }
        }
        else {
            if ($resultProperty) { $result = $searcher.FindOne().Properties.$resultProperty }
            else { $result = $searcher.FindOne().Properties }
        }
    }
    elseif ($returnManager -or $returnOrgChart) {
        $userDN = ([adsisearcher]"(&(objectCategory=Person)(objectClass=User)($queryProperty=$value))").FindOne().Properties.distinguishedname
        if ($userDN) { 
            if ($returnOrgChart) {
                #Using a global variable is admittedly sloppy here; it would be better practice to return values and pass them on, but this isn't an enterprise desktop application
                #and it didn't seem to merit the trouble (yes, I'm being lazy here). Refactor to your heart's content.
                $global:fmList = @()
                $global:fmList | Get-FunctionalManager($userDN) -recursive
                [array]::reverse($global:fmList)
                
                $count = $global:fmList.count
                if ($count -gt 0) { $result = $global:fmList }
                return
            }
            #($returnManager)
            else { 
                $result = Get-FunctionalManager($userDN) 
                return
            }
         
            if (!$result) {
                Write-Host "Manager not found in current domain for user with $queryProperty : $value" -ForegroundColor Red
                return
            }
        }
        else {
            Write-Host "$queryProperty - $value not found in current domain" -ForegroundColor Red
            return
        }
    }
    elseif ($returnAsset) {
        $userDN = ([adsisearcher]"(&(objectCategory=Person)(objectClass=User)($queryProperty=$value))").FindOne().Properties.distinguishedname
        if ($userDN) {
            $assetSearcher = ([adsisearcher]"(&(objectClass=computer)(objectCategory=computer)(managedby=$userDN))")
            $assetProperties = "distinguishedname", "name", "lastlogon", "operatingsystem", "operatingsystemversion", "dnshostname", "memberof", "whencreated"
            foreach ($property in $assetProperties) { $assetSearcher.PropertiesToLoad.Add($property) | Out-Null }
            $assetDNList = $assetSearcher.FindAll().Properties

            $result = $assetDNList
        }
        else {
            Write-Host "$queryProperty - $value not found in current domain" -ForegroundColor Red
            return
        }
    } 

    #Validate that results are present
    if (!$result) {
        if ($resultProperty) { Write-Host "$resultProperty not found in current domain for account with $queryProperty = $value" -ForegroundColor Red }
        else { Write-Host "Account with $queryProperty = $value not found in current domain" -ForegroundColor Red }
    }
    else {
        #($result)
        if ($resultProperty -eq "directreports") { $result = Expand-UserList($result) | Sort-Object Status, Reports, Name -Descending }

        #Many AD properties will return a list of DNs; clean up the results prior to output
        elseif ($resultProperty -ne "distinguishedname" -and ($result[0] -match "^CN=.*")) {
            $tempList = $result | Sort-Object | ForEach-Object {
                $groupDN = $_
                $commaPosition = $groupDN.IndexOf(",") - 3
                $groupName = $groupDN.Substring(3, $commaPosition)

                $commaPosition += 4
                $length = $groupDN.Length - $commaPosition
                $dnRemainder = $groupDN.Substring($commaPosition, $length)
                $commaPosition = $dnRemainder.IndexOf(",") - 3
                $groupType = $dnRemainder.Substring(3, $commaPosition)      

                $tempHT = @{
                    Name = $groupName
                    Type = $groupType
                }
                #Simply set $tempList to equal the entire ForEach-Object loop on $result, then write the $tempHT to the pipeline instead of using $tempList += $tempHT
                #https://stackoverflow.com/questions/60708578/why-should-i-avoid-using-the-increase-assignment-operator-to-create-a-colle
                $tempHT
            }
            $result = $tempList
            $resultIsDNList = $true
        }
    }
}
##    
##return output
##
END {
    #defaultProperties and orgchart have some additional cleanup that would be ridiculous to duplicate here, so skip over them for now and handle export logic in those areas
    if ($export -and !$defaultProperties -and !$returnOrgChart) { 
        try {
            if ($allProperties) { $result | Select-Object Name, Value | Sort-Object Name | Format-Table -AutoSize | Out-File -FilePath $targetFile -Append }
            elseif ($resultIsDNList) { $result | Select-Object Name, Type | Sort-Object Name | Format-Table -AutoSize | Out-File -FilePath $targetFile -Append }
            elseif ($returnAsset) { $result | ForEach-Object { Write-Output $_ | Format-Table } }
            else { $result | Sort-Object | Out-File -FilePath $targetFile -Append | Out-File -FilePath $targetFile -Append }
            Write-Host "Results successfully exported to $targetFile" -ForegroundColor Green
        }
        catch {
            $lineNumber = $_.InvocationInfo.ScriptLineNumber
            $errorMessage = $_.Exception
            Write-Host "---------------------------------" -ForegroundColor Red
            Write-Host "Unexpected error occurred while attempting to write to destination file $targetFile" -ForegroundColor Red
            Write-Host "---------------------------------" -ForegroundColor Red
            Write-Host "Line number $lineNumber : $errorMessage" -ForegroundColor Red
        }
    }
    else { 
        if ($allProperties) {
            #There _MUST_ be a better way of doing this, but sort-object is not working due to the schema of the result, otherwise I'd just do this:
            #$result | Sort-Object name -Descending | Format-Table -AutoSize }
            #but since it refuses to sort because it's a nested set of property collections, this was a quick and dirty workaround that I'd avoid in a more official codebase
            $userList = $result | ForEach-Object {
                $user = $_
                $propertyNames = $result.PropertyNames | Sort-Object
                
                $userProperties = $propertyNames | ForEach-Object {
                    $userProperty = @{
                        Name  = $_
                        Value = $user.$_
                    } 
                    $userProperty
                }
                $userProperties
            }
            $userList | Sort-Object Name | Select-Object Name, Value | Format-Table -AutoSize
        }
        elseif ($resultIsDNList) { $result | Select-Object Name, Type | Sort-Object Type, Name | Format-Table -AutoSize }
        elseif ($returnAsset) { $result | ForEach-Object { Write-Output $_ | Format-Table } }
        elseif ($returnOrgChart) {
            #first, return the compiled orgchart results for the upwards direction
            if ($export) { $result | Sort-Object | Out-File -FilePath $targetFile -Append | Out-File -FilePath $targetFile -Append }
            else { 
                $result | Sort-Object | Format-Table -AutoSize 
                write-host "Direct Reports:`n---------------" -ForegroundColor Green
            }
            
            #then, run and return the employee's direct reports (non-recursive)
            $searcher.Filter = "(&($queryProperty=$value))"
            $result = $searcher.FindOne().Properties.directreports
            $result = Expand-UserList($result) | Sort-Object Status, Reports, Name -Descending 

            if ($export) { $result | Sort-Object | Out-File -FilePath $targetFile -Append | Out-File -FilePath $targetFile -Append }
            else { $result | Sort-Object | Format-Table -AutoSize }
        }
        elseif ($defaultProperties) {
            $tempResult = $result | ForEach-Object {
                $user = $_
                $fmDN = $user.manager -join ";"

                #Rarely, there is no FM listed; in that case, don't substring null value
                try { $fmName = $fmDN.substring(3, ($fmDN.IndexOf(",OU") - 3)) }
                catch { $fmName = $fmDN }

                $tempObj = [pscustomobject] @{
                    ID            = $user.samaccountname -join ";"
                    Name          = $user.name -join ";"
                    Status        = $user.employeetype -join ";"
                    USPerson      = $user.usperson -join ";"
                    BU            = $user.company -join ";"
                    Title         = $user.title -join ";"
                    Manager       = $fmName
                    Email         = $user.userprincipalname -join ";"
                    Country       = $user.co -join ";"
                    Office        = $user.physicaldeliveryofficename -join ";"
                    StartDate     = $user.firstworkingday -join ";"
                    PwdLastSet    = [datetime]::FromFileTime($user.pwdlastset[0])
                    DirectReports = $user.directreports.count
                    MemberOf      = $user.memberof.count
                }
                $tempObj
            }
            $result = $tempResult
            if ($export) { Write-Output $result | Select-Object ID, Name, Status, USPerson, Title, Manager, Email, Country, Office, StartDate, PwdLastSet, DirectReports, MemberOf | Sort-Object ID | Out-File -FilePath $targetFile -Append }
            else { Write-Output $result | Select-Object ID, Name, Status, USPerson, Title, Manager, Email, Country, Office, StartDate, PwdLastSet, DirectReports, MemberOf | Sort-Object ID }
        }
        else { $result | Sort-Object | Format-Table -AutoSize }
    }
}