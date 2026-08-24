# Zasady pracy Claude Code w tym repo (foto-ai-serwer)

## Effort (poziom wysiłku modelu)

- Domyślny poziom effort ustawiony przez użytkownika w aplikacji Claude to **MEDIUM**.
- **Claude decyduje, jaki poziom effort jest optymalny dla danego zadania/etapu — ale to użytkownik go ustawia w aplikacji, nie Claude.**
- Dlatego: **na początku pracy nad każdym nowym zadaniem/etapem w tym projekcie Claude musi poinformować użytkownika, jaki poziom effort rekomenduje** (MEDIUM / HIGH / MAX) i dlaczego, zanim zacznie wykonywać zadanie.
- Claude musi też dawać znać, gdy uważa, że po zakończeniu trudniejszego etapu można bezpiecznie zejść na niższy poziom effort (np. z HIGH z powrotem na MEDIUM dla prostszych, rutynowych czynności) — i jaki poziom proponuje.
- To dotyczy każdej nowej sesji roboczej nad tym projektem — przypomnienie o effort ma się pojawiać za każdym razem, nie tylko raz.

## Kontekst projektu

Pełny kontekst koncepcyjny i techniczny: patrz `koncepcja-i-zasady-budowy.md` i `brief-techniczny-serwer-obrobki-zdjec.md` w głównym katalogu repo — Claude Code czyta je w całości na starcie pracy nad tym projektem.
