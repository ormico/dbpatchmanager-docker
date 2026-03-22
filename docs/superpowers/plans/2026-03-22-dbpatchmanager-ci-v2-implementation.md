# DBPatchManager CI v2 Docker Image — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Docker image (`ghcr.io/ormico/dbpatchmanager-ci-v2`) containing Ubuntu 24.04, .NET 6.0, ODBC drivers for MySQL/PostgreSQL/SQL Server, CLI tools, PowerShell, and the latest dbpatch v2 binary — used as a CI runner for database migration pipelines.

**Architecture:** Single Dockerfile at `v2/Dockerfile` built from the repo root context. Shared ODBC config at `shared/odbcinst.ini`. Smoke tests validate the image. Three GitHub Actions workflows handle PR validation, releases, and monthly rebuilds.

**Tech Stack:** Docker, Ubuntu 24.04, .NET 6.0, unixODBC, GitHub Actions, GitVersion, GHCR

**Spec:** `docs/superpowers/specs/2026-03-21-dbpatchmanager-ci-v2-image-design.md`

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `shared/odbcinst.ini` | Create | ODBC driver registration for MySQL, PostgreSQL, SQL Server |
| `v2/Dockerfile` | Create | Docker image definition — base OS, runtimes, drivers, dbpatch |
| `test/smoke-test.sh` | Create | Image validation script — checks drivers, tools, connectivity |
| `test/docker-compose.yml` | Create | Local dev setup — CI image + MySQL for manual testing |
| `.github/workflows/ci-pr.yml` | Create | PR validation — build image + smoke test |
| `.github/workflows/ci-main.yml` | Create | Release — version, build, push to GHCR, GitHub Release |
| `.github/workflows/scheduled-rebuild.yml` | Create | Monthly rebuild — pick up OS patches + new dbpatch releases |
| `README.md` | Create | Usage docs with workflow examples |
| `CHANGELOG.md` | Create | Release notes |
| `.dockerignore` | Create | Exclude .git, docs, .local from build context |

---

## Task 1: Create `.dockerignore`

**Files:**
- Create: `.dockerignore`

- [ ] **Step 1: Create `.dockerignore`**

```
.git
.github
.local
.claude
docs
test
LICENSE
README.md
CHANGELOG.md
GitVersion.yml
*.md
```

This keeps the build context small. Only `v2/`, `v3/`, and `shared/` need to be in the context.

- [ ] **Step 2: Commit**

```bash
git add .dockerignore
git commit -m "Add .dockerignore to minimize build context"
```

---

## Task 2: Create `shared/odbcinst.ini`

**Files:**
- Create: `shared/odbcinst.ini`

The `.so` paths below are the standard locations on Ubuntu 24.04 for each package. These must be verified when the Dockerfile is first built (Task 3). If any path is wrong, update this file to match.

- [ ] **Step 1: Create `shared/odbcinst.ini`**

```ini
[MySQL]
Description = MySQL ODBC 9.x Driver
Driver      = /usr/lib/x86_64-linux-gnu/odbc/libmyodbc9w.so
Setup       = /usr/lib/x86_64-linux-gnu/odbc/libmyodbc9S.so
UsageCount  = 1

[PostgreSQL]
Description = PostgreSQL ODBC driver
Driver      = /usr/lib/x86_64-linux-gnu/odbc/psqlodbcw.so
Setup       = /usr/lib/x86_64-linux-gnu/odbc/libodbcpsqlS.so
UsageCount  = 1

[ODBC Driver 18 for SQL Server]
Description = Microsoft ODBC Driver 18 for SQL Server
Driver      = /opt/microsoft/msodbcsql18/lib64/libmsodbcsql-18.so
UsageCount  = 1
```

- [ ] **Step 2: Commit**

```bash
git add shared/odbcinst.ini
git commit -m "Add shared ODBC driver configuration for MySQL, PostgreSQL, SQL Server"
```

---

## Task 3: Create `v2/Dockerfile`

**Files:**
- Create: `v2/Dockerfile`

**Important context:**
- Build from repo root: `docker build -f v2/Dockerfile .`
- COPY paths are relative to build context (repo root), not Dockerfile location
- MySQL ODBC driver is NOT in Ubuntu's apt repos — must download `.deb` from dev.mysql.com
- The `install-dbpatch.sh` from v2.1.2 installs to `/usr/local/lib/dbpatch/` with symlink at `/usr/local/bin/dbpatch`
- `.NET 5.0` apps forward-roll to `.NET 6.0` runtime
- `ACCEPT_EULA=Y` must be set as env var before `apt-get install` for `msodbcsql18`

