# Jak uruchomić serwer na RunPod — instrukcja krok po kroku

Zakładam, że umiesz już tworzyć poda na RunPod — ten dokument skupia się na
tym, co jest **specyficzne dla naszego obrazu**: jaki obraz wpisać, jakie
ustawienia, gdzie czytać logi, jak sprawdzić że wszystko działa, i jak
bezpiecznie zakończyć sesję.

**Od v15 obraz zawiera WYŁĄCZNIE InvokeAI** (SwarmUI/ComfyUI zostały
usunięte — patrz komentarz na górze `Dockerfile`).

**Od v6.14.0_v01_CyberRXL_v10 obraz ma dodatkowo wbudowany na stałe jeden
checkpoint (CyberRealisticXL V10.0 FP16)** — gotowy od razu po starcie, bez
pobierania w UI — oraz automatyczną konfigurację tokenów HuggingFace/Civitai
z Environment Variables RunPod (patrz punkt 1a niżej).

---

## 1. Tworzenie poda — konkretne ustawienia

1. **GPU:** RTX 4090 (24GB VRAM).

2. **Template:** zamiast wybierać gotowy community template, potrzebujesz
   pola do wpisania **własnego obrazu Docker**. W kreatorze poda szukaj
   opcji typu "Custom Container" / "Deploy custom container" / pola
   **"Container Image"** (czasem trzeba kliknąć "Edit Template" albo
   "Change Template" i wybrać "Custom" zamiast wyszukiwać nazwę template'u
   ze społeczności). W to pole wpisujesz dokładnie:

   ```
   piotrvsa/foto-ai-serwer:latest
   ```

   (tag `latest` zawsze wskazuje na najnowszą wersję, którą wypchnęliśmy —
   nie musisz pamiętać numerków wersji typu v1/v2).

3. **Container Disk:** ustaw na **200 GB**.

4. **Volume Disk / Network Volume:** **NIE ustawiaj / zostaw wyłączone.**
   Świadomie tego nie używamy (koncepcja-i-zasady-budowy.md, pkt 8) —
   wszystko jest efemeryczne poza samym obrazem.

5. **Expose HTTP Ports** (czasem nazwane "Expose Ports" albo trzeba dodać
   ręcznie w sekcji portów) — dodaj:

   ```
   9090
   ```

   (9090 = InvokeAI — jedyny port od v15)

6. Kliknij **Deploy**.

---

## 1a. Tokeny HuggingFace / Civitai (opcjonalne, ale zalecane)

W kreatorze poda znajdź sekcję **"Environment Variables"**. Dodaj tam
(klikając ikonę 🔑 przy polu "value", żeby zapisać jako zaszyfrowany
"Secret" — RunPod sam ostrzega, że zwykłe zmienne środowiskowe NIE są
szyfrowane):

| Key | Value |
|---|---|
| `HUGGINGFACE_TOKEN` | Twój token z huggingface.co/settings/tokens |
| `CIVITAI_API_KEY` | Twój klucz z civitai.com → Account settings → API Keys |

Skrypt startowy sam wykryje te zmienne i skonfiguruje oba tokeny przy
każdym starcie poda — nie musisz nic wklejać ręcznie w terminalu. Bez nich
obraz też zadziała, ale pobieranie modeli/LoRA (zwłaszcza z Civitai) może
się nie udać albo być zawodne.

**Nigdy nie wpisuj prawdziwych tokenów w rozmowie z Claude ani w plikach
repozytorium** — to pole w RunPod jest jedynym właściwym miejscem na nie.

---

## 2. Ile to będzie trwało

- **RunPod pobiera obraz Docker.** Status poda pokaże coś w stylu "Pulling
  image". Od `v6.14.0_v01_CyberRXL_v10` obraz jest większy niż w v15 (ma
  wbudowany checkpoint CyberRealisticXL, ~7GB) — pull może potrwać kilka-
  kilkanaście minut zamiast kilku, ale to jednorazowy koszt przy pobieraniu
  obrazu, nie przy każdym starcie poda.
- **Skrypt startowy** tworzy foldery, konfiguruje tokeny (jeśli ustawione)
  i od razu uruchamia InvokeAI — to sekundy. Model CyberRealisticXL jest
  już na miejscu (wbudowany w obraz) i pojawia się w UI automatycznie, bez
  pobierania i bez klikania.

Serwer jest gotowy do pracy, gdy w logach zobaczysz komunikat InvokeAI o
uruchomionym serwerze (patrz punkt 3).

---

## 3. Gdzie czytać logi

W panelu RunPod, na stronie Twojego poda, jest zakładka **"Logs"** — tam
lecą logi kontenera na żywo. Szukaj:

- Linii zaczynających się od `>>> [HH:MM:SS] (+Xs od startu skryptu)` —
  to nasze własne znaczniki: `[1/3]` foldery, `[2/3]` konfiguracja tokenów
  (jeśli ustawione), `[3/3]` start InvokeAI.
- Po `[3/3]` logi przechodzą w komunikaty samego InvokeAI — szukaj linii
  mówiącej, że serwer nasłuchuje (adres z portem 9090). To sygnał, że
  InvokeAI jest gotowe.

