# ==============================================================================
# Serwer AI do obrobki zdjec — obraz Docker (ComfyUI + SwarmUI + InvokeAI)
#
# Budowany etapami — patrz CHANGELOG.md po kazdym ukonczonym etapie.
# Wersje pinowane celowo, nie "latest" (patrz koncepcja-i-zasady-budowy.md, pkt 4.2).
#
# ETAP 1: baza systemu — CUDA + Python + PyTorch
# ==============================================================================

# CUDA 13.0.3 (patch aktualny na sierpien 2026) zamiast 12.8 z briefu — wsparcie
# dla CUDA 12.8 zostalo wycofane z oficjalnych paczek PyTorch (pytorch/pytorch#180398).
# RTX 4090 (Ada Lovelace) jest w pelni wspierana przez CUDA 13.0.
#
# Wariant "devel" (bez oddzielnego cuDNN systemowego) - paczki PyTorch cu130
# niosa wlasne biblioteki CUDA/cuDNN w wheelu, wiec dodatkowy cudnn-devel
# tylko zajmowalby miejsce bez korzysci. "devel" (nie "runtime") zostaje,
# bo daje nvcc/naglowki potrzebne do kompilacji niektorych wtyczek ComfyUI
# (np. wlasne rozszerzenia CUDA w SUPIR/ControlNet).
FROM nvidia/cuda:13.0.3-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

