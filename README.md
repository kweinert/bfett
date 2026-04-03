# bfett -- Portfolio Projekt

## Überblick

`bfett.sh` ist ein CLI für das Docker-Projekt mit den Kommandos `build` (erzeugt Docker Image),  `run` (startet Docker Container) und `make` (ruft make im Docker-Image auf). 

Der make-Befehl kennt die Targets `ingest`(aktualisiert Daten) und `transform` (aktualisiert Datenbank).

