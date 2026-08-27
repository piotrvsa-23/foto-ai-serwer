# KONCEPCJA I ZASADY BUDOWY — serwer AI do obróbki zdjęć

Wersja: 1.2 — zaktualizowana o decyzję z v15: rezygnacja z ComfyUI+SwarmUI na rzecz wyłącznie InvokeAI (patrz punkt 2.3a)
Cel dokumentu: dać Claude Code kontekst "dlaczego tak", zasady postępowania i listę błędów z poprzedniego podejścia (instalacja przez Gemini), których trzeba świadomie unikać. Specyfikacja techniczna (co dokładnie zainstalować, ile GB, jakie modele) znajduje się w osobnym pliku `brief-techniczny-serwer-obrobki-zdjec.md`.

**UWAGA (v15):** punkty 2 i 3 poniżej opisują PIERWOTNĄ koncepcję (dwa silniki:
ComfyUI+SwarmUI oraz InvokeAI) i zostają jako historyczny kontekst decyzji.
Od v15 obraz zawiera WYŁĄCZNIE InvokeAI — patrz punkt 2.3a z aktualnym stanem
i uzasadnieniem.

---

## 1. Cel całego projektu

Zbudować środowisko do dwóch rodzajów pracy ze zdjęciami:

1. **Restauracja i wyostrzanie** starych/zeskanowanych/niskiej jakości zdjęć do wersji hi-res, przy zachowaniu wierności oryginałowi.
2. **Edycja zawartości** własnych zdjęć — zmiana ubrania, fryzury, pozy, otoczenia — z zachowaniem tożsamości i podobieństwa osoby na zdjęciu.

Użytkownik nie koduje. Cała logika projektu i decyzje koncepcyjne (co ma robić system, jakie modele, jaka kolejność) są ustalane w rozmowie z Claude (chat), a wykonanie techniczne — budowa obrazu Docker, konfiguracja poda, skrypty — należy do Claude Code.

---

## 2. Filozofia podejścia: NIE budujemy od zera, klocek po klocku

To jest najważniejsza zasada tego projektu. Poprzednie podejście (z Gemini) polegało na ręcznym, krok-po-kroku instalowaniu poszczególnych komponentów bezpośrednio na działającym podzie, bez zamrożonych wersji i bez punktu odniesienia do sprawdzonego zestawu. Efekt: częste awarie, konieczność podmiany modułów w trakcie pracy, niezgodności wersji między kolejnymi instalacjami.

**Zasada na przyszłość:** zaczynamy od istniejących, sprawdzonych przez społeczność szablonów/repozytoriów Docker dla ComfyUI + SwarmUI (dostępne np. jako community templates na RunPod), a nie od pustego systemu operacyjnego. Modyfikujemy i dokładamy do sprawdzonej bazy, zamiast składać wszystko własnoręcznie od pierwszej linijki.

---

## 3. Błędy z poprzedniej instalacji (Gemini) — do świadomego uniknięcia

1. **Brak zamrożonych wersji.** Instalacja pobierała "najnowsze" wersje bibliotek (PyTorch, CUDA, custom nodes) przy każdym uruchomieniu, co prowadziło do niezgodności między modułami, które wcześniej działały razem.
2. **Rozjazdy CUDA/PyTorch.** Różne komponenty wymagały różnych wersji CUDA, co powodowało konflikty i błędy uniemożliwiające start.
3. **Podmienianie modułów w locie.** Gdy coś się wywalało, rozwiązaniem było podmienianie pojedynczych bibliotek/pakietów bez przetestowania całości od nowa — to tworzyło kolejne, trudne do namierzenia niezgodności.
4. **Brak jednego, przetestowanego stanu wyjściowego.** Każda sesja zaczynała się od potencjalnie innego stanu środowiska, więc błędy nie były powtarzalne ani łatwe do zdiagnozowania.
5. **Mieszanie zależności różnych narzędzi w jednym środowisku.** Różne UI/silniki instalowane obok siebie bez izolacji, przez co aktualizacja jednego potrafiła wywrócić drugi.

