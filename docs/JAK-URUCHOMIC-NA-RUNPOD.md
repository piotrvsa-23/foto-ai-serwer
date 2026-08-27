# Jak uruchomić serwer na RunPod — instrukcja krok po kroku

Zakładam, że umiesz już tworzyć poda na RunPod — ten dokument skupia się na
tym, co jest **specyficzne dla naszego obrazu**: jaki obraz wpisać, jakie
ustawienia, gdzie czytać logi, jak sprawdzić że wszystko działa, i jak
bezpiecznie zakończyć sesję.

**Od v15 obraz zawiera WYŁĄCZNIE InvokeAI** (SwarmUI/ComfyUI zostały
usunięte — patrz komentarz na górze `Dockerfile`).

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

## 2. Ile to będzie trwało

- **RunPod pobiera obraz Docker.** Status poda pokaże coś w stylu "Pulling
  image". Obraz od v15 jest znacznie mniejszy niż wcześniej (bez CUDA
  "devel", ComfyUI, SwarmUI i ich wtyczek) — powinno to być kilka minut.
- **Skrypt startowy** tworzy foldery i od razu uruchamia InvokeAI — to
  sekundy, nie minuty (modele NIE są pobierane automatycznie, patrz punkt 4).

Serwer jest gotowy do pracy, gdy w logach zobaczysz komunikat InvokeAI o
uruchomionym serwerze (patrz punkt 3).

---

## 3. Gdzie czytać logi

W panelu RunPod, na stronie Twojego poda, jest zakładka **"Logs"** — tam
lecą logi kontenera na żywo. Szukaj:

- Linii zaczynających się od `>>> [HH:MM:SS] (+Xs od startu skryptu)` —
  to nasze własne znaczniki: `[1/2]` foldery, `[2/2]` start InvokeAI.
- Po `[2/2]` logi przechodzą w komunikaty samego InvokeAI — szukaj linii
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

**Obraz nie zawiera żadnych modeli** (checkpointy to dziesiątki GB — trzymamy
je poza obrazem, koncepcja-i-zasady-budowy.md pkt 4.4). Za pierwszym
uruchomieniem InvokeAI poprowadzi Cię przez ekran startowy z **wbudowanym
Model Managerem** — stamtąd jednym kliknięciem pobierasz gotowe modele
(np. SD1.5, SDXL, FLUX.1 dev/schnell) prosto z HuggingFace/CivitAI, bez
terminala i bez osobnego skryptu.

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

**Container Disk jest kasowany bezpowrotnie przy Stop i przy Terminate.**
Zanim klikniesz jedno albo drugie:

1. Pobierz na swój komputer wszystko z `/workspace/output/` (przez Web
   Terminal → download, albo dowolny sposób transferu plików z poda).
2. Dopiero potem **Stop** lub **Terminate** poda.

Nie ma żadnego "zapisz i wróć później" — to co nie zostało pobrane, ginie.
To samo dotyczy modeli pobranych przez Model Manager InvokeAI — one też
znikają razem z Container Diskiem i trzeba je ściągnąć ponownie w kolejnej
sesji.

---

## 7. Koszt

Wg kalkulacji z briefu technicznego (sekcja 7): RTX 4090 to ok. **0,39-0,70
€/h** zależnie od typu chmury (Community vs Secure) + drobny koszt Container
Disk proporcjonalny do czasu pracy. Pamiętaj zatrzymać/zterminować poda,
gdy skończysz — płacisz za każdą godzinę, w której pod działa.
