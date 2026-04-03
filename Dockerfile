FROM rocker/r-ver:4.3.2

WORKDIR /app

# --------
# Schritt: R
# Installiere Systemabhängigkeiten für R und pak
RUN apt-get update && apt-get install -y \
	build-essential \
	libssl-dev \
	libcurl4-openssl-dev \
	curl \
	jq \
	&& rm -rf /var/lib/apt/lists/*

# Installiere pak von CRAN
RUN R -e "install.packages('pak', repos='https://cloud.r-project.org/')"

# Konfiguriere P3M als Repository für Binärpakete (Ubuntu 22.04 "jammy" als Beispiel)
RUN mkdir -p /usr/local/lib/R/etc && echo "options(repos = c(CRAN = 'https://p3m.dev/cran/__linux__/jammy/latest', duckdb = 'https://duckdb.r-universe.dev'))" >> /usr/local/lib/R/etc/Rprofile.site

# Installiere weitere Pakete als Binaries über pak
RUN R -e "pak::pkg_install(c('data.table', 'rmarkdown', 'tinytest', 'plotly', 'htmltools', 'htmlwidgets', 'flexdashboard', 'DBI', 'duckdb', 'reactable', 'echarts4r'))"

# es dauert 1h, duckdb aus den Quellen zu installieren. Wir wählen eine Abkürzung. Nachteil ist, dass es nicht automatisch die neueste Version installiert.
# r-universe führt zu einem glibc Problem.
#RUN R -e "install.packages('https://duckdb.r-universe.dev/bin/linux/noble/4.5/src/contrib/duckdb_1.2.1.9000.tar.gz', repos=NULL)"

# --------
# Schritt: dbt
RUN apt-get update && apt-get install -y \
	python3 \
	python3-pip \
	python3-venv \
	git \
	&& rm -rf /var/lib/apt/lists/*

# Erstelle eine virtuelle Umgebung für Python
RUN python3 -m venv /opt/dbt-venv

# Aktiviere die virtuelle Umgebung und aktualisiere pip
RUN /opt/dbt-venv/bin/pip install --upgrade pip

# Installiere dbt-core und dbt-postgres (Adapter für PostgreSQL)
RUN /opt/dbt-venv/bin/pip install dbt-core dbt-duckdb duckdb

# Setze PATH, damit dbt direkt ausführbar ist
ENV PATH="/opt/dbt-venv/bin:${PATH}"

# ---------
# Schritt: bfett dbt Projekt
# Installiere dbt packages
# damit dbt deps funktioniert, werden dbt.project.yml und packages.yml benötigt
# die anderen Dateien werden nur "sicherheitshalber" mitkopiert; sie werden
# bei späteren Läufen von dbt durch aktuelle Version ersetzt (bind mount)
COPY dbt_project.yml .
COPY packages.yml .
COPY profiles.yml .  
COPY models/ ./models/
COPY macros/ ./macros/
RUN mkdir -p ./target && \
    dbt deps    

# -----------
# Schritt: bfett.processes
ARG BFETT_P_VER=0.0.2
RUN R -e "pak::pkg_install('github::kweinert/bfett.processes')" && \
    R -e "stopifnot(packageVersion('bfett.processes')=='$BFETT_P_VER')"

# -----------
# Schritt: User

RUN groupadd -g 1000 bfettgroup && \
    useradd -u 1000 -g bfettgroup bfettuser && \
    mkdir -p /app && \
    chown -R bfettuser:bfettgroup . && \
    chmod -R 755 . && \
    mkdir -p /home/bfettuser && \
    chown -R bfettuser:bfettgroup /home/bfettuser && \
    chmod -R 755 /home/bfettuser && \
    mkdir -p /app/scripts
    
# -----------
# Schritt: Entrypoint    
COPY ./scripts/bfett_entry.sh /app/scripts 
COPY ./scripts/update_lsx_trades.sh /app/scripts
RUN chown -R bfettuser:bfettgroup /app/scripts && \
    chmod -R 755 /app/scripts && \
    chmod +x /app/scripts/bfett_entry.sh && \
    chmod +x /app/scripts/update_lsx_trades.sh
    
USER bfettuser

# additional command required: shell, update-lsx, update-dbt, serve, help
ENTRYPOINT ["/app/scripts/bfett_entry.sh"]