## 2.3a. DECYZJA v15 — wyłącznie InvokeAI (aktualny stan)

Po zbudowaniu i przetestowaniu wariantu z dwoma silnikami (punkty 2-3 wyżej)
użytkownik zdecydował się pracować wyłącznie w InvokeAI. ComfyUI, SwarmUI i
wszystkie wtyczki ComfyUI zostały usunięte z obrazu w v15. Konsekwencje tej
decyzji, świadomie zaakceptowane:

- Modele/węzły specyficzne dla ComfyUI (Qwen-Image-Edit, Flux.1 Kontext Dev,
  SUPIR) NIE są dostępne — InvokeAI ich nie obsługuje. Zamiast nich: własny
  ekosystem modeli InvokeAI (SD1.5/SDXL/FLUX.1 dev-schnell) plus jego
  wbudowana restauracja twarzy (GFPGAN/CodeFormer) i upscaling (ESRGAN).
- Obraz jest znacznie mniejszy i prostszy (brak CUDA "devel"/nvcc, brak
  .NET/SwarmUI, brak osobnych wtyczek do pinowania) — mniej ruchomych części
  do utrzymania.
- Punkt 4.3 poniżej (izolowany venv InvokeAI) **zostaje w mocy**, ale z innym
  uzasadnieniem niż pierwotnie — patrz komentarz w `Dockerfile` przy instalacji
  InvokeAI: to już nie izolacja od ComfyUI/SwarmUI (ich nie ma), tylko
  podążanie za oficjalnym sposobem instalacji InvokeAI (uv) i unikanie
  ograniczeń "externally managed" systemowego Pythona Ubuntu 22.04.

## 4. Zasady, które temu zapobiegają w tym projekcie

1. **Budujemy obraz Docker raz, testujemy, zamrażamy.** Po zbudowaniu i przetestowaniu obrazu, jego zawartość (wersje CUDA/Python/bibliotek) nie zmienia się samoczynnie przy kolejnych uruchomieniach.
2. **Pinujemy dokładne numery wersji** (CUDA, Python, konkretny tag InvokeAI) zamiast pobierania "latest" przy każdym buildzie.
3. **InvokeAI w osobnym środowisku wirtualnym (venv)** — pierwotnie odizolowanym od ComfyUI/SwarmUI, od v15 (patrz punkt 2.3a) uzasadnionym inaczej: to oficjalny sposób instalacji InvokeAI i higiena wobec systemowego Pythona.
4. **Modele AI (ciężkie pliki wag) trzymane poza obrazem Docker**, dociągane ręcznie przez użytkownika (w InvokeAI: wbudowany Model Manager) z zaufanych źródeł (HuggingFace/CivitAI) — obraz zostaje lekki i stabilny, a modele można aktualizować niezależnie od silnika.
5. **Każda zmiana w obrazie testowana lokalnie przed wypchnięciem na Docker Hub** — nie modyfikujemy "na produkcji" (czyli na działającym podzie, z którego użytkownik akurat korzysta).
6. **Jedno źródło prawdy.** Obraz na Docker Hub jest jedynym miejscem, z którego pod startuje — nie ma równoległych, ręcznie modyfikowanych wersji środowiska.
7. **ComfyUI Manager jako siatka bezpieczeństwa dla wtyczek** — pozwala na szybkie zdiagnozowanie i naprawę pojedynczej wtyczki bez przebudowy całego obrazu.

---

## 5. Definicja sukcesu

Środowisko uznajemy za gotowe, gdy:
- pod startuje z obrazu Docker bez ręcznej interwencji,
- InvokeAI startuje bez błędów i widzi GPU (RTX 4090),
- modele dociągnięte przez Model Manager InvokeAI ładują się poprawnie,
- kolejne uruchomienie tego samego obrazu daje identyczny, przewidywalny efekt.

---

## 7. Dodatkowe lekcje — z wcześniejszego, osobnego projektu (Ollama + Open WebUI + Qwen LLM na tym samym serwerze)

