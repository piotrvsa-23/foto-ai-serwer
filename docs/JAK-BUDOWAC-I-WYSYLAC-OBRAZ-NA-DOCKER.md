# Jak samodzielnie sprawdzić build i wypchnąć obraz na Docker Hub (GitHub Actions)

Ten dokument opisuje krok po kroku, jak **bez Claude** sprawdzić, czy zmiana
w kodzie zbudowała się poprawnie, i jak samodzielnie wypchnąć gotowy obraz
na Docker Hub. Przydaje się, gdy Claude wyśle build do zbudowania, ale
zabraknie Ci limitu/tokenów, zanim zdąży sam sprawdzić wynik i zrobić push.

Wszystko dzieje się **w przeglądarce**, na stronie GitHub — nie potrzebujesz
terminala ani żadnych dodatkowych narzędzi.

---

## Jak to działa (w skrócie)

W tym repo są dwa osobne mechanizmy (pliki w `.github/workflows/`):

1. **"Test builda obrazu Docker"** (`docker-build-test.yml`) — buduje obraz
   TYLKO żeby sprawdzić, czy się buduje bez błędów. **Nie wysyła nic na
   Docker Hub.** Uruchamia się **automatycznie** po każdym pushu zmian do
   `Dockerfile` lub `scripts/`.
2. **"Wypchnij obraz na Docker Hub"** (`docker-push.yml`) — buduje obraz
   PONOWNIE i tym razem **wysyła go na Docker Hub** pod wybranym tagiem.
   Uruchamia się **WYŁĄCZNIE ręcznie** — nigdy automatycznie. To świadome
   zabezpieczenie: nic nie trafia na Docker Hub bez wyraźnego kliknięcia.

Dlatego kolejność zawsze jest taka: **najpierw sprawdź, czy test builda
przeszedł (krok 1), dopiero potem ręcznie wypchnij obraz (krok 2).**

---

## Krok 1: Jak sprawdzić, czy build się udał

1. Wejdź na: **`https://github.com/piotrvsa-23/foto-ai-serwer/actions`**
2. Zobaczysz listę uruchomień (workflow runs), od najnowszego na górze.
   Każdy wiersz ma:
   - **nazwę** (np. "Test builda obrazu Docker"),
   - **tytuł** (zwykle treść commita, który to wywołał),
   - **ikonę statusu** po lewej stronie nazwy:
     - 🟢 **zielony ptaszek** = sukces, build przeszedł bez błędów,
     - 🔴 **czerwony X** = build padł,
     - 🟡 **żółte kółko (kręci się)** = wciąż trwa, jeszcze poczekaj,
   - **nazwę brancha** (gałęzi) — ważne, żeby sprawdzać właściwy branch:
     - `claude/foto-ai-runpod-setup-zzw2vi` = obraz **Cyber**
       (CyberRealisticXL),
     - `flux-v01` = obraz **Flux**.
3. Znajdź na liście najnowszy wiersz z nazwą **"Test builda obrazu Docker"**
   na branchu, który Cię interesuje.
4. **Jeśli zielony ptaszek** → build przeszedł, możesz przejść do **Kroku 2**
   (wypchnięcie na Docker Hub).
5. **Jeśli czerwony X** → kliknij w ten wiersz, żeby zobaczyć szczegóły:
   - Otworzy się strona z listą kroków (np. "Checkout repo", "Zbuduj obraz").
   - Krok, który padł, ma czerwoną ikonę i jest **rozwinięty automatycznie**
     — przewiń w dół, żeby zobaczyć czerwony tekst błędu (zwykle na samym
     końcu logu tego kroku).
   - Skopiuj ten fragment błędu i wklej go do Claude w kolejnej sesji, żeby
     zdiagnozować i naprawić.

**Alternatywa (szybszy podgląd bez wchodzenia w środek):** najedź kursorem
na kolorową kropkę/ikonę przy commicie na liście commitów repo
(`https://github.com/piotrvsa-23/foto-ai-serwer/commits/<nazwa-brancha>`)
— pokaże się dymek ze statusem tego samego builda.

---

## Krok 2: Jak ręcznie wypchnąć obraz na Docker Hub

**Rób to TYLKO gdy Krok 1 pokazał zielony ptaszek** dla najnowszego commita
na branchu, który chcesz wypchnąć.

