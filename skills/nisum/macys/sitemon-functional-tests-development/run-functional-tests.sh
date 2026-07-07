#!/bin/bash
set -e

# Helper script to run sitemonetization-xapi functional tests
# Usage:
#   ./run-functional-tests.sh                        # run all functional tests
#   ./run-functional-tests.sh Discovery_Search_AgeFilter_SM_DesktopIT   # run single test class

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}"
SERVICE_JAR="${PROJECT_DIR}/service/target/sitemonetization-xapi-service-1.0.0-SNAPSHOT.jar"
SERVICE_PORT=8080
SERVICE_PID=""
REDIS_PID=""

# Optional single test class passed as first argument
TEST_CLASS="${1:-}"

cleanup() {
    if [ -n "${SERVICE_PID}" ] && kill -0 "${SERVICE_PID}" 2>/dev/null; then
        echo "Stopping service (PID ${SERVICE_PID})..."
        kill "${SERVICE_PID}"
        wait "${SERVICE_PID}" 2>/dev/null || true
    fi
    if [ -n "${REDIS_PID}" ] && kill -0 "${REDIS_PID}" 2>/dev/null; then
        echo "Stopping Redis server (PID ${REDIS_PID})..."
        kill "${REDIS_PID}"
        wait "${REDIS_PID}" 2>/dev/null || true
    fi
}
trap cleanup EXIT

echo "=== Checking Redis ==="
if ! command -v redis-cli >/dev/null 2>&1; then
    echo "ERROR: redis-cli not found. Redis must be installed."
    exit 1
fi

if redis-cli ping >/dev/null 2>&1; then
    echo "Redis is already running"
    redis-cli FLUSHALL
    echo "Redis cache flushed"
else
    if ! command -v redis-server >/dev/null 2>&1; then
        echo "ERROR: Redis server is not running and redis-server is not installed."
        exit 1
    fi
    echo "Starting Redis server..."
    redis-server --daemonize no --port 6379 &
    REDIS_PID=$!
    for i in $(seq 1 30); do
        if redis-cli ping >/dev/null 2>&1; then
            echo "Redis is UP"
            break
        fi
        if ! kill -0 "${REDIS_PID}" 2>/dev/null; then
            echo "ERROR: Redis server process died before becoming healthy"
            exit 1
        fi
        echo "Waiting for Redis... ($i)"
        sleep 1
    done
    if ! redis-cli ping >/dev/null 2>&1; then
        echo "ERROR: Redis server did not become healthy"
        exit 1
    fi
fi

echo "=== Building service JAR and functional-test module ==="
cd "${PROJECT_DIR}"
mvn clean install -DskipTests -q

if [ ! -f "${SERVICE_JAR}" ]; then
    echo "ERROR: Service JAR not found at ${SERVICE_JAR}"
    exit 1
fi

echo "=== Starting service on port ${SERVICE_PORT} ==="
java -jar "${SERVICE_JAR}" --spring.profiles.active=ci --server.port=${SERVICE_PORT} &
SERVICE_PID=$!

echo "=== Waiting for service health ==="
for i in $(seq 1 60); do
    if curl -s "http://localhost:${SERVICE_PORT}/sitemonetization/actuator/health/liveness" | grep -q '"status":"UP"' || \
       curl -s "http://localhost:${SERVICE_PORT}/sitemonetization/actuator/health/liveness" | grep -q 'UP'; then
        echo "Service is UP"
        break
    fi
    if ! kill -0 "${SERVICE_PID}" 2>/dev/null; then
        echo "ERROR: Service process died before becoming healthy"
        exit 1
    fi
    echo "Waiting for service... ($i)"
    sleep 2
done

echo "=== Running functional tests ==="
if [ -n "${TEST_CLASS}" ]; then
    echo "Running single test class: ${TEST_CLASS}"
    mvn -pl functional-test verify -DskipFunctionalTests=false -Dit.test="${TEST_CLASS}" -DskipTests=true
else
    echo "Running all functional tests"
    mvn -pl functional-test verify -DskipFunctionalTests=false -DskipTests=true
fi

echo "=== Functional tests completed ==="
