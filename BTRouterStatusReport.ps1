# BTRouterStatusReport.ps1
# BT SmartHub (2) Router Status & Speed Test
# Quick script to grab the XML from the BT SmartHub status page (IP defined below) and do a SpeedTest.
# Then output the stats to a CSV file for reporting.
# Designed for BT SmartHub v2 and VDSL, but this can undoubtedly be modified for others
# 
# AUTHOR:  Chris Harris (https://github.com/utopianit-base)
# CREDITS: Some SpeedTest Code by Kelvin Tegelaar from http://www.cyberdrain.com/
# VERSION: 20200611
# DATED:   11/06/2020 (DD/MM/YYYY)
#
$OutputFile = '.\WANStatus.csv'
$BTModemIP = '192.168.1.254'
$BTStatusPath = '/nonAuth/wan_conn.xml'
$BypassSelfSignedCert = $true
######### Health monitoring thresholds ########## 
$MaxPacketLoss = 2                  # How much % packetloss until we alert. 
$MinimumDownloadSpeed = 35          # What is the minimum expected download speed in Mbit/ps
$MinimumUploadSpeed = 10            # What is the minimum expected upload speed in Mbit/ps
######### End Health monitoring thresholds ######

$BTModemURL = "https://$BTModemIP$BTStatusPath"

if($BypassSelfSignedCert -and ([System.Net.ServicePointManager]::CertificatePolicy.ToString() -ne 'TrustAllCertsPolicy')) {
    add-type @"
        using System.Net;
        using System.Security.Cryptography.X509Certificates;
        public class TrustAllCertsPolicy : ICertificatePolicy {
            public bool CheckValidationResult(
                ServicePoint srvPoint, X509Certificate certificate,
                WebRequest request, int certificateProblem) {
                return true;
            }
        }
"@
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
}

write-host "Getting Router Sync Status" -ForegroundColor Cyan

# Grab the status from the BT Modem
[xml]$BTStatusXML = (New-Object System.Net.WebClient).DownloadString($BTModemURL)
$CurrentDateTime = Get-Date
$WANLineStatusRateArray = $BTStatusXML.status.wan_linestatus_rate_list.value.replace('[','').replace(']','').replace("'",'').split(',')
$WANSyncDown   = [float]$WANLineStatusRateArray[11]/1000 # Sync Download Speed in Mb/s
$WANSyncUp     = [float]$WANLineStatusRateArray[12]/1000 # Sync Upload Speed in Mb/s
$WANStatus     = $WANLineStatusRateArray[0]
if($WANStatus -eq 'UP') {
    write-host "Router is UP. Syncing at $WANSyncDown Mb/s Download and $WANSyncUp Mb/s Upload" -ForegroundColor Green
} else {
    write-host "Router is DOWN or not available for querying." -ForegroundColor RED
}

# Grab the current SpeedTest results
function Run-SpeedTest {
    #Replace the Download URL to where you've uploaded the ZIP file yourself. We will only download this file once. 
    #Latest version can be found at: https://www.speedtest.net/nl/apps/cli
    $DownloadURL = "https://bintray.com/ookla/download/download_file?file_path=ookla-speedtest-1.0.0-win64.zip"
    $DownloadLocation  = "$($Env:ProgramData)\SpeedtestCLI"
    $DownloadFileName  = 'speedtest.zip'
    $SpeedTestEXEFile  = 'speedtest.exe'
    $DownloadFullPath  = "$($DownloadLocation)\$($DownloadFileName)"
    $SpeedTestFullPath = "$($DownloadLocation)\$($SpeedTestEXEFile)"

    # If the speedtest.exe file 
    if(-not (Test-Path $SpeedTestFullPath)) {

        try {
            $TestDownloadLocation = Test-Path $DownloadLocation
            if (!$TestDownloadLocation) {
                new-item $DownloadLocation -ItemType Directory -force
                Invoke-WebRequest -Uri $DownloadURL -OutFile $DownloadFullPath
                if(Test-Path $DownloadFullPath) {
                    Expand-Archive $DownloadFullPath -DestinationPath $DownloadLocation -Force
                } else {
                    write-host "Speedtest Failed to download to $DownloadFullPath" -ForegroundColor Red
                }
            } 
        }
        catch {  
            write-host "The download and extraction of SpeedtestCLI failed. Error: $($_.Exception.Message)"
            exit 1
        }
    }

    $PreviousResults = if (test-path "$($DownloadLocation)\LastResults.txt") { get-content "$($DownloadLocation)\LastResults.txt" | ConvertFrom-Json }
    $SpeedtestResults = & "$($DownloadLocation)\speedtest.exe" --format=json --accept-license --accept-gdpr
    $SpeedtestResults | Out-File "$($DownloadLocation)\LastResults.txt" -Force
    $SpeedtestResults = $SpeedtestResults | ConvertFrom-Json
 
    #creating object
    [PSCustomObject]$SpeedtestObj = @{
        DownloadSpeed = [math]::Round($SpeedtestResults.download.bandwidth / 1000000 * 8, 2)
        UploadSpeed   = [math]::Round($SpeedtestResults.upload.bandwidth / 1000000 * 8, 2)
        PacketLoss    = [math]::Round($SpeedtestResults.packetLoss)
        ISP           = $SpeedtestResults.isp
        ExternalIP    = $SpeedtestResults.interface.externalIp
        InternalIP    = $SpeedtestResults.interface.internalIp
        UsedServer    = $SpeedtestResults.server.host
        ResultsURL    = $SpeedtestResults.result.url
        Jitter        = [math]::Round($SpeedtestResults.ping.jitter)
        Latency       = [math]::Round($SpeedtestResults.ping.latency)
    }
    Return $SpeedtestObj
}

