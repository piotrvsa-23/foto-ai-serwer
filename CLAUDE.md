# Zasady pracy Claude Code w tym repo (foto-ai-serwer)

## Effort (poziom wysiłku modelu)

- Domyślny poziom effort ustawiony przez użytkownika w aplikacji Claude to **MEDIUM**.
- **Claude decyduje, jaki poziom effort jest optymalny dla danego zadania/etapu — ale to użytkownik go ustawia w aplikacji, nie Claude.**
- Dlatego: **na początku pracy nad każdym nowym zadaniem/etapem w tym projekcie Claude musi poinformować użytkownika, jaki poziom effort rekomenduje** (MEDIUM / HIGH / MAX) i dlaczego, zanim zacznie wykonywać zadanie.
- Claude musi też dawać znać, gdy uważa, że po zakończeniu trudniejszego etapu można bezpiecznie zejść na niższy poziom effort (np. z HIGH z powrotem na MEDIUM dla prostszych, rutynowych czynności) — i jaki poziom proponuje.
- To dotyczy każdej nowej sesji roboczej nad tym projektem — przypomnienie o effort ma się pojawiać za każdym razem, nie tylko raz.
- **KRYTYCZNE (twarda zasada, złamana raz — więcej nie może się powtórzyć):** samo napisanie rekomendacji poziomu effort ("rekomenduję HIGH") NIE oznacza zgody na jego użycie. Po wypowiedzeniu rekomendacji Claude ma **natychmiast się zatrzymać** i poczekać na wyraźne potwierdzenie użytkownika (np. "masz HIGH", "ok", "zgoda") — dopiero wtedy kontynuować pracę na tym poziomie. Nigdy nie kontynuować "po cichu" na zarekomendowanym-ale-niepotwierdzonym poziomie, licząc że użytkownik to zaakceptuje retroaktywnie. Użytkownik nie ma obowiązku pilnować na bieżąco każdej odpowiedzi Claude, żeby to wymusić — to Claude ma się zatrzymywać sam z siebie.

## Auto-aktualizacje wbudowane w narzędzia (KRYTYCZNE)

Wiele narzędzi (np. SwarmUI z jego backendem ComfyUI Self-Starting) ma
domyślnie WŁĄCZONE automatyczne aktualizowanie się (np. `git pull`) przy
każdym starcie — co bezpośrednio łamie zasadę zamrożonych wersji z pkt 4.2
`koncepcja-i-zasady-budowy.md` i mogłoby przy każdym starcie poda po cichu
podmieniać przetestowane wersje na nieprzetestowane.

**Zasada:** dla KAŻDEGO modułu, który ma własny mechanizm auto-loadowania/
auto-update przy starcie (SwarmUI, ComfyUI-Manager, InvokeAI, wtyczki itd.),
Claude musi sprawdzić w kodzie źródłowym (nie tylko w dokumentacji — bywa
niepełna/nieaktualna) domyślne ustawienia dotyczące automatycznych aktualizacji
i jawnie je wyłączyć/zablokować w konfiguracji zapisanej w obrazie. Dotyczy to
każdego etapu budowy, nie tylko SwarmUI — to sprawdzony, powtarzalny krok
weryfikacyjny, nie jednorazowa poprawka.

## Diagnostyka niekompatybilnych modeli (KRYTYCZNE, restrykcyjne)

**Kontekst incydentu (sierpień 2026, flux.1_v01):** Claude znalazł prawdziwą
przyczynę, dla której checkpoint `shauray/flux.1-dev-uncensored-q4` ładował
się w InvokeAI jako "Unknown" (inspekcja nagłówka pliku `.safetensors`
bezpośrednio z HuggingFace, bez pobierania całego pliku — solidna, poprawna
diagnoza). Ale przy szukaniu ZASTĘPCZEGO modelu Claude zadowolił się
płytkim, ogólnym wyszukiwaniem w sieci (`WebSearch` po ogólne frazy typu
"uncensored FLUX GGUF") i nie sprawdził najbardziej wiarygodnego źródła,
które już miał otwarte: kodu źródłowego samego InvokeAI (już sklonowanego
lokalnie), gdzie w pliku loadera FLUX (`flux.py`) był wprost zostawiony
przez deweloperów komentarz z nazwą i linkiem do KONKRETNEGO, znanego i
przetestowanego przez nich modelu ("Flux Unchained", link do Civitai) wraz
z kodem naprawiającym błąd jego ładowania. To dowód dużo mocniejszy niż
cokolwiek, co może zwrócić ogólne wyszukiwanie w sieci — a użytkownik
musiał o tę konkretną nazwę modelu dopytać osobno (przez inne narzędzie,
ChatGPT), zanim Claude na nią wpadł. Ten błąd (zatrzymanie się na
pierwszym "wystarczającym" wyjaśnieniu zamiast dalszego, dogłębnego
poszukiwania NAJLEPSZEGO rozwiązania) nie może się powtórzyć.

