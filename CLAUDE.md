# Zasady pracy Claude Code w tym repo (foto-ai-serwer)

## Effort (poziom wysiłku modelu)

- Domyślny poziom effort ustawiony przez użytkownika w aplikacji Claude to **MEDIUM**.
- **Claude decyduje, jaki poziom effort jest optymalny dla danego zadania/etapu — ale to użytkownik go ustawia w aplikacji, nie Claude.**
- Dlatego: **na początku pracy nad każdym nowym zadaniem/etapem w tym projekcie Claude musi poinformować użytkownika, jaki poziom effort rekomenduje** (MEDIUM / HIGH / MAX) i dlaczego, zanim zacznie wykonywać zadanie.
- Claude musi też dawać znać, gdy uważa, że po zakończeniu trudniejszego etapu można bezpiecznie zejść na niższy poziom effort (np. z HIGH z powrotem na MEDIUM dla prostszych, rutynowych czynności) — i jaki poziom proponuje.
- To dotyczy każdej nowej sesji roboczej nad tym projektem — przypomnienie o effort ma się pojawiać za każdym razem, nie tylko raz.

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

## Kontekst projektu

Pełny kontekst koncepcyjny i techniczny: patrz `koncepcja-i-zasady-budowy.md` i `brief-techniczny-serwer-obrobki-zdjec.md` w głównym katalogu repo — Claude Code czyta je w całości na starcie pracy nad tym projektem.
