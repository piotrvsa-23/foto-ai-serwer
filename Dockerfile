# ==============================================================================
# Serwer AI do obrobki zdjec — obraz Docker (TYLKO InvokeAI)
#
# Budowany etapami — patrz historia commitow po kazdym ukonczonym etapie.
# Wersje pinowane celowo, nie "latest" (patrz koncepcja-i-zasady-budowy.md, pkt 4.2).
#
# GALAZ flux-v01 (sierpien 2026): rownolegly wariant do glownej galezi
# (claude/foto-ai-runpod-setup-zzw2vi), zbudowany na bazie stanu v04 -
# ten sam wzorzec (jeden checkpoint zaszyty w obrazie + reszta modeli
# pobierana automatycznie w start.sh), ale z checkpointem FLUX.1-dev
# zamiast SDXL, do porownania jakosci/mozliwosci miedzy silnikami. Historia
# v1-v15/v6.14.0 ponizej dotyczy glownej galezi - ta galaz odgalezia sie
# od commita v04 i nie jest z nia scalana automatycznie.
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
# flux.1_v01 (sierpien 2026) — WARIANT ROWNOLEGLY do v6.14.0_v04_CyberRXL_v10,
# na wyrazna prosbe uzytkownika: ten sam schemat co v04 (JEDEN checkpoint
# zaszyty na stale w obrazie + dodatkowe modele pobierane automatycznie w
# runtime przez start.sh), ale z innym silnikiem generowania - FLUX.1-dev
# (transformer, architektura rectified-flow) zamiast SDXL - do porownania
# jakosci/mozliwosci z CyberRealisticXL.
#
# Checkpoint: shauray/flux.1-dev-uncensored-q4 (link podany przez uzytkownika)
# - transformer FLUX.1-dev zmergowany z LoRA "uncensored", skwantyzowany do
# bitsandbytes NF4 (potwierdzone przez opis modelu - "quantized to NF4",
# wymaga biblioteki bitsandbytes do wczytania, ktora invokeai==6.14.0 juz
# instaluje jako wlasna zaleznosc). Format pliku (pojedynczy .safetensors,
# NF4) jest STRUKTURALNIE IDENTYCZNY z oficjalnym, wspieranym przez InvokeAI
# checkpointem "InvokeAI/flux_dev::transformer/bnb_nf4/flux1-dev-bnb_nf4.safetensors"
# (sprawdzone w zrodle InvokeAI, starter_models.py, wpis flux_dev_quantized) -
# to nie przypadek, tylko ta sama, standardowa metoda kwantyzacji NF4 dla
# transformerow FLUX, wiec InvokeAI powinien go rozpoznac i wczytac
# analogicznie. UWAGA: to model spolecznosciowy/nieoficjalny (nie z
# black-forest-labs ani InvokeAI) - w przeciwienstwie do CyberRealisticXL
# (juz przetestowanego na tym projekcie) NIE mamy jeszcze potwierdzenia z
# realnego uruchomienia na RunPod, ze wczytuje sie bezblednie.
#
# Brak weryfikacji SHA256 tego pliku (w przeciwienstwie do CyberRealisticXL) -
# to model spolecznosciowy bez oficjalnej strony z opublikowanym hashem do
# porownania (CyberRealisticXL mial taki na HuggingFace - Xet Pointer
# Details). Integralnosc pobrania zabezpiecza tu tylko "curl --fail" (blad
# przy niepelnym pobraniu) - jesli plik pobierze sie niepoprawnie, InvokeAI
# odrzuci go przy probie wczytania (bledna suma kontrolna safetensors).
# ==============================================================================
RUN mkdir -p /workspace/invokeai/root/models/flux/main \
    && curl -L --fail --retry 3 --retry-delay 5 --connect-timeout 15 --max-time 900 \
        -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36" \
        -o /workspace/invokeai/root/models/flux/main/flux1-dev-uncensored-nf4.safetensors \
        "https://huggingface.co/shauray/flux.1-dev-uncensored-q4/resolve/main/diffusion_pytorch_model.safetensors"

# Dodatkowe modele (VAE, T5/CLIP encodery, IP-Adapter, ControlNet, upscaler)
# NIE sa zaszywane w obrazie (ten sam wzorzec co v6.14.0_v04_CyberRXL_v10 -
# patrz galaz claude/foto-ai-runpod-setup-zzw2vi, uzasadnienie w Dockerfile
# tamtej galezi: CI GitHub Actions okazalo sie zawodne/kruche dla duzych
# pobieran). scripts/start.sh na TEJ galezi pobiera je automatycznie przy
# kazdym starcie poda - zestaw dobrany pod architekture FLUX (inny niz SDXL
# w v04), patrz komentarze w scripts/start.sh.

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
# Poza checkpointem FLUX zaszytym wyzej, DODATKOWE modele (VAE, T5/CLIP
# encodery, IP-Adapter, ControlNet Union, SwinIR) NIE sa czescia obrazu -
# start.sh sam je automatycznie pobiera przy KAZDYM starcie poda, przed
# uruchomieniem InvokeAI. Patrz komentarze w samym scripts/start.sh po
# pelna liste i uzasadnienie doboru kazdego elementu.
# ==============================================================================
COPY scripts/start.sh /workspace/scripts/start.sh
RUN chmod +x /workspace/scripts/start.sh

CMD ["/workspace/scripts/start.sh"]
