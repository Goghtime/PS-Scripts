param (
    [string]$DataFolderPath = "C:\Windows\Admin\Data",
    [string]$ChromeHistoryLogPath = "C:\Windows\Admin\logs"
)

# Set up logging
$LogFileName = "ChromeHistory.log"
$LogFilePath = Join-Path -Path $ChromeHistoryLogPath -ChildPath $LogFileName

if (-not (Test-Path -Path $ChromeHistoryLogPath -PathType Container)) {
    $null = New-Item -Path $ChromeHistoryLogPath -ItemType Directory -Force
}

if (-not (Test-Path -Path $DataFolderPath -PathType Container)) {
    $null = New-Item -Path $DataFolderPath -ItemType Directory -Force
}

# Functions.
function Log-Message {
    param (
        [string]$Message
    )
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$TimeStamp - $Message"
    Add-Content -Path $LogFilePath -Value "$TimeStamp - $Message"
}

function Manage-CSVFiles {
    $CsvFiles = Get-ChildItem -Path $DataFolderPath -File -Filter "ChromeHistory_*.csv" | Sort-Object -Property LastWriteTime -Descending
    $CsvFilesToDelete = $CsvFiles | Select-Object -Skip 20

    foreach ($CsvFile in $CsvFilesToDelete) {
        Log-Message "Deleting old CSV file: $($CsvFile.FullName)"
        Remove-Item -Path $CsvFile.FullName -Force
    }
}

# Modules.
$PSSQLiteModule = Get-Module -Name PSSQLite -ListAvailable

if (!$PSSQLiteModule) {
    Log-Message "Installing PSSQLite module..."
    Install-Module -Name PSSQLite -Force
    Log-Message "PSSQLite module installed."
}


Import-Module -Name PSSQLite

# Setup.
$HostName = $env:COMPUTERNAME

Log-Message "Starting Chrome history processing."

# empty array to store results
$combinedResults = @()

# list of user profiles in the C:\Users
$UserProfiles = Get-ChildItem -Path C:\Users -Directory

# last run timestamp
$LastRunTimestampPath = Join-Path -Path $DataFolderPath -ChildPath "LastRunTimestamp.txt"

if (Test-Path -Path $LastRunTimestampPath) {
    $LastRunTimestamp = Get-Content -Path $LastRunTimestampPath
} else {
    $LastRunTimestamp = (Get-Date).AddYears(-1).ToString("yyyy-MM-dd HH:mm:ss")
}

# Loop through each user profile
foreach ($UserProfile in $UserProfiles) {
    $UserName = $UserProfile.Name

    # Define the source path (original History file) and the destination path (copy in the temporary directory)
    $SourcePath = Join-Path -Path $UserProfile.FullName -ChildPath "AppData\Local\Google\Chrome\User Data\Default\History"
    $TempCopyPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "ChromeHistoryCopy.db"

    # Check if the Chrome history file exists for the user
    if (Test-Path -Path $SourcePath) {
        try {
            # Copy the History file to the temporary directory
            Copy-Item -Path $SourcePath -Destination $TempCopyPath -Force

            # Connect to the copied Chrome history database
            $Connection = New-SQLiteConnection -DataSource $TempCopyPath

            # Execute query
            $query = @"
                SELECT '$HostName' AS HostName,
                       '$UserName' AS UserName,
                       visits.id AS VisitID,
                       DATETIME(visit_time / 1000000 + (strftime('%s', '1601-01-01')), 'unixepoch', 'localtime') AS EventTime,
                       urls.url AS URL,
                       visits.visit_duration AS DurationInSeconds
                FROM visits
                JOIN urls ON visits.url = urls.id
                WHERE DATETIME(visit_time / 1000000 + (strftime('%s', '1601-01-01')), 'unixepoch', 'localtime') > '$LastRunTimestamp'
"@

            $results = Invoke-SqliteQuery -Connection $Connection -Query $query

            # Append the results to combinedResults
            $combinedResults += $results

            $Connection.Close()

            # Remove the temporary copy
            Remove-Item -Path $TempCopyPath -Force

            Log-Message "Processed Chrome history for user: $UserName"
        }
        catch {
            Log-Message "Error processing Chrome history for user: $UserName"
            Log-Message $_.Exception.Message
        }
    }
    else {
        Log-Message "Chrome history not found for user: $UserName"
    }
}

# Export the combined results as a single CSV file with a timestamp
$TimeStamp = Get-Date -Format 'yyyyMMddHHmmss'
$CsvFileName = "ChromeHistory_$TimeStamp.csv"
$CsvFilePath = Join-Path -Path $DataFolderPath -ChildPath $CsvFileName
$combinedResults | Export-Csv -Path $CsvFilePath -NoTypeInformation

# Update the last run timestamp in the timestamp file
$CurrentTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$CurrentTimestamp | Set-Content -Path $LastRunTimestampPath

Log-Message "Combined results exported to $CsvFilePath"

# Ensure only the most recent 20 log files are retained
Manage-CSVFiles