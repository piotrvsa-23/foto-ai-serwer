#!/usr/bin/env bash
# Skrypt startowy poda - flux.1_v01, wariant TYLKO InvokeAI (galaz rownolegla
# do glownej galezi, oparta o wzorzec v6.14.0_v04_CyberRXL_v10, ale z
# checkpointem FLUX.1-dev zamiast SDXL - patrz naglowek Dockerfile):
# 1. Tworzy strukture folderow na Container Disk.
# 2. Jesli ustawione - automatycznie konfiguruje tokeny HuggingFace/Civitai
#    (patrz sekcja "TOKENY" nizej) - dla tego wariantu opcjonalne, zadne
#    ze zrodel ponizej nie sa gated, ale zostaje dla spojnosci z v04 i na
#    wypadek gdyby uzytkownik pozniej dodal tu gated model recznie.
# 3. Automatycznie pobiera dodatkowe modele FLUX (poza checkpointem
#    zaszytym w obrazie) - patrz sekcja "DODATKOWE MODELE" nizej.
# 4. Uruchamia InvokeAI (pierwszy plan, port 9090).
#
# UWAGA: dodatkowe modele CELOWO nie sa zaszywane w obrazie Docker - ten sam
# powod co w v04 (proby zaszycia duzych plikow w GitHub Actions okazaly sie
# zawodne/kruche - limity dysku runnera, zawieszajace sie buildy). RunPod ma
# duzo wiecej miejsca i stabilniejsze lacze, wiec te same pobierania po
# prostu dzieja sie tu, przy starcie poda.
#
# Nic tu nie aktualizuje InvokeAI - to zamrozone w obrazie
# (koncepcja-i-zasady-budowy.md, pkt 4.1-4.2). Ten skrypt tylko tworzy
# foldery, wstrzykuje tokeny z env vars i pobiera pliki modeli - nigdy nie
# modyfikuje kodu silnika.

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

log_elapsed "=== [1/4] Struktura folderow /workspace ==="
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
#
# KRYTYCZNE (naprawa po realnym incydencie na RunPod, sierpien 2026): oba
# bloki ponizej sa CELOWO opakowane w "if ... ; then ... ; else ... ; fi",
# NIE wolno tego uproscic z powrotem do samego wywolania pythona. Powod:
# skrypt ma ustawione "set -e" (przerwij caly skrypt przy pierwszym bledzie)
# - bez tego opakowania, zly/odrzucony przez serwer token (literowka,
# spacja, zly typ tokenu, wygasly klucz) zabijalby CALY skrypt startowy
# W TYM MIEJSCU, zanim InvokeAI w ogole zdazylby wystartowac. Realnie
# zaobserwowane na podzie uzytkownika: RunPod probowal restartowac kontener
# co ~15-20s w nieskonczonosc, za kazdym razem umierajac dokladnie tu -
# InvokeAI ANI RAZU nie zdazyl wystartowac. Zly token ma dawac ostrzezenie
# i kontynuacje BEZ danego tokenu, nigdy nie ma prawa zablokowac calego poda.
log_elapsed "=== [2/4] Tokeny HuggingFace / Civitai (jesli ustawione) ==="
if [ -n "${CIVITAI_API_KEY:-}" ]; then
    if /workspace/invokeai/.venv/bin/python -c "
import os, yaml
p = '/workspace/invokeai/root/invokeai.yaml'
with open(p) as f:
    d = yaml.safe_load(f) or {}
d.setdefault('remote_api_tokens', [])
d['remote_api_tokens'] = [t for t in d['remote_api_tokens'] if 'civitai' not in t.get('url_regex', '')]
d['remote_api_tokens'].append({'url_regex': 'civitai\\\\.com', 'token': os.environ['CIVITAI_API_KEY']})
with open(p, 'w') as f:
    yaml.dump(d, f)
"; then
        echo "OK: token Civitai skonfigurowany."
    else
        echo "UWAGA: nie udalo sie zapisac tokenu Civitai (blad zapisu configu) - kontynuuje BEZ niego." >&2
    fi
else
    echo "(pomijam - CIVITAI_API_KEY nieustawiony)"
fi

if [ -n "${HUGGINGFACE_TOKEN:-}" ]; then
    if /workspace/invokeai/.venv/bin/python -c "
import os
import huggingface_hub
huggingface_hub.login(token=os.environ['HUGGINGFACE_TOKEN'], add_to_git_credential=False)
"; then
        echo "OK: token HuggingFace skonfigurowany."
    else
        echo "UWAGA: token HuggingFace odrzucony przez serwer (bledny/wygasly/zle skopiowany?) - kontynuuje BEZ logowania HF. Sprawdz wartosc Secreta w RunPod." >&2
    fi