**Research needed during implementation:**
- Verify the exact MySQL Connector/ODBC `.deb` URL for Ubuntu 24.04 on https://dev.mysql.com/downloads/connector/odbc/
- After building, run `find / -name 'libmyodbc*' 2>/dev/null` inside the container to verify the `.so` path matches `odbcinst.ini`
- Verify `ACCEPT_EULA=Y` works non-interactively for SQL Server ODBC

- [ ] **Step 1: Create `v2/Dockerfile`**

```dockerfile
# dbpatchmanager-ci-v2 — CI runner image for DBPatch v2 pipelines
# Contains: .NET 6.0 runtime, ODBC drivers, CLI tools, dbpatch v2 binary
# Does NOT contain: database servers (use service containers)
#
# Build from repo root: docker build -f v2/Dockerfile .

FROM ubuntu:24.04

LABEL org.opencontainers.image.source="https://github.com/ormico/dbpatchmanager-docker"
LABEL org.opencontainers.image.description="CI runner image for DBPatch v2 database migration pipelines"

# Avoid interactive prompts during package install
ENV DEBIAN_FRONTEND=noninteractive

# --- Base packages ---
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
    gnupg \
    apt-transport-https \
    unzip \
    jq \
    unixodbc \
    unixodbc-dev \
    odbcinst \
    && rm -rf /var/lib/apt/lists/*

# --- Microsoft packages repo (shared by .NET, SQL Server tools, PowerShell) ---
RUN curl -fsSL https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb -o packages-microsoft-prod.deb \
    && dpkg -i packages-microsoft-prod.deb \
    && rm packages-microsoft-prod.deb

# --- .NET 6.0 runtime ---
# dbpatch v2 targets .NET 5.0 (EOL) — runs on .NET 6.0 via forward roll
RUN apt-get update && apt-get install -y --no-install-recommends \
    dotnet-runtime-6.0 \
    && rm -rf /var/lib/apt/lists/*

# --- PowerShell 7+ ---
RUN apt-get update && apt-get install -y --no-install-recommends \
    powershell \
    && rm -rf /var/lib/apt/lists/*

# --- MySQL ODBC driver ---
# Not available via Ubuntu's default apt repos. Download .deb from dev.mysql.com.
# TODO: Verify exact URL and version at implementation time.
# After install, verify .so path matches shared/odbcinst.ini:
#   find / -name 'libmyodbc*' 2>/dev/null
RUN curl -fsSL https://dev.mysql.com/get/Downloads/Connector-ODBC/9.2/mysql-connector-odbc_9.2.0-1ubuntu24.04_amd64.deb -o mysql-odbc.deb \
    && dpkg -i mysql-odbc.deb || apt-get install -f -y \
    && rm mysql-odbc.deb

# --- MySQL CLI tools ---
RUN apt-get update && apt-get install -y --no-install-recommends \
    mysql-client \
    && rm -rf /var/lib/apt/lists/*

# --- PostgreSQL ODBC driver + CLI tools ---
RUN apt-get update && apt-get install -y --no-install-recommends \
    odbc-postgresql \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# --- SQL Server ODBC driver + CLI tools (sqlcmd, bcp) ---
# https://learn.microsoft.com/en-us/sql/connect/odbc/linux-mac/installing-the-microsoft-odbc-driver-for-sql-server
ENV ACCEPT_EULA=Y
RUN apt-get update && apt-get install -y --no-install-recommends \
    msodbcsql18 \
    mssql-tools18 \
    && rm -rf /var/lib/apt/lists/*
ENV PATH="$PATH:/opt/mssql-tools18/bin"

# --- ODBC driver configuration ---
COPY shared/odbcinst.ini /etc/odbcinst.ini

# --- DBPatch v2 binary (latest v2.x.x release from GitHub) ---
# Filters releases by v2.* tag prefix so v3 releases are never pulled.
# Install layout matches install-dbpatch.sh from the dbpatchmanager repo.
RUN DOWNLOAD_URL=$(curl -fsSL https://api.github.com/repos/ormico/dbpatchmanager/releases \
        | jq -r '[.[] | select(.tag_name | startswith("v2."))][0].assets[] | select(.name == "dbpatch.zip") | .browser_download_url') \
    && echo "Downloading dbpatch v2 from: $DOWNLOAD_URL" \
    && mkdir -p /usr/local/lib/dbpatch \
    && curl -fsSL "$DOWNLOAD_URL" -o /usr/local/lib/dbpatch/dbpatch.zip \
    && unzip /usr/local/lib/dbpatch/dbpatch.zip -d /usr/local/lib/dbpatch \
    && chmod +x /usr/local/lib/dbpatch/dbpatch \
    && ln -s /usr/local/lib/dbpatch/dbpatch /usr/local/bin/dbpatch \
    && rm /usr/local/lib/dbpatch/dbpatch.zip \
    && echo "dbpatch installed: $(dbpatch --version || echo 'version check skipped')"

WORKDIR /workspace
```