# Python 3.11 — wymagany przez czesc wtyczek ComfyUI (nie dzialaja poprawnie na 3.12+)
RUN apt-get update && apt-get install -y --no-install-recommends \
        software-properties-common \
        curl \
        wget \
        git \
        git-lfs \
        ffmpeg \
        libgl1 \
        libglib2.0-0 \
    && add-apt-repository -y ppa:deadsnakes/ppa \
    && apt-get update && apt-get install -y --no-install-recommends \
        python3.11 \
        python3.11-venv \
        python3.11-dev \
    && curl -sS https://bootstrap.pypa.io/get-pip.py | python3.11 \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 \
    && update-alternatives --install /usr/bin/python python /usr/bin/python3.11 1 \
    && rm -rf /var/lib/apt/lists/*

# PyTorch — CUDA 13.0 (cu130), wersja stabilna
RUN pip install --break-system-packages \
        torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu130

# Weryfikacja wersji zaraz po instalacji — zapisywana do pliku, sprawdzana
# w checkliscie z briefu (sekcja 9), zeby nie ufac samej nazwie taga obrazu.
RUN python3 -c "import torch; print('torch:', torch.__version__); print('cuda (build):', torch.version.cuda)" \
    | tee /opt/build-versions.txt

WORKDIR /workspace

# ==============================================================================
# ETAP 2: ComfyUI + ComfyUI-Manager
# Wersje sprawdzone bezposrednio w tagach repo (sierpien 2026), nie z pamieci.
# ==============================================================================

# ComfyUI v0.33.3 — najnowszy stabilny tag w momencie budowy
RUN git clone --depth 1 --branch v0.33.3 https://github.com/comfy-org/ComfyUI.git /workspace/comfyui \
    && pip install --break-system-packages -r /workspace/comfyui/requirements.txt

# ComfyUI-Manager 4.2.2 — jako custom node, siatka bezpieczenstwa dla wtyczek
# (koncepcja-i-zasady-budowy.md, pkt 4.7)
RUN git clone --depth 1 --branch 4.2.2 https://github.com/Comfy-Org/ComfyUI-Manager.git \
        /workspace/comfyui/custom_nodes/ComfyUI-Manager \
    && pip install --break-system-packages -r /workspace/comfyui/custom_nodes/ComfyUI-Manager/requirements.txt

RUN { \
        echo "comfyui: v0.33.3"; \
        echo "comfyui-manager: 4.2.2"; \
    } | tee -a /opt/build-versions.txt

# ==============================================================================
# ETAP 3: SwarmUI
# Nakladka codziennej pracy (koncepcja-i-zasady-budowy.md, pkt 2.3).
# SwarmUI to aplikacja .NET - kompilujemy ja RAZ, tutaj, w obrazie (a nie przy
# kazdym starcie poda), zeby start poda nie zalezal od pobierania paczek NuGet
# z internetu za kazdym razem.
# ==============================================================================

# .NET 8 SDK — oficjalny skrypt instalacyjny Microsoftu (wersja pinowana,
# nie apt z domyslnego repo, ktore na Ubuntu 22.04 bywa niezgodne/przestarzale)
ENV DOTNET_ROOT=/usr/share/dotnet \
    PATH="/usr/share/dotnet:${PATH}" \
    DOTNET_NOLOGO=1 \
    DOTNET_CLI_TELEMETRY_OPTOUT=1
RUN curl -sSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh \
    && chmod +x /tmp/dotnet-install.sh \
    && /tmp/dotnet-install.sh --channel 8.0 --install-dir /usr/share/dotnet \
    && rm /tmp/dotnet-install.sh

# SwarmUI 0.9.8-Beta — najnowszy tag w momencie budowy (projekt uzywa "Beta"
# jako stalego oznaczenia etapu rozwoju, nie sygnalu niestabilnosci)
# Po buildzie czyscimy cache NuGet i posrednie pliki kompilacji (obj/) -
# nie sa potrzebne w finalnym obrazie, tylko zajmuja miejsce.
RUN git clone --depth 1 --branch 0.9.8-Beta https://github.com/mcmonkeyprojects/SwarmUI.git /workspace/swarmui \
    && cd /workspace/swarmui \
    && dotnet build src/SwarmUI.csproj -c Release \
    && rm -rf /workspace/swarmui/src/obj ~/.nuget/packages /tmp/NuGetScratch

# Backend (polaczenie z ComfyUI z etapu 2, zamiast pobierania wlasnej kopii)
# konfigurujemy w skrypcie startowym (etap: skrypt startowy) - to ustawienie
# uzytkownika/srodowiska, nie czesc samego builda obrazu.

RUN echo "swarmui: 0.9.8-Beta" | tee -a /opt/build-versions.txt

# ==============================================================================
# ETAP 4: InvokeAI — w OSOBNYM, izolowanym srodowisku (koncepcja-i-zasady-
# budowy.md, pkt 4.3): wlasny venv, wlasny Python 3.12, wlasny PyTorch.
# Blad/aktualizacja InvokeAI nie moze wplynac na ComfyUI/SwarmUI i odwrotnie.
# ==============================================================================

# uv — oficjalny, rekomendowany instalator InvokeAI (zarzadza tez wlasnym,
# izolowanym Pythonem 3.12 - "only-managed" - wiec nie potrzebujemy apt
# python3.12 obok python3.11 uzywanego przez ComfyUI)
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:${PATH}"

# InvokeAI v6.9.0 — najnowszy stabilny tag (po v6.9.0rc1-3) zweryfikowany
# w repo. UWAGA: invokeai==6.9.0 wymaga sztywno torch>=2.7.0,<2.8.dev0, a
# indeks cu130 nie ma w ogole wheeli torch w tym zakresie (dopiero 2.9+) -
# uv sam to wychwycil bledem rozwiazywania zaleznosci przy pierwszej probie.
# To srodowisko jest w pelni izolowane (wlasny venv/venv), wiec NIE musi
# uzywac tej samej wersji CUDA co reszta obrazu - cu128 w pelni wspiera
# RTX 4090 i ma wheelе torch 2.7.x wymagane przez ta wersje InvokeAI.
RUN uv venv --relocatable --prompt invoke --python 3.12 --python-preference only-managed \
        /workspace/invokeai/.venv \
    && uv pip install --python /workspace/invokeai/.venv/bin/python \
        invokeai==6.9.0 --torch-backend=cu128 \
    && rm -rf /root/.cache/uv

RUN /workspace/invokeai/.venv/bin/python -c \
        "import importlib.metadata as m; print('invokeai:', m.version('invokeai'))" \
    | tee -a /opt/build-versions.txt

# ==============================================================================
# ETAP 5: Wtyczki ComfyUI (koncepcja-i-zasady-budowy.md, pkt 2.4)
#
# UWAGA: SUPIR jest juz WBUDOWANY w rdzen ComfyUI v0.33.3 (sprawdzone w
# zrodle: comfy/ldm/supir/, ModelPatchLoader + SUPIRPatch w comfy_extras)
# - osobna wtyczka kijai/ComfyUI-SUPIR jest wiec zbedna, celowo pominieta.
# Podobnie ladowanie/zapis obrazu, maski i podstawowy loader LoRA to juz
# rdzen ComfyUI - nie wymagaja osobnych wtyczek.
#
# Ponizsze repo NIE maja tagow wersji (male wtyczki spolecznosciowe, bez
# wersjonowania) - pinujemy wiec do konkretnego commita (sprawdzonego przez
# git ls-remote w dniu builda), a nie do "main"/"master" (koncepcja, pkt 4.2).
# ==============================================================================

# Preprocesory ControlNet (depth/pose/edge) - commit z dnia weryfikacji
RUN git clone https://github.com/Fannovel16/comfyui_controlnet_aux.git \
        /workspace/comfyui/custom_nodes/comfyui_controlnet_aux \
    && cd /workspace/comfyui/custom_nodes/comfyui_controlnet_aux \
    && git checkout e8b689a513c3e6b63edc44066560ca5919c0576e \
    && pip install --break-system-packages -r requirements.txt

# CodeFormer (rekonstrukcja twarzy) - commit z dnia weryfikacji
RUN git clone https://github.com/mav-rik/facerestore_cf.git \
        /workspace/comfyui/custom_nodes/facerestore_cf \
    && cd /workspace/comfyui/custom_nodes/facerestore_cf \
    && git checkout ff4d7a5c102441d8f058dd6135797ffb57b6c6ad \
    && pip install --break-system-packages -r requirements.txt

# GFPGAN (rekonstrukcja twarzy) - commit z dnia weryfikacji
RUN git clone https://github.com/comfyorg/comfyui_gfpgan.git \
        /workspace/comfyui/custom_nodes/comfyui_gfpgan \
    && cd /workspace/comfyui/custom_nodes/comfyui_gfpgan \
    && git checkout 77577e49ae49e59e44098549d8d04ab2cba87fda \
    && pip install --break-system-packages -r requirements.txt

RUN { \
        echo "controlnet_aux: e8b689a"; \
        echo "facerestore_cf: ff4d7a5"; \
        echo "comfyui_gfpgan: 77577e4"; \
    } | tee -a /opt/build-versions.txt
