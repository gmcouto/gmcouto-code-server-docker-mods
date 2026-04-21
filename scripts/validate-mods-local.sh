#!/usr/bin/env bash
# validate-mods-local.sh — Local integration test (no GHCR push required)
#
# The linuxserver mod-init system only supports ghcr.io / lscr.io / Docker Hub
# and silently skips local images.  This script works around that by:
#   1. Building the mod image from local source
#   2. Baking its filesystem overlay into a combined test image (on top of the
#      linuxserver/code-server base) — mirroring what mod-init does at runtime
#   3. Running the combined image with only the *other* DOCKER_MODS (which are
#      still fetched from GHCR as normal)
#
# Usage:
#   ./scripts/validate-mods-local.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

MOD_IMAGE="code-server-ai-tools-mod:local-$$"
TEST_IMAGE="code-server-ai-tools-test:local-$$"
CONTAINER_NAME="code-server-validate-local-$$"
PORT=$(( RANDOM % 10000 + 8000 ))
STARTUP_TIMEOUT=480   # 8 minutes — npm installs are slow
POLL_INTERVAL=10

PASS=0
FAIL=0
LOG_FILE="${LOG_FILE:-/tmp/container-startup-local.log}"

# ── colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
pass()  { echo -e "${GREEN}PASS${NC}: $1"; PASS=$(( PASS + 1 )); }
fail()  { echo -e "${RED}FAIL${NC}: $1"; FAIL=$(( FAIL + 1 )); }
banner(){ echo; echo "=== $* ==="; }

# ── cleanup on exit ───────────────────────────────────────────────────────────
cleanup() {
    banner "Cleanup"
    if docker ps -a -q --filter "name=${CONTAINER_NAME}" | grep -q .; then
        docker logs "${CONTAINER_NAME}" > "${LOG_FILE}" 2>&1 || true
        echo "Container startup log saved to: ${LOG_FILE}"
        if [ "${FAIL}" -gt 0 ]; then
            echo "Failures detected — dumping last 80 lines of container log:"
            echo "---"
            tail -80 "${LOG_FILE}" || true
            echo "---"
        fi
        docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
    fi
    docker rmi "${TEST_IMAGE}" >/dev/null 2>&1 || true
    docker rmi "${MOD_IMAGE}"  >/dev/null 2>&1 || true
}
trap cleanup EXIT

# ── Step 1: build the mod image from local source ────────────────────────────
banner "Building mod image from local source"
docker build -t "${MOD_IMAGE}" "${REPO_ROOT}"

# ── Step 2: build a combined test image ──────────────────────────────────────
# Apply our mod's filesystem overlay onto the linuxserver base at build time.
# This is equivalent to what mod-init does at container startup for GHCR mods.
banner "Building combined test image (base + mod overlay)"
docker build -t "${TEST_IMAGE}" - <<DOCKERFILE
FROM lscr.io/linuxserver/code-server:latest AS base
FROM ${MOD_IMAGE} AS mod
FROM base
COPY --from=mod / /
DOCKERFILE

# ── Step 3: start the container ──────────────────────────────────────────────
# Our mod is pre-baked; load only the other DOCKER_MODS from GHCR as normal.
DOCKER_MODS="linuxserver/mods:code-server-nodejs|\
linuxserver/mods:code-server-nvm|\
linuxserver/mods:universal-docker|\
linuxserver/mods:code-server-python3"

banner "Starting code-server container"
echo "  Container  : ${CONTAINER_NAME}"
echo "  Port       : ${PORT}"
echo "  Test image : ${TEST_IMAGE}"

docker run -d \
    --name "${CONTAINER_NAME}" \
    -p "${PORT}:8443" \
    -e DOCKER_MODS="${DOCKER_MODS}" \
    -e PUID=1000 \
    -e PGID=1000 \
    -e PASSWORD="" \
    "${TEST_IMAGE}"

