# ==============================================================================
# Serwer AI do obrobki zdjec — obraz Docker (TYLKO InvokeAI)
#
# Budowany etapami — patrz historia commitow po kazdym ukonczonym etapie.
# Wersje pinowane celowo, nie "latest" (patrz koncepcja-i-zasady-budowy.md, pkt 4.2).
#
# v15 (sierpien 2026) — PIVOT: ComfyUI + SwarmUI + wszystkie wtyczki ComfyUI
# (etapy 2/3/5 z wersji v1-v14) zostaly CALKOWICIE USUNIETE. Uzytkownik
# zdecydowal sie pracowac wylacznie w InvokeAI. Konsekwencja funkcjonalna,
# ktora trzeba miec swiadomie na uwadze: InvokeAI NIE obsluguje modeli/wezlow
# specyficznych dla ComfyUI z brief-techniczny-serwer-obrobki-zdjec.md
# (Qwen-Image-Edit, Flux.1 Kontext Dev, SUPIR) - to byly ComfyUI-owe
# checkpointy/wezly. InvokeAI ma WLASNY ekosystem modeli (SD1.5/SDXL/FLUX.1
# dev-schnell przez swoj Model Manager) i WLASNA, wbudowana restauracja
# twarzy (GFPGAN/CodeFormer) oraz upscaling (ESRGAN) - dociagane recznie
# przez UI, bez osobnego skryptu (patrz koniec pliku).
#
# v6.14.0 (sierpien 2026) — bump InvokeAI 6.9.0 -> 6.14.0 (na prosbe
# uzytkownika, ktory szukal "najnowszej stabilnej" - okazala sie nia 6.14.0,
# nie 6.13.8 ktore znalazl on recznie: 6.14.0 to finalny, nie-rc release
# z 25.08.2026, zweryfikowany bezposrednio na PyPI - pypi.org/pypi/invokeai/
# json, pole "info.version", nie z pamieci). Tag obrazu na Docker Hub tez
# nazwany "v6.14.0" (nie kolejnym numerkiem "v16") - zeby uzytkownik od razu
# widzial, ktora wersja InvokeAI siedzi w ktorym obrazie. Reszta obrazu
# (baza CUDA, brak ComfyUI/SwarmUI, izolowany venv) - bez zmian wzgledem v15.
# Sprawdzone bezposrednio w metadanych PyPI: torch dla 6.14.0 to nadal
# torch<3.0,>=2.7.0 (extra "cuda" pinuje wprost torch==2.7.1+cu128 na
# linux/x86_64) - baza CUDA 12.8.2-runtime i --torch-backend=cu128 ponizej
# zostaja bez zmian, nie byla potrzebna zadna korekta.
# ==============================================================================

# nvidia/cuda:12.8.2-runtime-ubuntu22.04 — dopasowany DOKLADNIE do wymagan
# invokeai==6.14.0 (torch<3.0,>=2.7.0, wheel-e cu128 - patrz uzasadnienie
# przy instalacji InvokeAI nizej). Tag zweryfikowany bezposrednio w Docker
# Hub API (nvidia/cuda, "12.8.2-runtime-ubuntu22.04", sierpien 2026), nie
# z pamieci.
#
# Wariant "runtime" (NIE "devel") — swiadoma zmiana wzgledem v1-v14: "devel"
# (nvcc + naglowki CUDA) byl potrzebny WYLACZNIE do kompilacji wlasnych
# rozszerzen CUDA w wtyczkach ComfyUI (SUPIR/ControlNet). Bez ComfyUI nic
# w tym obrazie nie kompiluje kodu CUDA ze zrodel - PyTorch (cu128) i cala
# reszta zaleznosci InvokeAI instaluja sie z gotowych wheeli. "runtime" jest
# wiec wystarczajacy i znaczaco mniejszy/szybszy do pobrania.
FROM nvidia/cuda:12.8.2-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1

