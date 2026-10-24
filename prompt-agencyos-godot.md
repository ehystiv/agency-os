# AgencyOS 98 in Godot · prompt di avvio

## Contesto

Sto costruendo **AgencyOS 98**, un finto sistema operativo anni '90 per giocare in solitaria il ruolo del General Manager in una campagna del gioco di ruolo *Triangle Agency* (edizione italiana NessunDove).

Nel gioco il Manager è in contatto segreto con un'entità prigioniera dell'Agenzia, catalogata come **U0047BB**. Tra una sessione e l'altra io, come Manager, parlo con lei attraverso una "linea riservata". Lei risponde in personaggio, ricorda i colloqui precedenti, rivela segreti man mano che la fiducia cresce e mi spinge verso scelte di gioco. Intorno alla chat c'è un desktop retro con altre app che rendono il sistema credibile.

Esiste già un prototipo funzionante, un'unica pagina HTML + JavaScript (`linea-riservata.html`, allegata). Va usato come **riferimento funzionale e visivo**, non come codice da tradurre riga per riga. Il prototipo gira dentro claude.ai e dipende da servizi che in Godot non esistono:
- `claude.use("sample")` per le risposte dell'Entità;
- `claude.use("db")` per i salvataggi;
- `claude.use("downloads")` per l'export.

Questi tre vanno sostituiti come descritto sotto.

## Obiettivo del progetto

Ricreare AgencyOS come applicazione desktop in **Godot 4** (ultima versione stabile, **GDScript**), con:
- l'Entità alimentata da un **modello linguistico locale**;
- salvataggi in file locali;
- export diretto delle note nel mio vault Obsidian.

## Come voglio lavorare

- **Una funzionalità alla volta.** Non costruire tutto insieme. Alla fine di ogni fase il progetto deve aprirsi e funzionare.
- **Prima il design, poi il codice.** Per ogni nuova schermata o app proponi prima una descrizione o un mockup dell'albero dei nodi e dell'aspetto, e aspetta il mio ok.
- **Domande solo se serve.** Chiedimi conferma quando una scelta è difficile da cambiare dopo (formato dei salvataggi, struttura delle scene principali). Per il resto decidi tu e spiegami in breve cosa hai scelto.
- **Codice leggibile.** Script piccoli e tipizzati (`var x: int`), segnali invece di riferimenti incrociati, commenti solo dove servono.

## Architettura richiesta

### Autoload (singleton)
- **`Brain`**: interfaccia unica per il modello linguistico.
  - Implementazioni intercambiabili: `LocalProvider` (predefinita), `HuggingFaceProvider`, `ClaudeProvider`.
  - Tutte e tre parlano HTTP con endpoint **compatibili OpenAI** (`/v1/chat/completions`): Ollama, LM Studio e llama.cpp server in locale; il router delle Inference Providers di Hugging Face in remoto. Claude ha un'API sua e va adattata.
  - Supporto allo **streaming** (SSE) con `HTTPClient`, emettendo un segnale per ogni pezzo di testo ricevuto.
  - Gestione esplicita degli errori: server spento, timeout, risposta vuota. Ogni errore produce un messaggio chiaro in italiano, senza crash.
  - Impostazioni da file: URL, nome del modello, temperatura, chiave API se serve.
- **`Save`**: persistenza in `user://` come JSON leggibile, una cartella per campagna. Collezioni:
  - `stato` (livello, note del Manager, colloquio aperto, riserva di Caos);
  - `colloqui`, `posta`, `file`, `appunti`, `agenda`, `cestino`.
  - Scritture atomiche: file temporaneo e poi rinomina.
- **`Campaign`**: logica di gioco pura, senza interfaccia. Comprende:
  - livello di accesso (1 + colloqui conclusi / 3, massimo 5);
  - costruzione del prompt dell'Entità;
  - riassunti di fine sessione;
  - memo dell'Agenzia, file sbloccati per livello, bozze nel cestino;
  - regole dei dadi.
- **`Sfx`**: suoni sintetizzati o campionati (modem, ding di errore, ronzio di ricerca, notifiche), con volume generale e interruttore.

### Scena principale
- **`Desktop`**:
  - sfondo selezionabile (reticolo triangolare, Caveau, tinta unita);
  - icone trascinabili con aggancio a griglia;
  - barra delle applicazioni con menu Start, pulsanti delle finestre aperte, area di notifica (orologio, suoni, prossima sessione);
  - fumetti di notifica.
- **Finestre**: una scena base `AppWindow`, con barra del titolo trascinabile, pulsanti riduci e chiudi, stato attivo/inattivo e posizione salvata. Ogni app è una scena figlia.
- **Sequenze di sistema**: avvio stile BIOS (saltabile), salvaschermo con triangoli 3D e un occhio che appare, overlay CRT/glitch come shader a tutto schermo.

