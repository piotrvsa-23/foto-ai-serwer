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

## Monitorowanie buildów CI/CD (KRYTYCZNE, na wyraźną prośbę użytkownika)

Po wyzwoleniu builda (`docker-build-test.yml`) lub pusha na Docker Hub
(`docker-push.yml`) w GitHub Actions, Claude ma **TYLKO**:
1. sprawdzić status na GitHub Actions (build-test przeszedł/padł, push
   wyzwolony poprawnie),
2. dać użytkownikowi jasny, krótki komunikat o tym, co zrobił (jaki tag,
   jaki branch, czy build-test był zielony),
3. **ZATRZYMAĆ SIĘ** — nie planować dalszych automatycznych sprawdzeń
   (`ScheduleWakeup`) samego pusha ani nie sprawdzać Docker Hub.

**NIGDY nie sprawdzać samodzielnie, czy obraz faktycznie wylądował na
Docker Hub** (ani przez zaplanowane przypomnienia, ani przez dodatkowe
zapytania) — to marnuje tokeny/scheduler na coś, co użytkownik i tak sam
monitoruje ręcznie (Docker Hub, RunPod). Wyjątek: użytkownik wprost prosi
o sprawdzenie ("sprawdź czy się wypchnęło", "co z dockerem").

Powód tej zasady: build (`docker-build-test.yml`) TYLKO waliduje, że obraz
się kompiluje — NIE wysyła nic na Docker Hub. Push (`docker-push.yml`)
buduje obraz PONOWNIE od zera i wysyła go — to osobny, wolniejszy krok
(10-20 min), którego wynik nie jest potrzebny Claude'owi do dalszej pracy,
tylko użytkownikowi do testu na RunPod.

## Kontekst projektu

Pełny kontekst koncepcyjny i techniczny: patrz `koncepcja-i-zasady-budowy.md` i `brief-techniczny-serwer-obrobki-zdjec.md` w głównym katalogu repo — Claude Code czyta je w całości na starcie pracy nad tym projektem.
