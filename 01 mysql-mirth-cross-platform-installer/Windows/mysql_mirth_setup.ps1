#Requires -Version 5.1
<#
MirthCare SQL Training Stack - Windows installer/uninstaller
Installs the latest MySQL 8.4 LTS patch from dev.mysql.com, Microsoft Visual C++
runtime, Eclipse Temurin JDK 17, MySQL Connector/J, and a synthetic training DB.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Set-StrictMode -Version Latest

$AppName = 'MirthCare SQL Training Stack'
$MySqlSeries = '8.4'
$ServiceName = 'MySQL84MirthCare'
$InstallRoot = Join-Path $env:ProgramFiles 'MySQL\MySQL Server 8.4'
$BinDir = Join-Path $InstallRoot 'bin'
$ProgramDataRoot = Join-Path $env:ProgramData 'MirthCareMySQL'
$DataDir = Join-Path $ProgramDataRoot 'data'
$ConfigFile = Join-Path $ProgramDataRoot 'my.ini'
$SecureFilesDir = Join-Path $ProgramDataRoot 'secure-files'
$BaseDir = 'C:\MirthCareSQL'
$DriverDir = Join-Path $BaseDir 'drivers'
$LogDir = Join-Path $BaseDir 'logs'
$CredentialsFile = Join-Path $BaseDir 'mysql-training-credentials.txt'
$ManifestFile = Join-Path $BaseDir 'installed-files-manifest.txt'
$StateFile = Join-Path $BaseDir 'component-state.txt'
$DbName = 'MirthCareTrainingDB'
$DbUser = 'mirth_training'
$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$LogFile = Join-Path $LogDir "setup_$Timestamp.log"

New-Item -ItemType Directory -Force -Path $LogDir, $DriverDir, $ProgramDataRoot, $SecureFilesDir | Out-Null
Start-Transcript -Path $LogFile -Append | Out-Null

function Write-Info([string]$Message) { Write-Host "`n[INFO] $Message" -ForegroundColor Cyan }
function Write-Warn([string]$Message) { Write-Host "`n[WARN] $Message" -ForegroundColor Yellow }
function Write-Fail([string]$Message) { Write-Host "`n[ERROR] $Message" -ForegroundColor Red }

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-Administrator {
    if (Test-Administrator) { return }
    Write-Info 'Requesting Administrator access.'
    $scriptPath = $PSCommandPath
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
    Start-Process PowerShell.exe -Verb RunAs -ArgumentList $arguments
    Stop-Transcript | Out-Null
    exit 0
}

function Assert-SupportedWindows {
    $os = Get-CimInstance Win32_OperatingSystem
    if ([Environment]::Is64BitOperatingSystem -ne $true) {
        throw 'A 64-bit version of Windows is required.'
    }
    Write-Info "Detected $($os.Caption) $($os.Version), architecture $env:PROCESSOR_ARCHITECTURE"
}

function Get-LatestMySql84Package {
    Write-Info 'Resolving the newest MySQL 8.4 LTS Windows ZIP from dev.mysql.com.'
    $pageUrl = 'https://dev.mysql.com/downloads/mysql/8.4.html'
    $content = (Invoke-WebRequest -UseBasicParsing -Uri $pageUrl).Content
    $matches = [regex]::Matches($content, 'mysql-(8\.4\.\d+)-winx64\.zip')
    if ($matches.Count -eq 0) {
        throw 'Could not determine the current MySQL 8.4 Windows package version.'
    }
    $versions = $matches | ForEach-Object { [version]$_.Groups[1].Value } | Sort-Object -Descending -Unique
    $version = $versions[0].ToString()
    $fileName = "mysql-$version-winx64.zip"
    $downloadUrl = "https://dev.mysql.com/get/Downloads/MySQL-8.4/$fileName"

    $md5Pattern = [regex]::Escape($fileName) + '[\s\S]{0,600}?MD5:\s*`?([a-fA-F0-9]{32})'
    $md5Match = [regex]::Match($content, $md5Pattern)
    $expectedMd5 = if ($md5Match.Success) { $md5Match.Groups[1].Value.ToLowerInvariant() } else { $null }

    [pscustomobject]@{
        Version = $version
        FileName = $fileName
        DownloadUrl = $downloadUrl
        ExpectedMd5 = $expectedMd5
    }
}

