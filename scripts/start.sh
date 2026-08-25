#!/usr/bin/env bash
# Skrypt startowy poda - wariant "lean" (bez automatycznego pobierania
# duzych modeli AI - modele dociaga uzytkownik recznie w InvokeAI/SwarmUI
# wg wlasnych potrzeb, patrz docs/JAK-URUCHOMIC-NA-RUNPOD.md):
# 1. Tworzy strukture folderow na Container Disk.
# 2. Uruchamia InvokeAI (w tle, osobny port).
# 3. Uruchamia SwarmUI (na pierwszym planie - SwarmUI sam uruchamia
#    powiazany ComfyUI jako backend, patrz Data/Backends.fds z etapu 3).
#
# Nic tu nie aktualizuje ComfyUI/SwarmUI/wtyczek - to zamrozone w obrazie
# (koncepcja-i-zasady-budowy.md, pkt 4.1-4.2). Ten skrypt tylko tworzy
# foldery, nigdy nie modyfikuje kodu silnikow.

set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# NAPRAWA DNS (sierpien 2026): obraz bazowy Ubuntu 22.04 ma /etc/resolv.conf
# wskazujacy na systemd-resolved stub (127.0.0.53), ktory NIE dziala wewnatrz
# kontenera Docker (brak systemd/init) - kazde zapytanie DNS (np. do
# huggingface.co) konczy sie "Temporary failure in name resolution", na
# KAZDYM podzie RunPod, niezaleznie od fizycznego wezla (potwierdzone: ten
# sam blad wystapil na dwoch oddzielnych, swiezych podach). Nadpisujemy
# resolv.conf publicznymi serwerami DNS na czas dzialania kontenera - nie
# jest to trwala zmiana obrazu, wiec musi dziac sie tu, przy kazdym starcie.
echo "nameserver 8.8.8.8" > /etc/resolv.conf
echo "nameserver 1.1.1.1" >> /etc/resolv.conf

START_TS=$(date +%s)
log_elapsed() {
    local now elapsed
    now=$(date +%s)
    elapsed=$((now - START_TS))
    echo ">>> [$(date '+%H:%M:%S')] (+${elapsed}s od startu skryptu) $1"
}

log_elapsed "=== [1/3] Struktura folderow /workspace ==="
mkdir -p /workspace/input
mkdir -p /workspace/output
mkdir -p /workspace/cache
mkdir -p /workspace/comfyui/models/{diffusion_models,text_encoders,vae,model_patches,facerestore_models,face_restoration,loras}
echo "OK"

log_elapsed "=== [2/3] Start InvokeAI (tlo, port 9090) ==="
export INVOKEAI_HOST=0.0.0.0
export INVOKEAI_PORT=9090
mkdir -p /workspace/invokeai/root
/workspace/invokeai/.venv/bin/invokeai-web --root /workspace/invokeai/root \
    > /workspace/cache/invokeai.log 2>&1 &
INVOKEAI_PID=$!
echo "InvokeAI PID ${INVOKEAI_PID}, log: /workspace/cache/invokeai.log"

log_elapsed "=== [3/3] Start SwarmUI (pierwszy plan, port 7801) ==="
echo "SwarmUI uruchomi rowniez ComfyUI jako wlasny backend (Data/Backends.fds)."
echo "Od tego momentu czas nie jest juz logowany przez ten skrypt - SwarmUI"
echo "przejmuje pierwszy plan i loguje wlasny postep startu ponizej."
cd /workspace/swarmui
# --loglevel Debug (tymczasowo, sierpien 2026): diagnostyka bledu
# "unrecognized arguments" przy starcie ComfyUI - pokazuje w logu
# dokladna, prawdziwa komende uruchomieniowa zamiast zgadywania z
# kodu zrodlowego SwarmUI. Usunac po znalezieniu przyczyny.
exec ./launch-linux.sh --launch_mode none --host 0.0.0.0 --loglevel Debug
