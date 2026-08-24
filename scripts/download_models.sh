#!/usr/bin/env bash
# Pobiera modele AI z HuggingFace do wewnetrznego folderu models/ ComfyUI.
# Modele NIE sa czescia obrazu Docker (brief-techniczny, sekcja 2/3) -
# sciagane od nowa przy kazdym starcie poda. Idempotentny: pomija plik,
# jesli juz istnieje (przydatne przy restarcie skryptu w tej samej sesji).
#
# UWAGA (Claude Code, sierpien 2026): sciezki ponizej zweryfikowane przez
# wyszukiwanie/krzyzowe potwierdzenie wielu zrodel, NIE przez bezposrednie
# pobranie z huggingface.co - ten host jest zablokowany w sesji, w ktorej
# powstal ten skrypt. Pierwsze realne uruchomienie na RunPod jest wiec
# faktycznym testem tych sciezek. Jesli ktorys download zwroci 404,
# sprawdz aktualna nazwe pliku na stronie repo i popraw ponizej.

set -euo pipefail

COMFY_MODELS="/workspace/comfyui/models"

download() {
    local repo="$1" path="$2" dest="$3" rename="${4:-}"
    local url="https://huggingface.co/${repo}/resolve/main/${path}"
    local out="${dest}/${rename:-$(basename "$path")}"
    mkdir -p "$dest"
    if [ -f "$out" ]; then
        echo "[pomijam - juz istnieje] $out"
        return 0
    fi
    echo "[pobieram] ${repo}/${path} -> ${out}"
    if ! wget --tries=3 --timeout=60 --show-progress \
            --header="User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36" \
            -O "${out}.part" "$url"; then
        rm -f "${out}.part"
        echo "BLAD: nie udalo sie pobrac ${url}" >&2
        echo "Sprawdz recznie na https://huggingface.co/${repo}/tree/main - nazwa pliku mogla sie zmienic." >&2
        exit 1
    fi
    mv "${out}.part" "$out"
}

echo "=== Qwen-Image-Edit-2511 (FP8) ==="
download "Comfy-Org/Qwen-Image-Edit_ComfyUI" "split_files/diffusion_models/qwen_image_edit_2511_fp8mixed.safetensors" "${COMFY_MODELS}/diffusion_models"
download "Comfy-Org/Qwen-Image_ComfyUI" "split_files/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors" "${COMFY_MODELS}/text_encoders"
download "Comfy-Org/Qwen-Image_ComfyUI" "split_files/vae/qwen_image_vae.safetensors" "${COMFY_MODELS}/vae"

echo "=== Flux.1 Kontext Dev (FP8) ==="
download "Comfy-Org/flux1-kontext-dev_ComfyUI" "split_files/diffusion_models/flux1-dev-kontext_fp8_scaled.safetensors" "${COMFY_MODELS}/diffusion_models"
# UWAGA (sierpien 2026, naprawa 404): repo flux1-kontext-dev_ComfyUI NIE
# zawiera folderu vae (tylko diffusion_models) - bledna sciezka z pierwszej
# wersji skryptu, nie zmiana na HF. Flux Kontext Dev dzieli ten sam VAE co
# reszta rodziny Flux - pobieramy z black-forest-labs/FLUX.1-schnell
# (licencja Apache 2.0, bez logowania/gate, w przeciwienstwie do FLUX.1-dev).
download "black-forest-labs/FLUX.1-schnell" "ae.safetensors" "${COMFY_MODELS}/vae"
download "comfyanonymous/flux_text_encoders" "clip_l.safetensors" "${COMFY_MODELS}/text_encoders"
download "comfyanonymous/flux_text_encoders" "t5xxl_fp8_e4m3fn_scaled.safetensors" "${COMFY_MODELS}/text_encoders"

echo "=== SUPIR (finalne wyostrzenie/upscaling) ==="
download "Kijai/SUPIR_pruned" "SUPIR-v0Q_fp16.safetensors" "${COMFY_MODELS}/model_patches"
download "Kijai/SUPIR_pruned" "SUPIR-v0F_fp16.safetensors" "${COMFY_MODELS}/model_patches"

echo "=== Rekonstrukcja twarzy (GFPGAN + CodeFormer) ==="
# Oficjalne wydania GitHub (nie HuggingFace) - stabilniejsze, autorytatywne zrodlo.
mkdir -p "${COMFY_MODELS}/face_restoration"
if [ ! -f "${COMFY_MODELS}/face_restoration/GFPGANv1.4.pth" ]; then
    echo "[pobieram] GFPGANv1.4.pth"
    wget --tries=3 --timeout=60 -q --show-progress -O "${COMFY_MODELS}/face_restoration/GFPGANv1.4.pth" \
        "https://github.com/TencentARC/GFPGAN/releases/download/v1.3.4/GFPGANv1.4.pth"
else
    echo "[pomijam - juz istnieje] ${COMFY_MODELS}/face_restoration/GFPGANv1.4.pth"
fi
mkdir -p "${COMFY_MODELS}/facerestore_models"
if [ ! -f "${COMFY_MODELS}/facerestore_models/codeformer.pth" ]; then
    echo "[pobieram] codeformer.pth"
    wget --tries=3 --timeout=60 -q --show-progress -O "${COMFY_MODELS}/facerestore_models/codeformer.pth" \
        "https://github.com/sczhou/CodeFormer/releases/download/v0.1.0/codeformer.pth"
else
    echo "[pomijam - juz istnieje] ${COMFY_MODELS}/facerestore_models/codeformer.pth"
fi

echo "=== LoRA (Lightning / przyspieszajace - skrocenie liczby krokow) ==="
# Qwen-Image-Edit-2511-Lightning - dedykowana dla naszej dokladnej wersji
# Qwen (2511), 4 kroki zamiast ~40 (lightx2v/ModelTC, oficjalne repo autorow
# dystylacji, wprost dopasowane do naszej pinowanej wersji modelu).
download "lightx2v/Qwen-Image-Edit-2511-Lightning" "Qwen-Image-Edit-2511-Lightning-4steps-V1.0-bf16.safetensors" "${COMFY_MODELS}/loras"
# FLUX.1-Turbo-Alpha - LoRA dla bazowego Flux.1-dev, potwierdzona kompatybilnosc
# z Kontext-dev przez sam black-forest-labs (dyskusja #19 w ich repo). Wybrana
# zamiast mniejszych, mniej znanych "Kontext-Lightning" forkow spolecznosci -
# alimama-creative to uznane, sprawdzone zrodlo LoRA przyspieszajacych Flux.
# Plik w repo nazywa sie ogolnie "diffusion_pytorch_model.safetensors" -
# zapisujemy pod czytelniejsza nazwa (funkcja download() to obsluguje bez
# psucia idempotencji przy kolejnych uruchomieniach).
download "alimama-creative/FLUX.1-Turbo-Alpha" "diffusion_pytorch_model.safetensors" "${COMFY_MODELS}/loras" "flux1-turbo-alpha.safetensors"

echo "=== Gotowe. Rozmiar /workspace/comfyui/models: ==="
du -sh "${COMFY_MODELS}" 2>/dev/null || true
