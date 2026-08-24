# BRIEF TECHNICZNY — Serwer AI do obróbki zdjęć (RunPod + Docker)

Wersja: 1.1 — dodano sekcję 9 (weryfikacja po wdrożeniu)
Cel dokumentu: precyzyjna specyfikacja dla Claude Code do zbudowania obrazu Docker i konfiguracji poda na RunPod. To jest dokument "co i jak", nie "dlaczego" — kontekst koncepcyjny znajduje się w osobnym pliku `koncepcja-i-zasady-budowy.md`.

---

## 1. Infrastruktura (RunPod)

| Parametr | Wartość |
|---|---|
| GPU | RTX 4090, 24GB VRAM |
| RAM (pamięć operacyjna poda) | min. 32 GB |
| Container Disk | 200 GB |
| Network Volume | BRAK — nieużywany w tej koncepcji |
| Tryb pracy | pod uruchamiany na sesję robocza, terminate po każdej sesji |
| CUDA | 12.8 (wsparcie RTX 4090 i nowszych kart) |
| Python | 3.11 |

**Zasada nadrzędna:** nic nie jest trwałe poza samym obrazem Docker. Modele AI są ściągane od nowa przy każdym starcie poda. Zdjęcia wejściowe/wyjściowe muszą zostać ręcznie pobrane na komputer użytkownika PRZED zamknięciem/terminate poda — Container Disk jest kasowany bezpowrotnie przy stopie/terminate.

---

## 2. Zawartość STAŁEGO obrazu Docker (budowany raz, hostowany na Docker Hub)

### 2.1 System i zależności
- Python 3.11
- CUDA 12.8 + odpowiadający build PyTorch
- pip z flagą `--break-system-packages` gdzie wymagane

### 2.2 Silnik generacyjny
- ComfyUI (najnowsza stabilna wersja, backend pod obiema nakładkami UI)
- ComfyUI-Manager

### 2.3 Nakładki UI (obie na stałe w obrazie)
- **SwarmUI** — główna nakładka codziennej pracy: prompt tekstowy + suwaki parametrów, bez węzłów. Działa na tym samym backendzie ComfyUI.
- **InvokeAI** — druga nakładka, z Unified Canvas do precyzyjnej edycji wybranego fragmentu zdjęcia (np. tylko rękaw, tylko fragment twarzy). **Instalowana w osobnym, izolowanym środowisku wirtualnym (venv)**, żeby jej zależności nie kolidowały z ComfyUI/SwarmUI.

### 2.4 Wtyczki/węzły ComfyUI (zaszyte na stałe w obrazie)
- ComfyUI-SUPIR (węzeł restauracji/wyostrzania)
- Węzły GFPGAN i CodeFormer (rekonstrukcja twarzy)
- Podstawowe węzły pomocnicze: ładowanie/zapis obrazu, maski, ControlNet (depth/pose/edge)
- Węzeł do LoRA (loader + obsługa Lightning LoRA)

### 2.5 Skrypt startowy (uruchamiany automatycznie przy starcie poda)
Zadania skryptu:
1. Sprawdzić/ściągnąć modele z listy w punkcie 3 (jeśli nie istnieją lokalnie w danej sesji).
2. Uruchomić SwarmUI na porcie domyślnym.
3. Udostępnić dostęp do InvokeAI na osobnym porcie.
4. Utworzyć strukturę folderów z punktu 4.

---

## 3. Modele AI — ściągane przy KAŻDYM starcie poda (nie są częścią obrazu)

| Model | Rola | Format/kwantyzacja | Rozmiar | Źródło |
|---|---|---|---|---|
| Qwen-Image-Edit-2511 | zmiana pozy, precyzyjne edycje trudnych fragmentów, natywny ControlNet | FP8 | ~20 GB | HuggingFace |
| Flux.1 Kontext Dev | zmiana ubrania/fryzury/tła, najlepsze zachowanie tożsamości twarzy | FP8/GGUF | ~17 GB | HuggingFace (licencja niekomercyjna) |
| SUPIR | finalne wyostrzenie/upscaling do hi-res | — | ~6 GB | HuggingFace/GitHub |
| GFPGAN + CodeFormer | rekonstrukcja twarzy na starych/słabych zdjęciach | — | <1 GB | GitHub |
| LoRA (Lightning / przyspieszające) | skrócenie liczby kroków generowania (np. 8 zamiast 20-30) | — | ~5 GB | HuggingFace/CivitAI |

