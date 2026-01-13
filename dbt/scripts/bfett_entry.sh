#!/bin/bash

# Das Skript versteht die Kommandos "shell", "update-lsx", "update-dbt", "help" 
# "shell" öffnet eine shell. "help" druckt einen Hilfetext aus.
# "update-lsx" führt zuerst das Skript lsx.sh und danach das Kommando update-dbt aus.
# "update-dbt" führt dbt seed/compile/run aus.

# Funktion für update-dbt Logik
update_dbt() {
  echo "Processing transactions..."
  R -e "bfett.processes::process_transactions('/app/seeds/transactions.csv')"
  echo "Running dbt seed, compile, and run..."
  dbt seed # Kleine Tabellen kopieren
  dbt compile
  dbt run # TODO: lieber dbt build? spätestens wenn tests hinzugefügt werden.
}

# Prüfe das Kommando
case "$1" in
  shell)
    /bin/bash # Startet eine Bash-Shell
    ;;
  help)
    echo "Verfügbare Kommandos:"
    echo "  shell              - Startet eine interaktive Bash-Shell"
    echo "  update-lsx-trades  - Aktualisiert Handelsdaten von LSX"
    echo "  update-lsx-univ    - Aktualisiert Stammdaten von LSX"
    echo "  update-dbt         - Führt dbt seed, compile und run aus"
    echo "  help               - Zeigt diesen Hilfetext an"
    ;;
  update-lsx-trades)
    echo "Updating lsx trade data..."
    /app/scripts/update_lsx_trades.sh
    update_dbt
    ;;
  update-lsx-univ)
    echo "Updating lsx universe data..."
    echo "not yet implemented" # TODO
    exit 1
    ;;
  update-dbt)
    update_dbt
    ;;
  *)
    echo "Unbekanntes Kommando in bfett_entry.sh: $1"
    echo "Verwende 'help' für eine Liste der verfügbaren Kommandos."
    exit 1
    ;;
esac
