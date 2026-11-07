# Deck

Console da tavolo per PADD WS: una scatola piatta di 320 × 160 × 47,5 mm con lo schermo ufficiale da 7" al
centro e una postazione per giocatore a ogni capo (manopola, DASH, SELECT, USE). Ogni pezzo è di un
solo colore e si stampa senza supporti; tutti i pezzi entrano sul piatto da 256 mm.

![Render del Deck montato](previews/render.png)

| | |
|---|---|
| ![Dall'alto](previews/top.png) | ![Dentro, con il piano trasparente](previews/inside.png) |

## File

| file | cosa |
|---|---|
| `deck.sc` | il modello per SolidCraft, con la timeline e i parametri principali |
| `deck.step` | tutti i pezzi da stampare, per altri CAD |
| `parts/*.3mf` | gli stessi pezzi separati, un file per gruppo, nel verso del modello |
| `deck-bambu-studio.3mf` | il progetto per Bambu Studio (X1 Carbon, 0,20 mm Standard): tutti i pezzi già girati nel verso di stampa e divisi in 6 piatti, uno per colore e materiale |

Nel file `.sc` si cambiano dalla finestra dei parametri `lunghezza`, `larghezza`, `raggio`,
`parete` e `vetro_sp`.

## Pezzi da stampare

Tutto sta in `deck-bambu-studio.3mf`, il progetto per Bambu Studio: i pezzi sono già girati nel verso di
stampa (nessuno richiede supporti) e divisi in sei piatti, uno per colore e materiale. Si
cambia solo il filamento tra un piatto e l'altro, mai durante una stampa.

| piatto | pezzi | filamento |
|---|---|---|
| 1 | metà G1 del piano (a faccia in giù), pezzi del logo | 1: PETG nero |
| 2 | metà G2 del piano, 2 manopole (capovolte) | 1: PETG nero |
| 3 | cornice del vetro (flangia sulla piastra), 2 barre del display | 1: PETG nero |
| 4 | metà G1 della vasca (dritta), 2 anelli delle tacche, 2 indicatori, 8 lettere di DASH | 2: PETG giallo |
| 5 | metà G2 della vasca | 2: PETG giallo |
| 6 | 8 piedini | 3: TPU 95A |

Il piano si stampa a faccia in giù: il sopra è la faccia sulla piastra e ne prende la finitura, per
esempio la texture della piastra PEI testurizzata. Per questo la battuta del vetro è un pezzo a
parte, la cornice, che si incolla da sotto. Il suo labbro entra nell'apertura del piano e la centra,
il vetro ci appoggia sopra, a filo del piano. Sotto il piano ci sono i tubi degli inserti, che
crescono verso l'alto durante la stampa.

Il progetto è per la X1 Carbon con ugello da 0,4 mm e il profilo 0.20mm Standard, con i filamenti
Bambu PETG Basic e TPU 95A HF; se si usano altri filamenti si cambiano nell'elenco a sinistra.
Piano, cornice, vasca e manopole hanno già 3 perimetri e il 15% di riempimento.

Il progetto usa il PETG (Bambu PETG Basic nero e giallo, TPU 95A HF per i piedini). I pezzi da incollare sono spessi 1,2 mm ed entrano per 0,6 mm in sedi con 0,15 mm di
gioco per lato; sul PETG l'Attack (cianoacrilato) tiene poco da solo: meglio con il suo primer per
plastiche difficili, oppure stampare i pezzi da incollare in PLA.

## Da comprare

| q.tà | cosa |
|---|---|
| 1 | Raspberry Pi 2, con Raspberry Pi OS a 32 bit e l'eseguibile `linux-armv7` |
| 1 | display ufficiale Raspberry Pi 7" (800 × 480), con il cavo DSI |
| 2 | encoder ottici LPD3806-600BM-G5-24C |
| 2 | pulsanti arcade da 24 mm a scatto (DASH): si agganciano al piano, assottigliato a 2 mm attorno al foro da un incavo da sotto |
| 4 | pulsanti momentanei da pannello Ø16 mm con il dado (SELECT, USE), normalmente aperti, con almeno 6 mm di filetto; sotto il piano c'è posto per 35 mm |
| 1 | prolunga micro-USB da pannello (foro 9 × 4, viti a 28 mm: da adattare al connettore) |
| 1 | amplificatore PAM8403 e 2 altoparlanti Ø28 con il bordo spesso 3 mm, a incastro nelle guide del fianco posteriore |
| 18 | inserti in ottone a caldo M3 × 5 × 4 (tipo Voron: Ø5 in testa, lunghi 4 mm; fori da 4,4 × 4,5): 12 e 4 nei tubi sotto il piano (viti della vasca e barre), 2 nelle manopole |
| 12 | viti M3 × 35 a testa bombata (ISO 7380): da sotto la vasca, dentro le colonnine, negli inserti dei tubi del piano |
| 8 | viti M3 × 6: barre → tubi del piano, barre → telaio del display |
| 6 | viti M3 × 6 a testa bassa: encoder → piano (sotto le manopole restano 2 mm) |
| 2 | grani M3 × 5 per le manopole |
| 4 | rondelle M12 (24 × 13 × 2,5), due per manopola: fanno da volano |

Collegamenti e configurazione degli encoder: [deploy/raspberry/README.md](../../deploy/raspberry/README.md),
schema degli encoder ottici (`pulses_per_revolution: 600`, `debounce_us: 0`).

## Montaggio

1. Inserti a caldo nei tubi sotto il piano (12 per le viti della vasca, 4 per le barre) e di fianco
   nelle manopole, con la punta del saldatore a circa 230-240 °C per il PETG. Sopra gli inserti
   restano 4,5 mm di piano (3,5 sopra quelli delle barre).
2. Appoggiare le due metà del piano a faccia in giù, accostate alla giunta, e incollare da sotto la
   cornice del vetro: il labbro entra nell'apertura e allinea le metà, la flangia va incollata sotto
   il piano. La cornice sta a cavallo della giunta e unisce le due metà.
3. Incollare anelli, lettere di DASH e indicatori nelle sedi del piano e delle manopole, e il logo
   nelle sedi del fianco della vasca. Le lettere che stanno a cavallo della giunta si incollano dopo
   aver unito le metà.
4. Mettere il display nell'apertura dall'alto, con il vetro sul labbro della cornice, e avvitare sotto
   le due barre: al telaio del display (asole) e ai tubi del piano. Le barre tengono il vetro contro
   la cornice: si stringono senza forzare, perché la cornice è solo incollata.
5. Encoder da sotto, con 3 viti dall'alto ciascuno; SELECT e USE con il dado; DASH si aggancia a
   scatto nel suo foro; il Raspberry dietro al display, sui suoi distanziali.
6. Vasca: calare la metà G2 sulla G1 dall'alto, facendo entrare le code di rondine nelle sedi.
   Montare la presa sul fianco posteriore e infilare dall'alto gli altoparlanti nelle loro guide,
   con il cono verso le feritoie: le costole sul labbro si schiacciano e li tengono fermi contro
   la parete, senza vibrare. Un anello di gommapiuma adesiva sul bordo li isola ancora di più.
7. Cablare, appoggiare il piano sulla vasca e avvitarlo da sotto con le 12 viti M3 × 35, che passano
   dentro le colonnine.
8. Rondelle nella sede sotto le manopole, manopole sugli alberi (il piano dell'albero verso il grano),
   piedini sotto la vasca.

## Da verificare prima di stampare

- **Spessore del vetro** (`vetro_sp`, ora 1,1 mm): il disegno ufficiale non lo quota. Si misura
  col calibro e si cambia il parametro: il labbro della cornice si rifà da solo.
- **Raggio degli angoli del vetro** (ora 6,5 mm: non è quotato, sugli esemplari si misura 6,5-7 mm) e **fori M3 del telaio**: le asole delle
  barre assorbono ±4 mm in lunghezza, non in larghezza.
- **Spessore del piano attorno a DASH** (ora 2 mm): la distanza tra il sotto della ghiera e i
  ganci del pulsante a scatto.
- **Fori degli inserti** (ora Ø4,4, come per gli M3 × 5 × 4 di CNC Kitchen e ruthex): con altre marche
  conviene provare l'inserto in un foro di prova prima di stampare il piano.
- **Bordo degli altoparlanti** (ora 3 mm): se è più sottile le costole non bastano a tenerli.
- **Connettore di alimentazione**: foro e viti sono per una prolunga micro-USB tipica.
- **Encoder**: misure dei venditori (corpo Ø38 × 35,5, collare Ø20 × 5, albero Ø6 × 13 con il piano,
  fori M3 sul cerchio Ø30).