function Get-SpeedTestHealth {
    param (
        ######### Absolute monitoring values. Overridden by paramaters when called ########## 
        $MaxPacketLoss = 2,                 # How much % packetloss until we alert. 
        $MinimumDownloadSpeed = 100,        # What is the minimum expected download speed in Mbit/ps
        $MinimumUploadSpeed = 20            # What is the minimum expected upload speed in Mbit/ps
        ######### End absolute monitoring values ######
    )
    $SpeedtestHealth = @()
    #Comparing against previous result. Alerting is download or upload differs more than 20%.
    if ($PreviousResults) {
        if ($PreviousResults.download.bandwidth / $SpeedtestResults.download.bandwidth * 100 -le 80) { $SpeedtestHealth += "Download speed difference is more than 20%" }
        if ($PreviousResults.upload.bandwidth / $SpeedtestResults.upload.bandwidth * 100 -le 80) { $SpeedtestHealth += "Upload speed difference is more than 20%" }
    }
 
    #Comparing against preset variables.
    if ($SpeedtestObj.downloadspeed -lt $MinimumDownloadSpeed) { $SpeedtestHealth += "Download speed is lower than $MinimumDownloadSpeed Mbit/ps" }
    if ($SpeedtestObj.uploadspeed -lt $MinimumUploadSpeed) { $SpeedtestHealth += "Upload speed is lower than $MinimumUploadSpeed Mbit/ps" }
    if ($SpeedtestObj.packetloss -gt $MaxPacketLoss) { $SpeedtestHealth += "Packetloss is higher than $maxpacketloss%" }
 
    if (!$SpeedtestHealth) {
        $SpeedtestHealth = "Healthy"
    }
    Return $SpeedtestHealth
}

write-host "Running Speed Test..." -ForegroundColor Cyan
$SpeedtestObj    = Run-SpeedTest

if($SpeedtestObj.ISP -ne '') {
    write-host "Processing SpeedTest Health..." -ForegroundColor Cyan
    $SpeedtestHealth = Get-SpeedTestHealth -MaxPacketLoss $MaxPacketLoss -MinimumDownloadSpeed $MinimumUploadSpeed -MinimumUploadSpeed $MinimumUploadSpeed
    $SpeedtestObj.Add('DownloadSyncRate',$WANSyncDown)
    $SpeedtestObj.Add('UploadSyncRate',$WANSyncUp)
    $SpeedtestObj.Add('DateTime',$CurrentDateTime)
    $SpeedtestObj.Add('HealthStatus',$SpeedtestHealth)

    $SpeedTestSorted = $SpeedtestObj | Select-Object 'DateTime','DownloadSyncRate','UploadSyncRate','DownloadSpeed','UploadSpeed','PacketLoss','Jitter','Latency','ExternalIP','InternalIP','ResultsURL','UsedServer','HealthStatus'
    write-host "Speed Test Resulted in $($SpeedtestObj.DownloadSpeed) Mb/s Download and $($SpeedtestObj.UploadSpeed) Mb/s Upload" -ForegroundColor Green

    if (Test-Path $OutputFile) {
        write-host "Exporting Results to CSV File..." -ForegroundColor Cyan
        $SpeedTestSorted | Export-Csv $OutputFile -NoTypeInformation -Append
    } else {
        write-host "Exporting Results to new CSV File..." -ForegroundColor Cyan
        $SpeedTestSorted | Export-Csv $OutputFile -NoTypeInformation
    }
 } else {
    write-host "SpeedTest failed to return results" -ForegroundColor Red
  }