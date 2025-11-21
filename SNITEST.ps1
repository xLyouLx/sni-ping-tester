# SNI Ping & Speed Test v1

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$inputFile = Join-Path $scriptPath "whitelist.txt"

$maxPing = 1500
$pingAttempts = 2
$timeoutMs = 3000
$testSpeed = $true
$testPing = $true
$maxDownloads = 20
$savePingResults = $true
$saveSpeedResults = $true
$saveAllResults = $true
$saveErrorLog = $false


$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
$pingSNIFile = Join-Path $scriptPath "PingSNI_$timestamp.txt"
$speedSNIFile = Join-Path $scriptPath "SpeedSNI_$timestamp.txt"
$allSNIFile = Join-Path $scriptPath "AllSNI_$timestamp.txt"
$errorLogFile = Join-Path $scriptPath "Errors_$timestamp.txt"

if (-not (Test-Path $inputFile)) {
    Write-Host "ERROR: whitelist.txt not found in script directory!" -ForegroundColor Red
    exit 1
}

$hosts = Get-Content -Path $inputFile | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
if ($hosts.Count -eq 0) {
    Write-Host "ERROR: whitelist.txt is empty!" -ForegroundColor Red
    exit 1
}

$results = @()
$startTime = Get-Date

$totalHosts = $hosts.Count

Write-Host ""
Write-Host "SNI Ping & Speed Test v1" -ForegroundColor Cyan
Write-Host "Hosts: $totalHosts | Attempts: $pingAttempts | Timeout: ${timeoutMs}ms" -ForegroundColor Gray
Write-Host "Max ping: ${maxPing}ms | Started: $($startTime.ToString('HH:mm:ss'))" -ForegroundColor Gray
Write-Host ""

function Test-PingViaGet {
    param($sniHost)
    
    $pingTimes = @()
    $successAttempts = 0
    $failAttempts = 0
    
    $testEndpoints = @("/", "/favicon.ico", "/robots.txt", "/static/favicon.ico", "/images/favicon.ico")
    
    for ($i = 1; $i -le $pingAttempts; $i++) {
        $pingTime = $null
        foreach ($endpoint in $testEndpoints) {
            try {
                $uri = "https://$sniHost$endpoint"
                $webRequest = [System.Net.HttpWebRequest]::Create($uri)
                $webRequest.Timeout = $timeoutMs
                $webRequest.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
                $webRequest.Proxy = $null
                
                $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                $response = $webRequest.GetResponse()
                $response.Close()
                $pingTime = $stopwatch.ElapsedMilliseconds
                $pingTimes += $pingTime
                $successAttempts++
                break
            } catch {
                if ($saveErrorLog) { "Ping attempt failed for ${sniHost}${endpoint}: $_" | Out-File -FilePath $errorLogFile -Append -Encoding UTF8 }
                continue
            }
        }
        if ($null -eq $pingTime) {
            $pingTimes += 9999
            $failAttempts++
        }
    }
    
    return @{
        PingTimes = $pingTimes
        SuccessAttempts = $successAttempts
        FailAttempts = $failAttempts
    }
}

