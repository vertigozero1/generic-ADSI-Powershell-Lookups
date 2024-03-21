# script queries all user accounts whose passwords were reset during a specified time period--this was written to suit a unique use case
$targetPath = "C:\devtemp\vsCode\git\generic-ADSI-Powershell-Lookups"
$pathValid = Test-Path $targetPath
            if (!$pathValid) {
                Write-Host "ERROR: Invalid targetPath: $targetPath" -ForegroundColor Red
                return
            }

$dateTime = $((Get-Date -Format "yyyyMMdd-HHmm").ToString())

$targetFile = $targetPath + "\$dateTime adQuery-PwdLastSet-4Days.txt"

$startDate = (Get-Date).AddDays(-18).ToFileTimeUTC()
$endDate = (Get-Date).AddDays(-14).ToFileTimeUTC()
#$ADSIDate = (Get-Date).AddDays(-4).ToFileTimeUTC()
try {
    #$searcher = ([adsisearcher]"(&(objectCategory=Person)(objectClass=User))")
    #$searcher.Filter = "(&(pwdLastSet>=$ADSIDate))"
    #$searcher = ([adsisearcher]"(&(objectCategory=Person)(objectClass=User)(pwdLastSet>=$ADSIDate))")
    $searcher = ([adsisearcher]"(&(objectCategory=Person)(objectClass=User)(pwdLastSet>=$startDate)(pwdLastSet<=$endDate))")
    
    $properties = "samaccountname", "name", "employeetype", "usperson", "company", "title", "manager", "userprincipalname", "co", "physicaldeliveryofficename", "telephonenumber", "firstworkingday", "whencreated", "pwdlastset", "directreports", "memberof", "managedobjects", "lastlogontimestamp"
            foreach ($property in $properties) { $searcher.PropertiesToLoad.Add($property) | out-null }
    
    $resultCollection = $searcher.FindAll().Properties
    
    if(!$resultCollection) {
        Write-Host "none found"
        Break
    }

    $tempResult = $resultCollection | ForEach-Object {
        $user = $_
        $fmDN = $user.manager -join ";"

        #Rarely, there is no FM listed; in that case, don't substring null value
        try { $fmName = $fmDN.substring(3, ($fmDN.IndexOf(",OU") - 3)) }
        catch { $fmName = $fmDN }

        $tempObj = [pscustomobject] @{
            ID             = $user.samaccountname -join ";"
            Name           = $user.name -join ";"
            Status         = $user.employeetype -join ";"
            USPerson       = $user.usperson -join ";"
            BU             = $user.company -join ";"
            Title          = $user.title -join ";"
            Manager        = $fmName
            Email          = $user.userprincipalname -join ";"
            OfficePhone    = $user.telephonenumber -join ";"
            Country        = $user.co -join ";"
            Office         = $user.physicaldeliveryofficename -join ";"
            StartDate      = $user.firstworkingday -join ";"
            PwdLastSet     = [datetime]::FromFileTime($user.pwdlastset[0])
            #LastLogon      = [datetime]::FromFileTime($user.lastlogontimestamp[0])
            DirectReports  = $user.directreports.count
            MemberOf       = $user.memberof.count
            ManagedObjects = $user.managedobjects.count
        }
        $tempObj
    }
    $resultCollection = $tempResult

    $resultCollection | Select-Object ID, Name, Status, USPerson, Title, Manager, Email, OfficePhone, Country, Office, StartDate, PwdLastSet, LastLogon, DirectReports, MemberOf, ManagedObjects | Sort-Object ID | Export-CSV -path $targetFile -NoTypeInformation
}
catch {
    $lineNumber = $_.InvocationInfo.ScriptLineNumber
    $errorMessage = $_.Exception
    Write-Host "Line number $lineNumber : $errorMessage" -ForegroundColor Red
}