# Minimalny zestaw pakietow systemowych - BEZ Pythona 3.11/software-properties-
# common/deadsnakes PPA (byly potrzebne wylacznie dla ComfyUI, ktorego juz nie
# ma) i BEZ git/git-lfs/ffmpeg (nic w tym obrazie juz nie klonuje repo ani nie
# przetwarza wideo). InvokeAI ma wlasny, w pelni izolowany Python 3.12
# (zarzadzany przez uv, patrz nizej) - nie potrzebuje systemowego Pythona.
#
# ca-certificates — wymagane, zeby curl (ponizej, instalator uv) poprawnie
# weryfikowal certyfikaty HTTPS.
# libgl1 + libglib2.0-0 — wymagane przez opencv-python (zaleznosc InvokeAI
# uzywana do przetwarzania obrazu/control adapters) - bez tego opencv rzuca
# "ImportError: libGL.so.1: cannot open shared object file".
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        libgl1 \
        libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

# ==============================================================================
# InvokeAI — jedyny silnik/UI w tym obrazie.
#
# Nadal wlasny, izolowany venv (uv-managed Python 3.12) — mimo ze nie ma juz
# drugiego narzedzia (ComfyUI/SwarmUI), od ktorego trzeba by sie izolowac.
# Nowe uzasadnienie (koncepcja-i-zasady-budowy.md pkt 4.3 zaktualizowany o
# ten wniosek): to jest OFICJALNY, rekomendowany przez tworcow InvokeAI
# sposob instalacji (uv sam zarzadza dedykowanym Pythonem) - nie "dodatkowa
# warstwa", tylko podazanie za ich wlasnym mechanizmem. Dodatkowo Ubuntu
# 22.04 od pewnego czasu oznacza systemowego Pythona jako "externally
# managed" (PEP 668) - bez wlasnego venv kazda instalacja pip wymagalaby
# obejscia --break-system-packages bezposrednio w systemowym Pythonie, co
# utrudnialoby czyste aktualizacje samego InvokeAI w przyszlosci. Zostawienie
# osobnego venv kosztuje zero dodatkowej zlozonosci (to i tak default
# instalatora), a daje czysta, latwa do podmiany w calosci instalacje.
# ==============================================================================

# uv — oficjalny, rekomendowany instalator InvokeAI (zarzadza tez wlasnym,
# izolowanym Pythonem 3.12 - "only-managed")
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:${PATH}"

# InvokeAI v6.14.0 — najnowsza stabilna wersja (finalny release, nie rc),
# zweryfikowana bezposrednio na PyPI (sierpien 2026), nie z pamieci. UWAGA:
# invokeai==6.14.0 wymaga torch<3.0,>=2.7.0 - stad --torch-backend=cu128
# (cu128 w pelni wspiera RTX 4090 i ma wheel-e torch 2.7.x wymagane przez
# ta wersje InvokeAI - jej wlasny extra "cuda" pinuje wprost torch 2.7.1+
# cu128 na linux/x86_64, wiec to dokladnie ten sam wybor, ktory robi tu
# --torch-backend=cu128).
RUN uv venv --relocatable --prompt invoke --python 3.12 --python-preference only-managed \
        /workspace/invokeai/.venv \
    && uv pip install --python /workspace/invokeai/.venv/bin/python \
        invokeai==6.14.0 --torch-backend=cu128 \
    && rm -rf /root/.cache/uv

# Weryfikacja wersji zaraz po instalacji — zapisywana do pliku, sprawdzana
# w checkliscie z briefu (sekcja 9), zeby nie ufac samej nazwie taga obrazu.
RUN /workspace/invokeai/.venv/bin/python -c \
        "import importlib.metadata as m, sys, torch; \
print('invokeai:', m.version('invokeai')); \
print('python:', sys.version.split()[0]); \
print('torch:', torch.__version__); \
print('torch cuda (build):', torch.version.cuda)" \
    | tee /opt/build-versions.txt