# ── Step 4: wait for [ls.io-init] done. ──────────────────────────────────────
banner "Waiting for container initialisation (timeout: ${STARTUP_TIMEOUT}s)"
ELAPSED=0
READY=false
while [ "${ELAPSED}" -lt "${STARTUP_TIMEOUT}" ]; do
    if docker logs "${CONTAINER_NAME}" 2>&1 | grep -q '\[ls\.io-init\] done\.'; then
        READY=true
        break
    fi
    sleep "${POLL_INTERVAL}"
    ELAPSED=$(( ELAPSED + POLL_INTERVAL ))
    echo "  ${ELAPSED}s elapsed…"
done

if [ "${READY}" = false ]; then
    echo -e "${RED}ERROR${NC}: Container did not reach [ls.io-init] done. within ${STARTUP_TIMEOUT}s"
    exit 1
fi
echo "Container ready after ${ELAPSED}s"

# ── helper: run a check ───────────────────────────────────────────────────────
check_fail() {
    local desc="$1"; shift
    if docker exec "${CONTAINER_NAME}" bash -c "$*" >/dev/null 2>&1; then
        pass "${desc}"
    else
        fail "${desc}"
    fi
}
# ── checks ────────────────────────────────────────────────────────────────────
banner "Running checks"

docker logs "${CONTAINER_NAME}" > "${LOG_FILE}" 2>&1 || true

# ── regression: no APT lock collision ────────────────────────────────────────
if grep -q 'Could not get lock' "${LOG_FILE}"; then
    fail "APT lock collision detected in startup log (packages may not have installed)"
else
    pass "No APT lock collision in startup log"
fi

# ── python3 mod (packages installed by init-mods-package-install) ─────────────
check_fail "python3-dev installed (via mod)"  "dpkg -l python3-dev | grep -q '^ii'"
check_fail "python3-pip installed (via mod)"  "dpkg -l python3-pip | grep -q '^ii'"
check_fail "python3-pip works"                "python3 -m pip --version"

# ── nodejs mod ────────────────────────────────────────────────────────────────
check_fail "nodejs installed via apt"         "dpkg -l nodejs | grep -q '^ii'"
check_fail "npm installed via apt or nodejs"  "dpkg -l nodejs | grep -q '^ii'"

# ── our mod: Phase 1 packages (installed by the batch installer) ───────────────
check_fail "screen installed (via mod Phase 1)"  "dpkg -l screen | grep -q '^ii'"
check_fail "tmux installed (via mod Phase 1)"    "dpkg -l tmux   | grep -q '^ii'"
check_fail "fd-find installed (via mod Phase 1)" "dpkg -l fd-find | grep -q '^ii'"
check_fail "ripgrep installed (via mod Phase 1)" "dpkg -l ripgrep | grep -q '^ii'"
check_fail "fzf installed (via mod Phase 1)"     "dpkg -l fzf     | grep -q '^ii'"

# ── our mod: Phase 2 npm tools ───────────────────────────────────────────────
# npm globals are in the NVM node bin dir, only on PATH after sourcing nvm.sh.
# docker exec runs as root (HOME=/root), so we must use the explicit path and
# set NVM_DIR so nvm.sh can find the installed node versions.
NVM_INIT="NVM_DIR=/config/.nvm source /config/.nvm/nvm.sh"
check_fail "claude-code binary present"  "${NVM_INIT} && command -v claude"
check_fail "claude-code executes"        "${NVM_INIT} && claude --version"
check_fail "gemini-cli binary present"   "${NVM_INIT} && command -v gemini"
check_fail "cursor-agent binary present" "command -v cursor-agent"

# ── summary ───────────────────────────────────────────────────────────────────
banner "Results"
echo -e "  ${GREEN}Passed${NC} : ${PASS}"
echo -e "  ${RED}Failed${NC} : ${FAIL}"

if [ "${FAIL}" -gt 0 ]; then
    echo -e "\n${RED}VALIDATION FAILED${NC} — ${FAIL} critical check(s) did not pass."
    exit 1
fi

echo -e "\n${GREEN}VALIDATION PASSED${NC}"
exit 0
