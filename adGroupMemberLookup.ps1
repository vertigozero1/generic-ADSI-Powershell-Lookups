param([string]$groupName, [string]$targetPath, [switch]$export = $false, [switch]$recursive = $false, [switch]$count = $false)
# Test Values; uncomment these to run from an IDE without requiring CLI
#$recursive = $true
#$export = $true
#$groupName = "epm_powershell_exception" #BIG NESTED MEMBERSHIP LIST
#$groupName = "EntReporter_Rpt_Operators" #A few nested subgroups, not a big list--good for testing/demoing without going wild

##
## Input validation section defined as a function to allow collapsing in vsCode
## Script documentation is functionally present within the first validation step--if no args are provided, it spits out help text
##

function Confirm-Input ([string]$groupName, [string]$targetPath, [switch]$export, [switch]$recursive) {
    # Check for required input and display help text if missing
    if (!$groupName) {
        Write-Host "ERROR: Missing required parameter value for groupName, which should contain the friendly name of the AD group to be queried. " -ForegroundColor Red
        Write-Host "       PARAMETERS:"
        Write-Host "           groupName  : Required. Name of the AD group--must be an exact match (of the 'friendly' name, not DN). Use adGroupLookup.ps1 to query groups by name"
        Write-Host "           targetPath : Optional. Specifies a destination directory for the output CSV."
        Write-Host "                        If a value is provided for this parameter, the script will automatically export; there is no need to use both input parameters"
        Write-Host "           -export    : Optional, switch parameter. Adding -export will save the results to a file in the current working directory"
        Write-Host "           -count     : Optional, switch parameter. Returns a count of members in the specified group (does not include nested members, incompatible w/ recursion)"
        Write-Host "           -recursive : Optional, switch parameter. Standard behavior is to return the names of any nested groups; enabling recursion will process any and all"
        Write-Host "                        nested groups and their nested sub-groups, etc. until a full list of all effective members of the top-level group is returned."
        Write-Host "       *NOTE: the script will provide a progress bar of the overall query based upon the total count of members identified. When running recursively, this"
        Write-Host "              total will change to reflect newly-found members of sub-groups--the progress bar will adjust according to the new total."
        Write-Host " "
        Write-Host "Example usage:" -ForegroundColor Green
        Write-Host "    adGroupMemberLookup -groupName 'BISO' -targetPath 'C:\Temp'" -ForegroundColor Cyan
        Write-Host "           RESULT: Exports a CSV to C:\Temp\20230221-0951 adGroup BISO members.csv" -ForegroundColor Gray
        Write-Host "    adGroupMemberLookup webfilter_cloudfileshare -export" -ForegroundColor Cyan
        Write-Host "           RESULT: Exports a CSV to [current folder]\20230221-0951 adGroup webfilter_cloudfileshare members.csv" -ForegroundColor Gray
        Write-Host "    adGroupMemberLookup BISO" -ForegroundColor Cyan
        Write-Host "           RESULT: Displays a table of results on screen." -ForegroundColor Gray
        Write-Host "    adGroupMemberLookup BISO -count" -ForegroundColor Cyan
        Write-Host "           RESULT: Displays a quick count of member objects in the BISO group." -ForegroundColor Gray
        Write-Host "    adGroupMemberLookup entreporter_rpt_operators -export -recursive" -ForegroundColor Cyan
        Write-Host "           RESULT: Exports a CSV of all members of the group (and members of any groups which are part of the queried group)"
        Break
    }

    if ($groupName.contains("*")) { 
        Write-Host "`n***WARNING***" -ForegroundColor Red
        Write-Host "Use of a wildcard can result in a very intensive query with an excessive volume of results, which may not meet expectations.`n" -ForegroundColor Red
        Write-Host "It will return all members of groups with names matching the wildcard string, with no indication of the group names." -ForegroundColor Yellow
        Write-Host "All users will be sorted by name and may appear in the list multiple times, depending upon their membership in matching groups.`n" -ForegroundColor Yellow
        Write-Host "Once the query is committed, it will be sent to AD; stopping the script execution beyond this point will not halt the query." -ForegroundColor Red
        Write-Host "`nPrior to running this script with a wildcard, it is HIGHLY recommended to perform the same wildcard query with adGroupLookup.ps1." -ForegroundColor Blue
        Write-Host "Doing so will return a full list of matching groups with member counts, to test your query and ensure scope of output.`n" -ForegroundColor Blue

        $title = "Choose wisely:"
        $choices = @(
        ("&Y", "Yes, I know what I'm doing. You're not my supervisor. Send it."), #0
        ("&N", "No... on second thought, I'll double-check my query in adGroupLookup and come back if everything looks OK there.") #1
        ) | ForEach-Object { New-Object System.Management.Automation.Host.ChoiceDescription $_ }

        $message = "Are you certain that you would like to continue with the query?"

        $userInput = $Host.UI.PromptForChoice($title, $message, $choices, 1)
        if ($userInput -eq 1) { Break }
    }

    if($recursive -and $count){
        Write-Host "Recursive and Count arguments are mutually exclusive, since recursion requires additional queries.`nCount is intended to return an immediate count of top-level root group members.`nIgnoring the recursive argument, and only using count." -ForegroundColor Yellow
        $recursive = $false
    }

    ###Confirm that the group name is valid and will return results
    Write-Host "`nValidating query for AD group '$groupName'...`n"
    try {
        $groupNameList = ([adsisearcher]"(&(objectClass=group)(sAMAccountName=$groupName))").FindAll().properties.name | Sort-Object
        if ($groupNameList) {
            $groupCount = $groupNameList.count
            Write-Host "$groupCount group(s) found." -ForegroundColor Green
            Write-Host "`nQuerying members... Please be patient as this may take a moment, depending upon the number of members."
        }
        else { 
            Write-Host "AD Group $groupName is invalid, or the group contains no members." -ForegroundColor Red
            Write-Host "Please verify the name and spelling, then try again"
            Break
        }
    }
    catch {
        Write-Host "---------------------------------`nUnexpected error occurred while querying AD group $groupName.`n" -ForegroundColor Red
        Write-Host $_.Exception
        Break
    }
    if ($targetPath) {
        $pathValid = Test-Path $targetPath
        if (!$pathValid) {
            Write-Host "ERROR: Invalid targetPath: $targetPath" -ForegroundColor Red
            Break
        }
    }
}

