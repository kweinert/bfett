#!/bin/bash

# Aktuelles Verzeichnis speichern
ORIGINAL_DIR=$(pwd)

# Arbeitsverzeichnis als übergeordnetes Verzeichnis des Skripts festlegen
# $0 ist der Pfad zum Skript; realpath löst Symlinks auf
SCRIPT_PATH=$(realpath "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")
#WORK_DIR=$(dirname "$SCRIPT_DIR")

DBT_IMAGE="bfett-dbt"
FRONT_IMAGE="bfett-front"
TAG="latest"
HOST_DIR="$SCRIPT_DIR"
CONTAINER_DIR="/app"

# Logger-Funktion definieren
log() {
	echo "$1"
    logger -t bfett "$1"
}

set_image() {
    case "$1" in
        "dbt")
            IMAGE="$DBT_IMAGE"
            ;;
        "front")
            IMAGE="$FRONT_IMAGE"
            ;;
        *)
            echo "Error: Invalid parameter. Only 'dbt' or 'front' are allowed."
            return 1
            ;;
    esac
}

# stops container if it is running
check_docker() {

    # Prüfen, ob Docker läuft
    if ! docker info >/dev/null 2>&1; then
        log "Error: Docker is not running or not accessible"
        cd "$ORIGINAL_DIR"
        exit 1
    fi

    # Prüfen, ob IMAGE gesetzt ist
    if [ -z "$IMAGE" ]; then
        log "Error: Environment variable IMAGE is not set"
        cd "$ORIGINAL_DIR"
        exit 1
    fi

    # Prüfen, ob ein Container vom Image $IMAGE läuft
    RUNNING_CONTAINER=$(docker ps -q -f "ancestor=$IMAGE")
    if [ -n "$RUNNING_CONTAINER" ]; then
        log "Stopping existing container: $RUNNING_CONTAINER"
        docker stop "$RUNNING_CONTAINER" >/dev/null 2>&1 || {
            log "Error: Failed to stop container $RUNNING_CONTAINER"
            cd "$ORIGINAL_DIR"
            exit 1
        }
        log "Container $RUNNING_CONTAINER stopped successfully"
    fi
}

build_image() {
	check_docker
	BUILD_DIR="$SCRIPT_DIR/$IMAGE"
	if [ ! -d "$BUILD_DIR" ]; then
		log "Error: Build directory $BUILD_DIR does not exist"
		cd "$ORIGINAL_DIR"
		exit 1
	fi
	cd "$BUILD_DIR" || {
		log "Error: Could not change into $BUILD_DIR"
		cd "$ORIGINAL_DIR"
		exit 1
	}
	docker build --progress=plain -t "$IMAGE:$TAG" .
	EXIT_CODE=$?
	if [ $EXIT_CODE -eq 0 ]; then
		log "Build completed successfully"
	else
		log "Build failed with exit code: $EXIT_CODE"
	fi
}

run_docker() {
	if [ "$IMAGE" = "$DBT_IMAGE" ]; then
	  
		# Standardwerte
		mkdir -p "$HOST_DIR/data"
		mkdir -p "$HOST_DIR/database"
		mkdir -p "$HOST_DIR/logs"
		mkdir -p "$HOST_DIR/seeds"
		
		# Container löschen, falls vorhanden
		log "Removing existing container: $IMAGE"
		docker rm -f $IMAGE 2>/dev/null || true

		# Docker-Befehl ausführen
		log "Starting container: $IMAGE"
		local cmd="$1"
		docker run -it \
			--name "$IMAGE" \
			-v "$HOST_DIR/data:$CONTAINER_DIR/data" \
			-v "$HOST_DIR/database:$CONTAINER_DIR/database" \
			-v "$HOST_DIR/logs:$CONTAINER_DIR/logs" \
			-v "$HOST_DIR/seeds:$CONTAINER_DIR/seeds" \
			--user "$(id -u):$(id -g)" \
			"$IMAGE" \
			"$cmd"
	elif [ "$IMAGE" = "$FRONT_IMAGE" ]; then
		# Standardwerte
		mkdir -p "$HOST_DIR/data"
		mkdir -p "$HOST_DIR/database"
		mkdir -p "$HOST_DIR/logs"
		mkdir -p "$HOST_DIR/seeds"
		
		# Container löschen, falls vorhanden
		log "Removing existing container: $IMAGE"
		docker rm -f $IMAGE 2>/dev/null || true

		# Docker-Befehl ausführen
		log "Starting container: $IMAGE"
		local cmd="$1"
		docker run -d \
			--name "$IMAGE" \
			-v "$HOST_DIR/data:$CONTAINER_DIR/data" \
			-v "$HOST_DIR/database:$CONTAINER_DIR/database" \
			-v "$HOST_DIR/logs:$CONTAINER_DIR/logs" \
			-v "$HOST_DIR/seeds:$CONTAINER_DIR/seeds" \
			-p 8001:8001 \
			--user "$(id -u):$(id -g)" \
			"$IMAGE"
	fi

}