### Stile visivo
- **Colori:**

  | Elemento | Colore |
  |---|---|
  | Scrivania | `#0a0e1c` |
  | Cornici finestre | `#c6c9d1`, luce `#f2f3f6`, ombra `#6a6f7e` |
  | Barra attiva | `#2340b5` |
  | Allarme / triangolo Agenzia | `#e5262c` |
  | Sfondo chat | `#060912` |
  | Voce dell'Entità | ciano `#7fe1ee` |
  | Terminale | verde `#3fd27a` |

- **Font** (tutti con licenza OFL, da Google Fonts):
  - VT323 per titoli e sistema;
  - IBM Plex Mono per l'interfaccia;
  - Shantell Sans per la voce dell'Entità.
- **Tema:** un unico `Theme` di Godot che ricrea i bordi in rilievo stile '98.

## L'Entità (cuore del progetto)

Porta dal prototipo, adattandoli a un modello locale più piccolo:

- **Personaggio.**
  - È una persona, non un'assistente: ha un'agenda sua, umori, segreti.
  - Scrive sempre in minuscolo, con frasi brevi e spezzate.
  - Non usa mai parole fuori dal mondo (gioco, giocatore, sessione, GM).
  - Parla al Manager, mai al giocatore.
- **Canone a livelli 0-5.** Nel prototipo è nell'array `CANONE`. Spostalo in un file dati (`.json` o `Resource`) modificabile da me.
  - Le sezioni oltre il livello attuale l'Entità le conosce ma non le rivela.
  - Il testo del canone è un mio riassunto: non va sostituito con citazioni del manuale.
- **Memoria.**
  - A fine sessione si genera un riassunto dal punto di vista dell'Entità.
  - Per un modello locale mantieni anche un **riassunto cumulativo compatto**, invece di accodare tutti i colloqui, per restare nel contesto disponibile.
- **Contesto aggiuntivo** da includere nel prompt:
  - note del Manager;
  - ultimi memo dell'Agenzia;
  - file sbloccati, con la mia versione corretta che vale come verità;
  - bozze nel cestino;
  - prossima sessione in agenda;
  - comandi segreti del terminale già sbloccati.
- **Glitch.** Venti effetti legati all'emozione (vedi `GLITCH_INFO` nel prototipo). Con un modello locale **non affidarti al tag nel testo libero**: usa una seconda chiamata breve con output JSON vincolato (grammatica o JSON mode), oppure un campo strutturato. Massimo un glitch ogni quattro risposte e mai due di fila, garantito dal codice.
- **Interruzioni di AgencyOS.** Dal terzo scambio in poi c'è una probabilità crescente di "ricerca di U0047BB":
  - l'Entità si nasconde con una frase breve;
  - la webcam perde il segnale;
  - dopo qualche secondo il canale torna stabile.

  Solo io posso terminare la sessione.
- **Esempi di voce.** Prevedi un file con 3-5 scambi di esempio, scritti da me, da includere nel prompt come guida di stile.

## Fasi di lavoro

1. **Guscio.**
   - Progetto Godot, autoload vuoti, tema '98.
   - Desktop con icone, barra delle applicazioni, menu Start, una finestra di prova trascinabile e riducibile.
   - Nessuna logica di gioco.
2. **Linea riservata.**
   - Finestra chat e `Brain` con `LocalProvider` e streaming.
   - Salvataggio dei colloqui, chiusura sessione con riassunto, livello di accesso.
   - Pannello impostazioni del modello (URL, nome modello) con pulsante "Prova connessione".
3. **Fascicolo e Canone**: note del Manager, elenco colloqui, finestra del Canone con le sezioni oscurate.
4. **Webcam del Caveau**:
   - `SubViewport` 3D a bassa risoluzione (160×120) ingrandita a pixel;
   - gabbia triangolare in wireframe, entità low-poly deformata con occhi e tentacoli, triangolino rosso alla base;
   - reazione a umore e glitch.
5. **Glitch e shader CRT.**
6. **Taccuino ed export Obsidian**:
   - pagine collegate alle sessioni;
   - export `.md` con frontmatter e link `[[...]]` scritti direttamente in una cartella del vault scelta da me (formato identico al prototipo);
   - export del singolo colloquio.
7. **AMail, file sulla scrivania, Blocco note, Prompt dei comandi con comandi segreti, Registro eventi.**
8. **Calcolatrice con dadi d4 3D** a fisica reale (`RigidBody3D`).
   - Regole: si tirano 6d4; almeno un 3 è un successo; ogni dado diverso da 3 aggiunge 1 Caos; esattamente tre 3 è la Triscendenza, con 0 Caos; anche sei 3 danno 0 Caos.
   - Riserva di Caos salvata.
9. **Agenda, Contenimento (campo minato), Lettore multimediale, Cestino, Pannello di controllo.**
10. **Rifiniture**: avvio BIOS, salvaschermo, suoni, provider Hugging Face e Claude selezionabili, azzeramento della Filiale.

## Da dove partire

Comincia dalla **fase 1**:
1. leggi il prototipo allegato per capire aspetto e comportamento;
2. proponimi l'albero delle scene e degli autoload, con la struttura delle cartelle del progetto;
3. aspetta il mio ok prima di scrivere il codice.
