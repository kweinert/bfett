# Dockerfile Refactor Plan

## Goal
Combine `bfett/Dockerfile` and `bfett/dashboard/Dockerfile` into a single Dockerfile:
- Remove dbt, install `carbonfact/lea` instead
- Entrypoint: faucet shiny server

---

## Base Image
- **Use:** `ixpantia/faucet:r4.4` (includes faucet server pre-installed)
- **Rationale:** Provides R 4.4 + faucet for running Shiny apps

---

## Changes Summary

### Remove
| Item | Original Lines | Reason |
|------|-------------|--------|
| Python + dbt setup | 31-48 | Replaced with lea |
| dbt project files | 56-62 | Replaced with lea SQL scripts |
| Custom entrypoint script | 85-90 | Use faucet directly |
| bfett.processes package | 66-68 | Not needed |
| bfett/dashboard/Dockerfile | - | Merged into main |

### Add Instead
| Item | Installation | Notes |
|------|-------------|-------|
| Python + pip | Combined in single apt-get | For lea CLI |
| lea-cli | `pip install lea-cli` | Minimalist SQL orchestrator |
| Shiny + bslib | `install.packages(c('shiny', 'bslib'))` | From dashboard |
| faucet user | Use existing faucet user | Security best practice |

---

## Combined Dockerfile Structure

```dockerfile
FROM ixpantia/faucet:r4.4

WORKDIR /home/faucet

# -------------------------------------------------
# System deps (R + Python) - ONE RUN statement
RUN apt-get update && apt-get install -y \
    build-essential \
    libssl-dev \
    libcurl4-openssl-dev \
    curl \
    jq \
    python3 \
    python3-pip \
    python3-venv \
    git \
    && rm -rf /var/lib/apt/lists/*

# -------------------------------------------------
# Configure P3M for binary packages
RUN mkdir -p /usr/local/lib/R/etc && \
    echo "options(repos = c(CRAN = 'https://p3m.dev/cran/__linux__/jammy/latest', duckdb = 'https://duckdb.r-universe.dev'))" >> /usr/local/lib/R/etc/Rprofile.site

# -------------------------------------------------
# Install R packages via pak
RUN R -e "pak::pkg_install(c('data.table', 'rmarkdown', 'tinytest', 'plotly', 'htmltools', 'htmlwidgets', 'flexdashboard', 'DBI', 'duckdb', 'reactable', 'echarts4r', 'shiny', 'bslib'))"

# -------------------------------------------------
# Install Python packages (lea + duckdb via pip)
RUN python3 -m venv /opt/lea-venv
RUN /opt/lea-venv/bin/pip install --upgrade pip
RUN /opt/lea-venv/bin/pip install lea-cli duckdb
ENV PATH="/opt/lea-venv/bin:${PATH}"

# -------------------------------------------------
# Copy files and set ownership
COPY dashboard/app.R /home/faucet/dashboard/app.R
COPY dashboard/rpkgs/ /home/faucet/rpkgs/
COPY ingest/ /home/faucet/ingest/
COPY transform/ /home/faucet/transform/

RUN chown -R faucet:faucet /home/faucet/

USER faucet

# -------------------------------------------------
# Entrypoint - faucet runs Shiny server
EXPOSE 3838
CMD ["faucet", "start", "--dir", "/home/faucet/dashboard"]
```

---

## File Locations in Container

| Source | Destination |
|--------|-------------|
| `dashboard/app.R` | `/home/faucet/dashboard/app.R` |
| `dashboard/rpkgs/*` | `/home/faucet/rpkgs/*` |
| `ingest/*` | `/home/faucet/ingest/*` |
| `transform/*` | `/home/faucet/transform/*` |

---

## Entrypoint Change

| Before | After |
|--------|-------|
| `/app/scripts/bfett_entry.sh` | `faucet start --dir /home/faucet/dashboard` |

Faucet will:
- Automatically detect and run the Shiny app (`app.R`)
- Listen on port 3838
- Use IP hash load balancing (default for Shiny)
- Enable request logging and replication

---

## Package Summary

| Package | Source |
|---------|--------|
| data.table | bfett |
| rmarkdown | bfett |
| tinytest | bfett |
| plotly | bfett |
| htmltools | bfett |
| htmlwidgets | bfett |
| flexdashboard | bfett |
| DBI | bfett |
| duckdb | bfett |
| reactable | bfett |
| echarts4r | bfett |
| shiny | dashboard |
| bslib | dashboard |
| lea-cli | Python (NEW) |

---

## Files to Delete

- `bfett/dashboard/Dockerfile` - merged into main Dockerfile

---

## Build & Run Commands

```bash
# Build
docker build -t bfett .

# Run
docker run -p 3838:3838 bfett
```

---

## Environment Variables (Optional)

```bash
# Adjust workers
FAUCET_WORKERS=4

# Change port (default 3838)
FAUCET_HOST=0.0.0.0:3838
```
