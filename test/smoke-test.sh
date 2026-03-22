#!/usr/bin/env bash
# Smoke test for dbpatchmanager-ci-v2 image
# Run inside the container. Exits non-zero on any failure.
set -euo pipefail

PASS=0
FAIL=0

check() {
    local label="$1"
    shift
    if "$@" > /dev/null 2>&1; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== ODBC Drivers ==="
check "MySQL ODBC driver registered" odbcinst -q -d -n "MySQL"
check "PostgreSQL ODBC driver registered" odbcinst -q -d -n "PostgreSQL"
check "SQL Server ODBC driver registered" odbcinst -q -d -n "ODBC Driver 18 for SQL Server"

echo ""
echo "=== Runtimes ==="
check ".NET runtime installed" dotnet --info
check "PowerShell installed" pwsh -Command "Write-Output ok"

echo ""
echo "=== CLI Tools ==="
check "mysql CLI" mysql --version
check "psql CLI" psql --version
check "sqlcmd CLI" which sqlcmd
check "bcp CLI" which bcp
check "dbpatch binary" which dbpatch

echo ""
echo "=== MySQL Connectivity ==="
# Only run connectivity tests if MYSQL_HOST is set (i.e., a MySQL service container is available)
if [ -n "${MYSQL_HOST:-}" ]; then
    MYSQL_PORT="${MYSQL_PORT:-3306}"
    MYSQL_USER="${MYSQL_USER:-root}"
    MYSQL_PWD="${MYSQL_PWD:-root}"
    MYSQL_DB="${MYSQL_DB:-testdb}"

    check "MySQL TCP connection" mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PWD" -e "SELECT 1;"

    # Create table, insert, select
    if mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PWD" "$MYSQL_DB" <<-SQL
        CREATE TABLE IF NOT EXISTS smoke_test (id INT PRIMARY KEY, name VARCHAR(50));
        INSERT INTO smoke_test (id, name) VALUES (1, 'smoke') ON DUPLICATE KEY UPDATE name='smoke';
SQL
    then
        RESULT=$(mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PWD" "$MYSQL_DB" -N -e "SELECT name FROM smoke_test WHERE id=1;")
        if [ "$RESULT" = "smoke" ]; then
            echo "PASS: MySQL insert and select"
            PASS=$((PASS + 1))
        else
            echo "FAIL: MySQL insert and select (got: $RESULT)"
            FAIL=$((FAIL + 1))
        fi
    else
        echo "FAIL: MySQL insert and select (setup failed)"
        FAIL=$((FAIL + 1))
    fi

    # Cleanup (best-effort)
    mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PWD" "$MYSQL_DB" -e "DROP TABLE IF EXISTS smoke_test;" || true
else
    echo "SKIP: MySQL connectivity (MYSQL_HOST not set)"
fi

echo ""
echo "=== Results ==="
echo "Passed: $PASS, Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