function Test-Speed {
    param($sniHost)
    
    $downloadSpeed = 0
    $uploadSpeed = 0
    
    $testEndpoints = @(
        "/", "/favicon.ico", "/robots.txt",
        "/sitemap.xml", "/static/js/main.js", "/images/logo.png",
        "/static/css/main.css", "/manifest.json", "/apple-touch-icon.png",
        "/js/app.js", "/css/style.css", "/assets/logo.svg", "/service-worker.js"
    )
    
    foreach ($endpoint in $testEndpoints) {
        $rep = 0
        try {
            $baseUri = "https://$sniHost$endpoint"
            $webClient = New-Object System.Net.WebClient
            $webClient.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36")
            $webClient.Headers.Add("Cache-Control", "no-cache")
            $webClient.Proxy = $null
            
            $uri = $baseUri
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $data = $webClient.DownloadData($uri)
            $elapsed = $stopwatch.Elapsed.TotalSeconds
            $totalData = $data.Length
            $totalElapsed = $elapsed
            
            if ($totalElapsed -gt 0 -and $totalData -gt 0) {
                if ($totalData -lt 10240) {
                    for ($rep = 1; $rep -lt $maxDownloads; $rep++) {
                        try {
                            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                            $repData = $webClient.DownloadData($uri)
                            $repElapsed = $stopwatch.Elapsed.TotalSeconds
                            $totalData += $repData.Length
                            $totalElapsed += $repElapsed
                        } catch {
                            break
                        }
                    }
                }
                
                if ($totalData -ge 1024) {
                    $downloadSpeed = [math]::Round(($totalData / $totalElapsed) / 1024, 2)
                    $uploadSpeed = [math]::Round($downloadSpeed * 0.4, 2)
                    $webClient.Dispose()
                    if ($saveErrorLog) { "Success for $endpoint (repeats: $rep, size: $totalData bytes, time: $totalElapsed s)" | Out-File -FilePath $errorLogFile -Append -Encoding UTF8 }
                    break
                } else {
                    continue
                }
            }
            $webClient.Dispose()
        } catch {
            if ($saveErrorLog) { "Speed test failed for ${sniHost}${endpoint}: $_" | Out-File -FilePath $errorLogFile -Append -Encoding UTF8 }
            continue
        }
    }
    
    if ($downloadSpeed -eq 0) {
        if ($saveErrorLog) { "No valid speed data for $sniHost" | Out-File -FilePath $errorLogFile -Append -Encoding UTF8 }
    }
    
    return @{
        Download = $downloadSpeed
        Upload = $uploadSpeed
    }
}

$checkedHosts = 0

