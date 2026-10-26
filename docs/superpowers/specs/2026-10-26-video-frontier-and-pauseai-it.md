# Pipeline video: apprendimento longitudinale + primo video PauseAI in italiano

Data: 2026-10-26. Stato: specifica, da pianificare insieme (Claude + Codex) prima di qualsiasi build.

## Parte A — Il ciclo di apprendimento si riscrive

### Diagnosi: come un feedback passato diventa un limite

Tre meccanismi, tutti letti all'inizio di ogni nuovo video:

1. **`PREFLIGHT.md` riporta i verdetti grezzi.** `Write-AosVideoPreflight` (`aos.psm1`) copia testualmente
   tutti i verdetti della stessa famiglia e gli ultimi 5 delle altre. Il primo documento che un agente legge
   è quindi un elenco di frasi negative ("shape-like", "too snappy", "stiff"). Senza contesto, l'agente le
   tratta come una descrizione di quello che la pipeline sa fare.
2. **`video-rules.md` è un registro di incidenti in sola aggiunta.** Ha 34 regole, ciascuna con la sua origine
   ("from the v1 verdict, '...'"). Mescola invarianti oggettive (build sigillata, manifest, encoding, gate di
   attualità) con prescrizioni estetiche congelate (R17 "movimento calmo", R18 "un solo medium", R28 che
   sovrascrive R18). Ogni critica estetica diventa un vincolo permanente invece di un obiettivo da superare,
   e le regole si contraddicono man mano che si accumulano.
3. **Le memorie salvano le frasi dei verdetti come stato.** Esempi: "v1 still very much shape-like",
   "v4 verdict: stiff". In conversazione si leggono come un tetto. È successo in questa chat: ho indicato
   "forme" e "scatti" come "il punto debole della pipeline" quando l'utente ha proposto lo stile di
   Rational Animations.

### Progetto: tre livelli con vita diversa

| Livello | Contenuto | Chi lo legge | Come cambia |
|---|---|---|---|
| L0 verdetti grezzi | parole dell'utente, verbatim | solo audit (`--verdicts`) | sola aggiunta nel ledger, invariato |
| L1 invarianti | guardie tecniche e di processo vere oggi (sigillo, manifest, attualità, encoding, capacità) | ogni stage | si modifica e si elimina; niente citazioni, la provenienza sta in git e `decisions.md` |
| L2 frontiera di mestiere | per ogni dimensione: il miglior esempio finora, la tecnica che l'ha prodotto, il prossimo obiettivo rispetto a un riferimento | brief e look | **riscritto** a ogni retro, mai in sola aggiunta |

Dimensioni L2 iniziali (si possono cambiare): recitazione e design dei personaggi, qualità del movimento,
densità e texture della scena, metafore visive, ritmo, voce, suono, tipografia e leggibilità, accuratezza
dei dati.

Ogni voce L2 contiene: `best` (video, shot e percorso del file), `how` (tecnica, strumento o modulo del kit),
`level` (misura oppure giudizio, con la data), `next` (obiettivo formulato in positivo rispetto a un
riferimento), `try` (ipotesi per la prossima generazione). Le voci non contengono frasi negative: un gap è
scritto come obiettivo.

### Il retro converte, non accumula

Per ogni verdetto:

1. **Cambio di capacità.** Il gap si chiude nel kit (template, `src/lib`, libreria di asset/rig, strumento,
   check), con un test o un esempio renderizzato.
2. **Aggiornamento della frontiera.** La voce L2 riceve il nuovo `best`/`how`/`next`.
3. **Chiusura nel ledger.** Il verdetto riceve un evento `video-verdict-resolved` con il commit. Un verdetto
   non ancora risolvibile diventa un `next` aperto, mai una regola.

Le nuove regole L1 nascono solo per guardie tecniche verificabili. Il gusto e lo stile non diventano mai una
regola.

### Confronto tra generazioni (il miglioramento longitudinale)

All'inizio del look, il nuovo video mette i suoi frame accanto al `best` di ogni dimensione bersaglio, nello
stesso fotogramma di beat. Lo stage passa solo se il nuovo frame supera il `best`, con un giudizio cieco di
entrambi i vendor (`review-sheets` + `codex exec -i`) e la conferma dell'utente ai gate. L'esito aggiorna L2.
Così il riferimento è sempre il meglio raggiunto finora, non l'errore peggiore.

### Modifiche concrete

- `Write-AosVideoPreflight` emette: invarianti L1, frontiera L2 con gli esempi da cui partire, minuti per stage
  e deleghe. Niente più sezioni `## Verdicts on ...` / `## Other recent verdicts`. Il flag `--verdicts` le
  rimostra solo per audit.