- [ ] **Step 2: Build the image locally**

```bash
docker build -f v2/Dockerfile -t dbpatchmanager-ci-v2:local .
```

Expected: Successful build. If the MySQL ODBC `.deb` URL is wrong, research the correct URL at https://dev.mysql.com/downloads/connector/odbc/ and update the Dockerfile.

- [ ] **Step 3: Verify `.so` paths match `odbcinst.ini`**

```bash
docker run --rm dbpatchmanager-ci-v2:local bash -c "
  echo '=== MySQL ODBC ==='
  find / -name 'libmyodbc*' 2>/dev/null
  echo '=== PostgreSQL ODBC ==='
  find / -name 'psqlodbcw*' 2>/dev/null
  echo '=== SQL Server ODBC ==='
  find / -name 'libmsodbcsql*' 2>/dev/null
  echo '=== odbcinst -q -d ==='
  odbcinst -q -d
"
```

Expected: Paths match what's in `shared/odbcinst.ini`. If not, update `shared/odbcinst.ini` to match.

- [ ] **Step 4: Verify all tools are installed**

```bash
docker run --rm dbpatchmanager-ci-v2:local bash -c "
  echo '=== .NET ===' && dotnet --info
  echo '=== PowerShell ===' && pwsh --version
  echo '=== MySQL CLI ===' && mysql --version
  echo '=== PostgreSQL CLI ===' && psql --version
  echo '=== SQL Server CLI ===' && which sqlcmd && sqlcmd --version
  echo '=== bcp ===' && which bcp
  echo '=== dbpatch ===' && dbpatch --version
"
```

Expected: All tools report their versions. `.NET 6.0` runtime present. `dbpatch` shows `v2.x.x`.

- [ ] **Step 5: Commit**

```bash
git add v2/Dockerfile
git commit -m "Add v2 Dockerfile with Ubuntu 24.04, .NET 6.0, ODBC drivers, dbpatch v2"
```

---

## Task 4: Create smoke test script

**Files:**
- Create: `test/smoke-test.sh`

This script runs inside the CI image. It validates that all drivers, tools, and connectivity work. It's designed to be called from GitHub Actions workflows and from `docker-compose` for local testing.

- [ ] **Step 1: Create `test/smoke-test.sh`**

```bash
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
        ((PASS++))
    else
        echo "FAIL: $label"
        ((FAIL++))
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
check "dbpatch binary" dbpatch --version

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
    mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PWD" "$MYSQL_DB" <<-SQL
        CREATE TABLE IF NOT EXISTS smoke_test (id INT PRIMARY KEY, name VARCHAR(50));
        INSERT INTO smoke_test (id, name) VALUES (1, 'smoke') ON DUPLICATE KEY UPDATE name='smoke';
SQL
    RESULT=$(mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PWD" "$MYSQL_DB" -N -e "SELECT name FROM smoke_test WHERE id=1;")
    if [ "$RESULT" = "smoke" ]; then
        echo "PASS: MySQL insert and select"
        ((PASS++))
    else
        echo "FAIL: MySQL insert and select (got: $RESULT)"
        ((FAIL++))
    fi

    # Cleanup
    mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PWD" "$MYSQL_DB" -e "DROP TABLE IF EXISTS smoke_test;"
else
    echo "SKIP: MySQL connectivity (MYSQL_HOST not set)"
fi

echo ""
echo "=== Results ==="
echo "Passed: $PASS, Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x test/smoke-test.sh
```