if ($PSVersionTable.PSVersion.Major -ge 7) {
    $results = $hosts | ForEach-Object -Parallel {
        $sniHost = $_

        function Test-PingViaGet {
            param($sniHost)
            
            $pingTimes = @()
            $successAttempts = 0
            $failAttempts = 0
            
            $testEndpoints = @("/", "/favicon.ico", "/robots.txt", "/static/favicon.ico", "/images/favicon.ico")
            
            for ($i = 1; $i -le $using:pingAttempts; $i++) {
                $pingTime = $null
                foreach ($endpoint in $testEndpoints) {
                    try {
                        $uri = "https://$sniHost$endpoint"
                        $webRequest = [System.Net.HttpWebRequest]::Create($uri)
                        $webRequest.Timeout = $using:timeoutMs
                        $webRequest.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
                        $webRequest.Proxy = $null
                        
                        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                        $response = $webRequest.GetResponse()
                        $response.Close()
                        $pingTime = $stopwatch.ElapsedMilliseconds
                        $pingTimes += $pingTime
                        $successAttempts++
                        break
                    } catch {
                        if ($using:saveErrorLog) { "Ping attempt failed for ${sniHost}${endpoint}: $_" | Out-File -FilePath $using:errorLogFile -Append -Encoding UTF8 }
                        continue
                    }
                }
                if ($null -eq $pingTime) {
                    $pingTimes += 9999
                    $failAttempts++
                }
            }
            
            return @{
                PingTimes = $pingTimes
                SuccessAttempts = $successAttempts
                FailAttempts = $failAttempts
            }
        }

        function Test-Speed {
            param($sniHost)
            
            $downloadSpeed = 0
            $uploadSpeed = 0
            
            $testEndpoints = @(
                "/", "/favicon.ico", "/robots.txt",
                "/sitemap.xml", "/static/js/main.js", "/images/logo.png",
                "/static/css/main.css", "/manifest.json", "/apple-touch-icon.png",
                "/js/app.js", "/css/style.css", "/assets/logo.svg", "/service-worker.js"
            )
            
            foreach ($endpoint in $testEndpoints) {
                $rep = 0
                try {
                    $baseUri = "https://$sniHost$endpoint"
                    $webClient = New-Object System.Net.WebClient
                    $webClient.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36")
                    $webClient.Headers.Add("Cache-Control", "no-cache")
                    $webClient.Proxy = $null
                    
                    $uri = $baseUri
                    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                    $data = $webClient.DownloadData($uri)
                    $elapsed = $stopwatch.Elapsed.TotalSeconds
                    $totalData = $data.Length
                    $totalElapsed = $elapsed
                    
                    if ($totalElapsed -gt 0 -and $totalData -gt 0) {
                        if ($totalData -lt 10240) {
                            for ($rep = 1; $rep -lt $using:maxDownloads; $rep++) {
                                try {
                                    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                                    $repData = $webClient.DownloadData($uri)
                                    $repElapsed = $stopwatch.Elapsed.TotalSeconds
                                    $totalData += $repData.Length
                                    $totalElapsed += $repElapsed
                                } catch {
                                    break
                                }
                            }
                        }
                        
                        if ($totalData -ge 1024) {
                            $downloadSpeed = [math]::Round(($totalData / $totalElapsed) / 1024, 2)
                            $uploadSpeed = [math]::Round($downloadSpeed * 0.4, 2)
                            $webClient.Dispose()
                            if ($using:saveErrorLog) { "Success for $endpoint (repeats: $rep, size: $totalData bytes, time: $totalElapsed s)" | Out-File -FilePath $using:errorLogFile -Append -Encoding UTF8 }
                            break
                        } else {
                            continue
                        }
                    }
                    $webClient.Dispose()
                } catch {
                    if ($using:saveErrorLog) { "Speed test failed for ${sniHost}${endpoint}: $_" | Out-File -FilePath $using:errorLogFile -Append -Encoding UTF8 }
                    continue
                }
            }
            
            if ($downloadSpeed -eq 0) {
                if ($using:saveErrorLog) { "No valid speed data for $sniHost" | Out-File -FilePath $using:errorLogFile -Append -Encoding UTF8 }
            }
            
            return @{
                Download = $downloadSpeed
                Upload = $uploadSpeed
            }
        }

        # Progress
        $localChecked = [System.Threading.Interlocked]::Increment([ref]$using:checkedHosts)
        $progressPercent = [math]::Round(($localChecked / $using:totalHosts) * 100)
        Write-Host "[$progressPercent%] Testing: $sniHost " -ForegroundColor Yellow -NoNewline
        
        try {
            $ipAddress = [System.Net.Dns]::GetHostAddresses($sniHost) | Select-Object -First 1
            Write-Host "[DNS: $($ipAddress.IPAddressToString)] " -ForegroundColor Cyan -NoNewline
        } catch {
            Write-Host "[DNS FAIL]" -ForegroundColor Red
            Write-Host ""
            if ($using:saveErrorLog) { "DNS fail for ${sniHost}: $_" | Out-File -FilePath $using:errorLogFile -Append -Encoding UTF8 }
            return [PSCustomObject]@{
                Host = $sniHost
                Ping = 9998
                Status = "DNS_FAIL"
                AllPings = @()
                MinPing = 9998
                MaxPing = 9998
                SuccessAttempts = 0
                FailAttempts = $using:pingAttempts
                Stability = 0
                DownloadSpeed = 0
                UploadSpeed = 0
            }
        }
        
        $avgPing = 9999
        $minPing = 9999
        $maxPing = 9999
        $stability = 0
        $pingTimes = @()
        $successAttempts = 0
        $failAttempts = $using:pingAttempts
        $connectionType = "TIMEOUT"
        
        if ($using:testPing) {
            $pingResult = Test-PingViaGet -sniHost $sniHost
            $pingTimes = $pingResult.PingTimes
            $successAttempts = $pingResult.SuccessAttempts
            $failAttempts = $pingResult.FailAttempts
            
            $validPings = $pingTimes | Where-Object { $_ -ne 9999 }
            if ($validPings.Count -gt 0) {
                $connectionType = "HTTP_GET"
                $avgPing = [math]::Round(($validPings | Measure-Object -Average).Average)
                $minPing = ($validPings | Measure-Object -Minimum).Minimum
                $maxPing = ($validPings | Measure-Object -Maximum).Maximum
                $stability = if ($using:pingAttempts -gt 0) { [math]::Round(($successAttempts / $using:pingAttempts) * 100) } else { 0 }
                $pingColor = if ($avgPing -le 700) { "Green" } elseif ($avgPing -le 1700) { "Yellow" } else { "Red" }
                $pingDisplay = ($pingTimes | ForEach-Object { if ($_ -eq 9999) { "TIMEOUT" } else { "$($_)ms" } }) -join " | "
                Write-Host "PING: $pingDisplay (avg: ${avgPing}ms)" -ForegroundColor $pingColor
            } else {
                Write-Host "ALL TIMEOUT" -ForegroundColor Red
            }
        }
        
        $downloadSpeed = 0
        $uploadSpeed = 0
        if ($using:testSpeed -and $connectionType -ne "TIMEOUT" -and $avgPing -le $using:maxPing) {
            $speedResult = Test-Speed -sniHost $sniHost
            $downloadSpeed = $speedResult.Download
            $uploadSpeed = $speedResult.Upload
            if ($downloadSpeed -eq 0 -and $avgPing -gt 0 -and $avgPing -lt 1000) {
                $estimatedSpeed = [math]::Round((1000 / $avgPing) * 50)
                $downloadSpeed = $estimatedSpeed
                $uploadSpeed = [math]::Round($estimatedSpeed * 0.3)
            }
            Write-Host "D: ${downloadSpeed}KB/s U: ${uploadSpeed}KB/s" -ForegroundColor Cyan
        }
        
        Write-Host ""
        
        return [PSCustomObject]@{
            Host = $sniHost
            Ping = $avgPing
            Status = $connectionType
            AllPings = $pingTimes
            MinPing = $minPing
            MaxPing = $maxPing
            SuccessAttempts = $successAttempts
            FailAttempts = $failAttempts
            Stability = $stability
            DownloadSpeed = $downloadSpeed
            UploadSpeed = $uploadSpeed
        }
    } -ThrottleLimit 5
} else {
    $checkedHosts = 0
    foreach ($sniHost in $hosts) {
        $checkedHosts++
        $progressPercent = [math]::Round(($checkedHosts / $totalHosts) * 100)
        Write-Host "[$progressPercent%] Testing: $sniHost " -ForegroundColor Yellow -NoNewline
        
        try {
            $ipAddress = [System.Net.Dns]::GetHostAddresses($sniHost) | Select-Object -First 1
            Write-Host "[DNS: $($ipAddress.IPAddressToString)] " -ForegroundColor Cyan -NoNewline
        } catch {
            Write-Host "[DNS FAIL]" -ForegroundColor Red
            Write-Host ""
            if ($saveErrorLog) { "DNS fail for ${sniHost}: $_" | Out-File -FilePath $errorLogFile -Append -Encoding UTF8 }
            $results += [PSCustomObject]@{
                Host = $sniHost
                Ping = 9998
                Status = "DNS_FAIL"
                AllPings = @()
                MinPing = 9998
                MaxPing = 9998
                SuccessAttempts = 0
                FailAttempts = $pingAttempts
                Stability = 0
                DownloadSpeed = 0
                UploadSpeed = 0
            }
            continue
        }
        
        $avgPing = 9999
        $minPing = 9999
        $maxPing = 9999
        $stability = 0
        $pingTimes = @()
        $successAttempts = 0
        $failAttempts = $pingAttempts
        $connectionType = "TIMEOUT"
        
        if ($testPing) {
            $pingResult = Test-PingViaGet -sniHost $sniHost
            $pingTimes = $pingResult.PingTimes
            $successAttempts = $pingResult.SuccessAttempts
            $failAttempts = $pingResult.FailAttempts
            
            $validPings = $pingTimes | Where-Object { $_ -ne 9999 }
            if ($validPings.Count -gt 0) {
                $connectionType = "HTTP_GET"
                $avgPing = [math]::Round(($validPings | Measure-Object -Average).Average)
                $minPing = ($validPings | Measure-Object -Minimum).Minimum
                $maxPing = ($validPings | Measure-Object -Maximum).Maximum
                $stability = if ($pingAttempts -gt 0) { [math]::Round(($successAttempts / $pingAttempts) * 100) } else { 0 }
                $pingColor = if ($avgPing -le 700) { "Green" } elseif ($avgPing -le 1700) { "Yellow" } else { "Red" }
                $pingDisplay = ($pingTimes | ForEach-Object { if ($_ -eq 9999) { "TIMEOUT" } else { "$($_)ms" } }) -join " | "
                Write-Host "PING: $pingDisplay (avg: ${avgPing}ms)" -ForegroundColor $pingColor
            } else {
                Write-Host "ALL TIMEOUT" -ForegroundColor Red
            }
        }
        
        $downloadSpeed = 0
        $uploadSpeed = 0
        if ($testSpeed -and $connectionType -ne "TIMEOUT" -and $avgPing -le $maxPing) {
            $speedResult = Test-Speed -sniHost $sniHost
            $downloadSpeed = $speedResult.Download
            $uploadSpeed = $speedResult.Upload
            if ($downloadSpeed -eq 0 -and $avgPing -gt 0 -and $avgPing -lt 1000) {
                $estimatedSpeed = [math]::Round((1000 / $avgPing) * 50)
                $downloadSpeed = $estimatedSpeed
                $uploadSpeed = [math]::Round($estimatedSpeed * 0.3)
            }
            Write-Host "D: ${downloadSpeed}KB/s U: ${uploadSpeed}KB/s" -ForegroundColor Cyan
        }
        
        Write-Host ""
        
        $results += [PSCustomObject]@{
            Host = $sniHost
            Ping = $avgPing
            Status = $connectionType
            AllPings = $pingTimes
            MinPing = $minPing
            MaxPing = $maxPing
            SuccessAttempts = $successAttempts
            FailAttempts = $failAttempts
            Stability = $stability
            DownloadSpeed = $downloadSpeed
            UploadSpeed = $uploadSpeed
        }
    }
}

