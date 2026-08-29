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
# na wyrazna prosbe uzytkownika: silnik FLUX zamiast SDXL, do porownania
# jakosci/mozliwosci z CyberRealisticXL. W przeciwienstwie do v04, ZADEN
# checkpoint NIE jest tu zaszyty w obrazie (patrz uzasadnienie nizej) -
# obraz to "goly" InvokeAI, a WSZYSTKIE modele (glowny checkpoint + VAE/T5/
# CLIP/IP-Adapter/ControlNet/upscaler) pobiera automatycznie scripts/start.sh
# przy starcie poda.
#
# HISTORIA DECYZJI (wazne, zeby nie powtorzyc bledu):
# Pierwsza wersja tej galezi zaszywala tu checkpoint
# shauray/flux.1-dev-uncensored-q4 (link podany przez uzytkownika). Po
# realnym tescie na RunPod InvokeAI oznaczyl go jako "Unknown" - niemozliwy
# do wybrania w generowaniu. Przyczyne potwierdzono na 100% (inspekcja
# naglowka pliku .safetensors bezposrednio z HuggingFace, bez pobierania
# calego pliku): to NIE jest surowy checkpoint w formacie BFL/InvokeAI
# (klucze "double_blocks."), tylko model w formacie HuggingFace Diffusers
# (klucze "transformer_blocks.", "x_embedder." itd., config.json z
# "_class_name": "FluxTransformer2DModel") - mimo ze realnie jest
# skwantyzowany bitsandbytes-NF4 (obecne klucze "quant_state.bitsandbytes__nf4"),
# InvokeAI szuka konkretnie tej BFL-owej konwencji nazw i jej tu nie znajduje.
# Diffusers-format wymagalby innej struktury (folder z config.json, nie
# pojedynczy plik) i nie dawalo pewnosci powodzenia bez kolejnego cyklu
# testow na RunPod.
#
# ROZWIAZANIE: zamiast tego uzywamy "Flux Unchained" w formacie GGUF
# (kwantyzacja Q8_0, ~12.7GB, GraydientPlatformAPI/flux-unchained na
# HuggingFace) - format GGUF jest naglosc wspierany przez InvokeAI 6.14.0
# (Main_GGUF_FLUX_Config + FluxGGUFCheckpointModel) i to KONKRETNIE ta
# rodzina modeli ("Flux Unchained") jest wymieniona z nazwy/linku w
# zrodle InvokeAI (invokeai/backend/model_manager/load/model_loaders/flux.py,
# komentarz przy obejsciu bledu ksztaltu img_in.weight: "Example model with
# this issue (Q4_K_M): civitai.com/models/705823/ggufk-flux-unchained-km-quants") -
# najmocniejszy mozliwy sygnal kompatybilnosci (deweloperzy InvokeAI faktycznie
# testowali i naprawiali obsluge tej rodziny plikow). "Unchained" to wariant
# FLUX.1-dev bez wbudowanych ograniczen tresci (odpowiednik "uncensored").
# Q8_0 (nie Q6_K) wybrany pod RTX 4090 (24GB VRAM) - najwyzsza jakosc kwantyzacji
# ktora nadal wygodnie miesci sie w VRAM razem z T5/CLIP/VAE (~18GB razem).
#
# Checkpoint (12.7GB) pobiera sie w RUNTIME (scripts/start.sh), NIE w obrazie -
# ten sam powod co reszta dodatkow (patrz nizej i galaz
# claude/foto-ai-runpod-setup-zzw2vi): CI GitHub Actions ma za malo miejsca
# na dysku na duze pliki (potwierdzone realnym bledem "no space left on
# device" przy probie v03), a 12.7GB to jeszcze wiecej niz to, co tam padlo.
#
# POPRAWKA (sierpien 2026, po kolejnym realnym tescie na RunPod): checkpoint
# byl pierwotnie instalowany przez wewnetrzny downloader InvokeAI (REST API,
# tak jak T5 - patrz scripts/start.sh [4/4]), ale ten downloader wisial bez
# pobrania zadnego bajtu - plik jest skladowany przez HuggingFace w systemie
# "Xet", ktory ma udokumentowana historie problemow w tym projekcie (patrz
# sekcja "v6.14.0_v01" wyzej, identyczny objaw z CyberRealisticXL). Naprawa:
# checkpoint wrocil do zwyklego curl (scripts/start.sh [3/4], razem z
# VAE/IP-Adapter/SwinIR) - dziala niezawodnie dla pojedynczych plikow.
#
# POPRAWKA v03 (28.08.2026): naglowek "Authorization: Bearer $HUGGINGFACE_
# TOKEN" dodany w poprzedniej poprawce dalej NIE eliminowal throttlingu
# (realny test: ~1% w 5 min). Przyczyna dogrzebana do konca: /resolve/main/
# na huggingface.co dla tego pliku (Xet) odpowiada przekierowaniem 307 na
# INNY HOST (us.aws.cdn.hf.co / cdn-lfs*.huggingface.co) - a curl -L domyslnie
# (od wersji 7.58.0, naprawa CVE-2018-1000007) USUWA Authorization przy
# przekierowaniu miedzy hostami. Token trafial wiec tylko do pierwszego,
# przekierowujacego zapytania - samo pobieranie pliku zawsze lecialo bez
# autoryzacji. Naprawiono w scripts/start.sh (hf_curl_auth_args) przez
# dodanie --location-trusted, ktore wymusza zachowanie naglowka po zmianie
# hosta - bezpieczne, bo docelowy host to zawsze infrastruktura CDN samego
# HuggingFace, nie przypadkowa trzecia strona.
#
# POPRAWKA v04 (28.08.2026): --location-trusted NIE przyspieszyl pobierania w
# realnym tescie (dalej ~1.6MB/s w logu RunPod). Root cause dogrzebany do
# konca przez bezposredni trace (curl -v): URL CDN, na ktory przekierowuje
# ten plik, zawiera w parametrach "user_id=public&X-Xet-Cas-Uid=public" - HF
# wydaje PUBLICZNY, anonimowy podpisany link (bo repo jest publiczne),
# NIEZALEZNIE od tego, czy naglowek Authorization dotarl. Token nigdy nie
# mogl przyspieszyc pobierania przez zwykly curl. Naprawa: checkpoint
# pobiera sie teraz przez oficjalna funkcje biblioteki
# huggingface_hub.hf_hub_download (scripts/start.sh,
# download_checkpoint_via_hf_hub), ktora automatycznie wykrywa i uzywa
# dedykowanego klienta "hf_xet" (rownolegle, wieloczesciowe pobieranie -
# dokladnie do tego zaprojektowany protokol/CDN) zamiast pojedynczego
# strumienia curl. To INNY mechanizm niz wczesniej hangujacy wewnetrzny
# downloader InvokeAI (ktory dostawal surowy URL przez REST API, nie
# repo_id+filename przez wlasciwa funkcje biblioteki) - nie powinien miec
# tego samego problemu.
#
# POPRAWKA v05 (29.08.2026, po realnym tescie na RunPod - CHECKPOINT
# POTWIERDZONY: 12.7GB w 83 sekundy, hf_xet dziala doskonale): nowy blad -
# CLIP-L text encoder ladowal sie z bledem "OSError: Repo id must be in the
# form...['.../clip-vit-large-patch14/text_encoder/text_encoder']" przy
# probie uzycia. Przyczyna DOKLADNIE ta sama, co wczesniej zmusila
# przeniesienie T5 na REST API (patrz scripts/start.sh [4/4]): podfolder
# "bfloat16" w repo InvokeAI/clip-vit-large-patch14-text-encoder ma
# DODATKOWY poziom zagniezdzenia ("bfloat16/text_encoder/..."), wiec reczne
# splaszczenie (snapshot_download + shutil.move) zostawialo pliki jeden
# poziom za gleboko - poprzedni komentarz w tym miejscu BLEDNIE zakladal
# (bez realnego testu), ze CLIP-L dziala poprawnie tym mechanizmem. Naprawa:
# CLIP-L przeniesiony do [4/4], na to samo REST API InvokeAI co T5.
#
# POPRAWKA v06 (29.08.2026, EKSPERYMENTALNA - jeszcze niepotwierdzona
# realnym testem): caly start poda trwal ~19 minut, z czego wiekszosc to
# T5-XXL int8 pobierany PRZEZ WEWNETRZNY, WOLNY downloader InvokeAI (REST
# API) - w przeciwienstwie do checkpointu (hf_xet, 83s dla 12.7GB), REST
# API InvokeAI nie uzywa hf_xet. Teoria oparta na realnym sukcesie naprawy
# CLIP-L: poprawna rejestracja zalezy od SPOSOBU instalacji (jawne zrodlo -
# repo_id LUB lokalna sciezka - zawsze poprawnie probuje PODANA sciezke jako
# korzen), nie od tego, skad wziely sie bajty. scripts/start.sh teraz
# NAJPIERW pobiera T5 szybko przez snapshot_download (hf_xet) do lokalnego
# folderu o strukturze identycznej z ta z udanej instalacji REST API, potem
# zleca REST API instalacje z TEJ LOKALNEJ SCIEZKI zamiast z repo_id -
# powinno to dac szybkosc hf_xet przy zachowaniu poprawnej rejestracji. Z
# zabezpieczeniem: jesli szybkie pobieranie sie nie uda, automatyczny powrot
# do sprawdzonego (ale wolniejszego) zrodla siecowego repo_id::subfolder.
# WYMAGA POTWIERDZENIA REALNYM TESTEM NA RUNPOD.
# ==============================================================================

# Dodatkowe modele (glowny checkpoint GGUF, VAE, T5/CLIP encodery, IP-Adapter,
# ControlNet, upscaler) NIE sa zaszywane w obrazie - ten sam wzorzec co
# v6.14.0_v04_CyberRXL_v10 (patrz galaz claude/foto-ai-runpod-setup-zzw2vi,
# uzasadnienie w Dockerfile tamtej galezi: CI GitHub Actions okazalo sie
# zawodne/kruche dla duzych pobieran). scripts/start.sh na TEJ galezi pobiera
# je automatycznie przy kazdym starcie poda - zestaw dobrany pod architekture
# FLUX (inny niz SDXL w v04), patrz komentarze w scripts/start.sh.

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
