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
RUN git clone --depth 1 --branch 0.9.8-Beta https://github.com/mcmonkeyprojects/SwarmUI.git /workspace/swarmui \
    && cd /workspace/swarmui \
    && dotnet build src/SwarmUI.csproj -c Release

# Backend (polaczenie z ComfyUI z etapu 2, zamiast pobierania wlasnej kopii)
# konfigurujemy w skrypcie startowym (etap: skrypt startowy) - to ustawienie
# uzytkownika/srodowiska, nie czesc samego builda obrazu.

RUN echo "swarmui: 0.9.8-Beta" | tee -a /opt/build-versions.txt