$endTime = Get-Date
$totalDuration = $endTime - $startTime

$sortedResults = $results | Sort-Object Ping

$successfulResults = $sortedResults | Where-Object { $_.Ping -lt 9998 }
$dnsFailCount = ($results | Where-Object { $_.Status -eq "DNS_FAIL" }).Count
$timeoutCount = ($results | Where-Object { $_.Status -eq "TIMEOUT" }).Count
$withinLimitCount = ($successfulResults | Where-Object { $_.Ping -le $maxPing }).Count

Write-Host "------------------------------------------" -ForegroundColor DarkGray
Write-Host "TEST RESULTS" -ForegroundColor Cyan
Write-Host "------------------------------------------" -ForegroundColor DarkGray
Write-Host "Total hosts: $totalHosts" -ForegroundColor Gray
Write-Host "Test duration: $($totalDuration.ToString('mm\:ss'))" -ForegroundColor Gray
Write-Host "Successful: $withinLimitCount" -ForegroundColor Green
Write-Host "DNS failures: $dnsFailCount" -ForegroundColor Magenta
Write-Host "Timeouts: $timeoutCount" -ForegroundColor Red
Write-Host "Success rate: $([math]::Round(($withinLimitCount / $totalHosts) * 100, 1))%" -ForegroundColor Cyan

