#!/bin/bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
chmod +x "$SCRIPT_DIR/mysql_mirth_setup.sh"
exec "$SCRIPT_DIR/mysql_mirth_setup.sh"