# ==============================================================================
# v6.14.0_v01_CyberRXL_v10 (sierpien 2026) — na wyrazna prosbe uzytkownika,
# po realnych testach na RunPod: zaszywamy JEDEN, juz wybrany i przetestowany
# checkpoint (CyberRealisticXL V10.0 FP16) BEZPOSREDNIO W OBRAZIE, budowany
# raz w CI (szybkie, stabilne lacze), zamiast liczyc na pobieranie go co
# sesje przez UI InvokeAI w przegladarce - to ostatnie bylo w praktyce
# zawodne dla tego pliku (wielokrotne zawieszki bez ani jednego pobranego
# bajtu, potwierdzone w logu InvokeAI - plik jest skladowany przez
# HuggingFace w systemie "Xet"). Zwykle pobieranie przez curl na koncowce
# resolve/main dziala mimo Xet - HuggingFace serwuje ten sam plik przez
# zwykle przekierowanie HTTP niezaleznie od backendu skladowania - to
# dokladnie ten sam mechanizm, ktory juz dzialal w v1-v14 dla modeli ComfyUI.
#
# LoRA swiadomie NIE sa tu zaszywane (decyzja z uzytkownikiem) - to male
# pliki (pojedyncze-kilkaset MB), wiec zaszywanie nie daje realnej oszczednosci
# czasu, a uzytkownik nadal aktywnie testuje/zmienia zestaw LoRA - kazda
# zmiana wymagalaby pelnego rebuildu obrazu. Instaluje sie je przez UI,
# teraz juz plynnie dzieki automatyzacji tokenow ponizej.
# ==============================================================================

# SHA256 z oficjalnej strony pliku na HuggingFace (Xet Pointer Details) -
# build PADNIE, jesli pobrany plik nie zgadza sie z tym hashem (ochrona przed
# cichym zaszyciem uciete/uszkodzonej kopii modelu w obrazie).
RUN mkdir -p /workspace/invokeai/root/models/sdxl/main \
    && curl -L --fail --retry 3 --retry-delay 5 \
        -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36" \
        -o /workspace/invokeai/root/models/sdxl/main/CyberRealisticXLPlay_V10.0_FP16.safetensors \
        "https://huggingface.co/cyberdelia/CyberRealisticXL/resolve/main/CyberRealisticXLPlay_V10.0_FP16.safetensors" \
    && echo "fd5e870b5bbce4bddeb64f4bb8e49c57f84ab793c0262a503f0123be435e667d  /workspace/invokeai/root/models/sdxl/main/CyberRealisticXLPlay_V10.0_FP16.safetensors" \
        | sha256sum -c -