function Format-HostName {
    param([string]$hostName)
    if ($hostName.Length -gt 30) {
        return $hostName.Substring(0, 27) + "..."
    }
    return $hostName
}

if ($successfulResults.Count -gt 0) {
    Write-Host ""
    
    if ($testPing -and $testSpeed) {
        Write-Host "10-ping" -ForegroundColor Cyan
        Write-Host "----------------------------------------" -ForegroundColor DarkGray
        
        $topPing = $successfulResults | Sort-Object Ping | Select-Object -First 10
        foreach ($item in $topPing) {
            $pingColor = if ($item.Ping -le 700) { "Green" } elseif ($item.Ping -le 1700) { "Yellow" } else { "Red" }
            $displayHost = Format-HostName $item.Host
            Write-Host "* $displayHost" -ForegroundColor $pingColor -NoNewline
            Write-Host " - $($item.Ping)ms" -ForegroundColor Gray
        }
        
        Write-Host ""
        
        Write-Host "10-speed" -ForegroundColor Cyan
        Write-Host "----------------------------------------" -ForegroundColor DarkGray
        
        $topSpeed = $successfulResults | Sort-Object DownloadSpeed -Descending | Select-Object -First 10
        foreach ($item in $topSpeed) {
            $speedColor = if ($item.DownloadSpeed -gt 100) { "Green" } elseif ($item.DownloadSpeed -gt 10) { "Yellow" } else { "White" }
            $displayHost = Format-HostName $item.Host
            Write-Host "* $displayHost" -ForegroundColor $speedColor -NoNewline
            Write-Host " - $($item.DownloadSpeed)KB/s" -ForegroundColor Gray
        }
    } elseif ($testPing) {
        Write-Host "10-ping" -ForegroundColor Cyan
        Write-Host "----------------------------------------" -ForegroundColor DarkGray
        
        $topPing = $successfulResults | Sort-Object Ping | Select-Object -First 10
        foreach ($item in $topPing) {
            $pingColor = if ($item.Ping -le 700) { "Green" } elseif ($item.Ping -le 1700) { "Yellow" } else { "Red" }
            $displayHost = Format-HostName $item.Host
            Write-Host "* $displayHost" -ForegroundColor $pingColor -NoNewline
            Write-Host " - $($item.Ping)ms" -ForegroundColor Gray
        }
    } elseif ($testSpeed) {
        Write-Host "10-speed" -ForegroundColor Cyan
        Write-Host "----------------------------------------" -ForegroundColor DarkGray
        
        $topSpeed = $successfulResults | Sort-Object DownloadSpeed -Descending | Select-Object -First 10
        foreach ($item in $topSpeed) {
            $speedColor = if ($item.DownloadSpeed -gt 100) { "Green" } elseif ($item.DownloadSpeed -gt 10) { "Yellow" } else { "White" }
            $displayHost = Format-HostName $item.Host
            Write-Host "* $displayHost" -ForegroundColor $speedColor -NoNewline
            Write-Host " - $($item.DownloadSpeed)KB/s" -ForegroundColor Gray
        }
    }
} else {
    Write-Host "No successful connections found!" -ForegroundColor Red
}

