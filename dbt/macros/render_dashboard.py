import subprocess

def main(dbt, *args, **kwargs):
    """Führt das Dashboard-Rendering aus."""
    command = 'Rscript -e "rmarkdown::render(\'/dashboard/index.Rmd\', output_file=\'/dashboard/index.html\')"'
    result = subprocess.run(command, shell=True, capture_output=True, text=True)
    if result.returncode != 0:
        raise Exception(f"Fehler beim Rendern: {result.stderr}")
    dbt.log(f"Dashboard erfolgreich gerendert: {result.stdout}")
    # Kein SQL-Rückgabewert nötig für Operationen
