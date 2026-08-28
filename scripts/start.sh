#!/usr/bin/env bash
# Skrypt startowy poda - v6.14.0_v04_CyberRXL_v10, wariant TYLKO InvokeAI:
# 1. Tworzy strukture folderow na Container Disk.
# 2. Jesli ustawione - automatycznie konfiguruje tokeny HuggingFace/Civitai
#    (patrz sekcja "TOKENY" nizej).
# 3. Automatycznie pobiera dodatkowe modele/LoRA (poza checkpointem
#    zaszytym w obrazie) - patrz sekcja "DODATKOWE MODELE" nizej.
# 4. Uruchamia InvokeAI (pierwszy plan, port 9090).
#
# UWAGA (sierpien 2026, decyzja po nieudanych probach v03): dodatkowe modele
# (VAE, IP-Adapter, ControlNety, SwinIR, LoRA z Civitai) CELOWO nie sa juz
# zaszywane w obrazie Docker - proby zaszycia ich w GitHub Actions padaly
# wielokrotnie na ograniczeniach/niestabilnosci CI (za malo miejsca na
# dysku runnera, zawieszajace sie buildy), niezwiazanych z samymi plikami
# modeli. RunPod ma duzo wiecej miejsca i stabilniejsze lacze, wiec te same
# pobierania po prostu dzieja sie tu, przy starcie poda, zamiast przy
# budowaniu obrazu w CI - uzytkownik nie musi juz recznie wklejac linkow
# do Model Managera, dostaje gotowy zestaw automatycznie po kilku minutach.
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

# DODATKOWE MODELE (sierpien 2026, na wyrazna prosbe uzytkownika): zestaw
# wybrany pod konkretne zastosowania (inpaint fragmentow, przebieranie
# postaci z zachowaniem pozy, usuwanie uszkodzen ze skanow, naprawa/
# generowanie szczegolow) - NIE caly "SDXL Starter Bundle" InvokeAI (12
# pozycji), tylko podzbior faktycznie do tego przydatny:
#   - VAE (sdxl-vae-fp16-fix) + IP-Adapter Image Encoder - zaleznosc obu
#     ponizszych IP-Adapterow, bez niej nie dzialaja.
#   - IP-Adapter Standard + Plus/Precise - generowanie/inpaint z obrazem
#     referencyjnym.
#   - ControlNet: canny, depth, openpose, tile - openpose do zachowania
#     pozy przy zmianie stroju, tile do naprawy/dogenerowania szczegolow
#     przy zachowaniu struktury (kluczowe przy renowacji skanow), depth do
#     zachowania struktury 3D, canny jako uniwersalne uzupelnienie.
#     POMINIETE swiadomie: scribble (generowanie z odrecznego szkicu - nie
#     pasuje do zadnego z powyzszych zastosowan) i soft edge (duzy plik,
#     w duzej mierze pokrywa sie z canny/tile).
#   - SwinIR (upscaler BSRGAN) - dedykowany do odszumiania/naprawy
#     zdjec niskiej jakosci, wprost pod usuwanie uszkodzen ze skanow.
#   - LoRA "Add Detail - Slider" z Civitai (link podany przez uzytkownika,
#     spodobal mu sie) - naprawa/wzmacnianie szczegolow.
#   - Qwen3-4B-abliterated (Text LLM, sierpien 2026, na wyrazna prosbe
#     uzytkownika) - NIE generuje obrazow, tylko zasila wbudowana w InvokeAI
#     6.14.0 funkcje "Expand Prompt" (przycisk ze skrami w polu promptu,
#     patrz docs/features/prompt-tools.md w zrodle InvokeAI). Rozwiazuje
#     dwa problemy naraz: (1) Cyber (SDXL/CLIP) preferuje prompty w stylu
#     tagow z wagami, nie pelne zdania - Qwen moze to sam wygenerowac z
#     krotkiego opisu, (2) sam model obrazu (CLIP) nie rozumie polskiego -
#     Qwen3 oficjalnie wspiera 119+ jezykow (w tym polski), wiec moze
#     PRZETLUMACZYC polski opis na angielski PRZED wygenerowaniem promptu
#     z tagami. Wymaga wlasnego, edytowalnego w UI "System Prompt" (patrz
#     rozmowa/PR) - domyslny system prompt InvokeAI nie tlumaczy sam z
#     siebie, tylko rozwija tekst w tym samym jezyku, w ktorym go dostal.
#     Wariant "abliterated" (usunieta odmowa odpowiedzi) wybrany celowo -
#     zwykly Qwen3-Instruct czasem odmawia rozwijania opisow z tresciami
#     dla doroslych, co zablokowaloby to narzedzie akurat tam, gdzie jest
#     najbardziej potrzebne (checkpointy NSFW w tym projekcie).
#
# Idempotentne: kazdy element pomijany, jesli juz istnieje na dysku (np. po
# restarcie na tym samym Container Disk / Network Volume) - nie pobiera sie
# ponownie bez potrzeby. Kazdy element opakowany w obsluge bledow (ten sam
# wzorzec co tokeny wyzej) - nieudane pobranie JEDNEGO elementu (zerwane
# lacze, tymczasowa niedostepnosc HuggingFace/Civitai) tylko wypisuje UWAGA
# i skrypt leci dalej z reszta, nigdy nie blokuje calego startu poda.
# Uruchamiane W PIERWSZYM PLANIE (przed startem InvokeAI, nie w tle) -
# invokeai.yaml ma scan_models_on_startup: true, ktory skanuje modele
# TYLKO RAZ, przy starcie - pobieranie w tle rownolegle z InvokeAI
# konczyloby sie czescia modeli niezarejestrowanych do nastepnego restartu.
log_elapsed "=== [3/4] Dodatkowe modele (VAE/IP-Adapter/ControlNet/SwinIR/LoRA/Text LLM) ==="
mkdir -p /workspace/invokeai/root/models/sdxl/vae \
         /workspace/invokeai/root/models/any/clip_vision \
         /workspace/invokeai/root/models/sdxl/controlnet \
         /workspace/invokeai/root/models/sdxl/ip_adapter \
         /workspace/invokeai/root/models/any/upscale \
         /workspace/invokeai/root/models/sdxl/lora \
         /workspace/invokeai/root/models/any/text_llm

