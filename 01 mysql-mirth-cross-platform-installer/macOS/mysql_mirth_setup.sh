#!/bin/bash
# MirthCare SQL Training Stack - macOS installer/uninstaller
# Installs MySQL 8.4 LTS, Eclipse Temurin JDK 17, MySQL Workbench,
# MySQL Connector/J, and creates a local training database/user.

set -Eeuo pipefail
IFS=$'\n\t'

APP_NAME="MirthCare SQL Training Stack"
MYSQL_FORMULA="mysql@8.4"
JAVA_CASK="temurin@17"
WORKBENCH_CASK="mysqlworkbench"
DB_NAME="MirthCareTrainingDB"
DB_USER="mirth_training"
BASE_DIR="$HOME/MirthCareSQL"
DRIVER_DIR="$BASE_DIR/drivers"
LOG_DIR="$BASE_DIR/logs"
CREDENTIALS_FILE="$BASE_DIR/mysql-training-credentials.txt"
MANIFEST_FILE="$BASE_DIR/installed-files-manifest.txt"
STATE_FILE="$BASE_DIR/component-state.txt"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="$LOG_DIR/setup_$TIMESTAMP.log"

mkdir -p "$LOG_DIR" "$DRIVER_DIR"
touch "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

trap 'echo; echo "ERROR: Setup stopped at line $LINENO. Review: $LOG_FILE"; read -r -p "Press Enter to close..." _' ERR

info()  { printf '\n[INFO] %s\n' "$*"; }
warn()  { printf '\n[WARN] %s\n' "$*"; }
error() { printf '\n[ERROR] %s\n' "$*" >&2; }

pause() {
  echo
  read -r -p "Press Enter to continue..." _
}

require_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    error "This script is for macOS only. Use the Windows launcher on Windows."
    exit 1
  fi
}