##
## Defined as a function to simplify main code block
##
function Get-ObjectByDN ([string]$dn) {
    #Prep the query
    $searcher = [adsisearcher]"(distinguishedName=$dn)"

    #Extract the properties we care about. 
    #    *NOTE* TO MODIFY THE LIST OF PROPERTIES RETURNED:
    #           Add the desired values to the list below, using the existing ones as an example.
    #           Make sure that you ALSO modify the splatted hash tables and output section at the end of the script, to match the values
    
    $isGroup = $false
    $isServiceAccount = $false
    
    if ($dn.Contains("OU=Groups")) { 
        $isGroup = $true
        $objectProperties = "name", "description", "member", "whencreated", "distinguishedname"
    }
    elseif ($dn.Contains("OU=Service Accounts")) {
        $isServiceAccount = $true
        $objectProperties = "samaccountname", "name", "description", "memberof", "whencreated", "userprincipalname", "pwdlastset"
    }
    else { $objectProperties = "samaccountname", "name", "employeetype", "usperson", "company", "title", "manager", "userprincipalname", "physicaldeliveryofficename", "firstworkingday", "whencreated", "pwdlastset" }
    
    foreach ($property in $objectProperties) { $searcher.PropertiesToLoad.Add($property) | out-null }
    
    #Actual query
    $object = $searcher.FindOne().Properties

    if ($isGroup) {
        $tempObj = [pscustomobject] @{
            Type        = "Group"
            Name        = $object.name -join ";"
            Description = $object.description -join ";"
            MemberCount = $object.member.count
            MemberDNs   = $object.member
            WhenCreated = $object.whencreated -join ";"
            PwdLastSet  = "N/A"
            DN          = $object.distinguishedname -join ";"
        }
    }
    elseif ($isServiceAccount) {
        $tempObj = [pscustomobject] @{
            Type            = "Service Account"
            ID              = $object.samaccountname -join ";"
            Name            = $object.name -join ";"
            Email           = $object.userprincipalname -join ";"
            Description     = $object.description -join ";"
            GroupMembership = $object.memberof.count
            WhenCreated     = $object.whencreated -join ";"
            PwdLastSet      = $object.pwdlastset -join ";"
        }
    }
    else {
        #Since the FM field returns a full distinguished name value, grab it and substring to extract the actual name
        $fmDN = $object.manager -join ";"
        #Rarely, there is no FM listed; in that case, don't substring null value
        try { $fmName = $fmDN.substring(3, ($fmDN.IndexOf(",OU") - 3)) }
        catch { $fmName = $fmDN }

        $tempObj = [pscustomobject] @{
            Type        = "User Account"
            ID          = $object.samaccountname -join ";"
            Name        = $object.name -join ";"
            Status      = $object.employeetype -join ";"
            USPerson    = $object.usperson -join ";"
            BU          = $object.company -join ";"
            Title       = $object.title -join ";"
            Manager     = $fmName
            Email       = $object.userprincipalname -join ";"
            Office      = $object.physicaldeliveryofficename -join ";"
            StartDate   = $object.firstworkingday -join ";"
            WhenCreated = $object.whencreated -join ";"
            PwdLastSet  = $object.pwdlastset -join ";"
        }
    }
    
    [hashtable] $outputHT = @{
        Object           = $tempObj
        IsGroup          = $isGroup
        IsServiceAccount = $isServiceAccount
    }
    Return $outputHT
}