- [ ] **Step 3: Test it locally against the built image (without MySQL)**

```bash
docker run --rm dbpatchmanager-ci-v2:local bash -c "/workspace/test/smoke-test.sh"
```

Wait — the script isn't inside the image. Mount it:

```bash
docker run --rm -v "$(pwd)/test:/workspace/test" dbpatchmanager-ci-v2:local /workspace/test/smoke-test.sh
```

Expected: All non-MySQL checks pass. MySQL connectivity shows `SKIP`.

- [ ] **Step 4: Commit**

```bash
git add test/smoke-test.sh
git commit -m "Add smoke test script for image validation"
```

---

## Task 5: Create `test/docker-compose.yml`

**Files:**
- Create: `test/docker-compose.yml`

Provides a local dev setup: builds the CI image and spins up a MySQL service container for manual testing.

- [ ] **Step 1: Create `test/docker-compose.yml`**

```yaml
# Local development / manual testing
# Usage: docker compose -f test/docker-compose.yml up --build
services:
  ci:
    build:
      context: ..
      dockerfile: v2/Dockerfile
    environment:
      MYSQL_HOST: mysql
      MYSQL_PORT: "3306"
      MYSQL_USER: dbpatch
      MYSQL_PWD: dbpatch123
      MYSQL_DB: testdb
    depends_on:
      mysql:
        condition: service_healthy
    volumes:
      - ../test:/workspace/test
    command: /workspace/test/smoke-test.sh

  mysql:
    image: mysql:8.0
    environment:
      MYSQL_ROOT_PASSWORD: root
      MYSQL_DATABASE: testdb
      MYSQL_USER: dbpatch
      MYSQL_PASSWORD: dbpatch123
    ports:
      - "3306:3306"
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 10s
      timeout: 5s
      retries: 5
```

- [ ] **Step 2: Test locally**

```bash
docker compose -f test/docker-compose.yml up --build
```

Expected: MySQL starts, health check passes, CI container runs smoke tests, all checks including MySQL connectivity pass.

- [ ] **Step 3: Commit**

```bash
git add test/docker-compose.yml
git commit -m "Add docker-compose for local dev testing with MySQL"
```

---

## Task 6: Create `ci-pr.yml` workflow

**Files:**
- Create: `.github/workflows/ci-pr.yml`

- [ ] **Step 1: Create `.github/workflows/ci-pr.yml`**

```yaml
name: PR Validation

on:
  pull_request:
    branches: [main]

jobs:
  build-and-test:
    runs-on: ubuntu-latest

    services:
      mysql:
        image: mysql:8.0
        env:
          MYSQL_ROOT_PASSWORD: root
          MYSQL_DATABASE: testdb
          MYSQL_USER: dbpatch
          MYSQL_PASSWORD: dbpatch123
        ports:
          - 3306:3306
        options: >-
          --health-cmd "mysqladmin ping -h localhost"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
      - uses: actions/checkout@v4

      - name: Build v2 image
        run: docker build -f v2/Dockerfile -t dbpatchmanager-ci-v2:pr-${{ github.sha }} .

      - name: Run smoke tests
        run: |
          docker run --rm \
            --network host \
            -e MYSQL_HOST=127.0.0.1 \
            -e MYSQL_PORT=3306 \
            -e MYSQL_USER=dbpatch \
            -e MYSQL_PWD=dbpatch123 \
            -e MYSQL_DB=testdb \
            -v "${{ github.workspace }}/test:/workspace/test" \
            dbpatchmanager-ci-v2:pr-${{ github.sha }} \
            /workspace/test/smoke-test.sh
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/ci-pr.yml
git commit -m "Add PR validation workflow — build v2 image and run smoke tests"
```

---

## Task 7: Create `ci-main.yml` workflow

**Files:**
- Create: `.github/workflows/ci-main.yml`

**Context:**
- Triggered on `v*` tag push or manual dispatch
- Uses GitVersion to calculate semver
- Pushes to `ghcr.io/ormico/dbpatchmanager-ci-v2` with `latest`, full semver, and major.minor tags
- Creates a GitHub Release

- [ ] **Step 1: Create `.github/workflows/ci-main.yml`**

