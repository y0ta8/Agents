# ============================================
# Windows Defense Agent (Multi-Module Version)
# System Monitoring + File Access + Security Log Monitoring (4663)
# ============================================

$ErrorActionPreference = "SilentlyContinue"

# -------------------------
# Load Configuration
# -------------------------
$configPath = ".\config.json"
$config = Get-Content $configPath | ConvertFrom-Json

$orchestrator_ip   = $config.orchestrator_ip
$orchestrator_port = $config.orchestrator_port
$agentId           = $config.agent_id

# Allowed users for sensitive file access
$allowedUsers = @("Ayah", "Administrator")   # hp = unauthorized

# -------------------------
# 1) FILE ACCESS MONITORING MODULE (FileSystemWatcher)
# -------------------------

$pathToWatch = "C:\gizli_dosya.txt"
Write-Host "Watching sensitive file (FileSystemWatcher): $pathToWatch"

$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = "C:\"
$watcher.Filter = "gizli_dosya.txt"
$watcher.EnableRaisingEvents = $true

$action = {
    $file  = $Event.SourceEventArgs.FullPath
    $user  = (Get-WmiObject Win32_ComputerSystem).UserName.Split("\")[-1]
    $allowed = $allowedUsers -contains $user

    $eventObject = @{
        agent_id   = $agentId
        host       = $env:COMPUTERNAME
        event_type = "file_access"
        user       = $user
        allowed    = $allowed
        path       = $file
        timestamp  = (Get-Date).ToString("o")
    }

    $json = $eventObject | ConvertTo-Json -Depth 5
    $url  = "http://$orchestrator_ip`:$orchestrator_port/api/ingest"

    try {
        Invoke-RestMethod -Uri $url -Method Post -Body $json -ContentType "application/json"
        Write-Host "FILE EVENT SENT → $json"
    }
    catch {
        Write-Host "Failed to send file event."
    }
}

Register-ObjectEvent $watcher "Changed" -Action $action
Register-ObjectEvent $watcher "Opened"  -Action $action


# -------------------------
# 2) WINDOWS SECURITY LOG MONITORING MODULE (Event ID 4663)
# -------------------------

$global:lastRecordId = 0

function Check-SecurityLogs {
    param($allowedUsers, $agentId, $orchestrator_ip, $orchestrator_port)

    # Get recent 4663 events
    $events = Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4663} -MaxEvents 20
    
    foreach ($event in $events) {

        # Ignore old events
        if ($event.RecordId -le $global:lastRecordId) { continue }
        $global:lastRecordId = $event.RecordId

        $msg = $event.Message

        # Extract data from message
        if ($msg -match "Account Name:\s+(\S+)") { $user = $Matches[1] }
        if ($msg -match "Object Name:\s+(.+)$")   { $objectName = $Matches[1].Trim() }
        if ($msg -match "Accesses:\s+(.+)$")     { $accessType = $Matches[1].Trim() }

        if (!$objectName) { continue }

        $allowed = $allowedUsers -contains $user

        # Build JSON payload
        $eventObject = @{
            agent_id    = $agentId
            event_type  = "security_log_file_access"
            user        = $user
            file_path   = $objectName
            access_type = $accessType
            allowed     = $allowed
            timestamp   = $event.TimeCreated.ToString("o")
        }

        $json = $eventObject | ConvertTo-Json -Depth 5
        $url  = "http://$orchestrator_ip`:$orchestrator_port/api/ingest"

        try {
            Invoke-RestMethod -Uri $url -Method Post -Body $json -ContentType "application/json"
            Write-Host "SECURITY LOG EVENT SENT → $json"
        }
        catch {
            Write-Host "Failed to send security log event."
        }
    }
}


# -------------------------
# 3) SYSTEM MONITORING MODULE
# -------------------------

if ($config.send_interval) {
    $interval = $config.send_interval
} else {
    $interval = $config.interval
}

Write-Host "Agent started. Monitoring every $interval seconds..."


# -------------------------
# MAIN LOOP
# -------------------------

while ($true) {

    # --- System Monitoring ---
    $processes = Get-Process | Select-Object Name, Id, CPU, WorkingSet, StartTime -ErrorAction SilentlyContinue
    $files = Get-ChildItem -Path "$env:USERPROFILE" -Recurse -ErrorAction SilentlyContinue | 
             Select-Object Name, FullName, LastWriteTime -First 20

    $connections = Get-NetTCPConnection -ErrorAction SilentlyContinue |
                   Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort, State

    $event = @{
        agent_id   = $agentId
        host       = $env:COMPUTERNAME
        timestamp  = (Get-Date).ToString("o")
        processes  = $processes
        files      = $files
        connections = $connections
    }

    $json = $event | ConvertTo-Json -Depth 8
    $url  = "http://$orchestrator_ip`:$orchestrator_port/api/ingest"

    try {
        Invoke-RestMethod -Uri $url -Method Post -Body $json -ContentType "application/json"
        Write-Host "SYSTEM EVENT SENT → $url"
    }
    catch {
        Write-Host "Failed to send system event."
    }


    # --- Security Log Monitoring (4663) ---
    Check-SecurityLogs -allowedUsers $allowedUsers -agentId $agentId -orchestrator_ip $orchestrator_ip -orchestrator_port $orchestrator_port


    Start-Sleep -Seconds $interval
}