**Suma modeli: ~49 GB**

---

## 4. Struktura folderów na Container Disk (200GB)

```
/workspace/
├── models/              (~49 GB — punkt 3)
├── input/                (zdjęcia wejściowe użytkownika, ~20 GB zapasu)
├── output/               (zdjęcia gotowe, do pobrania przed stopem, ~20 GB zapasu)
├── comfyui/              (silnik + wtyczki)
├── swarmui/
├── invokeai/             (osobny venv)
└── cache/                (~20 GB robocze)
```
Wolny zapas na 200GB: ~85 GB.

---

## 5. Kolejność pracy (workflow) — rekomendowany łańcuch etapów

Dla edycji łączącej zmianę pozy + ubrania + tła (najbardziej złożony przypadek):

1. **Zmiana pozy** — Qwen-Image-Edit + referencyjny szkielet pozy (ControlNet OpenPose)
2. **Zmiana ubrania** — Flux.1 Kontext Dev
3. **Zmiana tła/otoczenia** — Flux.1 Kontext Dev
4. **Finalne wyostrzenie/upscaling** — SUPIR (zawsze na końcu, tryb tiled ze względu na 24GB VRAM)

Dla czystej restauracji starych/skanowanych zdjęć (bez zmian treści):
1. Naprawa uszkodzeń fizycznych (rysy/kurz/mora) — Qwen-Image-Edit
2. Rekonstrukcja twarzy — GFPGAN/CodeFormer
3. Finalne wyostrzenie — SUPIR

Każdy etap: zapisz wynik jako plik obrazu → użyj go jako wejście do kolejnego etapu w innym modelu, jeśli ten model lepiej radzi sobie z danym zadaniem.

---

## 6. Kiedy używać której nakładki UI

| Sytuacja | Nakładka |
|---|---|
| Edycja całościowa, opis słowny + suwaki | SwarmUI |
| Precyzyjna poprawka jednego, wybranego fragmentu zdjęcia | InvokeAI (Unified Canvas) |

---

## 7. Kalkulacja kosztów (odniesienie)

20h pracy/miesiąc, 200GB Container Disk:

| | Secure Cloud (0,70€/h) | Community Cloud (0,39€/h) |
|---|---|---|
| GPU 4090 × 20h | 14,00 € | 7,80 € |
| Container Disk 200GB (proporcjonalnie do czasu pracy) | ~0,49 € | ~0,49 € |
| **RAZEM/miesiąc** | **~14,49 €** | **~8,29 €** |

---

## 8. Cykl jednej sesji roboczej

1. Odpalić poda z gotowym obrazem Docker (Docker Hub).
2. Skrypt startowy ściąga modele (~15-20 min).
3. Wgrać zdjęcia do `/workspace/input/`.
4. Pracować w SwarmUI i/lub InvokeAI.
5. **Pobrać zawartość `/workspace/output/` na komputer użytkownika.**
6. Terminate poda.

---

## 9. Weryfikacja po wdrożeniu (obowiązkowa, nie opcjonalna)

Wyniesione z doświadczeń wcześniejszego, osobnego projektu — nazwa obrazu/template'u sama w sobie nie jest dowodem, że zawiera to, co powinna. Po każdym starcie poda z obrazu (a zwłaszcza po pierwszym uruchomieniu nowej wersji obrazu) sprawdzić:

- [ ] Rzeczywista wersja CUDA i Python w kontenerze zgadza się z punktem 1 (12.8 / 3.11)
- [ ] `nvidia-smi` / odpowiednik w ComfyUI potwierdza widoczność RTX 4090 (a nie "brak urządzenia" mimo fizycznej obecności karty)
- [ ] Modele z punktu 3 wylądowały w oczekiwanej ścieżce `/workspace/models/`, a nie w domyślnej, "ukrytej" lokalizacji danego narzędzia
- [ ] SwarmUI i InvokeAI startują jednocześnie, bez konfliktu portów/zależności
- [ ] Żadna wtyczka ComfyUI nie zgłasza błędu "IMPORT FAILED"

Każda poprawka do obrazu jest testowana przez **pełne, nowe wdrożenie obrazu** (nie przez ręczną edycję plików w już działającym kontenerze) — ręczna, niezapisana zmiana w żywym kontenerze znika przy kolejnym starcie i tworzy złudne poczucie, że problem jest rozwiązany.