```yaml
name: Release

on:
  push:
    tags: ['v*']
  workflow_dispatch:

permissions:
  contents: write
  packages: write

jobs:
  version:
    runs-on: ubuntu-latest
    outputs:
      semver: ${{ steps.gitversion.outputs.semVer }}
      major: ${{ steps.gitversion.outputs.major }}
      minor: ${{ steps.gitversion.outputs.minor }}
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Install GitVersion
        uses: gittools/actions/gitversion/setup@v3.2.0
        with:
          versionSpec: '6.x'

      - name: Calculate version
        id: gitversion
        uses: gittools/actions/gitversion/execute@v3.2.0

      - name: Verify tag is on main
        if: github.ref_type == 'tag'
        run: |
          git branch --contains "${{ github.sha }}" | grep -q 'main' \
            || (echo "ERROR: Tag is not on main branch" && exit 1)

  build-and-push:
    needs: version
    runs-on: ubuntu-latest

    services:
      mysql:
        image: mysql:8.0
        env:
          MYSQL_ROOT_PASSWORD: root
          MYSQL_DATABASE: testdb
          MYSQL_USER: dbpatch
          MYSQL_PASSWORD: dbpatch123
        ports:
          - 3306:3306
        options: >-
          --health-cmd "mysqladmin ping -h localhost"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
      - uses: actions/checkout@v4

      - name: Log in to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build image
        run: |
          docker build -f v2/Dockerfile \
            -t ghcr.io/ormico/dbpatchmanager-ci-v2:${{ needs.version.outputs.semver }} \
            -t ghcr.io/ormico/dbpatchmanager-ci-v2:${{ needs.version.outputs.major }}.${{ needs.version.outputs.minor }} \
            -t ghcr.io/ormico/dbpatchmanager-ci-v2:latest \
            .

      - name: Run smoke tests
        run: |
          docker run --rm \
            --network host \
            -e MYSQL_HOST=127.0.0.1 \
            -e MYSQL_PORT=3306 \
            -e MYSQL_USER=dbpatch \
            -e MYSQL_PWD=dbpatch123 \
            -e MYSQL_DB=testdb \
            -v "${{ github.workspace }}/test:/workspace/test" \
            ghcr.io/ormico/dbpatchmanager-ci-v2:${{ needs.version.outputs.semver }} \
            /workspace/test/smoke-test.sh

      - name: Push to GHCR
        run: |
          docker push ghcr.io/ormico/dbpatchmanager-ci-v2:${{ needs.version.outputs.semver }}
          docker push ghcr.io/ormico/dbpatchmanager-ci-v2:${{ needs.version.outputs.major }}.${{ needs.version.outputs.minor }}
          docker push ghcr.io/ormico/dbpatchmanager-ci-v2:latest

  release:
    needs: [version, build-and-push]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          tag_name: ${{ github.ref_name }}
          name: ${{ github.ref_name }}
          generate_release_notes: true
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/ci-main.yml
git commit -m "Add release workflow — version, build, smoke test, push to GHCR, GitHub Release"
```

---

## Task 8: Create `scheduled-rebuild.yml` workflow

**Files:**
- Create: `.github/workflows/scheduled-rebuild.yml`

- [ ] **Step 1: Create `.github/workflows/scheduled-rebuild.yml`**

```yaml
name: Scheduled Rebuild

on:
  schedule:
    - cron: '0 6 1 * *'  # 1st of month, 6 AM UTC
  workflow_dispatch:

permissions:
  packages: write

jobs:
  rebuild:
    runs-on: ubuntu-latest

    services:
      mysql:
        image: mysql:8.0
        env:
          MYSQL_ROOT_PASSWORD: root
          MYSQL_DATABASE: testdb
          MYSQL_USER: dbpatch
          MYSQL_PASSWORD: dbpatch123
        ports:
          - 3306:3306
        options: >-
          --health-cmd "mysqladmin ping -h localhost"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
      - uses: actions/checkout@v4

      - name: Log in to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build image
        run: docker build -f v2/Dockerfile -t ghcr.io/ormico/dbpatchmanager-ci-v2:latest .

      - name: Run smoke tests
        run: |
          docker run --rm \
            --network host \
            -e MYSQL_HOST=127.0.0.1 \
            -e MYSQL_PORT=3306 \
            -e MYSQL_USER=dbpatch \
            -e MYSQL_PWD=dbpatch123 \
            -e MYSQL_DB=testdb \
            -v "${{ github.workspace }}/test:/workspace/test" \
            ghcr.io/ormico/dbpatchmanager-ci-v2:latest \
            /workspace/test/smoke-test.sh

      - name: Push to GHCR
        run: docker push ghcr.io/ormico/dbpatchmanager-ci-v2:latest
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/scheduled-rebuild.yml
git commit -m "Add monthly scheduled rebuild workflow with smoke tests"
```

