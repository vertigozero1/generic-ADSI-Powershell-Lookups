param([string]$sourceFilePath, [string]$targetPath);
#Test values for simplified debugging in IDE
#$sourceFilePath = "C:\devtemp\vscode\powershell\test.csv"

###
### Initialization and input validation
###

if (!$sourceFilePath) {
    Write-Host "ERROR: Missing required parameter value for sourceFilePath, which should contain the full path to the input CSV file. "
    Write-Host "    *NOTE* The first (header) row of the CSV must contain the name of the AD property which will be used to query each line item value"
    Write-Host "Example usage: -sourceFilePath `"C:\Temp\idList.csv`" -targetPath 'C:\Temp\'"
    Write-Host "             : -sourceFilePath `"idList.csv`""
    Return
}
if (!$targetPath) { $targetPath = (Get-Location).Path }
else {
    $pathValid = Test-Path $targetPath
    if (!$pathValid) {
        Write-Host "ERROR: Invalid targetPath: $targetPath" -ForegroundColor Red
        Return
    }
}

$dateTime = $((Get-Date -Format "yyyyMMdd-HHmm").ToString())
$sourceFileName = [IO.Path]::GetFileNameWithoutExtension($sourceFilePath)
$targetFile = $targetPath + "\$dateTime userBulkLookup $sourceFileName.csv"

try { $csv = Import-Csv $sourceFilePath -Delimiter "," }
catch { 
    $lineNumber = $_.InvocationInfo.ScriptLineNumber
    $errorMessage = $_.Exception
    Write-Host "---------------------------------" -ForegroundColor Red
    Write-Host "Unexpected error occurred while importing source file" -ForegroundColor Red
    Write-Host "---------------------------------" -ForegroundColor Red
    Write-Host "Line number $lineNumber : $errorMessage" -ForegroundColor Red
    Return  
}

$fileSize = $csv.Count
$lookupFieldName = $csv[0].psobject.properties.name.ToString().ToLower()