function Test-DisplayNameInstalled([string]$Pattern) {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    return [bool](Get-ItemProperty $paths -ErrorAction SilentlyContinue | Where-Object { $_.PSObject.Properties.Name -contains 'DisplayName' -and $_.DisplayName -like $Pattern } | Select-Object -First 1)
}

function Record-ComponentState {
    if (Test-Path $StateFile) { return }
    $javaPreexisting = Test-DisplayNameInstalled '*Temurin*17*'
    $workbenchPreexisting = Test-DisplayNameInstalled '*MySQL Workbench*'
    $stateContent = @"
JAVA_PREEXISTING=$($javaPreexisting.ToString().ToLowerInvariant())
WORKBENCH_PREEXISTING=$($workbenchPreexisting.ToString().ToLowerInvariant())
"@
    $stateContent | Set-Content -Path $StateFile -Encoding ASCII
}

function Get-StateValue([string]$Key, [string]$Default = 'true') {
    if (-not (Test-Path $StateFile)) { return $Default }
    $line = Get-Content $StateFile | Where-Object { $_ -like "$Key=*" } | Select-Object -First 1
    if (-not $line) { return $Default }
    return ($line -split '=', 2)[1]
}

function Install-VCRuntime {
    Write-Info 'Installing or repairing Microsoft Visual C++ 2015-2022 x64 runtime required by MySQL.'
    $installer = Join-Path $env:TEMP 'vc_redist.x64.exe'
    Invoke-WebRequest -UseBasicParsing -Uri 'https://aka.ms/vs/17/release/vc_redist.x64.exe' -OutFile $installer
    $process = Start-Process -FilePath $installer -ArgumentList '/install','/quiet','/norestart' -Wait -PassThru
    if ($process.ExitCode -notin 0, 1638, 3010) {
        throw "Visual C++ runtime installer failed with exit code $($process.ExitCode)."
    }
    Remove-Item $installer -Force -ErrorAction SilentlyContinue
}

function Stop-OurMySqlService {
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($service) {
        if ($service.Status -ne 'Stopped') {
            Stop-Service -Name $ServiceName -Force
            $service.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(30))
        }
    }
}

function Remove-OurMySqlService {
    Stop-OurMySqlService
    $mysqld = Join-Path $BinDir 'mysqld.exe'
    if (Test-Path $mysqld) {
        & $mysqld --remove $ServiceName 2>$null | Out-Null
    }
    elseif (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
        sc.exe delete $ServiceName | Out-Null
    }
}

function Add-MachinePath([string]$PathToAdd) {
    $current = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $parts = @($current -split ';' | Where-Object { $_ })
    if ($parts -notcontains $PathToAdd) {
        $newPath = (($parts + $PathToAdd) -join ';')
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'Machine')
    }
    if (($env:Path -split ';') -notcontains $PathToAdd) {
        $env:Path = "$env:Path;$PathToAdd"
    }
}

function Remove-MachinePath([string]$PathToRemove) {
    $current = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $parts = @($current -split ';' | Where-Object { $_ -and $_ -ne $PathToRemove })
    [Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'Machine')
}

