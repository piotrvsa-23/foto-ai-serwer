#!/usr/bin/env bash
# Skrypt startowy poda - flux.1_v01, wariant TYLKO InvokeAI (galaz rownolegla
# do glownej galezi, oparta o wzorzec v6.14.0_v04_CyberRXL_v10, ale z
# checkpointem FLUX zamiast SDXL - patrz naglowek Dockerfile):
# 1. Tworzy strukture folderow na Container Disk.
# 2. Jesli ustawione - automatycznie konfiguruje tokeny HuggingFace/Civitai
#    (patrz sekcja "TOKENY" nizej) - dla tego wariantu opcjonalne, zadne
#    ze zrodel ponizej nie sa gated, ale zostaje dla spojnosci z v04 i na
#    wypadek gdyby uzytkownik pozniej dodal tu gated model recznie.
# 3. Automatycznie pobiera dodatkowe modele FLUX (VAE/IP-Adapter/SwinIR/
#    CLIP) - patrz sekcja "DODATKOWE MODELE" nizej.
# 4. Uruchamia InvokeAI W TLE, zleca mu (przez jego wlasne REST API) instalacje
#    glownego checkpointu GGUF ("Flux Unchained") i T5-XXL int8 encodera, czeka
#    na ich ukonczenie, po czym oddaje kontrole procesowi InvokeAI (pierwszy
#    plan, port 9090) - patrz uzasadnienie w sekcji [4/4] nizej.
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
# SDXL z v04 nie jest tu zamiennikiem). Ten krok pobiera TYLKO elementy,
# ktore realny test na RunPod potwierdzil jako poprawnie rozpoznawane przez
# automatyczny skaner InvokeAI (scan_models_on_startup) - VAE, CLIP-L text
# encoder, CLIP ViT-L image encoder, IP-Adapter, ControlNet Union, SwinIR.
# Glowny checkpoint I T5-XXL int8 (ktory w tym samym tescie skaner
# zarejestrowal Zle - patrz [4/4] nizej) instaluje sie oddzielnie, przez
# wlasne REST API InvokeAI, nie przez ten mechanizm.
#   - VAE (ae.safetensors) - TWARDA ZALEZNOSC (FLUX bez VAE nie zdekoduje
#     obrazu z latentow). Zrodlo: ffxvs/vae-flux, NIE oficjalne
#     black-forest-labs/FLUX.1-schnell - UWAGA (naprawa realnego bledu z tego
#     projektu, sierpien 2026): oficjalne repo BFL mimo deklarowanej licencji
#     Apache 2.0 zwraca 401 Unauthorized bez zalogowania (potwierdzone
#     recznie przez uzytkownika w przegladarce, patrz historia commitow -
#     "Napraw 401 dla VAE Flux"). ffxvs/vae-flux to sprawdzony, dzialajacy
#     bez logowania community-mirror identycznego pliku ae.safetensors.
#   - CLIP ViT-L Image Encoder (InvokeAI/clip-vit-large-patch14, INNY plik niz
#     CLIP-L text encoder instalowany w [4/4]) - zaleznosc IP-Adaptera FLUX.
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
# Idempotentne + odporne na bledy - ten sam wzorzec co v04 (i tokeny wyzej):
# nieudane pobranie JEDNEGO elementu tylko wypisuje UWAGA i skrypt leci
# dalej, nigdy nie blokuje calego startu poda.
log_elapsed "=== [3/4] Dodatkowe modele FLUX (VAE/CLIP/IP-Adapter/ControlNet/SwinIR) ==="
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

# CLIP-L text encoder (::subfolder w oficjalnym repo InvokeAI) i foldery
# diffusers (CLIP ViT-L image encoder, ControlNet Union) - snapshot_download
# zamiast pojedynczego curl. Dla wpisu "::subfolder" pobieramy tylko ten
# podfolder (allow_patterns) i splaszczamy go do docelowego katalogu, bo
# InvokeAI oczekuje plikow bezposrednio w folderze modelu, nie w
# zagniezdzonym podfolderze. UWAGA: T5-XXL int8 (ten sam wzorzec zrodla,
# "InvokeAI/t5-v1_1-xxl::bnb_llm_int8") CELOWO NIE jest tu pobierany -
# realny test na RunPod pokazal, ze mimo poprawnej struktury plikow na
# dysku automatyczny skaner InvokeAI (scan_models_on_startup) rejestruje go
# na zlym poziomie zagniezdzenia folderow i model ladowal sie jako
# "Unknown" (bezuzyteczny). CLIP-L text encoder z tego samego mechanizmu
# (subfolder "bfloat16") dziala poprawnie - to specyficzny problem tylko
# klasy T5Encoder_BnBLLMint8_Config, patrz [4/4] nizej po wlasciwa naprawe.
if /workspace/invokeai/.venv/bin/python << 'PYEOF'
import os, shutil
from huggingface_hub import snapshot_download

