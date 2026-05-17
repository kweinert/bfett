.PHONY: help ingest transform all

help:
	@echo "bfett Makefile"
	@echo ""
	@echo "  make ingest     → Prüft auf neue Daten und lädt sie"
	@echo "  make transform  → Inkrementelles Lea-Update (DuckDB)"
	@echo "  make all        → ingest + transform"
	@echo ""

ingest:
	Rscript ingest/lsx_trades.R
	Rscript ingest/transactions.R
	Rscript ingest/universe.R
	@echo "✅ Ingestion abgeschlossen"

transform:
	touch transform/staging/*.sql.jinja transform/core/*.sql transform/mart/*.sql
	lea run --scripts transform --incremental calendar_week $$(date +%G-%V)
	@echo "✅ Transformationen abgeschlossen (Lea)"

all: ingest transform
	@echo "✅ Vollständiger Update durchgeführt (ingest + transform)"



