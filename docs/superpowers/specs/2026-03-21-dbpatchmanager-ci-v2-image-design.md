# dbpatchmanager-docker: CI Container Image for DBPatch v2

**Created:** 2026-03-21
**Status:** Approved

---

## Purpose

Pre-built Docker image for running DBPatch v2 in CI/CD pipelines. Solves two problems:

1. **ODBC driver installation on Linux is fragile** — MySQL ODBC driver on Ubuntu requires adding MySQL's apt repo, installing unixodbc, and configuring odbcinst.ini. Doing this in every CI run is slow and breaks when MySQL changes their packaging.
2. **DBPatch binary distribution** — CI needs dbpatch installed at a known path. Baking it into the image avoids per-run download/install and the Windows-hardcoded `C:\dbpatch-v2\` path problem.

## Scope

This spec covers the v2 image only. A v3 image will be added when dbpatch v3 is released (issue #13 in `.local` notes). The v3 image is identical except for .NET 10 runtime and `v3.*` tag filtering.

---

## Architecture

One image per dbpatch major version. Each image contains all three database drivers (MySQL, PostgreSQL, SQL Server). Database servers are not included — they run as service containers.

```
+-------------------------------+     +------------------+
|  dbpatchmanager-ci-v2:latest  |---->|  mysql:8.0       |
|                               |     +------------------+
|  - Ubuntu 24.04               |---->|  postgres:16     |
|  - .NET 6.0 runtime           |     +------------------+
|  - dbpatch v2 (latest v2.x.x) |---->|  mssql/server    |
|  - ODBC drivers + CLI tools   |     +------------------+
|  - PowerShell 7+              |
+-------------------------------+
```

### Key Decisions

- **Separate images per major version, not combined.** Each image carries only the .NET runtime it needs. Consumer workflows explicitly choose which dbpatch version to test against. Clean lifecycle — stop building v2 when v2 is retired.
- **One image per major version, not per database platform.** ODBC drivers are small (~5-10MB each). All three fit in one image.
- **Ubuntu 24.04 base.** Familiar, well-supported, long-term support.

---

## Image Contents

| Layer | What | Package/Source |
|---|---|---|
| Base | Ubuntu 24.04 | `ubuntu:24.04` |
| .NET runtime | 6.0 | `dotnet-runtime-6.0` (v2 targets .NET 5, forward-rolls to 6.0) |
| PowerShell | 7+ | `powershell` |
| ODBC core | unixODBC | `unixodbc`, `unixodbc-dev`, `odbcinst` |
| MySQL ODBC | Connector/ODBC 9.x | `.deb` from dev.mysql.com |
| MySQL CLI | mysql, mysqldump | `mysql-client` |
| PostgreSQL ODBC | ODBC driver | `odbc-postgresql` |
| PostgreSQL CLI | psql, pg_dump | `postgresql-client` |
| SQL Server ODBC | ODBC Driver 18 | `msodbcsql18` |
| SQL Server CLI | sqlcmd, bcp | `mssql-tools18` |
| DBPatch | Latest v2.x.x | GitHub API filtered by `v2.*` tag prefix |
| Utilities | jq, curl, wget, unzip | For GitHub API + install |
| ODBC config | odbcinst.ini | `shared/odbcinst.ini` |

**Not included:** database servers, test data, scripts, source code.

### DBPatch Install Layout

```
/usr/local/lib/dbpatch/   <- extracted zip contents
/usr/local/bin/dbpatch    <- symlink
```

### DBPatch Version Filtering

GitHub API lists all releases. jq filters by `v2.*` tag prefix to avoid pulling v3 releases:

```bash
curl -fsSL https://api.github.com/repos/ormico/dbpatchmanager/releases \
  | jq -r '[.[] | select(.tag_name | startswith("v2."))][0].assets[] | select(.name == "dbpatch.zip") | .browser_download_url'
