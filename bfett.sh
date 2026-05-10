#!/bin/bash

IMAGE="bfett"
CONTAINER_NAME="bfett"
PORT="3840"
HOST_DIR="$(dirname "$(realpath "$0")")"
FAUCET_DIR="/home/faucet"

VOLUMES="-v $HOST_DIR/config:$FAUCET_DIR/config"
VOLUMES="$VOLUMES -v $HOST_DIR/data:$FAUCET_DIR/data"
VOLUMES="$VOLUMES -v $HOST_DIR/logs:$FAUCET_DIR/logs"
ENV_MOUNT="--mount type=bind,source=$HOST_DIR/.env,target=$FAUCET_DIR/.env,readonly"

check_docker() {
    if ! docker info >/dev/null 2>&1; then
        echo "Error: Docker is not running"
        exit 1
    fi
}

cmd_build() {
    echo "Building image: $IMAGE in $HOST_DIR"
    docker build --progress=plain --build-arg CACHEBUST=$(date +%s) -t "$IMAGE" "$HOST_DIR" 
    echo "Stopping and removing running container, if it exists: $CONTAINER_NAME"
    docker stop $CONTAINER_NAME 2>/dev/null || true && \
    docker rm -f $CONTAINER_NAME 2>/dev/null || true  
}

cmd_run() {
    check_docker

    mkdir -p "$HOST_DIR/config"
    mkdir -p "$HOST_DIR/data"
    mkdir -p "$HOST_DIR/logs"

    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

    echo "Starting container: $CONTAINER_NAME"
    docker run -d \
        --name "$CONTAINER_NAME" \
        $VOLUMES \
	$ENV_MOUNT \
        -p $PORT:3838 \
        "$IMAGE"
}

cmd_make() {
    TARGET="${2:-help}"

    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "Container not running. Starting..."
        cmd_run
    fi

    # Warte max. 30 Sekunden
    timeout 30s bash -c "
    	until docker exec $CONTAINER_NAME true >/dev/null 2>&1; do
       	    sleep 1
    	done
    " || { echo "Timeout: Container not ready"; exit 1; }

    echo "Running make $TARGET in container"
    docker exec "$CONTAINER_NAME" make "$TARGET"
}

show_help() {
    echo "Usage: $(basename "$0") [build|run|make|help]"
    echo ""
    echo "Commands:"
    echo "  build              Build the Docker image"
    echo "  run                Start the container (detached)"
    echo "  make <target>      Run make target in container"
    echo "  help               Show this help"
    echo ""
    echo "Examples:"
    echo "  ./bfett.sh build"
    echo "  ./bfett.sh run"
    echo "  ./bfett.sh make ingest"
    echo "  ./bfett.sh make db"
    echo "  ./bfett.sh make all"
}

case "$1" in
    build)
        cmd_build
        ;;
    run)
        cmd_run
        ;;
    make)
        cmd_make "$@"
        ;;
    help|*)
        show_help
        ;;
esac
