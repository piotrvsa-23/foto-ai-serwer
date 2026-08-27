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
# Skrypt startowy — jedyna rzecz uruchamiana automatycznie przy starcie poda.
# Modele AI (SD1.5/SDXL/FLUX.1 itd.) NIE sa czescia obrazu ani osobnego
# skryptu pobierajacego (jak w v1-v14 dla ComfyUI) - InvokeAI ma wlasny,
# wbudowany w UI Model Manager z gotowa lista modeli do pobrania jednym
# klikiem, wiec osobny download_models.sh jest tu zbedny.
# ==============================================================================
COPY scripts/start.sh /workspace/scripts/start.sh
RUN chmod +x /workspace/scripts/start.sh

CMD ["/workspace/scripts/start.sh"]