# ==============================================================================
# v6.14.0_v03_CyberRXL_v10 (sierpien 2026) — na wyrazna prosbe uzytkownika:
# caly "SDXL Starter Bundle" z InvokeAI zaszyty w obrazie (VAE, IP-Adapter,
# 6x ControlNet, upscaler SwinIR) - POZA "Juggernaut XL v9" (celowo pominiety,
# to kolejny, zbedny pelny checkpoint SDXL - uzytkownik ma juz swoj wybrany,
# CyberRealisticXL powyzej).
#
# Zrodla (repo_id/URL) przepisane WPROST ze zrodla InvokeAI, nie z pamieci -
# invokeai/backend/model_manager/starter_models.py, lista "sdxl_bundle" (stan
# na InvokeAI 6.14.0). "IP Adapter SDXL Image Encoder" jest tu dodany jako
# zaleznosc obu wtyczek IP-Adapter (bez niego same IP-Adaptery nie dzialaja) -
# InvokeAI liczy go jako 12. pozycje przy instalacji calego bundla w UI.
#
# Repo-only zrodla (VAE, encoder, ControlNet) to wielo-plikowe foldery
# w stylu diffusers (config.json + wagi) - pobierane przez snapshot_download
# (ta sama biblioteka huggingface_hub, ktorej InvokeAI juz uzywa wewnetrznie
# do tego samego celu), NIE przez pojedynczy curl jak przy checkpointcie -
# pojedynczy plik by tu nie wystarczyl. Scan_models_on_startup (nizej)
# rozpoznaje taki caly folder jako jeden model po obecnosci config.json/
# model_index.json - sprawdzone wprost w kodzie InvokeAI (search.py,
# ModelSearch._walk_directory).
#
# UWAGA: LoRA "Add Detail - Slider" z Civitai (link podany przez uzytkownika)
# swiadomie NIE jest tu zaszyta - jej pobranie przez Civitai API wymaga
# tokenu (potwierdzone realnym testem: 401 Unauthorized bez niego), a
# zgodnie z ustalonymi zasadami bezpieczenstwa (patrz historia rozmowy)
# ZADEN token uzytkownika nie trafia do tego repo ani obrazu. Zeby zaszyc ten
# konkretny plik w przyszlym buildzie, potrzebny jest OSOBNY sekret GitHub
# Actions (np. CIVITAI_API_KEY w ustawieniach repo, analogicznie do juz
# istniejacego DOCKERHUB_TOKEN) przekazywany przez --secret w buildzie, nigdy
# zapisywany w warstwie obrazu. Do tego czasu doinstalowuje sie ja recznie
# przez UI (dziala juz plynnie dzieki automatyzacji tokenow w start.sh).
# UWAGA (naprawa parse errora, sierpien 2026): wieloliniowy string bez "\"
# na koncu kazdej linii Dockerfile parser rozumie jako KONIEC instrukcji RUN,
# a linia zaczynajaca sie od "from ..." zostaje wtedy zinterpretowana jako
# nowa instrukcja FROM ("FROM requires either one or three arguments").
# Uzywamy wiec tego samego heredoc (<< 'EOF'), ktory juz dziala nizej dla
# invokeai.yaml - BuildKit traktuje cala tresc miedzy znacznikami jako
# nieprzetwarzany tekst, bez tego problemu.
RUN mkdir -p /workspace/invokeai/root/models/sdxl/vae \
             /workspace/invokeai/root/models/any/clip_vision \
             /workspace/invokeai/root/models/sdxl/controlnet \
             /workspace/invokeai/root/models/sdxl/ip_adapter \
             /workspace/invokeai/root/models/any/upscale

RUN /workspace/invokeai/.venv/bin/python << 'PYEOF'
from huggingface_hub import snapshot_download

repos = {
    'madebyollin/sdxl-vae-fp16-fix': '/workspace/invokeai/root/models/sdxl/vae/sdxl-vae-fp16-fix',
    'InvokeAI/ip_adapter_sdxl_image_encoder': '/workspace/invokeai/root/models/any/clip_vision/ip_adapter_sdxl_image_encoder',
    'xinsir/controlNet-canny-sdxl-1.0': '/workspace/invokeai/root/models/sdxl/controlnet/controlnet-canny-sdxl-1.0',
    'diffusers/controlNet-depth-sdxl-1.0': '/workspace/invokeai/root/models/sdxl/controlnet/controlnet-depth-sdxl-1.0',
    'SargeZT/controlNet-sd-xl-1.0-softedge-dexined': '/workspace/invokeai/root/models/sdxl/controlnet/controlnet-softedge-dexined-sdxl',
    'xinsir/controlNet-openpose-sdxl-1.0': '/workspace/invokeai/root/models/sdxl/controlnet/controlnet-openpose-sdxl-1.0',
    'xinsir/controlNet-scribble-sdxl-1.0': '/workspace/invokeai/root/models/sdxl/controlnet/controlnet-scribble-sdxl-1.0',
    'xinsir/controlNet-tile-sdxl-1.0': '/workspace/invokeai/root/models/sdxl/controlnet/controlnet-tile-sdxl-1.0',
}
for repo_id, dest in repos.items():
    print(f'--- snapshot_download {repo_id} -> {dest} ---')
    snapshot_download(repo_id=repo_id, local_dir=dest)