```

### ODBC Driver Configuration

`shared/odbcinst.ini` registers all three drivers:
- `[MySQL]` — `/usr/lib/x86_64-linux-gnu/odbc/libmyodbc9w.so`
- `[PostgreSQL]` — `/usr/lib/x86_64-linux-gnu/odbc/psqlodbcw.so`
- `[ODBC Driver 18 for SQL Server]` — `/opt/microsoft/msodbcsql18/lib64/libmsodbcsql-18.so`

---

## Repo Structure

```
dbpatchmanager-docker/
├── v2/
│   └── Dockerfile
├── v3/
│   └── Dockerfile                  # placeholder, built when v3 ships
├── shared/
│   └── odbcinst.ini
├── test/
│   ├── docker-compose.yml
│   └── smoke-test.sh
├── .github/
│   └── workflows/
│       ├── ci-pr.yml
│       ├── ci-main.yml
│       └── scheduled-rebuild.yml
├── GitVersion.yml
├── README.md
├── CHANGELOG.md
└── LICENSE
```

### Build Context Note

Docker `COPY` cannot reference parent directories. Both Dockerfiles reference `../shared/odbcinst.ini`, so builds must use the repo root as build context:

```bash
docker build -f v2/Dockerfile .
```

---

## Registry & Tagging

**Registry:** `ghcr.io/ormico/dbpatchmanager-ci-v2`

| Tag | Example | Purpose |
|---|---|---|
| `latest` | `dbpatchmanager-ci-v2:latest` | Always the most recent build |
| Full semver | `dbpatchmanager-ci-v2:1.0.0` | Pinned image version |
| Major.minor | `dbpatchmanager-ci-v2:1.0` | Float within patch releases |

Image version tags track changes to the **image itself** (driver updates, base OS changes) — not the dbpatch version inside. The dbpatch version is always "latest v2.x.x" at build time.

---

## Versioning

GitVersion with ContinuousDelivery mode. Already configured in `GitVersion.yml`.

- **main**: release branch, patch increment, no tag suffix
- **feature/\***: branch-name tag, inherited increment
- **hotfix/\***: beta tag, patch increment
- Tag prefix: `v`
- Commit message bumps: `+semver: major|minor|patch|none`

---

## CI/CD Workflows

### ci-pr.yml — PR Validation

- **Trigger:** PRs to `main`
- **Steps:** Build v2 image, run smoke tests with MySQL service container
- **Gate:** Build or smoke test failure blocks merge

### ci-main.yml — Release

- **Trigger:** Tag push (`v*`) or manual dispatch
- **Jobs:**
  1. GitVersion calculates semver, verifies tag is on `main`
  2. Build image, push to GHCR with version + latest tags
  3. Smoke test against the published image
  4. Create GitHub Release

### scheduled-rebuild.yml — Monthly Rebuild

- **Trigger:** Cron `0 6 1 * *` (1st of month, 6 AM UTC) + manual dispatch
- **Action:** Rebuild and push `latest` tag only
- **Purpose:** Pick up Ubuntu security patches and new dbpatch minor/patch releases

---

## Smoke Tests

`test/smoke-test.sh` runs inside the CI image and verifies:

1. ODBC drivers are registered (`odbcinst -q -d` lists MySQL, PostgreSQL, SQL Server)
2. .NET 6.0 runtime is present (`dotnet --info`)
3. PowerShell is available (`pwsh --version`)
4. CLI tools respond: `mysql --version`, `psql --version`, `sqlcmd`, `bcp`
5. dbpatch binary runs (`dbpatch --version` returns v2.x.x)
6. MySQL ODBC connectivity works (connect to MySQL service container, create table, insert, select)

`test/docker-compose.yml` provides local dev setup: CI image + MySQL for manual testing.

---

## Cross-Repo Prerequisites

These are tracked outside this repo but must be completed before the image is fully functional:

1. **dbpatchmanager: Linux build verification** — Confirm dbpatch v2.1.2 runs on Ubuntu 24.04 with .NET 6.0 runtime (forward roll from .NET 5).
2. **dbpatchmanager: `DBPATCH_HOME` env var** — Support configurable binary path so CI can find dbpatch at `/usr/local/bin` instead of `C:\dbpatch-v2\`.
3. **dbexamples: update connection configs** — Replace hardcoded `C:\dbpatch-v2\` with env var or relative path.
4. **GitHub Container Registry** — Enable GHCR for the `ormico` org/account.

---

## Consumer Usage

```yaml
# In dbexamples/.github/workflows/validate-pr.yml
jobs:
  validate-v2:
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
      - name: Build Employee-DB odbc-mysql
        run: |
          cd Employee-DB/dbpatchv2/odbc-mysql
          dbpatch build --connection-string "Driver=MySQL;Server=mysql;Database=testdb;Uid=dbpatch;Pwd=dbpatch123"
```

---

## Implementation Order

1. Repo setup (branch protection, GHCR) — issues #1, #2
2. v2 Dockerfile + odbcinst.ini — issues #3, #4
3. Smoke tests — issue #8
4. CI workflows (PR, release, scheduled) — issues #5, #6, #7
5. README — issue #9
6. Cross-repo prerequisites — issues #10, #11, #12
7. v3 Dockerfile (when v3 ships) — issue #13