Write-Host "`nSource file successfully imported. $fileSize line(s) found, including header." -ForegroundColor Green
Write-Host "Using file header `"$lookupFieldName`" as the property to query for each line item value." -ForegroundColor Cyan

#Establish some quick aliases for simplicity of querying--I know it's a hideous way to format a switch/case, but that's how the auto-formatting style does it \_(-.-)_/
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
}

$userArray = @()
$notFoundArray = @()

##
## Main code block
##

$totalObjects = $csv.count - 1
$i = 0

$userCount = 0
$csv | ForEach-Object {
    $i++
    #Make sure that if someone runs a test CSV with one item... we don't end up trying to divide by zero
    if ($totalObjects -gt 0) {
        $percentComplete = ($i / $totalObjects) * 100
        if ($percentComplete -gt 100) { $percentComplete = 100 } #shouldn't happen, but prevent it just in case
    }

    [string]$value = $_.psobject.properties.value.ToString()
    $queryText = "$lookupFieldName : $value"

    #Since the Manager property uses DN, do a quick query to return the necessary value so the normal query can function properly
    if ($lookupFieldName -eq "manager") {
        $manager = ([adsisearcher]"(&(objectCategory=Person)(objectClass=User)(name=$value))").FindOne().Properties.distinguishedname
        if ($manager) { $value = $manager }
        else {
            Write-Host "$queryText... not found" -ForegroundColor Red
            $notFoundArray += "`n$value"
            Return
        }
    }

    #Prepare the query
    $userSearch = ([adsisearcher]"(&(objectCategory=Person)(objectClass=User)($lookupFieldName=$value))")

    #Extract the properties we care about. 
    #    *NOTE* TO MODIFY THE LIST OF PROPERTIES RETURNED:
    #           Add the desired values to the list below, using the existing ones as an example.
    #           Make sure that you ALSO modify the splatted hash tables and output section at the end of the script, to match the values
    $userProperties = "employeeid", "name", "employeetype", "usperson", "company", "title", "manager", "userprincipalname", "physicaldeliveryofficename", "firstworkingday"
    foreach ($property in $userProperties) { $userSearch.PropertiesToLoad.Add($property) | out-null }
    
    #Actual query
    $user = $userSearch.FindAll().Properties

    #Handle results
    if ($user) {
        $userCount++
        $name = $user.name -join ";"
        #Write-Host "$queryText... $name found" -ForegroundColor Green
        $progressParameters = @{
            Id              = 1
            Status          = "$queryText... $name found"
            Activity        = "Processing bulk query by $lookupFieldName for $totalObjects user accounts..."
            PercentComplete = $percentComplete
        }
        Write-Progress @progressParameters
    }
    else {
        #Write-Host "$queryText... not found" -ForegroundColor Red
        $fileSize -= 1
        #If the first lookup failed, validate the lookup field with user prior to continuing
        if ($userCount -lt 1 -and $fileSize -ge 1) {
            $title = "Initial query failed; would you like to continue querying the remaining $fileSize lines?"
            $choices = @(
                ("&Y", "Yes; the file is valid, it was just an unfortunate first line that happened not to be found. We're good, please proceed."), #0
                ("&N", "No... on second thought, that's doesn't look right. Stop now, and I'll go adjust the source file before trying again.") #1
            ) | ForEach-Object { New-Object System.Management.Automation.Host.ChoiceDescription $_ }

            $message = "Response:"

            $userInput = $Host.UI.PromptForChoice($title, $message, $choices, 1)
            if ($userInput -eq 1) { Exit }
        }
        $progressParameters = @{
            Id              = 1
            Activity        = "Processing bulk query by $lookupFieldName..."
            Status          = "$queryText... not found"
            PercentComplete = $percentComplete
        }
        Write-Progress @progressParameters

        $notFoundArray += "`n$value"
        Return
    }
    
    #Since the manager query field will most likely return a list of users in and of itself, handle the results the same as any other lines for consistency
    #Without this code block, it plops all of the relevant values into one single line, which is a mess to look at
    if ($lookupFieldName -eq "manager") {
        #foreach ($report in $user) {
        $userArray = foreach ($report in $user) {
            #Manager field returns a DN, so extract the person's name
            $fmDN = $report.manager -join ";"
            $fmName = $fmDN.substring(3, ($fmDN.IndexOf(",OU") - 3))

            $tempObj = [pscustomobject] @{
                ID        = $report.employeeid -join ";"
                Name      = $report.name -join ";"
                Status    = $report.employeetype -join ";"
                USPerson  = $report.usperson -join ";"
                BU        = $report.company -join ";"
                Title     = $report.title -join ";"
                Manager   = $fmName
                Email     = $report.userprincipalname -join ";"
                Office    = $report.physicaldeliveryofficename -join ";"
                StartDate = $report.firstworkingday -join ";"
            }
            #$userArray += $tempObj
            $tempObj
        }
    }
    else {
        #Standard result--not a manager lookup
        $fmDN = $user.manager -join ";"
        #Rarely, there is no FM listed; in that case, don't substring null value
        try { $fmName = $fmDN.substring(3, ($fmDN.IndexOf(",OU") - 3)) }
        catch { $fmName = $fmDN }

        $tempObj = [pscustomobject] @{
            ID        = $user.employeeid -join ";"
            Name      = $user.name -join ";"
            Status    = $user.employeetype -join ";"
            USPerson  = $user.usperson -join ";"
            BU        = $user.company -join ";"
            Title     = $user.title -join ";"
            Manager   = $fmName
            Email     = $user.userprincipalname -join ";"
            Country   = $user.co -join ";"
            Office    = $user.physicaldeliveryofficename -join ";"
            StartDate = $user.firstworkingday -join ";"
        }
        #Add results to the output array and increase the number of found members
        $userArray += $tempObj
    }
}

###Produce the actual output
#    *NOTE* If you modified the user properties above, match the names in the Write-Output lines below (for all outputs)
#           Use the field name you specified in the hash table if it does not match the actual AD property
#           Ex. "Email" in the hash table and Select-Object list is actually the Active Directory UserPrincipalName
try { 
    Write-Host " "
    Write-Host "Found $userCount users from "$sourceFilePath -ForegroundColor Green
    Write-Output $userArray | Sort-Object name | Select-Object ID, Name, Status, USPerson, BU, Title, Manager, Email, Office, StartDate | Export-CSV -path $targetFile -NoTypeInformation 

    if ($notFoundArray.Count -gt 0) { 
        Write-Host $notFoundArray.Count "not found" -ForegroundColor Red
        [string]$output = "`nNot found:`n----------" + $notFoundArray 
        try { $output | Out-File -FilePath $targetFile -Append }
        catch {
            $lineNumber = $_.InvocationInfo.ScriptLineNumber
            $errorMessage = $_.Exception
            Write-Host "---------------------------------" -ForegroundColor Red
            Write-Host "Unexpected error occurred while attempting to write to destination file $targetFile" -ForegroundColor Red
            Write-Host "---------------------------------" -ForegroundColor Red
            Write-Host "Line number $lineNumber : $errorMessage" -ForegroundColor Red
        }
    }

    Write-Host " "
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