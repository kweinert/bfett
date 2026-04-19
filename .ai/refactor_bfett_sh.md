# bfett.sh Refactor Plan

## Goal
Refactor `bfett/bfett.sh` to support:
- `build` command → builds the Docker image
- `run` command → starts the container with volume mounts
- `make` command → runs `docker exec bfett make <target>`

---

## Current State

| Item | Value |
|------|-------|
| Images | `bfett-dbt`, `bfett-front` (two images) |
| Script | 275 lines, multiple image types |
| Volumes | `./data`, `./database`, `./logs`, `./seeds` → `/app/...` |

---

## Proposed Changes

### Image Consolidation
- **Single image**: `bfett:latest`
- Remove `bfett-dbt` and `bfett-front` distinction

### Commands

| Command | Action |
|---------|--------|
| `build` | `docker build -t bfett .` |
| `run` | `docker run -d --name bfett -p $PORT:$PORT -v ... bfett` |
| `make <target>` | `docker exec bfett make <target>` |

### Volume Mounts

| Host | Container |
|------|----------|
| `data` | `/home/faucet/data` |
| `logs` | `/home/faucet/logs` |

---

## check_docker() Function

Used to verify Docker daemon is running before any Docker commands.

```bash
check_docker() {
    if ! docker info >/dev/null 2>&1; then
        echo "Error: Docker is not running"
        exit 1
    fi
}
```

### Behavior by Command

| Command | Docker Daemon | Container | Action |
|---------|--------------|-----------|--------|
| build | ✓ | N/A | Builds image |
| build | ✗ | N/A | Error + exit |
| run | ✓ | N/A | Starts container |
| run | ✗ | N/A | Error + exit |
| make | ✓ | No | Auto-starts container |
| make | ✗ | No | Error + exit |
| make | ✓ | Yes | Runs make inside |

---

## Configuration Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `IMAGE` | `bfett` | Docker image name |
| `CONTAINER_NAME` | `bfett` | Container name |
| `PORT` | `3838` | Host port (container serves at 3838) |
| `HOST_DIR` | Script directory | Volume mount base |
| `FAUCET_DIR` | `/home/faucet` | Container directory |

## New bfett.sh Structure

```bash
#!/bin/bash

IMAGE="bfett"
CONTAINER_NAME="bfett"
PORT="3838"
HOST_DIR="$(cd "$(dirname "$0")" && pwd)"
FAUCET_DIR="/home/faucet"

VOLUMES="-v $HOST_DIR/data:$FAUCET_DIR/data"
VOLUMES="$VOLUMES -v $HOST_DIR/logs:$FAUCET_DIR/logs"

check_docker() {
    if ! docker info >/dev/null 2>&1; then
        echo "Error: Docker is not running"
        exit 1
    fi
}

cmd_build() {
    check_docker
    echo "Building image: $IMAGE"
    docker build --progress=plain -t "$IMAGE" "$HOST_DIR"
}

cmd_run() {
    check_docker

    mkdir -p "$HOST_DIR/data"
    mkdir -p "$HOST_DIR/logs"

    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

    echo "Starting container: $CONTAINER_NAME"
    docker run -d \
        --name "$CONTAINER_NAME" \
        $VOLUMES \
        -p $PORT:3838 \
        "$IMAGE"
}

cmd_make() {
    TARGET="${2:-help}"

    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "Container not running. Starting..."
        cmd_run
    fi

    echo "Running make $TARGET in container"
    docker exec "$CONTAINER_NAME" make "$TARGET"
}

show_help() {
    echo "Usage: $(basename "$0") [build|run|make|help]"
    echo ""
    echo "Commands:"
    echo "  build              Build the Docker image"
    echo "  run                Start the container (detached)"
    echo "  make <target>     Run make target in container"
    echo "  help              Show this help"
    echo ""
    echo "Examples:"
    echo "  ./bfett.sh build"
    echo "  ./bfett.sh run"
    echo "  PORT=8000 ./bfett.sh run   # custom port"
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
```

---

## Makefile Integration

The Makefile must be copied into the image for the `make` command to work:

```dockerfile
COPY Makefile /home/faucet/Makefile
```

---

## Removed Commands

| Old Command | Reason |
|------------|--------|
| `update-lsx-trades` | Use `make` instead |
| `update-lsx-univ` | Use `make` instead |
| `shell` | Use `docker exec -it bfett bash` |
| `view` | Use browser directly |
| `dbt-docs` | Not implemented |

---

## Usage Examples

```bash
# Build the image
./bfett.sh build

# Start the container
./bfett.sh run

# Run transformations
./bfett.sh make db

# Run ingest
./bfett.sh make ingest

# Run all (ingest + transform)
./bfett.sh make all

# Shell access
docker exec -it bfett bash
```