PYEOF

# Pojedyncze pliki bundla (IP-Adapter x2, upscaler SwinIR) - te maja
# bezposrednie URL-e w starter_models.py, wiec zwykly curl (jak przy
# checkpointcie) wystarczy, bez snapshot_download.
RUN curl -L --fail --retry 3 --retry-delay 5 \
        -o /workspace/invokeai/root/models/sdxl/ip_adapter/ip-adapter_sdxl_vit-h.safetensors \
        "https://huggingface.co/InvokeAI/ip_adapter_sdxl_vit_h/resolve/main/ip-adapter_sdxl_vit-h.safetensors" \
    && curl -L --fail --retry 3 --retry-delay 5 \
        -o /workspace/invokeai/root/models/sdxl/ip_adapter/ip-adapter-plus_sdxl_vit-h.safetensors \
        "https://huggingface.co/InvokeAI/ip-adapter-plus_sdxl_vit-h/resolve/main/ip-adapter-plus_sdxl_vit-h.safetensors" \
    && curl -L --fail --retry 3 --retry-delay 5 \
        -o "/workspace/invokeai/root/models/any/upscale/003_realSR_BSRGAN_DFOWMFC_s64w8_SwinIR-L_x4_GAN-with-dict-keys-params-and-params_ema.pth" \
        "https://github.com/JingyunLiang/SwinIR/releases/download/v0.0/003_realSR_BSRGAN_DFOWMFC_s64w8_SwinIR-L_x4_GAN-with-dict-keys-params-and-params_ema.pth"

# invokeai.yaml zaszyty w obrazie z jednym kluczowym ustawieniem:
# scan_models_on_startup: true. Bez tego zaszyty wyzej plik .safetensors
# lezalby w folderze modeli, ale InvokeAI NIGDY by go sam nie "zobaczyl" w UI
# (rejestracja modelu w jego wewnetrznej bazie to osobny krok od samego
# polozenia pliku na dysku). Ta flaga (sprawdzona w zrodle InvokeAI,
# model_install_default.py, _register_orphaned_models) kaze InvokeAI
# przeskanowac folder modeli PRZY KAZDYM starcie i samodzielnie zarejestrowac
# kazdy nieznaleziony jeszcze w bazie plik - dokladnie nasz przypadek, bo baza
# (databases/invokeai.db) i tak powstaje od zera przy kazdym starcie kontenera
# (Container Disk jest efemeryczny, patrz koncepcja-i-zasady-budowy.md pkt 8).
# Komentarz w zrodle ostrzega "normalnie nie powinno byc orphaned models,
# ten flag tylko do testow" - ale to ostrzezenie zaklada TRWALA baze danych
# miedzy restartami (typowa, stacjonarna instalacja InvokeAI), co u nas nigdy
# nie zachodzi - u nas ten "przypadek testowy" jest normalnym przypadkiem.
RUN mkdir -p /workspace/invokeai/root && cat > /workspace/invokeai/root/invokeai.yaml << 'EOF'
schema_version: "4.0.3"
scan_models_on_startup: true
EOF

# ==============================================================================
# Skrypt startowy — jedyna rzecz uruchamiana automatycznie przy starcie poda.
# Poza checkpointem i bundlem SDXL zaszytymi wyzej, kolejne modele/LoRA NIE sa
# czescia obrazu - InvokeAI ma wlasny, wbudowany w UI Model Manager z gotowa
# lista modeli do pobrania jednym klikiem, wiec osobny download_models.sh
# jest tu zbedny.
# ==============================================================================
COPY scripts/start.sh /workspace/scripts/start.sh
RUN chmod +x /workspace/scripts/start.sh

CMD ["/workspace/scripts/start.sh"]
