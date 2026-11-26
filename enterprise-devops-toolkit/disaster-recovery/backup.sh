#!/usr/bin/env bash
# =============================================================================
# disaster-recovery/backup.sh
# Enterprise DevOps Deployment Toolkit (EDDT)
#
# Automated SQLite Database Backup Script
#
# Features:
#   1. Creates timestamped backup in disaster-recovery/backups/
#   2. Verifies SQLite integrity using 'PRAGMA integrity_check'
#   3. Generates SHA-256 checksum for tamper and corruption detection
#   4. Prunes backups older than RETENTION_DAYS
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."
BACKUP_DIR="${SCRIPT_DIR}/backups"
DB_SOURCE="${1:-${PROJECT_ROOT}/app/taskflow.db}"
RETENTION_DAYS=7

TIMESTAMP=$(date -u +%Y%m%d_%H%M%SZ)
BACKUP_FILE="${BACKUP_DIR}/taskflow_backup_${TIMESTAMP}.db"
CHECKSUM_FILE="${BACKUP_FILE}.sha256"

mkdir -p "${BACKUP_DIR}"

echo "=========================================================="
echo " [Disaster Recovery] Initiating Automated Database Backup"
echo " Timestamp : ${TIMESTAMP}"
echo " Source DB : ${DB_SOURCE}"
echo " Target Dir: ${BACKUP_DIR}"
echo "=========================================================="

# 1. Check if source DB exists
if [ ! -f "${DB_SOURCE}" ]; then
  echo "[-] ERROR: Source database does not exist at '${DB_SOURCE}'"
  echo "    Initialize the app or pass the correct DB path: ./backup.sh <path-to-db>"
  exit 1
fi

# 2. Perform safe hot backup using SQLite online backup API or VACUUM INTO
echo "[1/4] Creating atomic point-in-time database backup..."
python3 -c "
import sqlite3, sys
try:
    src = sqlite3.connect('${DB_SOURCE}')
    dst = sqlite3.connect('${BACKUP_FILE}')
    with dst:
        src.backup(dst, pages=100)
    dst.close()
    src.close()
    print('Backup copy completed.')
except Exception as e:
    print(f'Backup failed: {e}', file=sys.stderr)
    sys.exit(1)
"

# 3. Integrity Check
echo "[2/4] Verifying backup database integrity..."
INTEGRITY=$(python3 -c "
import sqlite3
con = sqlite3.connect('${BACKUP_FILE}')
cur = con.cursor()
res = cur.execute('PRAGMA integrity_check').fetchone()[0]
con.close()
print(res)
")

if [ "${INTEGRITY}" != "ok" ]; then
  echo "[-] CRITICAL INTEGRITY ERROR: Backup database failed integrity check: ${INTEGRITY}"
  rm -f "${BACKUP_FILE}"
  exit 1
fi
echo "[+] Integrity check passed: ${INTEGRITY}"

# 4. Generate SHA-256 Checksum
echo "[3/4] Generating SHA-256 checksum for audit trail..."
if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "${BACKUP_FILE}" > "${CHECKSUM_FILE}"
elif command -v shasum >/dev/null 2>&1; then
  shasum -a 256 "${BACKUP_FILE}" > "${CHECKSUM_FILE}"
else
  python3 -c "
import hashlib
h = hashlib.sha256(open('${BACKUP_FILE}','rb').read()).hexdigest()
open('${CHECKSUM_FILE}','w').write(f'{h}  ${BACKUP_FILE}\n')
"
fi
cat "${CHECKSUM_FILE}"

# 5. Prune backups older than retention policy
echo "[4/4] Applying retention policy (pruning backups older than ${RETENTION_DAYS} days)..."
find "${BACKUP_DIR}" -name "taskflow_backup_*.db*" -mtime +${RETENTION_DAYS} -delete 2>/dev/null || true

BACKUP_SIZE=$(ls -lh "${BACKUP_FILE}" | awk '{print $5}')
echo "=========================================================="
echo " [SUCCESS] Database Backup Created Successfully!"
echo " File: ${BACKUP_FILE} (${BACKUP_SIZE})"
echo "=========================================================="
