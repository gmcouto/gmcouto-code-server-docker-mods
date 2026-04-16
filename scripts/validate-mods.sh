#!/usr/bin/env bash
# validate-mods.sh — Integration test for code-server-ai-tools mod
#
# Starts a real code-server container with all DOCKER_MODS and verifies
# that every mod installs correctly without APT lock conflicts.
#
# The linuxserver mod-init system only supports ghcr.io / lscr.io / Docker Hub.
# Local registries are NOT supported (the registry prefix is stripped).
# Always test against an image that has been pushed to GHCR.
#
# Usage:
#   ./scripts/validate-mods.sh [IMAGE_TAG]
#
# IMAGE_TAG defaults to "latest".  In CI, pass github.sha so the validate
# job tests the exact image that was just built and pushed.
#
# Examples:
#   ./scripts/validate-mods.sh                 # test :latest on GHCR
#   ./scripts/validate-mods.sh abc1234         # test :<sha> on GHCR
#   IMAGE_TAG=dev ./scripts/validate-mods.sh   # env-var form

set -euo pipefail

IMAGE_TAG="${IMAGE_TAG:-${1:-latest}}"
AI_TOOLS_IMAGE="ghcr.io/gmcouto/code-server-ai-tools:${IMAGE_TAG}"

CONTAINER_NAME="code-server-validate-$$"
PORT=$(( RANDOM % 10000 + 8000 ))
STARTUP_TIMEOUT=480   # 8 minutes — npm installs are slow on fresh runners
POLL_INTERVAL=10

PASS=0
FAIL=0
WARN=0
LOG_FILE="${LOG_FILE:-/tmp/container-startup.log}"

# ── colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
pass()  { echo -e "${GREEN}PASS${NC}: $1"; PASS=$(( PASS + 1 )); }
fail()  { echo -e "${RED}FAIL${NC}: $1"; FAIL=$(( FAIL + 1 )); }
warn()  { echo -e "${YELLOW}WARN${NC}: $1"; WARN=$(( WARN + 1 )); }
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
}
trap cleanup EXIT

# ── start container ───────────────────────────────────────────────────────────
DOCKER_MODS="linuxserver/mods:code-server-nodejs|\
linuxserver/mods:code-server-nvm|\
linuxserver/mods:universal-docker|\
linuxserver/mods:code-server-python3|\
${AI_TOOLS_IMAGE}"

banner "Starting code-server container"
echo "  Container  : ${CONTAINER_NAME}"
echo "  Port       : ${PORT}"
echo "  AI image   : ${AI_TOOLS_IMAGE}"

docker run -d \
    --name "${CONTAINER_NAME}" \
    -p "${PORT}:8443" \
    -e DOCKER_MODS="${DOCKER_MODS}" \
    -e PUID=1000 \
    -e PGID=1000 \
    -e PASSWORD="" \
    lscr.io/linuxserver/code-server:latest

# ── wait for [ls.io-init] done. ───────────────────────────────────────────────
banner "Waiting for container initialisation (timeout: ${STARTUP_TIMEOUT}s)"
ELAPSED=0
READY=false
while [ "${ELAPSED}" -lt "${STARTUP_TIMEOUT}" ]; do
    if docker logs "${CONTAINER_NAME}" 2>&1 | grep -q '\[ls\.io-init\] done\.'; then
        READY=true
        break
    fi
    # Bail early if our mod was skipped (can't test without it)
    if docker logs "${CONTAINER_NAME}" 2>&1 | grep -q 'OFFLINE:.*code-server-ai-tools.*skipping'; then
        echo -e "${RED}ERROR${NC}: mod-init skipped the ai-tools image — is '${AI_TOOLS_IMAGE}' pushed to GHCR?"
        exit 1
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
check_warn() {
    local desc="$1"; shift
    if docker exec "${CONTAINER_NAME}" bash -c "$*" >/dev/null 2>&1; then
        pass "${desc}"
    else
        warn "${desc} (non-critical)"
    fi
}

# ── checks ────────────────────────────────────────────────────────────────────
banner "Running checks"

# Capture log now for the apt-lock check
docker logs "${CONTAINER_NAME}" > "${LOG_FILE}" 2>&1 || true

# ── regression: no APT lock collision ────────────────────────────────────────
# Check this first — if there's a lock collision the other checks may lie.
if grep -q 'Could not get lock' "${LOG_FILE}"; then
    fail "APT lock collision detected in startup log (packages may not have installed)"
else
    pass "No APT lock collision in startup log"
fi

# ── our mod was loaded ────────────────────────────────────────────────────────
if grep -q 'code-server-ai-tools.*applied to container' "${LOG_FILE}"; then
    pass "ai-tools mod was applied by mod-init"
else
    fail "ai-tools mod was NOT applied by mod-init (check image tag / GHCR push)"
fi

# ── python3 mod (packages installed by init-mods-package-install) ─────────────
# NOTE: Do NOT just check 'command -v python3' — it's in the Ubuntu base image.
# Check dpkg to confirm the dev packages were actually installed by the mod.
check_fail "python3-dev installed (via mod)"  "dpkg -l python3-dev | grep -q '^ii'"
check_fail "python3-pip installed (via mod)"  "dpkg -l python3-pip | grep -q '^ii'"
check_fail "python3-pip works"                "python3 -m pip --version"

# ── nodejs mod ────────────────────────────────────────────────────────────────
# Check the apt-installed nodejs package, not just any node binary (NVM adds
# its own node to PATH via .bashrc which is not sourced in docker exec).
check_fail "nodejs installed via apt"         "dpkg -l nodejs | grep -q '^ii'"
check_fail "npm installed via apt or nodejs"  "dpkg -l nodejs | grep -q '^ii'"

# ── our mod: Phase 1 packages (installed by the batch installer) ───────────────
check_fail "screen installed (via mod Phase 1)"  "dpkg -l screen | grep -q '^ii'"
check_fail "tmux installed (via mod Phase 1)"    "dpkg -l tmux   | grep -q '^ii'"

# ── our mod: Phase 2 npm tools ───────────────────────────────────────────────
# npm globals are in the NVM node bin dir, only on PATH after sourcing nvm.sh.
# docker exec runs as root (HOME=/root), so we must use the explicit path and
# set NVM_DIR so nvm.sh can find the installed node versions.
NVM_INIT="NVM_DIR=/config/.nvm source /config/.nvm/nvm.sh"
check_fail "claude-code binary present"  "${NVM_INIT} && command -v claude"
check_fail "claude-code executes"        "${NVM_INIT} && claude --version"
check_warn "gemini-cli binary present"   "${NVM_INIT} && command -v gemini"
check_warn "cursor-agent binary present" "command -v cursor-agent"

# ── summary ───────────────────────────────────────────────────────────────────
banner "Results"
echo -e "  ${GREEN}Passed${NC} : ${PASS}"
echo -e "  ${YELLOW}Warned${NC} : ${WARN} (non-critical, not counted as failures)"
echo -e "  ${RED}Failed${NC} : ${FAIL}"

if [ "${FAIL}" -gt 0 ]; then
    echo -e "\n${RED}VALIDATION FAILED${NC} — ${FAIL} critical check(s) did not pass."
    exit 1
fi

echo -e "\n${GREEN}VALIDATION PASSED${NC}"
exit 0
