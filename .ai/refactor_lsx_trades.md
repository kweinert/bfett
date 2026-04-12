# Refactoring-Plan: ingest/lsx_trades.sh

## 1. Ziel

Das bestehende R-Script `ingest/lsx_trades.sh` refaktorieren und um CSV.GZ → Parquet Konvertierung erweitern.

## 2. Ist-Zustand

**`ingest/lsx_trades.sh`** – 67-zeiliges R-Script:

1. Legt Verzeichnis `/app/data/lsx_trades` an
2. Fragt GitHub API `https://api.github.com/repos/kweinert/lsx_trades/releases` ab
3. Filtert `.csv.gz`-Assets aus den Releases
4. Lädt fehlende Dateien herunter (existierende werden übersprungen)

**Probleme:** Keine Konfigurierbarkeit, kein strukturiertes Logging, keine Checksummen-Validierung.

## 3. Neue Architektur

### Vorher (monolithisch)

```
lsx_trades.sh (67 Zeilen, alles auf Root-Level)
```

### Nachher (modular)

```
ingest/
  └── lsx_trades.R          # Einstiegspunkt, Orchestrierung

.env                          # Konfiguration (Pfade, URLs)

data/
  ├── raw/lsx_trades/        # Parquet-Output
  └── tmp/lsx_trades/        # Temporärer Speicher für CSV.GZ
```

### Datenfluss

```
GitHub API → Download CSV.GZ → /tmp/lsx_trades/
                                 ↓
                         fread() einlesen
                                 ↓
                         nanoparquet schreiben
                                 ↓
                         data/raw/lsx_trades/*.parquet
                                 ↓
                         CSV.GZ löschen
```

## 4. Abhängigkeiten

| Komponente | Abhängig von |
|------------|--------------|
| Config laden | `.env` Datei |
| GitHub API | Config (URL) |
| Download | Config (Pfade), GitHub API |
| Konvertierung | Download |
| Orchestrierung | Alle oben |

## 5. Schritt-für-Schritt Implementierung

### Schritt 1: `.env` Datei erstellen

**Datei:** `.env`

**Inhalt:**
```
LSX_GITHUB_URL=https://api.github.com/repos/kweinert/lsx_trades/releases
LSX_RAW_DIR=data/raw/lsx_trades
LSX_TMP_DIR=/tmp/lsx_trades
```

**Fehlerfall:** Datei nicht vorhanden → Script mit `stop()` beenden.

---

### Schritt 2: Verzeichnisse erstellen

**Funktion:** `ensure_directories()`

**Input:** Config-Variablen `LSX_RAW_DIR`, `LSX_TMP_DIR`

**Output:** Erstellt Verzeichnisse mit `dir.create(recursive = TRUE)`

**Fehlerfall:** Konnte Verzeichnis nicht erstellen → `stop()`

---

### Schritt 3: GitHub API Funktion

**Datei:** `ingest/lsx_trades.R`

**Funktion:** `fetch_releases()`

**Input:** `LSX_GITHUB_URL`

**Output:** Dataframe mit Spalten `name`, `browser_download_url`

**Fehlerfall:** HTTP-Status ≠ 200 → `stop()` mit Statuscode

---

### Schritt 4: Download Funktion

**Funktion:** `download_csv_gz()`

**Input:** `url`, `dest_path`

**Output:** Datei gespeichert unter `dest_path`

**Fehlerfall:** Alle 3 Retry-Versuche fehlgeschlagen → `warning()`, weitermachen mit nächster Datei

---

### Schritt 5: Konvertierungs Funktion

**Funktion:** `convert_to_parquet()`

**Input:** `csv_gz_path`, `parquet_path`

**Output:** Parquet-Datei unter `parquet_path`

**Validierung:** Datumsprüfung
- `filename_date_str`: Datum aus Dateinamen extrahieren (Format `YYYY-mm-dd`)
- `data_date_str`: `strftime(max(tradeTime), format = "%Y-%m-%d")`
- Wenn `data_date_str < filename_date_str` → `stop()`, Datei ablehnen

**Fehlerfall:** Konvertierung fehlgeschlagen oder Datumsvalidierung fehlgeschlagen → `warning()`, CSV.GZ löschen, weitermachen

---

### Schritt 6: Orchestrierung

**Datei:** `ingest/lsx_trades.R`

**Haupt-logik:**
1. `readRenviron(".env")` aufrufen
2. `ensure_directories()` aufrufen
3. Releases via `fetch_releases()` holen
4. Cutoff-Datum ermitteln: neueste Datei in `LSX_RAW_DIR` via Dateinamen (substring)
5. Nur Dateien mit Datum > Cutoff verarbeiten
6. Für jede Datei:
   - `file_name <- basename(browser_download_url)` verwenden (nicht `name`-Spalte)
   - Prüfen ob `.parquet` bereits existiert → skip
   - Prüfen ob `.csv.gz` in `LSX_TMP_DIR` existiert → skip
   - Sonst: `download_csv_gz()` → `convert_to_parquet()` → CSV.GZ löschen
5. Aufräumen: Temp-Verzeichnis leeren

---

## 6. Risiken & Mitigations

| Risiko | Auswirkung | Mitigation |
|--------|------------|------------|
| `nanoparquet` nicht installiert | Abbruch | Als Abhängigkeit in Dokumentation vermerken |
| `data.table` nicht installiert | Abbruch | Als Abhängigkeit in Dokumentation vermerken |
| CSV-Format ändert sich | Konvertierungsfehler | Fehler abfangen, warnen, Datei verwerfen |
| Bestehende Parquet überschreiben | Datenverlust | Prüfung vor Konvertierung, nur neue Dateien |
| Temp-Verzeichnis voll | Download fehlgeschlagen | Retry-Logik, ggf. ältere Temp-Dateien löschen |
| Daten enthalten ältere Trades als Dateiname suggeriert | Datenkonsistenz verletzt | Datumsvalidierung: max(tradeTime) vs Dateiname, Datei ablehnen wenn älter |

## 7. Checkliste

- [ ] `.env` Datei mit Config-Variablen erstellen
- [ ] `ensure_directories()` Funktion erstellen
- [ ] `fetch_releases()` Funktion erstellen
- [ ] `download_csv_gz()` Funktion mit 3x Retry erstellen
- [ ] `convert_to_parquet()` Funktion erstellen
- [ ] Orchestrierungs-Logik in `ingest/lsx_trades.R` zusammenführen
- [ ] `ingest/lsx_trades.sh` archivieren oder löschen