Ten projekt (rozmowa/model językowy) został porzucony na rzecz stacku wyłącznie do obróbki zdjęć — dzięki temu cała pula 24GB VRAM jest dostępna dla modeli graficznych, bez dzielenia się z dużym modelem LLM. Mimo że sam projekt LLM odpadł, z jego przebiegu (dwa odrębne, udokumentowane podejścia z Gemini/ChatGPT) wynika kilka **uniwersalnych zasad bezpieczeństwa i higieny pracy**, które przenosimy wprost do budowy obrazu Docker dla obróbki zdjęć:

1. **Zasada nadrzędna: najpierw dane, potem instalacja/zmiana — nigdy odwrotnie.** W tamtym projekcie doszło do bezpowrotnej utraty ~19GB modelu, bo skrypt "porządkujący" uznał brak jednej konkretnej ścieżki za dowód, że danych nigdzie nie ma, i je skasował. W naszym projekcie modele są wprawdzie efemeryczne (ściągane co sesję), ale ta sama zasada obowiązuje wobec zdjęć użytkownika w `/workspace/input` i `/workspace/output` — żadna operacja kasująca/przenosząca nie jest wykonywana bez wcześniejszego pokazania zawartości i rozmiaru oraz potwierdzenia.

2. **Checklist bezpieczeństwa przed każdą operacją rm/mv/cp na danych użytkownika:** (a) pokazać zawartość katalogu, (b) pokazać rozmiar, (c) sprawdzić czy nie zawiera niezapisanych jeszcze efektów pracy użytkownika, (d) dopiero po potwierdzeniu użytkownika — wykonać operację.

3. **NAJWAŻNIEJSZY BŁĄD Z TAMTEGO PROJEKTU: zmiany wprowadzone "na żywo" w działającym kontenerze, ale niezapisane do obrazu/skryptu startowego, znikają przy restarcie.** To dokładnie problem, który nasze podejście (budowa i zamrożenie obrazu Docker, punkt 4.1) ma z założenia wyeliminować — ale jest to jednocześnie test, który trzeba świadomie wykonać: **każdą poprawkę testujemy przez pełne wdrożenie nowej wersji obrazu, nie przez ręczną edycję w żywym kontenerze**, bo taka edycja tworzy złudne poczucie "działa", które znika przy następnym starcie.

4. **Zawsze weryfikować faktycznie wdrożone wersje po starcie poda, nie ufać nazwie/tagowi obrazu.** W tamtym projekcie template deklarujący "Ollama + Open WebUI" faktycznie zawierał stare, nieplanowane wersje obu komponentów. Po każdym deployu naszego obrazu: sprawdzić realne wersje CUDA/Python/ComfyUI/SwarmUI/InvokeAI, nie zakładać, że skoro build przebiegł bez błędu, to wersje się zgadzają.

5. **Jedna aktywna instalacja danego narzędzia na raz.** W tamtym projekcie równoległe instalacje tej samej aplikacji w różnych katalogach prowadziły do niejednoznaczności, która instalacja faktycznie jest używana (objaw: karta GPU "niewidoczna" dla programu mimo fizycznej obecności). Rozdzielenie ComfyUI/SwarmUI/InvokeAI opisane w punkcie 4.3 ma temu zapobiec — ale zasada obowiązuje też przy każdej aktualizacji: nie instalować nowej wersji obok starej "na wszelki wypadek".

6. **Backup/poprzednia wersja obrazu zostaje aż do pełnego potwierdzenia działania nowej** (GPU widoczne, modele się ładują, oba UI startują) — kasujemy dopiero po tym potwierdzeniu, nie wcześniej.

---

## 8. Co NIE jest częścią tego etapu

- Network Volume (świadomie pominięty — patrz brief techniczny, sekcja kosztów).
- Wideo (rozważane informacyjnie na przyszłość, nie wchodzi w zakres bieżącej budowy).
- Trenowanie własnych modeli/LoRA — na tym etapie korzystamy wyłącznie z gotowych, gotowych do pobrania wag.
- Ollama/Open WebUI/model językowy (Qwen LLM) — porzucony osobny projekt, patrz punkt 7.