load_brew_environment() {
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

install_homebrew() {
  load_brew_environment
  if command -v brew >/dev/null 2>&1; then
    info "Homebrew already installed: $(brew --version | head -n 1)"
    return
  fi

  info "Installing Homebrew. macOS may request your administrator password."
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  load_brew_environment

  if ! command -v brew >/dev/null 2>&1; then
    error "Homebrew installation did not complete successfully."
    exit 1
  fi
}

mysql_bin() {
  local prefix
  prefix="$(brew --prefix "$MYSQL_FORMULA" 2>/dev/null || true)"
  if [[ -n "$prefix" && -x "$prefix/bin/mysql" ]]; then
    printf '%s\n' "$prefix/bin/mysql"
  elif command -v mysql >/dev/null 2>&1; then
    command -v mysql
  else
    return 1
  fi
}

mysqladmin_bin() {
  local prefix
  prefix="$(brew --prefix "$MYSQL_FORMULA" 2>/dev/null || true)"
  if [[ -n "$prefix" && -x "$prefix/bin/mysqladmin" ]]; then
    printf '%s\n' "$prefix/bin/mysqladmin"
  elif command -v mysqladmin >/dev/null 2>&1; then
    command -v mysqladmin
  else
    return 1
  fi
}

wait_for_mysql() {
  info "Waiting for MySQL to accept local TCP connections..."
  for _ in {1..45}; do
    if nc -z 127.0.0.1 3306 >/dev/null 2>&1; then
      info "MySQL is running."
      return 0
    fi
    sleep 2
  done
  error "MySQL did not become ready. Run the Diagnostics option and review the log."
  return 1
}

generate_password() {
  # Restricted character set avoids shell/SQL quoting problems while remaining strong.
  printf 'Mc!%sAa9' "$(openssl rand -hex 16)"
}

sql_escape_literal() {
  printf '%s' "$1" | sed "s/'/''/g"
}

create_training_database() {
  local mysql password password_sql root_password root_password_sql sql initial_root
  mysql="$(mysql_bin)"
  password="$(generate_password)"
  password_sql="$(sql_escape_literal "$password")"
  root_password=""
  initial_root=0

  info "Creating the synthetic healthcare training database and dedicated account."

  if "$mysql" --protocol=socket -u root -e "SELECT 1" >/dev/null 2>&1; then
    initial_root=1
    root_password="$(generate_password)"
  else
    if [[ -f "$CREDENTIALS_FILE" ]]; then
      root_password="$(sed -n 's/^Root Password: //p' "$CREDENTIALS_FILE" | head -n 1)"
    fi
    if [[ -z "$root_password" ]]; then
      warn "The local MySQL root account already has a password."
      read -r -s -p "Enter the existing MySQL root password: " root_password
      echo
    fi
  fi

  root_password_sql="$(sql_escape_literal "$root_password")"
  sql="CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$password_sql';
ALTER USER '$DB_USER'@'localhost' IDENTIFIED BY '$password_sql';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;"

  if [[ "$initial_root" -eq 1 ]]; then
    sql="$sql
ALTER USER 'root'@'localhost' IDENTIFIED BY '$root_password_sql';"
    printf '%s\n' "$sql" | "$mysql" --protocol=socket -u root
  else
    MYSQL_PWD="$root_password" "$mysql" --protocol=socket -u root -e "$sql"
  fi

  umask 077
  cat > "$CREDENTIALS_FILE" <<CREDS
SYNTHETIC TRAINING DATABASE - NOT REAL PATIENT INFORMATION

Host: 127.0.0.1
Port: 3306
Database: $DB_NAME
Username: $DB_USER
Password: $password
Root Username: root
Root Password: $root_password
JDBC URL: jdbc:mysql://127.0.0.1:3306/$DB_NAME?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=America%2FToronto
JDBC Driver Class: com.mysql.cj.jdbc.Driver

Generated: $(date)
Keep this file private. Do not use these credentials in production.
CREDS
  chmod 600 "$CREDENTIALS_FILE"
  unset root_password
  info "Credentials saved securely to: $CREDENTIALS_FILE"
}

download_connector_j() {
  local metadata version jar_url jar_path
  info "Resolving the newest MySQL Connector/J release from Maven Central."
  metadata="$(curl -fsSL https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/maven-metadata.xml)"
  version="$(printf '%s' "$metadata" | sed -n 's:.*<release>\([^<]*\)</release>.*:\1:p' | head -n 1)"
  if [[ -z "$version" ]]; then
    error "Could not determine the current Connector/J version."
    return 1
  fi

  jar_url="https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/$version/mysql-connector-j-$version.jar"
  jar_path="$DRIVER_DIR/mysql-connector-j-$version.jar"
  curl -fL --retry 3 --connect-timeout 20 -o "$jar_path" "$jar_url"
  printf '%s\n' "$jar_path" >> "$MANIFEST_FILE"
  info "Connector/J installed: $jar_path"

  copy_driver_to_mirth "$jar_path"
}

copy_driver_to_mirth() {
  local jar="$1"
  local candidates=(
    "/Applications/Mirth Connect/custom-lib"
    "/Applications/NextGen Connect/custom-lib"
    "/Applications/Mirth Connect.app/Contents/custom-lib"
  )
  local dir target
  for dir in "${candidates[@]}"; do
    if [[ -d "$dir" ]]; then
      target="$dir/$(basename "$jar")"
      info "Detected Mirth/NextGen Connect. Copying JDBC driver to: $dir"
      sudo cp "$jar" "$target"
      printf '%s\n' "$target" >> "$MANIFEST_FILE"
      warn "Restart the Mirth Connect server before using the MySQL driver."
      return 0
    fi
  done
  info "Mirth Connect server folder was not detected. Driver remains in $DRIVER_DIR."
}

record_component_state() {
  if [[ -f "$STATE_FILE" ]]; then
    return
  fi
  local java_preexisting=0 workbench_preexisting=0
  brew list --cask "$JAVA_CASK" >/dev/null 2>&1 && java_preexisting=1
  brew list --cask "$WORKBENCH_CASK" >/dev/null 2>&1 && workbench_preexisting=1
  cat > "$STATE_FILE" <<STATE
JAVA_PREEXISTING=$java_preexisting
WORKBENCH_PREEXISTING=$workbench_preexisting
STATE
}

state_value() {
  local key="$1"
  [[ -f "$STATE_FILE" ]] || { printf '1\n'; return; }
  sed -n "s/^${key}=//p" "$STATE_FILE" | head -n 1
}

install_stack() {
  require_macos
  install_homebrew

  record_component_state

  info "Updating Homebrew package metadata."
  brew update

  info "Installing the newest MySQL 8.4 LTS patch available through Homebrew."
  brew install "$MYSQL_FORMULA"

  info "Installing Eclipse Temurin JDK 17 for Mirth Connect compatibility."
  brew install --cask "$JAVA_CASK"

  info "Installing MySQL Workbench."
  if ! brew install --cask "$WORKBENCH_CASK"; then
    warn "MySQL Workbench could not be installed on this macOS/CPU combination. MySQL Server installation will continue."
  fi

  info "Starting MySQL as a background service."
  brew services start "$MYSQL_FORMULA"

  # Make client commands available in this session without requiring a permanent forced link.
  export PATH="$(brew --prefix "$MYSQL_FORMULA")/bin:$PATH"
  wait_for_mysql
  create_training_database
  : > "$MANIFEST_FILE"
  download_connector_j

  verify_stack

  cat <<DONE

====================================================================
INSTALLATION COMPLETE
====================================================================
MySQL:      $("$(mysql_bin)" --version)
Java:       $(java -version 2>&1 | head -n 1)
Database:   $DB_NAME
Credentials:$CREDENTIALS_FILE
Log:        $LOG_FILE

MySQL Workbench connection:
  Host: 127.0.0.1
  Port: 3306
  User: $DB_USER
  Password: stored in $CREDENTIALS_FILE
====================================================================
DONE
}

upgrade_stack() {
  require_macos
  install_homebrew
  info "Upgrading the installed training stack within the pinned LTS release line."
  brew update
  brew upgrade "$MYSQL_FORMULA" || true
  brew upgrade --cask "$JAVA_CASK" || true
  brew upgrade --cask "$WORKBENCH_CASK" || true
  brew services restart "$MYSQL_FORMULA"
  wait_for_mysql
  : > "$MANIFEST_FILE"
  download_connector_j
  verify_stack
}

verify_stack() {
  require_macos
  load_brew_environment
  echo
  echo "================ STACK DIAGNOSTICS ================"
  echo "macOS:       $(sw_vers -productVersion 2>/dev/null || true)"
  echo "Architecture:$(uname -m)"
  echo "Homebrew:    $(brew --version 2>/dev/null | head -n 1 || echo 'Not installed')"

  if brew list --versions "$MYSQL_FORMULA" >/dev/null 2>&1; then
    echo "MySQL pkg:   $(brew list --versions "$MYSQL_FORMULA")"
    echo "Service:"
    brew services list | grep -E '^mysql(@8\.4)?[[:space:]]' || true
    if mysql_bin >/dev/null 2>&1; then
      "$(mysql_bin)" --version || true
    fi
  else
    echo "MySQL:       Not installed by this package"
  fi

  echo "Java:"
  java -version 2>&1 | head -n 3 || echo "Java not installed"
  echo "Connector/J:"
  ls -1 "$DRIVER_DIR"/mysql-connector-j-*.jar 2>/dev/null || echo "Not downloaded"
  echo "Port 3306:"
  lsof -nP -iTCP:3306 -sTCP:LISTEN 2>/dev/null || echo "Nothing listening on port 3306"
  echo "Log:         $LOG_FILE"
  echo "==================================================="
}

remove_manifest_files() {
  if [[ -f "$MANIFEST_FILE" ]]; then
    while IFS= read -r item; do
      [[ -z "$item" ]] && continue
      if [[ -e "$item" ]]; then
        if [[ "$item" == /Applications/* ]]; then
          sudo rm -f "$item"
        else
          rm -f "$item"
        fi
      fi
    done < "$MANIFEST_FILE"
  fi
}

uninstall_keep_data() {
  require_macos
  install_homebrew
  warn "This removes MySQL binaries, Workbench, Java 17, and the copied JDBC driver. MySQL database files are retained."
  read -r -p "Continue? Type YES: " answer
  [[ "$answer" == "YES" ]] || { info "Cancelled."; return; }

  brew services stop "$MYSQL_FORMULA" || true
  remove_manifest_files
  brew uninstall "$MYSQL_FORMULA" || true
  if [[ "$(state_value WORKBENCH_PREEXISTING)" == "0" ]]; then
    brew uninstall --cask "$WORKBENCH_CASK" || true
  else
    info "Preserving pre-existing MySQL Workbench installation."
  fi
  if [[ "$(state_value JAVA_PREEXISTING)" == "0" ]]; then
    brew uninstall --cask "$JAVA_CASK" || true
  else
    info "Preserving pre-existing Java 17 installation."
  fi
  info "Programs removed. Homebrew MySQL data directories were kept."
}

remove_all_mysql_macos() {
  info "Removing Homebrew and Oracle-package MySQL server installations."
  local formula
  for formula in mysql mysql@8.4 mysql@8.0; do
    brew services stop "$formula" >/dev/null 2>&1 || true
    if brew list --versions "$formula" >/dev/null 2>&1; then
      brew uninstall --force "$formula" || true
    fi
  done

  sudo launchctl bootout system /Library/LaunchDaemons/com.oracle.oss.mysql.mysqld.plist >/dev/null 2>&1 || true
  sudo rm -f /Library/LaunchDaemons/com.oracle.oss.mysql.mysqld.plist
  sudo rm -rf /Library/PreferencePanes/MySQL.prefPane

  shopt -s nullglob
  local oracle_paths=(/usr/local/mysql /usr/local/mysql-*)
  if (( ${#oracle_paths[@]} > 0 )); then
    sudo rm -rf "${oracle_paths[@]}"
  fi
  shopt -u nullglob

  sudo rm -rf /usr/local/var/mysql /opt/homebrew/var/mysql /opt/homebrew/var/mysql@8.4 /usr/local/var/mysql@8.4
  sudo rm -rf /etc/mysql
  sudo rm -f /etc/my.cnf
  sudo find /private/var/db/receipts -maxdepth 1 -name 'com.mysql.*' -delete 2>/dev/null || true
  rm -f "$HOME/Library/LaunchAgents/homebrew.mxcl.mysql"*.plist 2>/dev/null || true
}

full_purge() {
  require_macos
  install_homebrew
  cat <<'WARNING'

FULL PURGE WARNING
This permanently deletes local MySQL databases, users, configuration, logs,
training credentials, JDBC drivers, MySQL Workbench, and Java 17 installed by
this package. This cannot be undone without a backup.
WARNING
  read -r -p "Type DELETE-MYSQL-DATA to continue: " answer
  [[ "$answer" == "DELETE-MYSQL-DATA" ]] || { info "Cancelled."; return; }

  remove_manifest_files
  remove_all_mysql_macos
  if [[ "$(state_value WORKBENCH_PREEXISTING)" == "0" ]]; then
    brew uninstall --cask "$WORKBENCH_CASK" || true
  else
    info "Preserving pre-existing MySQL Workbench installation."
  fi
  if [[ "$(state_value JAVA_PREEXISTING)" == "0" ]]; then
    brew uninstall --cask "$JAVA_CASK" || true
  else
    info "Preserving pre-existing Java 17 installation."
  fi

  local brew_prefix
  brew_prefix="$(brew --prefix)"
  sudo rm -rf \
    "$brew_prefix/var/mysql@8.4" \
    "$brew_prefix/var/mysql" \
    "$HOME/Library/LaunchAgents/homebrew.mxcl.mysql@8.4.plist" \
    "$HOME/Library/LaunchAgents/homebrew.mxcl.mysql.plist"
  rm -rf "$BASE_DIR"
  info "Full purge completed. Homebrew itself was not removed."
}

show_menu() {
  while true; do
    clear || true
    cat <<MENU
============================================================
$APP_NAME - macOS
============================================================
1. Install or repair complete stack
2. Upgrade MySQL 8.4 LTS / Java / Workbench / JDBC driver
3. Diagnose current installation
4. Uninstall programs but KEEP MySQL data
5. FULL purge ALL MySQL server installs and DELETE data
6. Exit
============================================================
MENU
    read -r -p "Select an option [1-6]: " choice
    case "$choice" in
      1) install_stack; pause ;;
      2) upgrade_stack; pause ;;
      3) verify_stack; pause ;;
      4) uninstall_keep_data; pause ;;
      5) full_purge; pause ;;
      6) exit 0 ;;
      *) warn "Invalid option."; sleep 1 ;;
    esac
  done
}

require_macos
show_menu
