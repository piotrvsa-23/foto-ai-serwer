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
FROM nvidia/cuda:13.0.3-cudnn-devel-ubuntu22.04

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