**Zasada (obowiązuje przy KAŻDYM problemie z niekompatybilnością/nierozpoznawaniem
modelu przez InvokeAI, ComfyUI, SwarmUI czy inne narzędzie w tym projekcie):**

1. **Ustalenie przyczyny to dopiero połowa zadania.** Samo trafne
   zdiagnozowanie "dlaczego coś nie działa" nie kończy pracy — drugą,
   równie ważną połową jest znalezienie NAJLEPSZEGO, potwierdzonego
   rozwiązania, a nie pierwszego, które "powinno zadziałać".
2. **Kod źródłowy narzędzia jest źródłem prawdy wyższego rzędu niż
   wyszukiwanie w sieci.** Jeśli repo narzędzia (InvokeAI, ComfyUI,
   SwarmUI itd.) jest już sklonowane lokalnie (albo da się sklonować),
   Claude MUSI przeszukać je pod kątem:
   - twardo zakodowanych nazw modeli, linków (Civitai/HuggingFace) i
     komentarzy w loaderach/probe'rach — deweloperzy często zostawiają
     ślady konkretnych, przetestowanych przez nich przypadków (np.
     obejścia błędów kształtu tensora, specjalne aliasy kluczy) właśnie
     przy okazji wsparcia dla konkretnego, popularnego pliku modelu;
   - listy "starter models"/wbudowanych presetów (jeśli istnieją) — to
     zbiór modeli GWARANTOWANIE kompatybilnych, z gotowym dokładnym
     stringiem źródła (repo_id, subfolder, plik);
   - klas/funkcji odpowiedzialnych za rozpoznawanie formatu (probe/config
     classes) — żeby zrozumieć DOKŁADNIE jakiej struktury/kluczy/formatu
     narzędzie oczekuje, zamiast zgadywać na podstawie opisu modelu na
     HuggingFace/Civitai.
3. **Nie kończyć poszukiwań na pierwszym pasującym trafieniu.** Nawet po
   znalezieniu jednej wiarygodnej opcji, jeśli to możliwe bez nadmiernego
   kosztu, sprawdzić czy istnieje lepsza (wyższa jakość, lepiej
   udokumentowana zgodność, aktywniej wspierana) — i przedstawić
   użytkownikowi opcje z uczciwą oceną pewności każdej z nich, tak jak
   przy oznaczaniu "potwierdzone vs niepotwierdzone" powyżej.
4. **Weryfikować twierdzenia z zewnętrznych źródeł (w tym z innych
   modeli AI jak ChatGPT/Gemini, z forów, z opisów modeli) zanim się na
   nich oprze** — sprawdzić je względem faktycznego kodu źródłowego
   narzędzia, a nie przyjmować za pewnik. Jeśli się nie zgadzają z kodem
   źródłowym, jawnie to zakomunikować użytkownikowi (tak jak przy
   sprostowaniu błędnej sugestii Gemini co do ścieżki repo T5 w tym
   samym incydencie).
5. Gdy plik modelu jest dostępny do pobrania, a nie ma pewności co do
   jego wewnętrznego formatu/struktury kluczy tensora — **zweryfikować to
   bezpośrednio przed wdrożeniem**, tanim sposobem (np. odczyt samego
   nagłówka `.safetensors`/metadanych przez HTTP Range request, bez
   pobierania całego pliku) zamiast zakładać zgodność na podstawie samej
   nazwy/opisu modelu. Jeśli środowisko sesji ma zablokowany bezpośredni
   dostęp do hosta z plikiem (np. polityka egress), wykorzystać do tego
   zewnętrzny runner z pełnym dostępem do sieci (np. tymczasowy,
   jednorazowy workflow GitHub Actions), tak jak zrobiono w tym incydencie.

## Kontekst projektu

Pełny kontekst koncepcyjny i techniczny: patrz `koncepcja-i-zasady-budowy.md` i `brief-techniczny-serwer-obrobki-zdjec.md` w głównym katalogu repo — Claude Code czyta je w całości na starcie pracy nad tym projektem.
