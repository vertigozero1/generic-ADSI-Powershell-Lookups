#param ([switch]$all = $false)
function Format-PaddedOutput ([Int16]$charLength, [string]$leftText, [string]$rightText, [string]$foregroundColor = "White", [switch]$piped) {
    $numSpaces = $charLength - $leftText.Length
    if ($piped) { $paddedText = "|$leftText{0,$numSpaces}|" -f $rightText }
    else { $paddedText = "$leftText{0,$numSpaces}" -f $rightText }
    Write-Host $paddedText -ForegroundColor $foregroundColor
}

$targetPath = "C:\Users\p0018192\OneDrive - Parsons Corp\Team PowerShell Scripts"
$archivePath = "C:\Users\p0018192\OneDrive - Parsons Corp\Team PowerShell Scripts\Archived"

$targetPathValid = Test-Path $targetPath
if (!$targetPathValid) {
    Write-Host "Destination folder $targetPath invalid." -ForegroundColor Red
    Return
}
$archivePathValid = Test-Path $archivePath
if (!$archivePathValid) {
    Write-Host "Archive folder $archivePath invalid." -ForegroundColor Red
    Return
}
Write-Host "Destination folders valid." -ForegroundColor Green

$scriptsInFolder = Get-ChildItem *.ps1 -File
$fileCount = $scriptsInFolder.Count - 1

Write-Host "$fileCount total file(s) found in working folder." -ForegroundColor Green

$moveCount = 0
$moveList = @()

$thisScriptName = Split-Path -Leaf $PSCommandPath

#Validate file list
foreach ($sourceFilePath in $scriptsInFolder) {
    $moving = $true

    $filename = $sourceFilePath.Name.ToLower()

    if ($filename -eq $thisScriptName) { Continue }
    
    #Modify this list to adjust which files are ignored for deployment to the share folder
    $exclusionText = "test", "deprecated", "sandbox" | Sort-Object
    foreach ($string in $exclusionText) {
        if ($filename.Contains($string)) { 
            $moving = $false 
            Write-Host "Excluding $filename (`"$string`")" -ForegroundColor DarkGray
            Break #File has been identified for exclusion, no need to keep checking it
        }
    }

    if ($moving) {
        $numSpaces = 40 - ($filename.Length)
        $paddedText = "{0,10}" -f '' + $filename + "{0,$numSpaces}" -f "will be deployed"
        Write-Host $paddedText -ForegroundColor Green

        $moveList += $sourceFilePath
        $moveCount++
    }
}

$skipCount = $fileCount - $moveCount
Write-Host "`n$moveCount file(s) will be deployed; $skipCount will be skipped`n"

Write-Host "Files will be deployed to $targetPath"
Write-Host "Existing files in destination will be archived to $archivePath`n"

Format-PaddedOutput 100 "Deployment Folder..." "...Archive Folder" -piped

foreach ($sourceFile in $moveList) {
    $sourceFileName = $sourceFile.Name

    $targetFile = "$targetPath\$sourceFileName"
    $fileExists = Test-Path $targetFile
    if ($fileExists) {
        $sourceFileChildItem = Get-ChildItem $sourceFile
        $targetFileChildItem = Get-ChildItem $targetFile

        $targetFileLastModified = $targetFileChildItem.LastWriteTime.ToString("yyyyMMdd_HHMM")
        $sourceFileLastModified = $sourceFileChildItem.LastWriteTime.ToString("yyyyMMdd_HHMM")

        $archiveFileName = $sourceFileName.Substring(0, ($sourceFileName.Length - 4)) + "-$targetFileLastModified.ps1"
        $archiveFile = "$archivePath\$archiveFileName"
        
        Format-PaddedOutput 100 "$sourceFileName found" "...will archive as $archiveFileName" Green -piped
        if ($sourceFileLastModified -eq $targetFileLastModified) {
            Format-PaddedOutput 100  "$sourceFileName last write date matches deployed version..." "...skipping deployment" -foregroundColor DarkGray -piped
            Write-Host ""
            Continue
        }

        try {
            #Test for an existing file which would collide with our planned move
            $archivePathValid = Test-Path $archiveFile
            if ($archivePathValid) {
                Format-PaddedOutput 100 " $archiveFilename already present..." -foregroundColor Yellow -piped
                $offsetLength = $archiveFileName.Length - 4
                for ($i = 0; $i -lt 10; $i++) {
                    $archiveFileName = $archiveFileName.Substring(0, $offsetLength) + "_$i.ps1"
                    $archiveFile = "$archivePath\$archiveFileName"
                    $archivePathValid = Test-Path $archiveFile
                    if (!$archivePathValid) {
                        Format-PaddedOutput 100 " $archiveFileName available!" -ForegroundColor Green -piped
                        $i = 10
                    }
                    else { Format-PaddedOutput 100 " $archiveFileName already present..." -ForegroundColor DarkGray -piped }
                }
                if ($archivePathValid) {
                    Write-Host "ERROR: No available archive destination... unable to transfer $sourceFileName safely without overwrites occurring.`nPlease check the directory contents and try again once the issue is resolved." -ForegroundColor Red
                    Break  
                }
            }
            Move-Item $targetFile -Destination $archiveFile
        }
        catch {
            Write-Host "---------------------------------" -ForegroundColor Red
            Write-Host "Unexpected error while attempting to move target file to archive`nTarget file:  $targetFile`nArchive file: $archiveFile" -ForegroundColor Red
            Write-Host $_.Exception
            Write-Host "---------------------------------" -ForegroundColor Red
            Break
        }
    }
    
    if ($archivePathValid) { $message = "Archive successful..." }
    else { $message = "No matching file in destination..." }
    
    Format-PaddedOutput 100 $message "...deploying $sourceFileName" Green -piped
    Write-Host ""

    try { Copy-Item $sourceFile -Destination $targetFile }
    catch {
        Write-Host "---------------------------------" -ForegroundColor Red
        Write-Host "Unexpected error while attempting to copy source file to destination`nSource file:  $sourceFile`nDestination file: $targetFile" -ForegroundColor Red
        Write-Host $_.Exception
        Write-Host "---------------------------------" -ForegroundColor Red
        Break
    }
}
Write-Host "`nOperation completed successfully." -ForegroundColor Green