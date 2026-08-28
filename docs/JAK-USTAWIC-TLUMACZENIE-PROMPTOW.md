# Jak ustawić tłumaczenie promptów PL→EN (Expand Prompt) dla FLUX.1 i CyberRealisticXL

Ten dokument opisuje krok po kroku, jak skonfigurować w InvokeAI wbudowaną
funkcję **Expand Prompt** tak, żeby:

- można było pisać prompty **po polsku**,
- model LLM sam **tłumaczył je na angielski**,
- i od razu **formatował** je w stylu odpowiednim dla danego silnika obrazu
  (FLUX.1 lubi pełne, opisowe zdania; CyberRealisticXL/SDXL lubi krótkie
  frazy-tagi z wagami).

Dotyczy dwóch obrazów z tego repo:

- **`flux.1_v02`** (branch `flux-v01`) — model LLM trzeba zainstalować
  ręcznie, jednorazowo (patrz Część A).
- **`v6.14.0_v05_CyberRXL_v10`** (branch główny) — model LLM **jest już
  pobierany automatycznie** przy starcie poda, trzeba tylko skonfigurować
  System Prompt (patrz Część B, pomiń instalację modelu).

Model LLM (Qwen3-4B-abliterated) **nie generuje obrazów** — tylko
przepisuje/tłumaczy tekst promptu, zanim trafi do silnika obrazu (FLUX lub
SDXL). Wybrany celowo w wariancie "abliterated" (bez wbudowanej odmowy
odpowiedzi), żeby nie blokował się na opisach dla dorosłych — a to właśnie
tu jest potrzebne (oba checkpointy w tym projekcie są NSFW).

---

## Krok 0: Jak otworzyć InvokeAI na RunPod

1. Wejdź na stronę swojego poda na RunPod (zakładka **Pods**).
2. Kliknij przycisk **Connect** przy uruchomionym podzie.
3. W sekcji **HTTP Service(s)** kliknij link przy porcie **9090**.
4. Otworzy się InvokeAI w nowej karcie przeglądarki — to jest **osobna
   aplikacja**, nie panel RunPoda. Wszystkie dalsze kroki dzieją się
   **wewnątrz tej karty**.

---

## Część A: Model LLM dla FLUX.1 (obraz `flux.1_v02`)

W tym obrazie model LLM **nie jest pobierany automatycznie** — trzeba go
dodać ręcznie, raz na pod (zostaje na dysku poda, dopóki go nie usuniesz
albo nie stworzysz zupełnie nowego poda).

### A1. Zainstaluj model LLM (Qwen3-4B-abliterated)

1. W lewym pasku bocznym InvokeAI kliknij ikonę **Models** (wygląda jak
   stos/szufladka kwadratów).
2. Otworzy się **Model Manager**. W prawym górnym rogu kliknij żółty
   przycisk **"+ Add Models"**.
3. Na górze przełącz się na zakładkę **"HuggingFace"** (ikona logo
   HuggingFace).
4. W polu tekstowym **"Hugging Face Repo ID"** wklej dokładnie:
   ```
   huihui-ai/Qwen3-4B-abliterated
   ```
5. Kliknij przycisk **"Install Repo"** obok pola.
6. Na dole ekranu, w sekcji **"Model Install Queue"**, pojawi się nowa
   pozycja z paskiem postępu — model waży ok. 8GB, pobieranie może
   potrwać kilka-kilkanaście minut w zależności od łącza.
7. Poczekaj, aż status zmieni się na **"Completed"**.
8. Wróć do listy modeli (Model Manager → lista po lewej). Powinna pojawić
   się nowa sekcja **"Text LLM"** z pozycją `qwen3-4b-abliterated`.

### A2. Ustaw System Prompt dla FLUX.1 (tłumaczenie PL→EN, opis naturalny)

1. Przejdź do głównego ekranu generowania obrazu (zakładka **Canvas** /
   **Generate** w górnym pasku).
2. Znajdź pole **Positive Prompt**. W jego **prawym górnym rogu** powinny
   być widoczne dwie małe ikony: ✨ (gwiazdka/iskierki) i 🖼️ (obrazek).
   - Jeśli ich **nie widzisz** — model LLM z kroku A1 jeszcze się nie
     zainstalował (odśwież stronę po zakończeniu instalacji).
3. Kliknij ikonę **✨ (Expand Prompt)**.
4. W otwartym okienku, z listy **"Model"** wybierz `qwen3-4b-abliterated`.
5. Obok pola **"System Prompt"** kliknij małą ikonę **ołówka**
   ("Manage system prompts").
6. W otwartym oknie kliknij **"New System Prompt"**.
7. W polu **"Name"** wpisz np.:
   ```
   Flux - PL na EN (opis naturalny)
   ```
8. W polu **"Content"** wklej **dokładnie** ten tekst:
   ```
   Jesteś ekspertem od promptów do generowania obrazów AI. Użytkownik poda krótki opis po polsku. Przetłumacz go i rozwiń w szczegółowy, żywy opis PO ANGIELSKU, odpowiedni do generowania obrazu. Wypisz tylko finalny angielski prompt, nic więcej.
   ```
