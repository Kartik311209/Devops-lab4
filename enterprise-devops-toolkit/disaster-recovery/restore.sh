#!/usr/bin/env bash
# =============================================================================
# disaster-recovery/restore.sh
# Enterprise DevOps Deployment Toolkit (EDDT)
#
# Safe Database Restore Procedure
#
# Usage:
#   ./restore.sh [--force] [path-to-backup.db] [target-db-path]
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."
BACKUP_DIR="${SCRIPT_DIR}/backups"

FORCE=false
BACKUP_FILE=""
TARGET_DB=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force|-f)
      FORCE=true
      shift
      ;;
    *)
      if [ -n "$1" ]; then
        if [ -z "${BACKUP_FILE}" ]; then
          BACKUP_FILE="$1"
        elif [ -z "${TARGET_DB}" ]; then
          TARGET_DB="$1"
        fi
      fi
      shift
      ;;
  esac
done

TARGET_DB="${TARGET_DB:-${PROJECT_ROOT}/app/taskflow.db}"

echo "=========================================================="
echo " [Disaster Recovery] Database Restore Procedure"
echo " Target DB : ${TARGET_DB}"
echo "=========================================================="

# 1. Locate backup file if not specified
if [ -z "${BACKUP_FILE}" ]; then
  echo "[1/5] No backup specified. Searching for latest backup in ${BACKUP_DIR}..."
  BACKUP_FILE=$(find "${BACKUP_DIR}" -name "taskflow_backup_*.db" -type f 2>/dev/null | sort -r | head -n 1 || echo "")
fi

if [ -z "${BACKUP_FILE}" ] || [ ! -f "${BACKUP_FILE}" ]; then
  echo "[-] ERROR: Backup file not found at '${BACKUP_FILE}'"
  echo "    Usage: ./restore.sh [--force] [path-to-backup.db] [target-db-path]"
  exit 1
fi
echo "[1/5] Using backup file: ${BACKUP_FILE}"

# Normalize paths for safety check
REAL_BACKUP=$(cd "$(dirname "${BACKUP_FILE}")" && pwd)/$(basename "${BACKUP_FILE}")
REAL_TARGET=""
if [ -f "${TARGET_DB}" ]; then
  REAL_TARGET=$(cd "$(dirname "${TARGET_DB}")" && pwd)/$(basename "${TARGET_DB}")
fi

if [ -n "${REAL_TARGET}" ] && [ "${REAL_BACKUP}" = "${REAL_TARGET}" ]; then
  echo "[-] ERROR: Backup source and target are the same file! Choose a backup file from backups/."
  exit 1
fi

# 2. Checksum and Integrity Verification
echo "[2/5] Verifying backup checksum and internal integrity..."
CHECKSUM_FILE="${BACKUP_FILE}.sha256"
if [ -f "${CHECKSUM_FILE}" ]; then
  echo "Verifying SHA-256 checksum..."
  python3 -c "
import hashlib, sys
expected = open('${CHECKSUM_FILE}').read().strip().split()[0]
actual = hashlib.sha256(open('${BACKUP_FILE}','rb').read()).hexdigest()
if expected != actual:
    print(f'CHECKSUM MISMATCH! Expected {expected}, got {actual}', file=sys.stderr)
    sys.exit(1)
print('Checksum verified OK.')
"
fi

INTEGRITY=$(python3 -c "
import sqlite3
con = sqlite3.connect('${BACKUP_FILE}')
res = con.execute('PRAGMA integrity_check').fetchone()[0]
con.close()
print(res)
")
if [ "${INTEGRITY}" != "ok" ]; then
  echo "[-] CRITICAL: Backup failed internal integrity check (${INTEGRITY}). Restore aborted."
  exit 1
fi
echo "[+] Backup integrity verified."

# 3. Pre-restore Safety Backup of Existing Data
if [ -f "${TARGET_DB}" ]; then
  SAFETY_COPY="${TARGET_DB}.pre-restore-$(date +%Y%m%d_%H%M%S).bak"
  echo "[3/5] Existing database detected. Creating safety snapshot at:"
  echo "      ${SAFETY_COPY}"
  cp "${TARGET_DB}" "${SAFETY_COPY}"

  if [ "${FORCE}" != "true" ]; then
    echo "----------------------------------------------------------"
    echo " [CONFIRMATION REQUIRED]"
    echo " Target database '${TARGET_DB}' will be restored from:"
    echo " '${BACKUP_FILE}'"
    echo "----------------------------------------------------------"
    read -r -p "Are you sure you want to proceed with restore? [y/N]: " CONFIRM
    if [[ ! "${CONFIRM}" =~ ^[Yy]$ ]]; then
      echo "[!] Restore cancelled by operator. No changes made."
      exit 0
    fi
  fi
else
  echo "[3/5] Target database does not exist yet. Safe to create."
fi

# 4. Perform Atomic Restore
echo "[4/5] Restoring database file..."
mkdir -p "$(dirname "${TARGET_DB}")"
cp "${BACKUP_FILE}" "${TARGET_DB}"

# 5. Post-restore Verification
echo "[5/5] Running post-restore verification query..."
TASK_COUNT=$(python3 -c "
import sqlite3
con = sqlite3.connect('${TARGET_DB}')
count = con.execute('SELECT COUNT(*) FROM tasks').fetchone()[0]
con.close()
print(count)
")
echo "[+] Database successfully verified. Current task count: ${TASK_COUNT}"

echo "=========================================================="
echo " [SUCCESS] Database Restore Complete!"
echo " Target database '${TARGET_DB}' is restored and verified."
echo "=========================================================="
