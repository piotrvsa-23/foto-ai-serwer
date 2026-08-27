#!/usr/bin/env bash
# Skrypt startowy poda - v6.14.0_v01_CyberRXL_v10, wariant TYLKO InvokeAI:
# 1. Tworzy strukture folderow na Container Disk.
# 2. Jesli ustawione - automatycznie konfiguruje tokeny HuggingFace/Civitai
#    (patrz sekcja "TOKENY" nizej).
# 3. Uruchamia InvokeAI (pierwszy plan, port 9090).
#
# Dodatkowe modele/LoRA (poza jednym zaszytym w obrazie, patrz Dockerfile)
# NIE sa pobierane automatycznie - dociaga je uzytkownik recznie przez
# wbudowany Model Manager InvokeAI, patrz docs/JAK-URUCHOMIC-NA-RUNPOD.md.
#
# Nic tu nie aktualizuje InvokeAI - to zamrozone w obrazie
# (koncepcja-i-zasady-budowy.md, pkt 4.1-4.2). Ten skrypt tylko tworzy
# foldery i wstrzykuje tokeny z env vars, nigdy nie modyfikuje kodu silnika.

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

log_elapsed "=== [1/3] Struktura folderow /workspace ==="
mkdir -p /workspace/input
mkdir -p /workspace/output
mkdir -p /workspace/cache
mkdir -p /workspace/invokeai/root
echo "OK"

# TOKENY (sierpien 2026, na wyrazna prosbe uzytkownika): HUGGINGFACE_TOKEN
# i CIVITAI_API_KEY sa ustawiane przez uzytkownika w RunPod (Environment
# Variables / Secrets), NIGDY w tym repo/obrazie - patrz uzasadnienie
# bezpieczenstwa w rozmowie/PR. Ten skrypt tylko CZYTA je ze srodowiska
# kontenera (ustawia je RunPod) i wstrzykuje do konfiguracji InvokeAI, zeby
# uzytkownik nie musial robic tego recznie w terminalu po kazdym starcie.
# Idempotentne i bezpieczne do uruchomienia bez zadnego tokenu (obie sekcje
# sa pomijane, jesli dana zmienna jest pusta/nieustawiona).
log_elapsed "=== [2/3] Tokeny HuggingFace / Civitai (jesli ustawione) ==="
if [ -n "${CIVITAI_API_KEY:-}" ]; then
    /workspace/invokeai/.venv/bin/python -c "
import os, yaml
p = '/workspace/invokeai/root/invokeai.yaml'
with open(p) as f:
    d = yaml.safe_load(f) or {}
d.setdefault('remote_api_tokens', [])
d['remote_api_tokens'] = [t for t in d['remote_api_tokens'] if 'civitai' not in t.get('url_regex', '')]
d['remote_api_tokens'].append({'url_regex': 'civitai\\\\.com', 'token': os.environ['CIVITAI_API_KEY']})
with open(p, 'w') as f:
    yaml.dump(d, f)
"
    echo "OK: token Civitai skonfigurowany."
else
    echo "(pomijam - CIVITAI_API_KEY nieustawiony)"
fi

if [ -n "${HUGGINGFACE_TOKEN:-}" ]; then
    /workspace/invokeai/.venv/bin/python -c "
import os
import huggingface_hub
huggingface_hub.login(token=os.environ['HUGGINGFACE_TOKEN'], add_to_git_credential=False)
"
    echo "OK: token HuggingFace skonfigurowany."
else
    echo "(pomijam - HUGGINGFACE_TOKEN nieustawiony)"
fi

log_elapsed "=== [3/3] Start InvokeAI (pierwszy plan, port 9090) ==="
export INVOKEAI_HOST=0.0.0.0
export INVOKEAI_PORT=9090
echo "Od tego momentu czas nie jest juz logowany przez ten skrypt - InvokeAI"
echo "przejmuje pierwszy plan i loguje wlasny postep startu ponizej."
exec /workspace/invokeai/.venv/bin/invokeai-web --root /workspace/invokeai/root
