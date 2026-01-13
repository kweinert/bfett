# bfett-dbt: dbt backend für Portfolio-Projekt

## Überblick

Das Repo ist ein Teil des `bfett` Projekts. Es kümmert sich um die Datenpflege, insbesondere um 

- die systematische Aufbereitung von Handelsdaten (Lang+Schwarz)
- Verschneidung mit Portfolio-Daten.

Es handelt sich um ein Hobby-Projekt.

Dieses Github-Repository enthält die Modelle für das dbt-Projekt, jedoch nicht die Daten. 

## Abhängigkeiten

Das Projekt wird auf Linux (konkret Xubuntu LTS 24.04) entwickelt und derzeit nur dort getestet.

Das Projekt nutzt 
- [docker](https://www.docker.com/) zum Verwalten der Abhängigkeiten.
- [duckdb](https://duckdb.org/) als Datenbank-Backend
- [dbt core](https://www.getdbt.com/) als Datenmanagement-System
- [R](https://www.r-project.org/) als Skriptsprache für Nicht-Standard-Transformationen

In der [Dockerfile](https://github.com/kweinert/bfett-dbt/blob/main/Dockerfile) sind alle Abhängigkeiten (dbt, duckdb, Python, R) deklariert.

## Nutzung

Es wird davon ausgegangen, dass bfett-dbt als Docker-Image ausführbar ist. Mittels docker-run werden folgende Parameter unterstützt:

- update-lsx-trades: aktualisiert Handelsdaten von LSX. Siehe [lsx_trades](https://github.com/kweinert/lsx_trades)
- update-dbt: führt dbt seed, compile und run aus. Wird automatisch nach update-lsx-trades ausgeführt.
- shell: Startet eine interaktive Bash-Shell. Gut zum Debuggen

## Qualität / Einschränkungen

Einige ISIN, die auf Trade Republic handelbar sind, sind offenbar nicht in den Handelsdaten von LSX enthalten. Das sind z.B. ISIN von Knockout Zertifikaten.

Für Freitag, 4.4.2025, hat der späteste Trade einen Zeitstempel von 14 Uhr. 

## Roadmap / What's new

### Version 0.4

- [ ] Umgang mit Aktiensplits testen
- [ ] Daten für Candle-Sticks
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

