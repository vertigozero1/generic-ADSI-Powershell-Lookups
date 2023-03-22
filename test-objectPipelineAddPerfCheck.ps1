1..20 | ForEach-Object {
    $size = 10 * $_
    $Performance = @{Size = $Size}
    $Performance.Pipeline = (Measure-Command {
        $Collection = 1..$Size | ForEach-Object {
            [PSCustomObject]@{Index = $_; Name = "Name$_"}
        }
    }).Ticks
    $Performance.Increase = (Measure-Command {
        $Collection = @()
        1..$Size | ForEach-Object {
            $Collection  += [PSCustomObject]@{Index = $_; Name = "Name$_"}
        }
    }).Ticks
    [pscustomobject]$Performance
} | Format-Table *,@{n='Factor'; e={$_.Increase / $_.Pipeline}; f='0.00'} -AutoSize