**Jeśli coś pójdzie nie tak:** skrypt jest zaprojektowany, żeby przerwać
się od razu z jasnym komunikatem błędu (`set -euo pipefail`) — nie będzie
cichej, mylącej awarii. Skopiuj mi ten fragment logu, jeśli coś się wywali.

---

## 4. Jak sprawdzić, że działa i skąd wziąć modele

Na stronie poda w RunPod, przy uruchomionym podzie, powinien być klikalny
link (albo złóż go ręcznie z ID poda):

```
https://<ID-poda>-9090.proxy.runpod.net
```

Otwórz w zwykłej przeglądarce (Chrome/Firefox na Twoim komputerze) —
powinien pokazać interfejs InvokeAI, nie błąd.

**Obraz ma wbudowany jeden model: CyberRealisticXL V10.0 FP16** — pojawi się
w liście modeli InvokeAI automatycznie, bez pobierania. Każdy kolejny model
(inne checkpointy, LoRA) doinstalowujesz sam przez **wbudowany Model
Manager** — jednym kliknięciem, prosto z HuggingFace/Civitai, bez terminala
i bez osobnego skryptu (tokeny z punktu 1a sprawiają, że to też przebiega
płynnie, bez zawieszek).

**WAŻNE — inny zestaw modeli niż w wersjach v1-v14.** InvokeAI NIE obsługuje
Qwen-Image-Edit, Flux.1 Kontext Dev ani SUPIR (to były modele/węzły
specyficzne dla ComfyUI, usuniętego w v15). Do restauracji/wyostrzania i
edycji zdjęć używasz teraz modeli z ekosystemu InvokeAI (np. FLUX.1, SDXL)
oraz jego wbudowanych narzędzi: **Unified Canvas** (precyzyjna edycja
wybranego fragmentu) i wbudowanej **restauracji twarzy**
(GFPGAN/CodeFormer) oraz **upscalingu** (ESRGAN) — dostępnych bezpośrednio
z poziomu UI, bez dodatkowej instalacji.

**Checklista z briefu (sekcja 9, zaktualizowana pod InvokeAI-only) — warto
przejść po pierwszym uruchomieniu:**
- [ ] InvokeAI się otwiera pod portem 9090
- [ ] `nvidia-smi` w Web Terminal potwierdza widoczność RTX 4090
- [ ] W ustawieniach InvokeAI (albo w logu startowym) widać, że urządzenie
      obliczeniowe to CUDA, nie CPU

---

## 5. Praca ze zdjęciami — upload i download

**Na co dzień NIE potrzebujesz terminala ani SSH.** InvokeAI ma to wbudowane
bezpośrednio w interfejs, w zwykłej przeglądarce:

- **Upload (wgrywanie zdjęcia wejściowego):** przeciągnij i upuść plik w
  odpowiednie pole w UI (np. Unified Canvas), albo kliknij je i wybierz
  plik z dysku — tak jak w każdej stronie internetowej.
- **Download (pobieranie wyniku):** w galerii wyników w UI kliknij obraz i
  pobierz go (przycisk pobierania albo zwykłe "zapisz obraz jako" prawym
  przyciskiem myszy).

To wystarczy do całej codziennej pracy.

**Terminal (Web Terminal / przycisk "Connect" na stronie poda w RunPod —
otwiera się w przeglądarce, NIE trzeba żadnego programu SSH) jest
potrzebny tylko do rzeczy zaawansowanych:** sprawdzenia `nvidia-smi`, albo
masowego przenoszenia wielu plików naraz. Foldery `/workspace/input/` i
`/workspace/output/` istnieją "pod spodem", ale zwykle nie musisz tam
zaglądać ręcznie.

---

## 6. KRYTYCZNE — zanim zamkniesz poda

**Container Disk jest kasowany bezpowrotnie przy Terminate** (Stop w teorii
zachowuje dysk i pozwala wznowić tego samego poda później — ale w praktyce,
sprawdzone doświadczalnie, RunPod czasem po prostu **nie potrafi
wznowić zatrzymanego poda** na tej samej karcie GPU ("Your Pod's GPUs are no
longer available" / "Failed to get mount info for source pod") — wtedy
jedyną drogą jest migracja (jeśli się uda) albo Terminate i postawienie
nowego poda od zera. Traktuj więc Stop jako "prawdopodobnie bezpieczne", nie
"gwarantowane" — i zawsze rób poniższe, zanim klikniesz cokolwiek:

1. Pobierz na swój komputer wszystko z `/workspace/output/` (przez Web
   Terminal → download, albo dowolny sposób transferu plików z poda).
2. Dopiero potem **Stop** lub **Terminate** poda.

To co nie zostało pobrane, może zniknąć bezpowrotnie. Modele/LoRA
doinstalowane ręcznie przez Model Manager (czyli wszystko poza wbudowanym
CyberRealisticXL) też nie przetrwają utraty Container Disku — trzeba je
ściągnąć ponownie w kolejnej sesji/na nowym podzie.

---

## 7. Koszt

Wg kalkulacji z briefu technicznego (sekcja 7): RTX 4090 to ok. **0,39-0,70
€/h** zależnie od typu chmury (Community vs Secure) + drobny koszt Container
Disk proporcjonalny do czasu pracy. Pamiętaj zatrzymać/zterminować poda,
gdy skończysz — płacisz za każdą godzinę, w której pod działa.