- Nuovo `agents-home/video/frontier.md`, prodotto una volta distillando le 34 regole e tutti i verdetti
  (lavoro di Claude, critica indipendente di Codex).
- `video-rules.md` dimagrisce alle sole invarianti. R17/R18/R19/R28/R29 come prescrizioni estetiche passano in
  L2 come tecniche e obiettivi.
- `templates/video/AGENTS.md` (ciclo R20) e `retro.md` passano al formato "verdetto → capacità → frontiera".
- Memorie: le voci video che riportano frasi di verdetto si fondono in un puntatore alla frontiera più il
  principio (già salvato in `video-verdicts-are-targets-not-limits`).
- Test in `tests/aos.Tests.ps1`: le intestazioni del preflight cambiano. Il nuovo test (scritto da Codex)
  verifica che nessuna frase di verdetto entri in `PREFLIGHT.md` senza `--verdicts` e che la frontiera ci sia.
- Nuova voce datata in testa a `docs/decisions.md`. Restano da rispettare `aos test` (PS 5.1 + 7) e la regola
  ASCII.

## Parte B — Primo video PauseAI in italiano

### Fissato

- **Script: definitivo, verbatim, nessuna revisione** (vedi `script.md` alla creazione del progetto). Sono
  circa 240 parole, che a ritmo di narrazione italiana fanno circa 1:40–1:55.
- Pubblico: generale. Il video non è definitivo: è un primo artefatto.
- Le fonti stanno nel `sources.md`/`currency.json` del progetto e nella descrizione del video. Per lo script
  fissato servono almeno: la dichiarazione CAIS 2023, le stime individuali di 10–20% (es. Hinton), i sondaggi
  sui ricercatori (AI Impacts 2023), stime pubbliche oltre il 50% e lo stato del dibattito italiano. Il gate
  R27 si applica. Le fonti sostengono le frasi dello script, non le cambiano.

### Identità visiva

Linguaggio visivo **alla Rational Animations**: illustrazione 2D pulita, personaggi tondi ed espressivi che
recitano, metafore messe in scena (un'idea = un'immagine), palette calda con accenti saturi, luce morbida,
camera fluida e personaggi grandi in quadro. **I personaggi e il marchio sono nostri.** Niente mascotte, logo o
personaggi riconoscibili di RA: il video non deve sembrare un loro contenuto.

### Gate di produzione

1. **G1 Riferimenti → style bible misurata.** 3–5 video RA analizzati con `watch` (palette campionata, spessore
   delle linee, proporzioni dei personaggi, durata degli shot, movimenti di camera, ritmo dei tagli).
   `pool_triage` smista i frame di riferimento.
2. **G2 Look lab.** Stesso personaggio + 2 beat in 3 tecniche: rig SVG in Remotion, Grease Pencil in Blender
   (MCP disponibile), 3D toon in Blender. Giudizio cieco dei due vendor sui frame, `nar_choose` come segnale
   secondario, scelta dell'utente.
3. **G3 Voce.** Provino Kokoro con le voci italiane (`if_sara`, `im_nicola`) + 1–2 alternative locali.
   Decide l'utente all'ascolto (R05).
4. **G4 Animatic** a tempo sulla voce, con mappa beat → metafora.
5. **G5 Produzione** a batch paralleli, **G6 QA** (check esistenti + pacing + confronto con la frontiera),
   **G7 verdetto dell'utente** → retro nel nuovo formato.

### Orchestrazione

- **Claude (direttore):** mappa beat → metafore, ricerca e attualità, voce, review sheet, integrazione, QA.
- **Codex (scrittore principale, nel suo worktree):** sistema dei personaggi e dei rig (il pezzo che decide la
  qualità) e una metà dei batch di shot. Rilascia il claim prima di delegare (memoria `release-claim-before-codex`).
- **Pool locale / API gratuite (`aos-pool`):** `pool_crosscheck` delle affermazioni sulle fonti (materiale
  pubblico), `pool_variants` per le proposte di metafora per beat, `pool_triage` per i frame di riferimento.
  È un segnale da verificare, non una decisione.
- Al massimo 2 attori attivi per vendor. La capacità si legge a ogni gate (R34).

### Ordine

La Parte A va prima della Parte B, perché il preflight del nuovo video è la prima cosa che gli agenti leggono.

## Domande aperte per l'utente

1. ~~Il limite "linguaggio RA, personaggi e marchio nostri" va bene?~~ Sì (utente, 2026-10-26).
2. Possiamo mostrare un cartello finale PauseAI Italia (logo + link), solo a schermo e senza narrazione, e
   abbiamo il loro via libera?
3. I video RA di riferimento li sceglie l'utente, o li propongo io?
