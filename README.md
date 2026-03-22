# dbpatchmanager-docker

Pre-built CI container images for [DBPatch](https://github.com/ormico/dbpatchmanager) database migration pipelines.

## What's Included

| Component | Version |
|---|---|
| Ubuntu | 24.04 |
| .NET Runtime | 8.0 |
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

```yaml
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
```

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
| `ghcr.io/ormico/dbpatchmanager-ci-v2` | Latest v2.x.x | 8.0 |
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
