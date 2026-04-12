# bfett -- Portfolio Projekt

Das Repo kümmert sich um die Datenpflege, insbesondere um 

- die systematische Aufbereitung von Handelsdaten (Lang+Schwarz)
- Verschneidung mit Portfolio-Daten.

Es handelt sich um ein Hobby-Projekt.

## Überblick

`bfett.sh` ist ein CLI für das Docker-Projekt mit den Kommandos `build` (erzeugt Docker Image),  `run` (startet Docker Container) und `make` (ruft make im Docker-Image auf). 

Der make-Befehl kennt die Targets `ingest`(aktualisiert Daten) und `transform` (aktualisiert Datenbank).


## Qualität / Einschränkungen

Einige ISIN, die auf Trade Republic handelbar sind, sind offenbar nicht in den Handelsdaten von LSX enthalten. Das sind z.B. ISIN von Knockout Zertifikaten.

Für Freitag, 4.4.2025, hat der späteste Trade einen Zeitstempel von 14 Uhr. 

## Roadmap / What's new

### Version 0.4
- [x] .env File for single point of config
- [x] make ingest/lsx_trades.sh work (and transform the csv.gz to parquet)
- [ ] use gsheets for ingest/transactions
- [ ] Refactor as Mono-Repo
- [ ] IRR für jede Woche

### Version 0.3

- [x] Shiny statt Rmd ==> eigenes [Repo](https://github.com/kweinert/bfett-front)
- [x] mehr als ein Portfolio

### Version 0.2

- [x] Wochenchart, wo Cash und Portfolio dargestellt sind
- [x] aus transactions die Tabellen cash, open_positions und closed_trades generieren.
- [x] Stammdaten von L+S herunterladen

### Version 0.1

- [x] Qualität prüfen
- [x] [Lang+Schwarz](https://www.ls-x.de/de/download) als Datenquelle erschließen
- [x] Skript um Kommandos erweitern (update / view / etc)

### Später / Vielleicht

- [ ] update_lsx_univ.sh
- [ ] [edgarWebR](https://cran.r-project.org/web/packages/edgarWebR/vignettes/edgarWebR.html) als Datenquelle erschließen
- [ ] discount / premium zones bestimmen für einzelne Isin
- [ ] Umgang mit Aktiensplits testen
- [ ] Daten für Candle-Sticks