---

## Task 9: Create `README.md`

**Files:**
- Create: `README.md`

- [ ] **Step 1: Create `README.md`**

```markdown
# dbpatchmanager-docker

Pre-built CI container images for [DBPatch](https://github.com/ormico/dbpatchmanager) database migration pipelines.

## What's Included

| Component | Version |
|---|---|
| Ubuntu | 24.04 |
| .NET Runtime | 6.0 |
| PowerShell | 7+ |
| MySQL ODBC | Connector/ODBC 9.x |
| MySQL CLI | mysql, mysqldump |
| PostgreSQL ODBC | odbc-postgresql |
| PostgreSQL CLI | psql, pg_dump |
| SQL Server ODBC | ODBC Driver 18 |
| SQL Server CLI | sqlcmd, bcp |
| DBPatch | Latest v2.x.x |

## Quick Start

Use the image as a job container in GitHub Actions:

` `` yaml
jobs:
  validate:
    runs-on: ubuntu-latest
    container:
      image: ghcr.io/ormico/dbpatchmanager-ci-v2:latest
    services:
      mysql:
        image: mysql:8.0
        env:
          MYSQL_ROOT_PASSWORD: root
          MYSQL_DATABASE: testdb
          MYSQL_USER: dbpatch
          MYSQL_PASSWORD: dbpatch123
        ports:
          - 3306:3306
        options: >-
          --health-cmd "mysqladmin ping -h localhost"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    steps:
      - uses: actions/checkout@v4
      - name: Run migrations
        run: dbpatch build --connection-string "Driver=MySQL;Server=mysql;Database=testdb;Uid=dbpatch;Pwd=dbpatch123"
` ``

## Available Tags

| Tag | Description |
|---|---|
| `latest` | Most recent build (updated monthly) |
| `1.0.0` | Pinned to specific image version |
| `1.0` | Floats within patch releases |

Image version tags track changes to the image itself (driver updates, base OS), not the dbpatch version inside.

## Images

| Image | DBPatch | .NET |
|---|---|---|
| `ghcr.io/ormico/dbpatchmanager-ci-v2` | Latest v2.x.x | 6.0 |
| `ghcr.io/ormico/dbpatchmanager-ci-v3` | Latest v3.x.x | 10 (future) |

## Local Development

```bash
# Build the image
docker build -f v2/Dockerfile -t dbpatchmanager-ci-v2:local .

# Run with MySQL for testing
docker compose -f test/docker-compose.yml up --build
```

## License

MIT
```

Note: Fix the triple-backtick escaping in the YAML code block (the spaces above are to prevent markdown parsing issues in this plan — remove the space in `` ` `` when creating the actual file).

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "Add README with usage examples and image documentation"
```

---

## Task 10: Create `CHANGELOG.md`

**Files:**
- Create: `CHANGELOG.md`

- [ ] **Step 1: Create `CHANGELOG.md`**

```markdown
# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added
- v2 Docker image with Ubuntu 24.04, .NET 6.0, ODBC drivers (MySQL, PostgreSQL, SQL Server), CLI tools, PowerShell, dbpatch v2
- Smoke test suite for image validation
- GitHub Actions workflows for PR validation, releases, and monthly rebuilds
- Docker Compose setup for local development
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "Add CHANGELOG"
```

---

## Task 11: Local end-to-end validation

No new files. This task validates everything works together before merging.

- [ ] **Step 1: Build the image from repo root**

```bash
docker build -f v2/Dockerfile -t dbpatchmanager-ci-v2:local .
```

Expected: Successful build.

- [ ] **Step 2: Run smoke tests with MySQL via docker-compose**

```bash
docker compose -f test/docker-compose.yml up --build
```

Expected: All smoke test checks pass, including MySQL connectivity.

- [ ] **Step 3: Verify image size**

```bash
docker images dbpatchmanager-ci-v2:local --format "{{.Size}}"
```

Expected: Under 1.5GB (acceptance criteria from spec).

- [ ] **Step 4: Clean up**

```bash
docker compose -f test/docker-compose.yml down -v
```