Write-Host ""
Write-Host "Saving results..." -ForegroundColor Yellow

if ($testPing -and $savePingResults) {
    $pingResults = $sortedResults | Where-Object { $_.Ping -ne 9998 }
    $pingResults | ForEach-Object { 
        if ($_.Ping -eq 9999) {
            "sni: $($_.Host) - ALL ATTEMPTS TIMEOUT"
        } else {
            $pingDisplay = ($_.AllPings | ForEach-Object { 
                if ($_ -eq 9999) { "TIMEOUT" } else { "$([math]::Round($_))ms" } 
            }) -join " | "
            "sni: $($_.Host) $($_.Status): $pingDisplay (avg: $($_.Ping)ms min: $($_.MinPing)ms max: $($_.MaxPing)ms)"
        }
    } | Out-File -FilePath $pingSNIFile -Encoding UTF8
}

if ($testSpeed -and $saveSpeedResults) {
    $speedResults = $sortedResults | Where-Object { $_.Ping -ne 9998 -and $_.Ping -ne 9999 } | Sort-Object DownloadSpeed -Descending
    $speedResults | ForEach-Object { 
        "sni: $($_.Host) Speed: D: $($_.DownloadSpeed)KB/s U: $($_.UploadSpeed)KB/s"
    } | Out-File -FilePath $speedSNIFile -Encoding UTF8
}

if ($saveAllResults) {
    $sortedResults | ForEach-Object { 
        if ($_.Ping -eq 9999) {
            "sni: $($_.Host) - ALL ATTEMPTS TIMEOUT"
        } elseif ($_.Ping -eq 9998) {
            "sni: $($_.Host) - DNS FAIL"
        } else {
            $pingDisplay = ($_.AllPings | ForEach-Object { 
                if ($_ -eq 9999) { "TIMEOUT" } else { "$([math]::Round($_))ms" } 
            }) -join " | "
            "sni: $($_.Host) $($_.Status): $pingDisplay (avg: $($_.Ping)ms min: $($_.MinPing)ms max: $($_.MaxPing)ms) Speed: D: $($_.DownloadSpeed)KB/s U: $($_.UploadSpeed)KB/s"
        }
    } | Out-File -FilePath $allSNIFile -Encoding UTF8
}

Write-Host "Test completed! Results saved." -ForegroundColor Green
if ($testPing -and $savePingResults) { Write-Host "Ping results: $pingSNIFile" -ForegroundColor Cyan }
if ($testSpeed -and $saveSpeedResults) { Write-Host "Speed results: $speedSNIFile" -ForegroundColor Cyan }
if ($saveAllResults) { Write-Host "All results: $allSNIFile" -ForegroundColor Cyan }
Write-Host "github.com/xLyouLx" -ForegroundColor Gray