##
###Main code block
##

Confirm-Input $groupName $targetPath $export $recursive

#Automatically set script to export results to CSV if a path is specified
if ($targetPath) { $export = $true }
#If we're exporting results to CSV, establish the full destination file path
if ($export) {
    if (!$targetPath) { $targetPath = (Get-Location).Path }
    $dateTime = $((Get-Date -Format "yyyyMMdd-HHmm").ToString())
    if ($recursive) { $targetFile = $targetPath + "\$dateTime adGroupRECURSIVE $groupName members.csv" }
    else { $targetFile = $targetPath + "\$dateTime adGroup $groupName members.csv" }
}
$dateTime = $((Get-Date -Format "yyyy_MM_dd-HH:mm").ToString())

###Actual Query
$objectDNList = ([adsisearcher]"(&(objectClass=group)(sAMAccountName=$groupName))").FindAll().properties.member | Sort-Object

#Split the results by type--direct user account members, service account members, and nested sub-groups with their own members
$global:userArray = @()
$global:serviceAccountArray = @()
$global:groupArray = @()
$global:i = -1

function Get-GroupMembers ($objectDNs) {
    try {    
        if ($tempObjectDNs -ne $objectDNs) { 
            $totalObjects += $objectDNs.count 
            $tempObjectDNs = $objectDNs
        }
        if($count){
            Write-Host "Total initial count of top-level members: $totalObjects`n" -ForegroundColor Green
            break
        }
        $objectDNs | ForEach-Object {
            $global:i++
            $dn = $_

            $tempHT = Get-ObjectByDN $dn
            
            $objectType = $tempHT.Object.Type
            $objectName = $tempHT.Object.Name
            $percentComplete = ($global:i / $totalObjects) * 100
            if ($percentComplete -gt 100) { $percentComplete = 100 }
            $progressParameters = @{
                Activity        = "Querying $totalObjects group member(s)..."
                Status          = "$objectType found: $objectName"
                PercentComplete = $percentComplete
            }
            Write-Progress @progressParameters

            if ($tempHT.IsGroup) {
                $global:groupArray += $tempHT.Object
                if ($recursive) { 
                    $members = $tempHT.Object.MemberDNs
                    Get-GroupMembers $members 
                }
            }
            elseif ($tempHT.IsServiceAccount) { $global:serviceAccountArray += $tempHT.Object }
            else { $global:userArray += $tempHT.Object }
        }    
    }
    catch {
        $lineNumber = $_.InvocationInfo.ScriptLineNumber
        $errorMessage = $_.Exception
        Write-Host "---------------------------------" -ForegroundColor Red
        Write-Host "Unexpected error occurred while querying details of group member: $dn" -ForegroundColor Red
        Write-Host "---------------------------------" -ForegroundColor Red
        Write-Host "Line number $lineNumber : $errorMessage" -ForegroundColor Red
        Break
    }
}
Get-GroupMembers $objectDNList

