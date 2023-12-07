# Import the PSSQLite module if not already loaded
if (-not (Get-Module -Name PSSQLite)) {
    Import-Module -Name PSSQLite
}

# Get the current host's hostname
$HostName = $env:COMPUTERNAME

# Define the directory where CSV file will be saved
$CsvFilePath = "C:\Windows\Admin\Data\ChromeDownloads.csv"
$DataFolderPath = "C:\Windows\Admin\Data"  # Specify the correct parent directory for the "data" folder
$ChromeHistoryLogPath = "C:\Windows\Admin\logs"

# Ensure the log directory exists
$null = New-Item -Path $ChromeHistoryLogPath -ItemType Directory -Force

# Create an empty array to store all results
$combinedResults = @()

# Get the list of user profiles in the C:\Users directory
$UserProfiles = Get-ChildItem -Path C:\Users -Directory

# Set up logging
$LogFilePath = Join-Path -Path $ChromeHistoryLogPath -ChildPath "ChromeDownloads.log"
Start-Transcript -Path $LogFilePath

# Check if the data directory exists, and create it if it doesn't
if (-not (Test-Path -Path $DataFolderPath -PathType Container)) {
    $null = New-Item -Path $DataFolderPath -ItemType Directory -Force
}

# Loop through each user profile
foreach ($UserProfile in $UserProfiles) {
    $UserName = $UserProfile.Name

    # Define the source path (original History file) and the destination path (copy in the temporary directory)
    $SourcePath = Join-Path -Path $UserProfile.FullName -ChildPath "AppData\Local\Google\Chrome\User Data\Default\History"
    $TempCopyPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "ChromeHistoryCopy.db"

    # Check if the Chrome history file exists for the user
    if (Test-Path -Path $SourcePath) {
        Write-Host "Processing Chrome history for user: $UserName"
        try {
            # Copy the History file to the temporary directory
            Copy-Item -Path $SourcePath -Destination $TempCopyPath -Force

            # Connect to the copied Chrome history database
            $Connection = New-SQLiteConnection -DataSource $TempCopyPath

            # Execute the query to view download data
            $results = Invoke-SqliteQuery -Connection $Connection -Query @"
            SELECT '$HostName' AS HostName,
                   '$UserName' AS UserName,
                   id AS DownloadID,
                   DATETIME(start_time / 1000000 + (strftime('%s', '1601-01-01')), 'unixepoch', 'localtime') AS StartTime,
                   DATETIME(end_time / 1000000 + (strftime('%s', '1601-01-01')), 'unixepoch', 'localtime') AS EndTime,
                   target_path AS FilePath,
                   total_bytes AS TotalBytes
            FROM downloads
"@

            # Append the results to the combinedResults array
            $combinedResults += $results

            # Close the database connection
            $Connection.Close()

            # Remove the temporary copy of the History file
            Remove-Item -Path $TempCopyPath -Force

            Write-Host "Processed Chrome history for user: $UserName"
        }
        catch {
            Write-Host "Error processing Chrome history for user: $UserName"
            Write-Host $_.Exception.Message
        }
    }
    else {
        Write-Host "Chrome history not found for user: $UserName"
    }
}

# Export the combined results as a single CSV file
$CsvFilePath = Join-Path -Path $DataFolderPath -ChildPath "ChromeDownloads.csv"
$combinedResults | Export-Csv -Path $CsvFilePath -NoTypeInformation

# Stop logging
Stop-Transcript

Write-Host "Combined results exported to $CsvFilePath"