# (repo_id, subfolder_or_None, dest)
items = [
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
    echo "OK: CLIP-L/CLIP ViT-L/ControlNet Union gotowe."
else
    echo "UWAGA: co najmniej jeden z CLIP-L/CLIP ViT-L/ControlNet Union nie pobral sie poprawnie - patrz log wyzej. Kontynuuje." >&2
fi

# [4/4] GLOWNY CHECKPOINT (Flux Unchained GGUF Q8_0) + T5-XXL int8 - PRZEZ
# WLASNE REST API INVOKEAI, nie recznym kopiowaniem plikow (sierpien 2026,
# naprawa po realnym niepowodzeniu na RunPod):
#
# Historia problemu: pierwsza wersja tego skryptu probowala, tak jak dla
# VAE/CLIP/ControlNet wyzej, recznie pobrac T5-XXL int8
# (huggingface_hub.snapshot_download + splaszczenie folderu) i podlozyc pod
# scan_models_on_startup. Na dysku struktura wyszla poprawna, ale
# automatyczny skaner InvokeAI zarejestrowal WEWNETRZNY podfolder
# (".../text_encoder_2") jako korzen modelu zamiast folderu-rodzica, ktorego
# oczekuje klasa T5Encoder_BnBLLMint8_Config (ktora zawsze doklada WLASNY,
# dodatkowy segment "text_encoder_2/config.json" do przekazanej sciezki) -
# w efekcie model ladowal sie jako "Unknown", bezuzyteczny. Ten sam problem
# dotyczylby kazdego glownego checkpointu, ktorego dokladny oczekiwany uklad
# folderow nie jest 100% pewny (co dotyczy kazdego formatu GGUF - patrz
# uzasadnienie wyboru modelu w Dockerfile).
#
# Zamiast zgadywac uklad folderow, ten krok startuje InvokeAI W TLE i uzywa
# JEGO WLASNEGO, oficjalnego REST API (POST /api/v2/models/install) do
# zlecenia instalacji obu modeli ze zrodel identycznych z tymi, ktorych
# InvokeAI uzywa we wlasnych "starter models" (starter_models.py) - to
# DOKLADNIE ten sam mechanizm, co reczne dodanie modelu przez
# Model Manager -> Add Model -> HuggingFace Repo ID w interfejsie InvokeAI,
# wiec caly, czesto niejawny kod ustalania poprawnej struktury folderow i
# typu modelu wykonuje sam InvokeAI, a nie nasza reimplementacja.
log_elapsed "=== [4/4] Checkpoint FLUX Unchained (GGUF Q8_0) + T5-XXL int8 przez REST API InvokeAI, potem start (port 9090) ==="
export INVOKEAI_HOST=0.0.0.0
export INVOKEAI_PORT=9090

/workspace/invokeai/.venv/bin/invokeai-web --root /workspace/invokeai/root &
INVOKEAI_PID=$!

echo "Czekam az REST API InvokeAI bedzie gotowe..."
API_READY=0
for _ in $(seq 1 90); do
    if curl -sf "http://127.0.0.1:9090/api/v1/app/version" >/dev/null 2>&1; then
        API_READY=1
        break
    fi
    sleep 2
done

if [ "$API_READY" -eq 1 ]; then
    echo "OK: API gotowe. Zlecam instalacje checkpointu i T5-XXL int8..."
    /workspace/invokeai/.venv/bin/python << 'PYEOF'
import json
import time
import urllib.parse
import urllib.request

API = "http://127.0.0.1:9090/api/v2/models"
SOURCES = [
    "https://huggingface.co/GraydientPlatformAPI/flux-unchained/resolve/main/fluxunchained-dev-q8-0-v2.gguf",
    "InvokeAI/t5-v1_1-xxl::bnb_llm_int8",
]


def post_install(source: str):
    url = f"{API}/install?source={urllib.parse.quote(source, safe='')}"
    req = urllib.request.Request(url, data=b"{}", method="POST", headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.load(resp)
    except Exception as e:
        print(f"UWAGA: nie udalo sie zlecic instalacji {source}: {e}")
        return None


job_ids = []
for source in SOURCES:
    job = post_install(source)
    if job:
        print(f"Zlecono instalacje: {source} (job id {job.get('id')})")
        job_ids.append(job["id"])
    else:
        print(f"POMINIETO (blad zlecenia): {source}")

# Duze pliki (checkpoint ~12.7GB, T5 int8 ~5GB) - dajemy do 25 minut zanim
# przestajemy czekac i oddajemy stery InvokeAI (instalacja i tak dokonczy
# sie w tle, tylko nie zobaczymy tu jej wyniku).
terminal_statuses = {"completed", "error", "cancelled"}
deadline = time.time() + 1500
pending = set(job_ids)
while pending and time.time() < deadline:
    time.sleep(10)
    try:
        with urllib.request.urlopen(f"{API}/install", timeout=30) as resp:
            all_jobs = json.load(resp)
    except Exception as e:
        print(f"UWAGA: nie udalo sie odczytac statusu instalacji: {e}")
        continue
    by_id = {j["id"]: j for j in all_jobs}
    for jid in list(pending):
        job = by_id.get(jid)
        if job is not None and job.get("status") in terminal_statuses:
            print(f"Job {jid} ({job.get('source')}): {job.get('status')}")
            pending.discard(jid)

if pending:
    print(f"UWAGA: instalacja nie zdazyla sie zakonczyc w limicie czasu (joby: {sorted(pending)}) - InvokeAI dokonczy ja w tle, moze byc niedostepna od razu po starcie.")
else:
    print("OK: checkpoint FLUX Unchained i T5-XXL int8 zainstalowane.")
PYEOF
else
    echo "UWAGA: REST API InvokeAI nie odpowiedzialo w 3 minuty - pomijam automatyczna instalacje checkpointu/T5, dociagnij je recznie przez Model Manager." >&2
fi

echo "Instalacja zlecona/zakonczona - InvokeAI dziala dalej w tle (port 9090)."
wait "$INVOKEAI_PID"
