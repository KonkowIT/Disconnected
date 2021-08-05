$PSDefaultParameterValues['*:Encoding'] = 'utf8'
$host.UI.RawUI.WindowTitle = "Disconnected"

# Date
$dateNow = Get-Date -format "yyyy-MM-dd HH:mm:ss"
$dateResult = get-date -format "dd MMMM yyyy, HH:mm"

# Dont check this SN
$dontCheck = @()

# Networks
$allNetowrks = @(
    @{network = "Amic Energy"; days = 1},
    @{network = "BNP Paribas"; days = 1},
    @{network = "CityFit"; days = 1},
    @{network = "Empik"; days = 1}
    @{network = "Empik Future Store"; days = 1},
    @{network = "Farsz Bar"; days = 1},
    @{network = "Lagardere"; days = 1},
    @{network = "Lagardere Lotniska"; days = 1},
    @{network = "Media Markt"; days = 0},
    @{network = "Pakiet Tranzyt"; days = 0},
    @{network = "PKP"; days = 0},
    @{network = "TUI"; days = 1},
    @{network = "TUI Next Gen"; days = 1}
)

# Slack channel
$slackChannel = "sn_disconnected"

function Send-ToSlack {
    param (
        [string]$message,
        [string]$channel
    )

    try {
        [Net.ServicePointManager]::SecurityProtocol = 
            [Net.SecurityProtocolType]::Tls13 -bor `
            [Net.SecurityProtocolType]::Tls12 -bor `
            [Net.SecurityProtocolType]::Tls11 -bor `
            [Net.SecurityProtocolType]::Tls
    }
    catch {
        "Blad w trakcie dodawania SecurityProtocolType: $($_.exception.message)"
    }

    if (($null -eq (Get-InstalledModule psslack -ea SilentlyContinue)) -and ($PSVersionTable.PSVersion.Major -ge 5)) {
        "Instalowanie modulu PSSlack..."
        start-process C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -ArgumentList "install-packageprovider -name nuget -force;install-Module psslack -Force" -Verb RunAs -Wait -WindowStyle Minimized
    }
    
    if ($PSVersionTable.PSVersion.Major -ge 5) {
        $token = "***"
        $isOK = (Send-SlackMessage -Token $token -parse full -Channel $channel -Text $message).ok
        #$isOK = (Send-SlackMessage -Token $token -parse full -Channel "testowanko" -Text $message).ok
    
        if (($null -eq $isOK) -or ("" -eq $isOK)) {
            $isOK = "False"
        }

        "Wysylanie wiadomosc na kanal Slack: $($isOK)"
    } 
    else {
        "Wiadomosc nie zostala wyslana, poniewaz powershell jest w wersji ponizej 5.0"
    }
}

function GetComputers {
    [CmdletBinding()]
    param(
        [parameter(ValueFromPipeline)]
        [ValidateNotNull()]
        [String]$networkName
    )

    # URL
    $requestURL = 'http://api2.arrow.screennetwork.pl/'

    # Headers
    $requestHeaders = @{'sntoken' = '***'; 'Content-Type' = 'application/json' }
    
    # Body
    $requestBody = @"
{

"network": [`"$($networkName)`"]

}
"@

    # Request
    try {
        $request = Invoke-WebRequest -Uri $requestURL -Method POST -Body $requestBody -Headers $requestHeaders -ea Stop
    }
    catch [exception] {
        $_.Exception.Response
        Exit 1
    }

    # Creating PS array of sn
    if ($request.StatusCode -eq 200) {
        $requestContent = $request.content | ConvertFrom-Json
    }
    else {
        Write-host ( -join ("Received bad StatusCode for request: ", $request.StatusCode, " - ", $request.StatusDescription)) -ForegroundColor Red
        Exit 1
    }

    $snList = @()
    $requestContent | % {
        if (($_.tasks.Count -eq 0) -and ($_.ip -eq "NULL")) {
            if ($_.last_tcp -ne $null) { 
                $tcp = $_.last_tcp
                if($tcp.Contains('T')){
                    $tcp = $tcp.replace('T', ' ')
                }

                if($tcp.Contains('Z')){
                    $tcp = $tcp.Substring(0, $tcp.Length -5)
                }      
            }
            else { 
                $tcp = "NULL"
            }

            $hash = [ordered]@{
                sn       = $_.name;
                miasto   = $_.city;
                ulica    = $_.street;
                placowka = $_.lok_name;
                last_tcp = $tcp 
            }

            $snList = [array]$snList + (New-Object psobject -Property $hash)
        }
    }

    return $snList
}

