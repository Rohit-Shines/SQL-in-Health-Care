# MirthCare SQL Training Stack

This package installs a consistent local SQL environment for healthcare SQL and Mirth Connect tutorials.

## Installed components

- MySQL Community Server **8.4 LTS**, newest patch available when the installer runs (Windows downloads directly from Oracle MySQL; macOS uses the Homebrew `mysql@8.4` formula for reliable terminal automation)
- Eclipse Temurin **JDK 17** for Mirth/NextGen Connect compatibility
- MySQL Workbench when supported
- Current MySQL Connector/J JDBC driver
- Local database: `MirthCareTrainingDB`
- Local account: `mirth_training`
- Diagnostic logs and a private credentials file

The package intentionally pins the MySQL major release to **8.4 LTS**. Automatically moving students between major releases would make videos and troubleshooting inconsistent.

## macOS

1. Open the `macOS` folder.
2. Double-click `MySQL-Mirth-Setup.command`.
3. If macOS blocks it, right-click the file, choose **Open**, and confirm.
4. Choose option **1**.
5. Enter the Mac administrator password if requested.

Terminal alternative:

```bash
cd macOS
chmod +x MySQL-Mirth-Setup.command mysql_mirth_setup.sh
./MySQL-Mirth-Setup.command
```

## Windows

1. Open the `Windows` folder.
2. Right-click `MySQL-Mirth-Setup.bat`.
3. Choose **Run as administrator**.
4. Approve the User Account Control prompt.
5. Choose option **1**.

The PowerShell execution policy is bypassed only for this launcher process. It is not permanently changed.

## Menu options

1. Install or repair the complete stack
2. Upgrade within MySQL 8.4 LTS and update dependencies
3. Diagnose the installation
4. Remove programs while preserving database data
5. Fully remove all detected MySQL services/common MySQL folders and permanently delete MySQL data
6. Exit

Full removal requires typing `DELETE-MYSQL-DATA` to prevent accidental database deletion. It removes common Homebrew/Oracle MySQL locations on macOS and detected MySQL services/common MySQL folders on Windows. Review the warning carefully.

For a clean reinstall of a laptop that already has MySQL:

1. Run option **3** to inspect the existing installation.
2. Back up any database that must be retained.
3. Run option **5** and type the confirmation phrase.
4. Reopen the launcher and run option **1**.

## Connection details

After installation, the generated credentials are stored here:

- macOS: `~/MirthCareSQL/mysql-training-credentials.txt`
- Windows: `C:\MirthCareSQL\mysql-training-credentials.txt`

The connection uses:

```text
Host: 127.0.0.1
Port: 3306
Database: MirthCareTrainingDB
User: mirth_training
Driver class: com.mysql.cj.jdbc.Driver
```

## Mirth Connect JDBC driver

The installer downloads Connector/J to:

- macOS: `~/MirthCareSQL/drivers/`
- Windows: `C:\MirthCareSQL\drivers\`

When a common Mirth/NextGen Connect server installation is detected, the installer also copies the JAR into `custom-lib`. Restart the Mirth Connect server after the copy.

## Important limitations

- macOS and Windows use different executable formats, so no single native script can run unchanged on both systems. The ZIP contains one double-click launcher for each operating system.
- Windows installation supports 64-bit Windows. The automated Temurin MSI fallback is x64.
- MySQL binds to `127.0.0.1` for training safety. It is not exposed to other computers.
- Do not use generated passwords or configuration as a production hospital deployment standard.
- Never load real patient information into this training database.
- Existing Java 17 or MySQL Workbench installations detected before first use are preserved during uninstall.
- Administrator approval cannot be bypassed: macOS may request a password and Windows shows a UAC prompt.

## Official sources

- MySQL downloads: https://www.mysql.com/downloads/
- MySQL Community Server: https://dev.mysql.com/downloads/mysql/8.4.html
- MySQL Windows installation: https://dev.mysql.com/doc/refman/8.4/en/windows-installation.html
- MySQL macOS installation: https://dev.mysql.com/doc/refman/8.4/en/macos-installation.html
- MySQL Connector/J: https://dev.mysql.com/doc/connector-j/en/
- Eclipse Temurin installation: https://adoptium.net/installation/
- Homebrew: https://brew.sh/
