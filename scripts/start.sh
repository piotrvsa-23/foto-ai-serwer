#!/usr/bin/env bash
# Skrypt startowy poda (brief-techniczny, sekcja 2.5 i 8):
# 1. Tworzy strukture folderow na Container Disk.
# 2. Sciaga modele AI (jesli jeszcze nie sciagniete w tej sesji).
# 3. Uruchamia InvokeAI (w tle, osobny port).
# 4. Uruchamia SwarmUI (na pierwszym planie - SwarmUI sam uruchamia
#    powiazany ComfyUI jako backend, patrz Data/Backends.fds z etapu 3).
#
# Nic tu nie aktualizuje ComfyUI/SwarmUI/wtyczek - to zamrozone w obrazie
# (koncepcja-i-zasady-budowy.md, pkt 4.1-4.2). Ten skrypt tylko dokłada
# dane (modele, foldery), nigdy nie modyfikuje kodu silnikow.

set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

START_TS=$(date +%s)
log_elapsed() {
    local now elapsed
    now=$(date +%s)
    elapsed=$((now - START_TS))
    echo ">>> [$(date '+%H:%M:%S')] (+${elapsed}s od startu skryptu) $1"
}

log_elapsed "=== [1/4] Struktura folderow /workspace ==="
mkdir -p /workspace/input
mkdir -p /workspace/output
mkdir -p /workspace/cache
mkdir -p /workspace/comfyui/models/{diffusion_models,text_encoders,vae,model_patches,facerestore_models,face_restoration}
echo "OK"

log_elapsed "=== [2/4] Modele AI (patrz scripts/download_models.sh po szczegoly) ==="
bash "${SCRIPT_DIR}/download_models.sh"
log_elapsed "Modele gotowe."

log_elapsed "=== [3/4] Start InvokeAI (tlo, port 9090) ==="
export INVOKEAI_HOST=0.0.0.0
export INVOKEAI_PORT=9090
mkdir -p /workspace/invokeai/root
/workspace/invokeai/.venv/bin/invokeai-web --root /workspace/invokeai/root \
    > /workspace/cache/invokeai.log 2>&1 &
INVOKEAI_PID=$!
echo "InvokeAI PID ${INVOKEAI_PID}, log: /workspace/cache/invokeai.log"

log_elapsed "=== [4/4] Start SwarmUI (pierwszy plan, port 7801) ==="
echo "SwarmUI uruchomi rowniez ComfyUI jako wlasny backend (Data/Backends.fds)."
echo "Od tego momentu czas nie jest juz logowany przez ten skrypt - SwarmUI"
echo "przejmuje pierwszy plan i loguje wlasny postep startu ponizej."
cd /workspace/swarmui
exec ./launch-linux.sh --launch_mode none --host 0.0.0.0