function CheckDisconnected {
    [CmdletBinding()] Param(
        [Parameter(Mandatory = $true)][string] $fullNetworkName,
        [Parameter(Mandatory = $true)][int] $maxDisconnectedDays
    )

    $disconnected = $null
    $disconnectedRecheck = $null
    $finallResult = $null
    $listSN = $null
    $sn = $null

    # first check
    $listSN = GetComputers -networkName "$($fullNetworkName)"
    if($listSN.count -ne 0) {
        foreach ($sn in $listSN) {
            if ($sn.last_tcp -ne "NULL") { 
                try{
                    $lastTCP = [datetime]$sn.last_tcp 
                } catch {
                    $sn
                    $_.exception.message
                }
                
            } else { 
                $lastTCP = $dateNow 
            }

            $disconnectedDays = (New-TimeSpan -Start $lastTCP -End $dateNow -ea SilentlyContinue).Days
        
            if ($disconnectedDays -gt $maxDisconnectedDays) {
                $hash = [ordered]@{
                    SN                = $sn.sn;
                    Miasto            = $sn.miasto;
                    Ulica             = $sn.ulica;
                    Placowka          = $sn.placowka;
                    "Rozlaczony(dni)" = $disconnectedDays
                }
    
                $disconnected = [array]$disconnected + (New-Object psobject -Property $hash)
            }
        }
    }

    # wait
    sleep -s 3

    $listSN = $null
    $sn = $null

    # second check
    $listSN = GetComputers -networkName "$($fullNetworkName)"
    if ($listSN.count -ne 0) {
        foreach ($sn in $listSN) {
            if ($sn.last_tcp -ne "NULL") { 
                try{
                    $lastTCP = [datetime]$sn.last_tcp 
                } catch {
                    $sn
                    $_.exception.message
                }
                
            } else { 
                $lastTCP = $dateNow 
            }

            $disconnectedDays = (New-TimeSpan -Start $lastTCP -End $dateNow).Days
    
            if ($disconnectedDays -gt $maxDisconnectedDays) {
                $hash = [ordered]@{
                    SN                = $sn.sn;
                    Miasto            = $sn.miasto;
                    Ulica             = $sn.ulica;
                    Placowka          = $sn.placowka;
                    "Rozlaczony(dni)" = $disconnectedDays
                }

                $disconnectedRecheck = [array]$disconnectedRecheck + (New-Object psobject -Property $hash)
            }
        }
    }

    # comparing two checks
    if (($disconnected.count -ne 0) -and ($disconnectedRecheck.Count -ne 0)) {
        foreach ($dis in $disconnected) {
            if (($disconnectedRecheck -match $dis.SN) -and ($dontCheck -notcontains $dis.SN)) {
                $finallResult = [array]$finallResult + $dis
            }
        }
    }

    # adding to message
    if ($finallResult.Count -ne 0) {
        $msg += "*$($fullNetworkName)* `n ``````` `n "
        $msg += ($finallResult | Format-Table -AutoSize | Out-String).trim()
        $msg += " `n ``````` `n "

        try {
            Send-ToSlack -message $msg -channel $slackChannel
        }
        catch {
            Send-ToSlack -message "Problem z wysylaniem listy komputerow z sieci: $fullNetworkName" -channel $slackChannel
        }
    } else {
        "Brak niepolaczonych komputerow"
    }
}

# Message 
$intro = ( -join (" ``Niepolaczone kopmutery bez zadan - ", $dateResult, "`` `n`n"))
Send-ToSlack -message $intro -channel $slackChannel

# Checking diconnected SN's without a task
for ($i = 0; $i -le $allNetowrks.Count - 1; $i ++) {
    "`nSprawdzanie niepolaczonych komputerow w sieci: $($allNetowrks[$i].network)"
    CheckDisconnected -fullNetworkName $allNetowrks[$i].network -maxDisconnectedDays $allNetowrks[$i].days
}
