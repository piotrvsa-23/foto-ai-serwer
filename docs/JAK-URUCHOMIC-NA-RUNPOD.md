# Jak uruchomić serwer na RunPod — instrukcja krok po kroku

Zakładam, że umiesz już tworzyć poda na RunPod — ten dokument skupia się na
tym, co jest **specyficzne dla naszego obrazu**: jaki obraz wpisać, jakie
ustawienia, gdzie czytać logi, jak sprawdzić że wszystko działa, i jak
bezpiecznie zakończyć sesję.

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
   ręcznie w sekcji portów) — dodaj oba:

   ```
   7801
   9090
   ```

   (7801 = SwarmUI, 9090 = InvokeAI)

6. Kliknij **Deploy**.

---

## 2. Ile to będzie trwało (dwie fazy, obie normalne, nie panikuj)

- **Faza 1 — RunPod pobiera obraz Docker.** Status poda pokaże coś w stylu
  "Pulling image". Może potrwać od kilku do kilkunastu minut (obraz jest
  duży — CUDA + PyTorch + trzy silniki AI w jednym).
- **Faza 2 — skrypt startowy ściąga modele AI z HuggingFace.** To widać w
  logach (patrz punkt 3 niżej), szacunkowo **15-20 minut** (~44GB modeli).

Dopiero po obu fazach serwer jest gotowy do pracy.

---

## 3. Gdzie czytać logi

W panelu RunPod, na stronie Twojego poda, jest zakładka **"Logs"** — tam
lecą logi kontenera na żywo. Szukaj:

- Linii zaczynających się od `>>> [HH:MM:SS] (+Xs od startu skryptu)` —
  to nasze własne znaczniki: `[1/4]` foldery, `[2/4]` modele (tu zobaczysz
  każdy pobierany plik z paskiem postępu), `[3/4]` start InvokeAI,
  `[4/4]` start SwarmUI.
- Po `[4/4]` logi przechodzą w komunikaty samego SwarmUI — szukaj linii
  mówiącej, że serwer nasłuchuje (coś w stylu "Server started" / adres z
  portem 7801). To sygnał, że SwarmUI (i uruchomiony przez niego ComfyUI)
  są gotowe.
- Log InvokeAI leci osobno do pliku **`/workspace/cache/invokeai.log`**
  wewnątrz kontenera — jeśli chcesz go zobaczyć, otwórz "Web Terminal" /
  "Connect" na stronie poda i wpisz:
  ```
  tail -f /workspace/cache/invokeai.log
  ```

**Jeśli coś pójdzie nie tak:** skrypt jest zaprojektowany, żeby przerwać
się od razu z jasnym komunikatem (np. `BLAD: nie udalo sie pobrac ...`
z dokładnym adresem, który zawiódł) — nie będzie cichej, mylącej awarii.
Skopiuj mi ten fragment logu, jeśli coś się wywali.

---

## 4. Jak sprawdzić, że działa

Na stronie poda w RunPod, przy uruchomionym podzie, powinny być klikalne
linki (albo złóż je ręcznie z ID poda):

- SwarmUI: `https://<ID-poda>-7801.proxy.runpod.net`
- InvokeAI: `https://<ID-poda>-9090.proxy.runpod.net`

Otwórz oba w zwykłej przeglądarce (Chrome/Firefox na Twoim komputerze) —
powinny pokazać interfejs, nie błąd.

**WAŻNE — to NIE jest "jedno UI = jeden model".** Oba interfejsy dają
dostęp do WSZYSTKICH pobranych modeli (Qwen, Flux) jednocześnie — model
wybierasz z listy rozwijanej wewnątrz danego UI, przy każdej generacji.
Różnica między SwarmUI a InvokeAI to sposób pracy, nie model:

- **SwarmUI (port 7801)** — główne, codzienne narzędzie: opis słowny +
  suwaki, całe zdjęcie naraz. Od tego zwykle zaczynasz.
- **InvokeAI (port 9090)** — do precyzyjnej poprawki JEDNEGO wybranego
  fragmentu zdjęcia (np. tylko rękaw, tylko fragment twarzy) — ma Unified
  Canvas do tego. Otwierasz go tylko gdy potrzebujesz punktowej poprawki.

**Checklista z briefu (sekcja 9) — warto przejść po pierwszym uruchomieniu:**
- [ ] SwarmUI i InvokeAI oba się otwierają
- [ ] W SwarmUI: `Server` → `Backends` pokazuje aktywny backend ComfyUI
- [ ] Żadna wtyczka ComfyUI nie pokazuje błędu "IMPORT FAILED"
      (widoczne w logu przy starcie ComfyUI, w tym samym oknie Logs)
- [ ] `nvidia-smi` w Web Terminal potwierdza widoczność RTX 4090

---

## 5. Praca ze zdjęciami — upload i download

**Na co dzień NIE potrzebujesz terminala ani SSH.** Oba UI (SwarmUI i
InvokeAI) mają to wbudowane bezpośrednio w interfejs, w zwykłej
przeglądarce:

- **Upload (wgrywanie zdjęcia wejściowego):** przeciągnij i upuść plik w
  odpowiednie pole w UI (np. pole obrazu wejściowego przy edycji), albo
  kliknij je i wybierz plik z dysku — tak jak w każdej stronie internetowej.
- **Download (pobieranie wyniku):** w galerii wyników w UI kliknij obraz i
  pobierz go (przycisk pobierania albo zwykłe "zapisz obraz jako" prawym
  przyciskiem myszy).

To wystarczy do całej codziennej pracy.

**Terminal (Web Terminal / przycisk "Connect" na stronie poda w RunPod —
otwiera się w przeglądarce, NIE trzeba żadnego programu SSH) jest
potrzebny tylko do rzeczy zaawansowanych:** podejrzenia logu InvokeAI
(punkt 3), sprawdzenia `nvidia-smi`, albo masowego przenoszenia wielu
plików naraz. Foldery `/workspace/input/` i `/workspace/output/` istnieją
"pod spodem" i to tam UI zapisuje/czyta pliki — ale zwykle nie musisz tam
zaglądać ręcznie.

---

## 6. KRYTYCZNE — zanim zamkniesz poda

**Container Disk jest kasowany bezpowrotnie przy Stop i przy Terminate.**
Zanim klikniesz jedno albo drugie:

1. Pobierz na swój komputer wszystko z `/workspace/output/` (przez Web
   Terminal → download, albo dowolny sposób transferu plików z poda).
2. Dopiero potem **Stop** lub **Terminate** poda.

Nie ma żadnego "zapisz i wróć później" — to co nie zostało pobrane, ginie.

---

## 7. Koszt

Wg kalkulacji z briefu technicznego (sekcja 7): RTX 4090 to ok. **0,39-0,70
€/h** zależnie od typu chmury (Community vs Secure) + drobny koszt Container
Disk proporcjonalny do czasu pracy. Pamiętaj zatrzymać/zterminować poda,
gdy skończysz — płacisz za każdą godzinę, w której pod działa.
