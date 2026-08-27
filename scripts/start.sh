#!/usr/bin/env bash
# Skrypt startowy poda - v15, wariant TYLKO InvokeAI:
# 1. Tworzy strukture folderow na Container Disk.
# 2. Uruchamia InvokeAI (pierwszy plan, port 9090).
#
# Modele NIE sa pobierane automatycznie - dociaga je uzytkownik recznie
# przez wbudowany Model Manager InvokeAI, patrz docs/JAK-URUCHOMIC-NA-RUNPOD.md.
#
# Nic tu nie aktualizuje InvokeAI - to zamrozone w obrazie
# (koncepcja-i-zasady-budowy.md, pkt 4.1-4.2). Ten skrypt tylko tworzy
# foldery, nigdy nie modyfikuje kodu silnika.

set -euo pipefail

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

log_elapsed "=== [1/2] Struktura folderow /workspace ==="
mkdir -p /workspace/input
mkdir -p /workspace/output
mkdir -p /workspace/cache
mkdir -p /workspace/invokeai/root
echo "OK"

log_elapsed "=== [2/2] Start InvokeAI (pierwszy plan, port 9090) ==="
export INVOKEAI_HOST=0.0.0.0
export INVOKEAI_PORT=9090
echo "Od tego momentu czas nie jest juz logowany przez ten skrypt - InvokeAI"
echo "przejmuje pierwszy plan i loguje wlasny postep startu ponizej."
exec /workspace/invokeai/.venv/bin/invokeai-web --root /workspace/invokeai/root