1. Wejdź na: **`https://github.com/piotrvsa-23/foto-ai-serwer/actions`**
2. Po **lewej stronie** zobaczysz listę workflow'ów (nie runów — to inna
   lista, nazw jest mniej). Kliknij **"Wypchnij obraz na Docker Hub"**.
3. Po prawej stronie, nad listą uruchomień, zobaczysz szary przycisk
   **"Run workflow"** z małą strzałką w dół — kliknij go. Rozwinie się
   mały formularz.
4. W polu **"Use workflow from"** (górne, z listą rozwijaną) wybierz
   **właściwy branch**:
   - `claude/foto-ai-runpod-setup-zzw2vi` dla obrazu Cyber,
   - `flux-v01` dla obrazu Flux.
   - **To jest krytyczne** — jeśli zostawisz domyślny branch (`main`),
     wypchniesz nieaktualną/inną wersję kodu.
5. W polu tekstowym **"Tag obrazu (oprocz 'latest', ktory zawsze jest
   dodawany)"** wpisz dokładny tag, jaki ma dostać ten obraz, np.:
   ```
   CyberRXL10_v06
   ```
   albo
   ```
   flux.1_v05
   ```
   (Dokładną nazwę tagu, jakiej należy użyć dla danej zmiany, znajdziesz
   w treści ostatniego commita na danym branchu — Claude zawsze ją tam
   podaje w pierwszej linii wiadomości commita.)
6. Kliknij zielony przycisk **"Run workflow"** wewnątrz formularza.
7. Formularz się zamknie, a na górze listy uruchomień (może być potrzebne
   odświeżenie strony po 2-3 sekundach) pojawi się nowy wiersz **"Wypchnij
   obraz na Docker Hub"** z żółtym, kręcącym się kółkiem — to znaczy, że
   budowanie i wysyłanie właśnie trwa. Może to zająć **10-20 minut**
   (buduje CAŁY obraz jeszcze raz, od zera, potem wysyła go na Docker Hub).
8. Czekaj, aż ikona zmieni się na zielony ptaszek (sukces) albo czerwony X
   (błąd — wtedy wróć do instrukcji z Kroku 1 punkt 5, żeby zobaczyć log).

---

## Krok 3: Jak sprawdzić, że obraz naprawdę jest na Docker Hub

1. Wejdź na: **`https://hub.docker.com/r/piotrvsa/foto-ai-serwer/tags`**
   (nie trzeba się logować, to publiczne repo obrazów).
2. Zobaczysz listę wszystkich tagów. Znajdź tag, który właśnie wypchnąłeś
   (np. `CyberRXL10_v06`) — powinien być na górze listy (sortowanie po
   dacie ostatniej aktualizacji) z aktualną datą/godziną ("Last pushed").
3. Jeśli tag jest na liście z aktualną datą — obraz jest gotowy. Możesz
   wpisać go w polu **"Container Image"** w RunPod:
   ```
   piotrvsa/foto-ai-serwer:CyberRXL10_v06
   ```

---

## Skrócona ściągawka

| Co chcesz zrobić | Gdzie kliknąć |
|---|---|
| Sprawdzić, czy build przeszedł | `github.com/piotrvsa-23/foto-ai-serwer/actions` → szukaj zielonego ptaszka przy "Test builda obrazu Docker" na właściwym branchu |
| Zobaczyć błąd builda | Kliknij czerwony wiersz → rozwinięty krok na dole ma czerwony tekst błędu |
| Wypchnąć obraz na Docker Hub | Actions → lewy panel → "Wypchnij obraz na Docker Hub" → "Run workflow" → wybierz branch → wpisz tag → "Run workflow" |
| Sprawdzić, czy obraz jest na Docker Hub | `hub.docker.com/r/piotrvsa/foto-ai-serwer/tags` → szukaj tagu z aktualną datą |

---

## Uwaga o limicie minut GitHub Actions

Repo jest **publiczne**, więc GitHub Actions jest tu **całkowicie
darmowe i bez limitu minut** — nie musisz się już martwić o wyczerpanie
2000 darmowych minut/miesiąc (to dotyczyło tylko okresu, gdy repo było
prywatne). Możesz budować i wypychać obrazy tak często, jak potrzeba.