if /workspace/invokeai/.venv/bin/python << 'PYEOF'
import os
from huggingface_hub import snapshot_download

repos = {
    'madebyollin/sdxl-vae-fp16-fix': '/workspace/invokeai/root/models/sdxl/vae/sdxl-vae-fp16-fix',
    'InvokeAI/ip_adapter_sdxl_image_encoder': '/workspace/invokeai/root/models/any/clip_vision/ip_adapter_sdxl_image_encoder',
    'xinsir/controlnet-canny-sdxl-1.0': '/workspace/invokeai/root/models/sdxl/controlnet/controlnet-canny-sdxl-1.0',
    'diffusers/controlnet-depth-sdxl-1.0': '/workspace/invokeai/root/models/sdxl/controlnet/controlnet-depth-sdxl-1.0',
    'xinsir/controlnet-openpose-sdxl-1.0': '/workspace/invokeai/root/models/sdxl/controlnet/controlnet-openpose-sdxl-1.0',
    'xinsir/controlnet-tile-sdxl-1.0': '/workspace/invokeai/root/models/sdxl/controlnet/controlnet-tile-sdxl-1.0',
    'huihui-ai/Qwen3-4B-abliterated': '/workspace/invokeai/root/models/any/text_llm/qwen3-4b-abliterated',
}
ok = True
for repo_id, dest in repos.items():
    if os.path.isdir(dest) and os.listdir(dest):
        print(f'(pomijam - juz pobrane) {repo_id}')
        continue
    try:
        print(f'--- pobieram {repo_id} -> {dest} ---')
        snapshot_download(repo_id=repo_id, local_dir=dest)
    except Exception as e:
        print(f'UWAGA: nie udalo sie pobrac {repo_id}: {e}')
        ok = False
raise SystemExit(0 if ok else 1)
PYEOF
then
    echo "OK: VAE/Image Encoder/ControlNet (canny/depth/openpose/tile)/Text LLM gotowe."
else
    echo "UWAGA: co najmniej jeden z VAE/Image Encoder/ControlNet/Text LLM nie pobral sie poprawnie - patrz log wyzej. Kontynuuje." >&2
fi

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
    "/workspace/invokeai/root/models/sdxl/ip_adapter/ip-adapter_sdxl_vit-h.safetensors" \
    "https://huggingface.co/InvokeAI/ip_adapter_sdxl_vit_h/resolve/main/ip-adapter_sdxl_vit-h.safetensors"

download_if_missing \
    "/workspace/invokeai/root/models/sdxl/ip_adapter/ip-adapter-plus_sdxl_vit-h.safetensors" \
    "https://huggingface.co/InvokeAI/ip-adapter-plus_sdxl_vit-h/resolve/main/ip-adapter-plus_sdxl_vit-h.safetensors"

download_if_missing \
    "/workspace/invokeai/root/models/any/upscale/003_realSR_BSRGAN_DFOWMFC_s64w8_SwinIR-L_x4_GAN-with-dict-keys-params-and-params_ema.pth" \
    "https://github.com/JingyunLiang/SwinIR/releases/download/v0.0/003_realSR_BSRGAN_DFOWMFC_s64w8_SwinIR-L_x4_GAN-with-dict-keys-params-and-params_ema.pth"

# LoRA z Civitai - wymaga tokenu (401 bez niego, potwierdzone realnym testem).
# Pobierana TYLKO jesli CIVITAI_API_KEY jest ustawiony (ten sam token, ktory
# krok [2/4] wyzej wpisuje juz do invokeai.yaml) - bez tokenu pomijana z
# ostrzezeniem, nigdy nie blokuje startu.
LORA_DEST="/workspace/invokeai/root/models/sdxl/lora/add-detail-slider_sdxl.safetensors"
if [ -s "$LORA_DEST" ]; then
    echo "(pomijam - juz pobrane) add-detail-slider_sdxl.safetensors"
elif [ -n "${CIVITAI_API_KEY:-}" ]; then
    if curl -L --fail --retry 3 --retry-delay 5 --connect-timeout 15 --max-time 900 \
            -H "Authorization: Bearer ${CIVITAI_API_KEY}" \
            -o "$LORA_DEST" \
            "https://civitai.com/api/download/models/1506027?fileId=1406088"; then
        echo "OK: LoRA Add Detail - Slider pobrana."
    else
        echo "UWAGA: nie udalo sie pobrac LoRA Add Detail - Slider z Civitai - kontynuuje bez niej." >&2
    fi
else
    echo "(pomijam LoRA Add Detail - Slider - CIVITAI_API_KEY nieustawiony)"
fi

log_elapsed "=== [4/4] Start InvokeAI (pierwszy plan, port 9090) ==="
export INVOKEAI_HOST=0.0.0.0
export INVOKEAI_PORT=9090
echo "Od tego momentu czas nie jest juz logowany przez ten skrypt - InvokeAI"
echo "przejmuje pierwszy plan i loguje wlasny postep startu ponizej."
exec /workspace/invokeai/.venv/bin/invokeai-web --root /workspace/invokeai/root
