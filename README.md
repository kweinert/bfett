# bfett -- Portfolio Projekt

## Überblick

`bfett.sh` ist ein CLI für das Docker-Projekt mit den Kommandos `build` (erzeugt Docker Image),  `run` (startet Docker Container) und `make` (ruft make im Docker-Image auf). 

Der make-Befehl kennt die Targets `ingest`(aktualisiert Daten) und `transform` (aktualisiert Datenbank).

## Next Steps

    [ ] .env File for single point of config
    [ ] make ingest/lsx_trades.sh work (and transform the csv.gz to parquet)
    [ ] duckdb gsheets extension for ingest/transactions