9. Kliknij **Save**.
10. Zamknij okno zarządzania System Promptami. Wróć do okienka Expand
    Prompt i z listy **"System Prompt"** wybierz prompt, który właśnie
    utworzyłeś ("Flux - PL na EN...").

Gotowe — konfiguracja FLUX.1 zapisuje się w bazie InvokeAI na tym podzie,
nie trzeba jej powtarzać przy każdej generacji (tylko przy nowym podzie).

---

## Część B: Model LLM dla CyberRealisticXL (obraz `v6.14.0_v05_CyberRXL_v10`)

W tym obrazie model LLM **jest już pobierany automatycznie** przez
`start.sh` razem z resztą dodatków (VAE, ControlNet, IP-Adapter, LoRA) —
**pomiń krok A1**, nie trzeba nic instalować ręcznie.

### B1. Sprawdź, czy model już się zainstalował

1. Poczekaj, aż pod pokaże `Ready` i log pokaże, że InvokeAI wystartował
   (linia `Invoke running on http://0.0.0.0:9090`).
2. W lewym pasku InvokeAI kliknij **Models** → Model Manager.
3. Sprawdź, czy w liście jest sekcja **"Text LLM"** z pozycją
   `qwen3-4b-abliterated`. Jeśli tak — gotowe, przejdź do B2.
4. Jeśli sekcji nie ma (np. sprawdzasz od razu po starcie, zanim
   pobieranie dodatków się skończyło) — poczekaj kilka minut i odśwież
   stronę, albo doinstaluj ręcznie tak jak w kroku A1 (ten sam Repo ID:
   `huihui-ai/Qwen3-4B-abliterated`).

### B2. Ustaw System Prompt dla CyberRealisticXL (tagi/wagi SDXL)

Powtórz kroki **A2 (1–6, 9–10)** z tą różnicą, że w kroku 7-8 wpisz:

7. W polu **"Name"**:
   ```
   Cyber - PL na EN (tagi SDXL)
   ```
8. W polu **"Content"** wklej **dokładnie** ten tekst:
   ```
   Jesteś ekspertem od promptów SDXL dla Stable Diffusion. Użytkownik poda opis po polsku. Przetłumacz go i zamień na prompt w stylu tagów/fraz po angielsku, rozdzielonych przecinkami, z wagami we WŁAŚCIWEJ dla InvokeAI składni: (fraza)1.2 — NIGDY (fraza:1.2) z dwukropkiem. Używaj wag tylko tam, gdzie naprawdę podkreślają ważny element. Wypisz tylko finalny prompt, nic więcej.
   ```

> **Ważne — dwie różne składnie wag:**
> - **InvokeAI (ten prompt):** `(fraza)1.2` — waga zaraz po nawiasie, bez
>   dwukropka.
> - **Automatic1111 / ComfyUI / Civitai (INNA aplikacja):**
>   `(fraza:1.2)` — z dwukropkiem.
>
> To dwie różne, niekompatybilne składnie. Prompty skopiowane wprost z
> Civitai (często pisane w stylu A1111) **mogą nie zadziałać poprawnie**
> w InvokeAI, jeśli mają dwukropek w nawiasie z wagą.

---

## Codzienne użycie (po jednorazowej konfiguracji)

1. Otwórz InvokeAI (Krok 0).
2. W polu **Positive Prompt** wpisz krótki opis **po polsku**, np.:
   `kobieta w czerwonej sukience na plaży o zachodzie słońca`
3. Kliknij ikonę **✨ Expand Prompt**.
4. Upewnij się, że wybrany jest właściwy **System Prompt** dla danego
   modelu (Flux albo Cyber — patrz sekcja "Ważne" wyżej, jeśli używasz
   obu obrazów naprzemiennie, pamiętaj o przełączeniu promptu).
5. Kliknij **Expand** — pole promptu zostanie zastąpione rozwiniętym,
   angielskim tekstem gotowym do generowania.
6. Jeśli wynik Cię nie zadowala — **Ctrl+Z** (Cmd+Z na Mac) w polu
   promptu w ciągu 30 sekund cofa zmianę i przywraca Twój oryginalny,
   polski tekst.

---

## Skrócone ściągawki (do szybkiego kopiowania)

**Repo ID modelu LLM (instalacja ręczna, tylko FLUX.1 / obraz `flux.1_v02`):**
```
huihui-ai/Qwen3-4B-abliterated
```

**System Prompt — FLUX.1 (opis naturalny):**
```
Jesteś ekspertem od promptów do generowania obrazów AI. Użytkownik poda krótki opis po polsku. Przetłumacz go i rozwiń w szczegółowy, żywy opis PO ANGIELSKU, odpowiedni do generowania obrazu. Wypisz tylko finalny angielski prompt, nic więcej.
```

**System Prompt — CyberRealisticXL (tagi SDXL):**
```
Jesteś ekspertem od promptów SDXL dla Stable Diffusion. Użytkownik poda opis po polsku. Przetłumacz go i zamień na prompt w stylu tagów/fraz po angielsku, rozdzielonych przecinkami, z wagami we WŁAŚCIWEJ dla InvokeAI składni: (fraza)1.2 — NIGDY (fraza:1.2) z dwukropkiem. Używaj wag tylko tam, gdzie naprawdę podkreślają ważny element. Wypisz tylko finalny prompt, nic więcej.
```