function Write-MySqlConfig {
    New-Item -ItemType Directory -Force -Path $ProgramDataRoot, $DataDir, $SecureFilesDir | Out-Null
    $basedir = $InstallRoot.Replace('\','/')
    $datadir = $DataDir.Replace('\','/')
    $secureDir = $SecureFilesDir.Replace('\','/')
    $configContent = @"
[mysqld]
basedir=$basedir
datadir=$datadir
port=3306
bind-address=127.0.0.1
mysqlx-bind-address=127.0.0.1
character-set-server=utf8mb4
collation-server=utf8mb4_0900_ai_ci
secure-file-priv=$secureDir
max_connections=200
log_error=$($ProgramDataRoot.Replace('\','/'))/mysql-error.log

[client]
port=3306
protocol=tcp
default-character-set=utf8mb4
"@
    $configContent | Set-Content -Path $ConfigFile -Encoding ASCII
}

function Wait-MySqlPort {
    Write-Info 'Waiting for MySQL to accept TCP connections on 127.0.0.1:3306.'
    for ($i = 0; $i -lt 45; $i++) {
        $client = New-Object System.Net.Sockets.TcpClient
        try {
            $task = $client.ConnectAsync('127.0.0.1', 3306)
            if ($task.Wait(1000) -and $client.Connected) { return }
        }
        catch { }
        finally { $client.Dispose() }
        Start-Sleep -Seconds 1
    }
    throw 'MySQL service started but port 3306 did not become available.'
}

function Install-MySqlServer {
    $package = Get-LatestMySql84Package
    Write-Info "Installing MySQL Community Server $($package.Version) LTS."

    $existingService = Get-Service | Where-Object { $_.Name -match '^MySQL' -and $_.Name -ne $ServiceName }
    if ($existingService) {
        Write-Warn ('Other MySQL service(s) detected: ' + (($existingService | Select-Object -ExpandProperty Name) -join ', '))
        Write-Warn 'This package uses its own service name and port 3306. Stop or remove another port-3306 service before continuing.'
        $portInUse = Get-NetTCPConnection -LocalPort 3306 -State Listen -ErrorAction SilentlyContinue
        if ($portInUse) {
            throw 'Port 3306 is already in use by another process. Use Diagnostics and uninstall/stop the conflicting MySQL instance first.'
        }
    }

    Remove-OurMySqlService
    if (Test-Path $InstallRoot) {
        Remove-Item $InstallRoot -Recurse -Force
    }

    $zipPath = Join-Path $env:TEMP $package.FileName
    Invoke-WebRequest -UseBasicParsing -Uri $package.DownloadUrl -OutFile $zipPath

    if ($package.ExpectedMd5) {
        $actualMd5 = (Get-FileHash -Algorithm MD5 -Path $zipPath).Hash.ToLowerInvariant()
        if ($actualMd5 -ne $package.ExpectedMd5) {
            throw "MySQL download checksum mismatch. Expected $($package.ExpectedMd5), received $actualMd5."
        }
        Write-Info 'MySQL download checksum verified.'
    }
    else {
        Write-Warn 'The download page did not expose an MD5 value to the parser; HTTPS download completed without local checksum verification.'
    }

    $extractRoot = Join-Path $env:TEMP "mysql_extract_$([guid]::NewGuid().ToString('N'))"
    Expand-Archive -Path $zipPath -DestinationPath $extractRoot -Force
    $sourceDir = Get-ChildItem -Path $extractRoot -Directory | Select-Object -First 1
    if (-not $sourceDir) { throw 'The MySQL ZIP did not contain the expected root folder.' }

    New-Item -ItemType Directory -Force -Path (Split-Path $InstallRoot -Parent) | Out-Null
    Move-Item -Path $sourceDir.FullName -Destination $InstallRoot
    Remove-Item $extractRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

    Write-MySqlConfig
    $mysqld = Join-Path $BinDir 'mysqld.exe'
    if (-not (Test-Path $mysqld)) { throw 'mysqld.exe was not found after extraction.' }

    if ((Test-Path $DataDir) -and (Get-ChildItem $DataDir -Force -ErrorAction SilentlyContinue)) {
        Write-Info 'Existing MirthCare MySQL data directory detected; preserving it.'
    }
    else {
        Write-Info 'Initializing a new MySQL data directory.'
        New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
        & $mysqld "--defaults-file=$ConfigFile" --initialize-insecure --console
        if ($LASTEXITCODE -ne 0) { throw "MySQL data initialization failed with exit code $LASTEXITCODE." }
    }

    # MySQL requires --install to appear before --defaults-file on Windows.
    & $mysqld --install $ServiceName "--defaults-file=$ConfigFile"
    if ($LASTEXITCODE -ne 0) { throw "MySQL service installation failed with exit code $LASTEXITCODE." }

    Set-Service -Name $ServiceName -StartupType Automatic
    Start-Service -Name $ServiceName
    (Get-Service -Name $ServiceName).WaitForStatus('Running', [TimeSpan]::FromSeconds(45))
    Wait-MySqlPort
    Add-MachinePath $BinDir
}

function New-TrainingPassword {
    $bytes = New-Object byte[] 18
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $hex = -join ($bytes | ForEach-Object { $_.ToString('x2') })
    return "Mc!${hex}Aa9"
}

function Escape-SqlLiteral([string]$Value) {
    return $Value.Replace("'", "''")
}

function Get-StoredCredentialValue([string]$Name) {
    if (-not (Test-Path $CredentialsFile)) { return $null }
    $line = Get-Content $CredentialsFile | Where-Object { $_ -like "$Name`: *" } | Select-Object -First 1
    if (-not $line) { return $null }
    return $line.Substring($Name.Length + 2)
}

function ConvertTo-PlainText([Security.SecureString]$SecureValue) {
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureValue)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

function Initialize-TrainingDatabase {
    $mysql = Join-Path $BinDir 'mysql.exe'
    if (-not (Test-Path $mysql)) { throw 'mysql.exe was not found.' }

    $password = New-TrainingPassword
    $escapedPassword = Escape-SqlLiteral $password
    $rootPassword = $null
    $setInitialRootPassword = $false

    & $mysql --protocol=tcp -h 127.0.0.1 -P 3306 -u root --connect-timeout=5 -e 'SELECT 1' *> $null
    if ($LASTEXITCODE -eq 0) {
        $rootPassword = New-TrainingPassword
        $setInitialRootPassword = $true
    }
    else {
        $rootPassword = Get-StoredCredentialValue 'Root Password'
        if ([string]::IsNullOrWhiteSpace($rootPassword)) {
            $rootPassword = ConvertTo-PlainText (Read-Host 'Existing MySQL root password' -AsSecureString)
        }
    }

    $escapedRootPassword = Escape-SqlLiteral $rootPassword
    $sql = @"
CREATE DATABASE IF NOT EXISTS ``$DbName`` CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
CREATE USER IF NOT EXISTS '$DbUser'@'localhost' IDENTIFIED BY '$escapedPassword';
ALTER USER '$DbUser'@'localhost' IDENTIFIED BY '$escapedPassword';
GRANT ALL PRIVILEGES ON ``$DbName``.* TO '$DbUser'@'localhost';
FLUSH PRIVILEGES;
"@
    if ($setInitialRootPassword) {
        $sql += "`nALTER USER 'root'@'localhost' IDENTIFIED BY '$escapedRootPassword';`n"
    }

    $tempSql = Join-Path $env:TEMP "mirthcare_init_$([guid]::NewGuid().ToString('N')).sql"
    try {
        $sql | Set-Content -Path $tempSql -Encoding ASCII
        if ($setInitialRootPassword) {
            Get-Content $tempSql | & $mysql --protocol=tcp -h 127.0.0.1 -P 3306 -u root
        }
        else {
            $env:MYSQL_PWD = $rootPassword
            Get-Content $tempSql | & $mysql --protocol=tcp -h 127.0.0.1 -P 3306 -u root
            Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue
        }
        if ($LASTEXITCODE -ne 0) { throw 'Unable to create or update the training database.' }
    }
    finally {
        Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue
        Remove-Item $tempSql -Force -ErrorAction SilentlyContinue
    }

    $credentialsContent = @"
SYNTHETIC TRAINING DATABASE - NOT REAL PATIENT INFORMATION

Host: 127.0.0.1
Port: 3306
Database: $DbName
Username: $DbUser
Password: $password
Root Username: root
Root Password: $rootPassword
JDBC URL: jdbc:mysql://127.0.0.1:3306/$DbName?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=America%2FToronto
JDBC Driver Class: com.mysql.cj.jdbc.Driver

Generated: $(Get-Date)
Keep this file private. Do not use these credentials in production.
"@
    $credentialsContent | Set-Content -Path $CredentialsFile -Encoding UTF8

    $acl = Get-Acl $CredentialsFile
    $acl.SetAccessRuleProtection($true, $false)
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($env:USERNAME, 'FullControl', 'Allow')
    $acl.SetAccessRule($rule)
    Set-Acl -Path $CredentialsFile -AclObject $acl
    $rootPassword = $null
}

function Install-Java17 {
    Write-Info 'Installing Eclipse Temurin JDK 17 for Mirth Connect.'
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($winget) {
        & winget install --id EclipseAdoptium.Temurin.17.JDK --exact --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
        if ($LASTEXITCODE -notin 0, -1978335189) {
            Write-Warn "winget returned exit code $LASTEXITCODE; attempting Adoptium MSI fallback."
        }
        else { return }
    }

    $msi = Join-Path $env:TEMP 'OpenJDK17U-jdk_x64_windows_hotspot.msi'
    $api = 'https://api.adoptium.net/v3/installer/latest/17/ga/windows/x64/jdk/hotspot/normal/eclipse?project=jdk'
    Invoke-WebRequest -UseBasicParsing -Uri $api -OutFile $msi
    $args = @('/i', "`"$msi`"", '/qn', '/norestart', 'ADDLOCAL=FeatureMain,FeatureEnvironment,FeatureJarFileRunWith,FeatureJavaHome')
    $process = Start-Process msiexec.exe -ArgumentList $args -Wait -PassThru
    if ($process.ExitCode -notin 0, 3010) { throw "Temurin JDK installer failed with exit code $($process.ExitCode)." }
    Remove-Item $msi -Force -ErrorAction SilentlyContinue
}

function Install-MySqlWorkbench {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        Write-Warn 'winget is unavailable, so MySQL Workbench was not installed automatically.'
        return
    }
    Write-Info 'Installing MySQL Workbench.'
    & winget install --id Oracle.MySQLWorkbench --exact --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "MySQL Workbench installation returned exit code $LASTEXITCODE. MySQL Server installation will continue."
    }
}

function Install-ConnectorJ {
    Write-Info 'Resolving the newest MySQL Connector/J release from Maven Central.'
    $metadata = (Invoke-WebRequest -UseBasicParsing -Uri 'https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/maven-metadata.xml').Content
    $match = [regex]::Match($metadata, '<release>([^<]+)</release>')
    if (-not $match.Success) { throw 'Could not determine the latest MySQL Connector/J release.' }
    $version = $match.Groups[1].Value
    $jarName = "mysql-connector-j-$version.jar"
    $jarPath = Join-Path $DriverDir $jarName
    $jarUrl = "https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/$version/$jarName"
    Invoke-WebRequest -UseBasicParsing -Uri $jarUrl -OutFile $jarPath
    Set-Content -Path $ManifestFile -Value $jarPath -Encoding UTF8

    $mirthCandidates = @(
        (Join-Path $env:ProgramFiles 'Mirth Connect\custom-lib'),
        (Join-Path $env:ProgramFiles 'NextGen Connect\custom-lib')
    )
    $programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    if ($programFilesX86) {
        $mirthCandidates += (Join-Path $programFilesX86 'Mirth Connect\custom-lib')
    }

    foreach ($dir in $mirthCandidates) {
        if (Test-Path $dir) {
            $target = Join-Path $dir $jarName
            Copy-Item $jarPath $target -Force
            Add-Content -Path $ManifestFile -Value $target
            Write-Warn "JDBC driver copied into Mirth: $target. Restart the Mirth Connect server."
            break
        }
    }
}

function Install-Stack {
    Assert-SupportedWindows
    Record-ComponentState
    Install-VCRuntime
    Install-MySqlServer
    Install-Java17
    Install-MySqlWorkbench
    Initialize-TrainingDatabase
    Install-ConnectorJ
    Show-Diagnostics

    Write-Host "`n============================================================" -ForegroundColor Green
    Write-Host 'INSTALLATION COMPLETE' -ForegroundColor Green
    Write-Host "MySQL Service: $ServiceName"
    Write-Host "Database:      $DbName"
    Write-Host "Credentials:   $CredentialsFile"
    Write-Host "Log:           $LogFile"
    Write-Host 'Host/Port:     127.0.0.1:3306'
    Write-Host '============================================================' -ForegroundColor Green
}

function Update-Stack {
    Record-ComponentState
    Write-Warn 'The updater replaces MySQL binaries while preserving the MirthCare data directory. A backup is still recommended.'
    $answer = Read-Host 'Type YES to continue'
    if ($answer -ne 'YES') { Write-Info 'Cancelled.'; return }
    Install-VCRuntime
    Install-MySqlServer
    Install-Java17
    Install-MySqlWorkbench
    Install-ConnectorJ
    Show-Diagnostics
}

function Show-Diagnostics {
    Write-Host "`n================ STACK DIAGNOSTICS ================" -ForegroundColor White
    $os = Get-CimInstance Win32_OperatingSystem
    Write-Host "Windows:      $($os.Caption) $($os.Version)"
    Write-Host "Architecture: $env:PROCESSOR_ARCHITECTURE"
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($service) { Write-Host "Service:      $($service.Name) - $($service.Status)" }
    else { Write-Host 'Service:      Not installed' }

    $mysql = Join-Path $BinDir 'mysql.exe'
    if (Test-Path $mysql) { & $mysql --version }
    else { Write-Host 'MySQL:        Not installed by this package' }

    $java = Get-Command java.exe -ErrorAction SilentlyContinue
    if ($java) { & java.exe -version 2>&1 | Select-Object -First 3 }
    else { Write-Host 'Java:         Not found in current PATH' }

    Write-Host 'Port 3306:'
    Get-NetTCPConnection -LocalPort 3306 -State Listen -ErrorAction SilentlyContinue |
        Select-Object LocalAddress, LocalPort, OwningProcess |
        Format-Table -AutoSize
    Write-Host "JDBC drivers: $DriverDir"
    Get-ChildItem -Path $DriverDir -Filter 'mysql-connector-j-*.jar' -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty FullName
    Write-Host "Log:          $LogFile"
    Write-Host '==================================================' -ForegroundColor White
}

function Remove-ManifestFiles {
    if (-not (Test-Path $ManifestFile)) { return }
    foreach ($item in Get-Content $ManifestFile) {
        if ($item -and (Test-Path $item)) {
            Remove-Item $item -Force -ErrorAction SilentlyContinue
        }
    }
}

function Uninstall-KeepData {
    Write-Warn 'This removes MySQL binaries/service, Workbench, Java 17, and JDBC driver copies. Database files are retained.'
    $answer = Read-Host 'Type YES to continue'
    if ($answer -ne 'YES') { Write-Info 'Cancelled.'; return }

    Remove-OurMySqlService
    Remove-ManifestFiles
    Remove-MachinePath $BinDir
    if (Test-Path $InstallRoot) { Remove-Item $InstallRoot -Recurse -Force }

    if (Get-Command winget.exe -ErrorAction SilentlyContinue) {
        if ((Get-StateValue 'WORKBENCH_PREEXISTING') -eq 'false') {
            & winget uninstall --id Oracle.MySQLWorkbench --exact --silent --disable-interactivity 2>$null
        }
        else { Write-Info 'Preserving pre-existing MySQL Workbench installation.' }
        if ((Get-StateValue 'JAVA_PREEXISTING') -eq 'false') {
            & winget uninstall --id EclipseAdoptium.Temurin.17.JDK --exact --silent --disable-interactivity 2>$null
        }
        else { Write-Info 'Preserving pre-existing Java 17 installation.' }
    }
    Write-Info "Programs removed. Data retained in: $DataDir"
}

function Remove-AllMySqlServices {
    $services = Get-CimInstance Win32_Service | Where-Object { $_.Name -match '^MySQL' }
    foreach ($service in $services) {
        Write-Warn "Removing MySQL service: $($service.Name)"
        Stop-Service -Name $service.Name -Force -ErrorAction SilentlyContinue
        sc.exe delete $service.Name | Out-Null
    }
}

function Remove-AllMySqlMachinePaths {
    $current = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $parts = @($current -split ';' | Where-Object { $_ -and $_ -notmatch '\\MySQL\\' })
    [Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'Machine')
}

function Remove-CommonMySqlFolders {
    $folders = @(
        (Join-Path $env:ProgramFiles 'MySQL'),
        (Join-Path $env:ProgramData 'MySQL'),
        $ProgramDataRoot
    )
    $programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    if ($programFilesX86) { $folders += (Join-Path $programFilesX86 'MySQL') }
    foreach ($folder in $folders | Select-Object -Unique) {
        if (Test-Path $folder) {
            Write-Warn "Deleting MySQL folder: $folder"
            Remove-Item $folder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Full-Purge {
    $purgeWarning = @'

FULL PURGE WARNING
This permanently removes ALL detected MySQL services and common MySQL folders,
accounts, configuration, logs, credentials, JDBC drivers, MySQL Workbench,
and Java 17 installed by this package.
'@
    Write-Host $purgeWarning -ForegroundColor Red
    $answer = Read-Host 'Type DELETE-MYSQL-DATA to continue'
    if ($answer -ne 'DELETE-MYSQL-DATA') { Write-Info 'Cancelled.'; return }

    Remove-ManifestFiles
    Remove-AllMySqlServices
    Remove-AllMySqlMachinePaths
    if (Get-Command winget.exe -ErrorAction SilentlyContinue) {
        & winget uninstall --id Oracle.MySQL --exact --silent --disable-interactivity 2>$null
    }
    Remove-CommonMySqlFolders

    if (Get-Command winget.exe -ErrorAction SilentlyContinue) {
        if ((Get-StateValue 'WORKBENCH_PREEXISTING') -eq 'false') {
            & winget uninstall --id Oracle.MySQLWorkbench --exact --silent --disable-interactivity 2>$null
        }
        else { Write-Info 'Preserving pre-existing MySQL Workbench installation.' }
        if ((Get-StateValue 'JAVA_PREEXISTING') -eq 'false') {
            & winget uninstall --id EclipseAdoptium.Temurin.17.JDK --exact --silent --disable-interactivity 2>$null
        }
        else { Write-Info 'Preserving pre-existing Java 17 installation.' }
    }

    Stop-Transcript | Out-Null
    if (Test-Path $BaseDir) { Remove-Item $BaseDir -Recurse -Force }
    Write-Host 'Full purge completed.' -ForegroundColor Green
    exit 0
}

function Show-Menu {
    while ($true) {
        Clear-Host
        Write-Host '============================================================'
        Write-Host "$AppName - Windows"
        Write-Host '============================================================'
        Write-Host '1. Install or repair complete stack'
        Write-Host '2. Upgrade MySQL 8.4 LTS / Java / Workbench / JDBC driver'
        Write-Host '3. Diagnose current installation'
        Write-Host '4. Uninstall programs but KEEP MySQL data'
        Write-Host '5. FULL purge ALL MySQL server installs and DELETE data'
        Write-Host '6. Exit'
        Write-Host '============================================================'
        $choice = Read-Host 'Select an option [1-6]'
        try {
            switch ($choice) {
                '1' { Install-Stack }
                '2' { Update-Stack }
                '3' { Show-Diagnostics }
                '4' { Uninstall-KeepData }
                '5' { Full-Purge }
                '6' { return }
                default { Write-Warn 'Invalid option.' }
            }
        }
        catch {
            Write-Fail $_.Exception.Message
            Write-Fail "Review the log: $LogFile"
        }
        Read-Host 'Press Enter to continue' | Out-Null
    }
}

try {
    Ensure-Administrator
    Show-Menu
}
finally {
    try { Stop-Transcript | Out-Null } catch { }
}
