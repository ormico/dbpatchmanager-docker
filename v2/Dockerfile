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
# After install, verify .so path matches shared/odbcinst.ini:
#   find / -name 'libmyodbc*' 2>/dev/null
RUN curl -fsSL https://dev.mysql.com/get/Downloads/Connector-ODBC/9.6/mysql-connector-odbc_9.6.0-1ubuntu24.04_amd64.deb -o mysql-odbc.deb \
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