else
    echo "(pomijam - HUGGINGFACE_TOKEN nieustawiony)"
fi

# DODATKOWE MODELE FLUX (sierpien 2026) - odpowiednik zestawu z v04, ale
# dobrany pod architekture FLUX (kompletnie inna od SDXL - zaden z plikow
# SDXL z v04 nie jest tu zamiennikiem):
#   - VAE (ae.safetensors) + T5-XXL (int8) + CLIP-L - to NIE sa "dodatki"
#     jak ControlNet/IP-Adapter w v04, tylko TWARDE ZALEZNOSCI: FLUX bez
#     nich w ogole nie wygeneruje obrazu. Wersja T5 int8-quantized
#     (bnb_llm_int8, nie pelne bfloat16 ~9.5GB) dobrana pod pare z
#     checkpointem NF4 - dokladnie ten sam dobor, ktory InvokeAI stosuje
#     wewnetrznie dla swojego wlasnego "FLUX.1 dev (quantized)" (sprawdzone
#     w zrodle, starter_models.py, flux_dev_quantized.dependencies).
#   - VAE z ffxvs/vae-flux, NIE z oficjalnego black-forest-labs/FLUX.1-schnell -
#     UWAGA (naprawa realnego bledu z tego projektu, sierpien 2026): oficjalne
#     repo BFL mimo deklarowanej licencji Apache 2.0 zwraca 401 Unauthorized
#     bez zalogowania (potwierdzone recznie przez uzytkownika w przegladarce,
#     patrz historia commitow - "Napraw 401 dla VAE Flux"). ffxvs/vae-flux to
#     wtedy sprawdzony, dzialajacy bez logowania community-mirror identycznego
#     pliku ae.safetensors.
#   - CLIP ViT-L Image Encoder (InvokeAI/clip-vit-large-patch14, INNY plik niz
#     CLIP-L text encoder wyzej) - zaleznosc IP-Adaptera FLUX ponizej.
#   - IP-Adapter FLUX (XLabs) - generowanie/inpaint z obrazem referencyjnym,
#     odpowiednik IP-Adapterow SDXL z v04.
#   - ControlNet Union FLUX (InstantX) - JEDEN model obslugujacy 7 trybow
#     (canny, tile, depth, blur, pose, gray, low quality) - pokrywa ta sama
#     funkcjonalnosc co 4 osobne ControlNety SDXL w v04 (canny/depth/
#     openpose/tile), tylko w jednym pliku (typowe dla ekosystemu FLUX).
#   - SwinIR (ten sam plik co w v04) - upscaler dziala na obrazie
#     pikselowym, nie na latentach, wiec jest identyczny niezaleznie od
#     silnika (SDXL czy FLUX) - bez zmian wzgledem v04.
#   - BRAK odpowiednika LoRA "Add Detail - Slider" z v04 - to byla LoRA
#     wytrenowana pod SDXL, niekompatybilna architektonicznie z FLUX
#     (inny ksztalt tensorow) - nie ma tu prostego zamiennika 1:1.
#
# UWAGA (ryzyko, uczciwie odnotowane): checkpoint (Dockerfile) i ControlNet
# Union to modele spolecznosciowe/nieoficjalne (nie z black-forest-labs ani
# InvokeAI) - w przeciwienstwie do w pelni sprawdzonego zestawu v04, TEN
# zestaw NIE MA JESZCZE potwierdzenia z realnego uruchomienia na RunPod.
#
# Idempotentne + odporne na bledy - ten sam wzorzec co v04 (i tokeny wyzej):
# nieudane pobranie JEDNEGO elementu tylko wypisuje UWAGA i skrypt leci
# dalej, nigdy nie blokuje calego startu poda. Uruchamiane W PIERWSZYM
# PLANIE (przed startem InvokeAI) - invokeai.yaml ma scan_models_on_startup:
# true, ktory skanuje modele TYLKO RAZ, przy starcie.
log_elapsed "=== [3/4] Dodatkowe modele FLUX (VAE/T5/CLIP/IP-Adapter/ControlNet/SwinIR) ==="
mkdir -p /workspace/invokeai/root/models/flux/vae \
         /workspace/invokeai/root/models/any/t5_encoder \
         /workspace/invokeai/root/models/any/clip_embed \
         /workspace/invokeai/root/models/any/clip_vision \
         /workspace/invokeai/root/models/flux/ip_adapter \
         /workspace/invokeai/root/models/flux/controlnet \
         /workspace/invokeai/root/models/any/upscale