# Hilfetext Funktion
show_help() {
    echo "Usage: $(basename "$0") [update|view|dbt-docs|build|help|shell]"
    echo "Commands:"
    echo "  help                 Show this help message"
    echo "  build                Build the Docker image in $WORK_DIR/bfett-dbt. This is required to use the commands below."
    echo "  shell                Run the Docker image and enter shell in it"
    echo "  update-lsx-trades    Update Trade data"
    echo "  dbt-docs             View database docs"
    echo "  view                 View dashboard"
    echo "Description:"
    echo "  This script manages the bfett application with Docker."
    echo "  Ensure Docker is installed and running before use."
}

view_url() {
    local url="$1"  # Der Parameter wird als url übergeben
    local restart="$2"
    set_image front
    
    # Prüfen, ob ein Container vom Image $IMAGE läuft oder ein Neustart erzwungen wird
    RUNNING_CONTAINER=$(docker ps -q -f "ancestor=$IMAGE")
    if [ -z "$RUNNING_CONTAINER" ] || [ "$restart" = "restart" ]; then
        run_docker
        
        # Mehrfach versuchen, die Seite zu erreichen (max. 30s insgesamt)
        local max_attempts=10
        local delay=3
        local attempt=1
        while [ $attempt -le $max_attempts ]; do
            if curl --silent --fail --max-time 5 "$url" >/dev/null; then
                log "Server gestartet"
                break
            fi
            log "Versuch $attempt/$max_attempts: Server noch nicht erreichbar, warte $delay Sekunden..."
            sleep $delay
            attempt=$((attempt + 1))
        done
        
        # Prüfen, ob der Server nach den Versuchen erreichbar ist
        if [ $attempt -gt $max_attempts ]; then
            log "Error: Timeout des Servers nach $((max_attempts * delay)) Sekunden."
            exit 1
        fi
    fi
    
    # Plattformabhängiger Öffnungsbefehl
    if command -v xdg-open > /dev/null; then
        xdg-open "$url"
    elif command -v open > /dev/null; then
        open "$url"
    else
        log "Error: No suitable command to open $url"
        cd "$ORIGINAL_DIR"
        exit 1
    fi
    log "Dashboard view requested"
}

# Parameter prüfen
if [ $# -lt 1 ]; then
    show_help
    exit 1
fi

case "$1" in
     help)
        show_help
        EXIT_CODE=0
        ;;

	 build)
        case "$2" in
            front)
                set_image "front"
                build_image
                ;;
            dbt)
                set_image "dbt"
                build_image
                ;;
            all|"")
                set_image "front"
                build_image
                set_image "dbt"
                build_image
                ;;
            *)
                echo "Error: Invalid build parameter. Use 'front', 'dbt', 'all', or leave empty."
                show_help
                exit 1
                ;;
        esac
        ;;
        
    update-lsx-trades|update-lsx-univ|update-dbt)
		set_image dbt
		check_docker
		run_docker "$1" "-it"
        EXIT_CODE=$?
        if [ $EXIT_CODE -eq 0 ]; then
            log "Update completed successfully"
        else
            log "Update failed with exit code: $EXIT_CODE"
        fi
        ;;
    
    shell)
        set_image dbt
		check_docker
		run_docker "$1" "-it"
        ;;
  
    view)
        # $2=="restart" supported
        view_url "http://localhost:8001" $2
        ;;

    *)
        log "Error: command '$1' unknown to bfett"
        show_help
        cd "$ORIGINAL_DIR"
        exit 1
        ;;
esac

# Zurück zum ursprünglichen Verzeichnis
cd "$ORIGINAL_DIR" || {
    log "Warning: Could not return to $ORIGINAL_DIR"
    exit 1
}

exit $EXIT_CODE