###Produce the actual output
#    *NOTE* If you modified the user properties above, match the names in the Write-Output lines below (for all outputs)
#           Use the field name you specified in the hash table if it does not match the actual AD property
#           Ex. "Email" in the hash table and Select-Object list is actually the Active Directory UserPrincipalName

$userCount = $global:userArray.Count
$serviceAccountCount = $global:serviceAccountArray.count
$groupCount = $global:groupArray.count

try { 
    #Clear-Host
    if ($recursive) { Write-Host "Recursive search enabled--all nested group members are represented in the data below." -ForegroundColor Cyan }
    Write-Host "`n$groupName members: $userCount user(s), $serviceAccountCount account(s), $groupCount and nested group(s)"
    Write-Host "Current as of $dateTime"
    Write-Host "---------------------------------"
    $propertiesForExport = "Type", "ID", "Name", "Status", "USPerson", "BU", "Title", "Manager", "Email", "Office", "StartDate", "WhenCreated", @{Name = "pwdLastSet"; Expression = { [datetime]::FromFileTime($_.pwdLastSet) } }, "GroupMembership", "MemberCount", "Description"

    if ($userCount -ge 1) {
        if ($recursive) { Write-Host "ALL USER ACCOUNT(S)" -ForegroundColor Green }
        else { Write-Host "USER ACCOUNT(S)" -ForegroundColor Green }

        if ($export) { Write-Output $global:userArray | Select-Object $propertiesForExport | Export-CSV -path $targetFile -NoTypeInformation -Append }
        Write-Output $global:userArray | Select-Object ID, Name, Status, USPerson, BU, Title, Manager, Email, Office, StartDate, WhenCreated, @{Name = "pwdLastSet"; Expression = { [datetime]::FromFileTime($_.pwdLastSet) } } | Format-Table -AutoSize
    }
    if ($serviceAccountCount -ge 1) {
        if ($recursive) { Write-Host "`nALL SERVICE ACCOUNT(S)" -ForegroundColor Green }
        else { Write-Host "`nSERVICE ACCOUNT(S)" -ForegroundColor Green }

        if ($export) { Write-Output $global:serviceAccountArray | Select-Object $propertiesForExport | Export-CSV -path $targetFile -NoTypeInformation -Append -Force }
        Write-Output $global:serviceAccountArray | Select-Object ID, Name, Email, GroupMembership, WhenCreated, @{Name = "pwdLastSet"; Expression = { [datetime]::FromFileTime($_.pwdLastSet) } }, Description | Format-Table -AutoSize
    }
    if ($groupCount -ge 1) {
        if ($recursive) { Write-Host "`nALL NESTED GROUP(S)" -ForegroundColor Green }
        else { Write-Host "`nNESTED GROUP(S)" -ForegroundColor Green }

        if ($export) { Write-Output $global:groupArray | Select-Object $propertiesForExport | Export-CSV -path $targetFile -NoTypeInformation -Append -Force }
        Write-Output $global:groupArray | Select-Object Name, MemberCount, Description | Format-Table -AutoSize 
    }
    if ($export) { Write-Host "Results successfully exported to $targetFile" -ForegroundColor Green }
}
catch { 
    $lineNumber = $_.InvocationInfo.ScriptLineNumber
    $errorMessage = $_.Exception
    Write-Host "---------------------------------" -ForegroundColor Red
    Write-Host "Unexpected error occurred while attempting to write to destination file $targetFile" -ForegroundColor Red
    Write-Host "---------------------------------" -ForegroundColor Red
    Write-Host "Line number $lineNumber : $errorMessage" -ForegroundColor Red
}