download_if_missing() {
    local dest="$1" url="$2"
    if [ -s "$dest" ]; then
        echo "(pomijam - juz pobrane) $(basename "$dest")"
        return 0
    fi
    if curl -L --fail --retry 3 --retry-delay 5 --connect-timeout 15 --max-time 900 \
            -o "$dest" "$url"; then
        echo "OK: $(basename "$dest")"
    else
        echo "UWAGA: nie udalo sie pobrac $(basename "$dest") - kontynuuje bez niego." >&2
    fi
}

download_if_missing \
    "/workspace/invokeai/root/models/flux/vae/ae.safetensors" \
    "https://huggingface.co/ffxvs/vae-flux/resolve/main/ae.safetensors"

download_if_missing \
    "/workspace/invokeai/root/models/flux/ip_adapter/ip_adapter.safetensors" \
    "https://huggingface.co/XLabs-AI/flux-ip-adapter-v2/resolve/main/ip_adapter.safetensors"

download_if_missing \
    "/workspace/invokeai/root/models/any/upscale/003_realSR_BSRGAN_DFOWMFC_s64w8_SwinIR-L_x4_GAN-with-dict-keys-params-and-params_ema.pth" \
    "https://github.com/JingyunLiang/SwinIR/releases/download/v0.0/003_realSR_BSRGAN_DFOWMFC_s64w8_SwinIR-L_x4_GAN-with-dict-keys-params-and-params_ema.pth"

# T5-XXL/CLIP-L (::subfolder w oficjalnych repo InvokeAI) i foldery diffusers
# (CLIP ViT-L image encoder, ControlNet Union) - snapshot_download zamiast
# pojedynczego curl, ten sam mechanizm co bundle w historii tego projektu
# (v03/v04). Dla wpisow "::subfolder" pobieramy tylko ten podfolder
# (allow_patterns) i splaszczamy go do docelowego katalogu, bo InvokeAI
# oczekuje plikow bezposrednio w folderze modelu, nie w zagniezdzonym
# podfolderze.
if /workspace/invokeai/.venv/bin/python << 'PYEOF'
import os, shutil
from huggingface_hub import snapshot_download

# (repo_id, subfolder_or_None, dest)
items = [
    ('InvokeAI/t5-v1_1-xxl', 'bnb_llm_int8', '/workspace/invokeai/root/models/any/t5_encoder/t5_bnb_int8_quantized_encoder'),
    ('InvokeAI/clip-vit-large-patch14-text-encoder', 'bfloat16', '/workspace/invokeai/root/models/any/clip_embed/clip-vit-large-patch14'),
    ('InvokeAI/clip-vit-large-patch14', None, '/workspace/invokeai/root/models/any/clip_vision/clip-vit-large-patch14'),
    ('InstantX/FLUX.1-dev-Controlnet-Union', None, '/workspace/invokeai/root/models/flux/controlnet/FLUX.1-dev-Controlnet-Union'),
]
ok = True
for repo_id, subfolder, dest in items:
    if os.path.isdir(dest) and os.listdir(dest):
        print(f'(pomijam - juz pobrane) {repo_id}')
        continue
    tmp = dest + '.tmp_download'
    try:
        print(f'--- pobieram {repo_id}{"::" + subfolder if subfolder else ""} -> {dest} ---')
        if subfolder:
            snapshot_download(repo_id=repo_id, allow_patterns=f'{subfolder}/*', local_dir=tmp)
            src = os.path.join(tmp, subfolder)
            os.makedirs(dest, exist_ok=True)
            for name in os.listdir(src):
                shutil.move(os.path.join(src, name), os.path.join(dest, name))
        else:
            snapshot_download(repo_id=repo_id, local_dir=dest)
    except Exception as e:
        print(f'UWAGA: nie udalo sie pobrac {repo_id}: {e}')
        ok = False
    finally:
        if subfolder:
            shutil.rmtree(tmp, ignore_errors=True)
raise SystemExit(0 if ok else 1)
PYEOF
then
    echo "OK: T5-XXL/CLIP-L/CLIP ViT-L/ControlNet Union gotowe."
else
    echo "UWAGA: co najmniej jeden z T5-XXL/CLIP-L/CLIP ViT-L/ControlNet Union nie pobral sie poprawnie - patrz log wyzej. Bez T5/CLIP-L FLUX NIE WYGENERUJE obrazu - dociagnij recznie przez Model Manager. Kontynuuje." >&2
fi

log_elapsed "=== [4/4] Start InvokeAI (pierwszy plan, port 9090) ==="
export INVOKEAI_HOST=0.0.0.0
export INVOKEAI_PORT=9090
echo "Od tego momentu czas nie jest juz logowany przez ten skrypt - InvokeAI"
echo "przejmuje pierwszy plan i loguje wlasny postep startu ponizej."
exec /workspace/invokeai/.venv/bin/invokeai-web --root /workspace/invokeai/root
