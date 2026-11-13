[<img src="../../docs/flags/it.svg" alt="" height="14"> **Italiano**](README.md) · [<img src="../../docs/flags/gb.svg" alt="" height="14"> English](README.en.md)

# Deck

> **Progetto non ancora collaudato.** Il Deck non è ancora stato stampato e provato per intero:
> misure, pezzi e istruzioni cambieranno con le prossime revisioni.

Console da tavolo per PADD WS: una scatola piatta di 320 × 160 × 47,5 mm con lo schermo ufficiale da 7" al
centro e una postazione per giocatore a ogni capo (manopola, DASH, SELECT, USE). Ogni pezzo è di un
solo colore e si stampa senza supporti; tutti i pezzi entrano sul piatto da 256 mm.

![Render del Deck montato](previews/render.png)

| | |
|---|---|
| ![Dall'alto](previews/top.png) | ![Dentro, senza il piano e il display](previews/inside.png) |

Vista esplosa, con i pezzi nell'ordine di montaggio. Display, scheda con il Pi ed encoder, in grigio
trasparente, sono componenti da comprare e non si stampano.

![Vista esplosa del Deck](previews/exploded.gif)

## File

| file | cosa |
|---|---|
| `deck.sc` | il modello per SolidCraft, con la timeline e i parametri principali |
| `deck.step` | tutti i pezzi da stampare, per altri CAD |
| `parts/*.3mf` | gli stessi pezzi separati, un file per gruppo, nel verso del modello, con le placche della presa di ricambio; le metà G1 e G2 di piano e vasca sono i file `-P1` e `-P2` |
| `deck-bambu-studio.3mf` | il progetto per Bambu Studio (X1 Carbon, 0,20 mm Standard): tutti i pezzi già girati nel verso di stampa e divisi in 6 piatti, ognuno di un solo colore e materiale |

Nel file `.sc` si cambiano dalla finestra dei parametri `lunghezza`, `larghezza`, `raggio`,
`parete` e `vetro_sp`.

## Pezzi da stampare

Tutto sta in `deck-bambu-studio.3mf`, il progetto per Bambu Studio: i pezzi sono già girati nel verso di
stampa (nessuno richiede supporti) e divisi in sei piatti, ognuno di un solo colore e materiale. Si
cambia solo il filamento tra un piatto e l'altro, mai durante una stampa.

| piatto | pezzi | filamento |
|---|---|---|
| 1 | metà G1 del piano (a faccia in giù), pezzi del logo | 1: PETG nero |
| 2 | metà G2 del piano, 2 manopole (capovolte), 10 mozzi delle manopole | 1: PETG nero |
| 3 | cornice del vetro (flangia sulla piastra), 4 barre del display (capovolte) | 1: PETG nero |
| 4 | metà G1 della vasca (dritta), 2 anelli delle tacche, 2 indicatori, 8 lettere di DASH | 2: PETG giallo |
| 5 | metà G2 della vasca, placca della presa micro-USB (a faccia in giù) | 2: PETG giallo |
| 6 | 8 piedini | 3: TPU 95A |

Il piano si stampa a faccia in giù: il sopra è la faccia sulla piastra e ne prende la finitura, per
esempio la texture della piastra PEI testurizzata. Per questo la battuta del vetro è un pezzo a
parte, la cornice, che si incolla da sotto. Il suo labbro entra nell'apertura del piano e la centra,
il vetro ci appoggia sopra, a filo del piano. Sotto il piano ci sono i tubi degli inserti, che
crescono verso l'alto durante la stampa.

Il progetto è per la X1 Carbon con ugello da 0,4 mm e il profilo 0.20mm Standard, con i filamenti
Bambu PETG Basic e TPU 95A HF; se si usano altri filamenti si cambiano nell'elenco a sinistra.
Piano, cornice, vasca e manopole hanno già 3 perimetri e il 15% di riempimento.

I pezzi da incollare sono spessi 1,2 mm ed entrano per 0,6 mm in sedi con 0,15 mm di gioco per
lato; sul PETG l'Attack (cianoacrilato) tiene poco da solo: meglio con il suo primer per
plastiche difficili, oppure stampare i pezzi da incollare in PLA.

## Mozzi delle manopole

La manopola non si infila direttamente sull'albero dell'encoder: dentro ha una sede dentata dove si
incolla un mozzo con il foro a D. I fori piccoli stampati vengono più stretti del disegno, e quanto
dipende da stampante e filamento; per questo ci sono mozzi con cinque giochi diversi, due per tipo,
riconoscibili dalle tacche sulla flangia:

| tacche | gioco per lato attorno all'albero |
|---|---|
| 1 | 0,10 mm |
| 2 | 0,15 mm |
| 3 | 0,20 mm (quello del modello) |
| 4 | 0,25 mm |
| 5 | 0,30 mm |

Si provano sull'albero e si tengono i due che entrano con una spinta decisa senza ballare. Il mozzo
entra nella manopola in una delle 10 posizioni dei denti, con 0,2 mm di gioco: i denti trascinano la
manopola, la colla serve solo a non farla sfilare. La flangia in basso tiene le rondelle nella loro
sede.

## Placca della presa

La presa di alimentazione sta su una placca intercambiabile, nel fianco posteriore. La placca riempie
una tacca della parete, aperta verso l'alto, e dietro ha due ali che scorrono in guide a C. Si
infila dall'alto prima di chiudere il piano, che poi la tiene giù. Quando si spinge la spina la
reggono le guide e un appoggio al centro, in basso; quando la si tira, la parete. Le guide hanno
zoccoli e squadrette sul fondo.

La faccia è larga 43,6 mm e alta 34,3, spessa come la parete (2,5 mm). Dietro, tra le ali, restano
40 mm di larghezza per la presa; sotto il centro c'è l'appoggio, alto 5 mm.

| file | presa |
|---|---|
| `parts/power-plate-micro-usb.3mf` | prolunga micro-USB da pannello con due viti M3 a 28 mm (è quella del progetto Bambu Studio) |
| `parts/power-plate-usb-c.3mf` | presa USB-C rotonda con il dado, foro Ø12,2 (filetto M12) |
| `parts/power-plate-dc-jack.3mf` | jack DC 5,5 × 2,1 con filetto da 8 mm e interruttore a levetta da 6 mm |
| `parts/power-plate-blank.3mf` | piena: da forare, o da ridisegnare partendo da `deck.step` |

Le placche si stampano a faccia in giù, così il lato in vista viene liscio. Nel modello le placche di
ricambio sono nascoste, dietro la console.

## Da comprare

| q.tà | cosa |
|---|---|
| 1 | Raspberry Pi 2, con l'immagine della SD del Deck ([deploy/raspberry/deck](../../deploy/raspberry/deck/README.md): Raspberry Pi OS a 32 bit ridotto, con l'eseguibile `linux-armv7`) |
| 1 | display ufficiale Raspberry Pi 7" (800 × 480), con il cavo DSI |
| 2 | encoder ottici LPD3806-600BM-G5-24C |
| 2 | pulsanti arcade da 30 mm a scatto, Sanwa OBSF-30 (DASH): foro da 30, ghiera Ø33,2; si agganciano al piano, assottigliato a 3 mm attorno al foro da un incavo da sotto; sotto il piano servono 35,5 mm |
| 4 | pulsanti momentanei da pannello Ø16 mm con il dado (SELECT, USE), normalmente aperti, con almeno 6 mm di filetto; sotto il piano c'è posto per 35 mm |
| 1 | prolunga micro-USB da pannello con due viti M3 a 28 mm (oppure un'altra presa, con la sua placca: vedi sopra) |
| 1 | cavo sdoppiatore micro-USB (a Y): dalla prolunga al Pi 2 e alla micro-USB del display; così i pin 5V e GND del display restano liberi, senza cavetti verso la GPIO |
| 1 | amplificatore PAM8403 e 2 altoparlanti sottili Ø28 (8 Ω, 2 W, spessi fino a 5,4 mm), a incastro nelle guide dei fianchi corti, uno davanti a ogni giocatore |
| 1 | cavo audio con spina jack 3,5 mm stereo maschio a 3 poli (TRS, non a 4 poli), 20-30 cm (un cavo audio tagliato o un cavetto "jack 3,5 mm a fili liberi"): dalla presa audio del Pi 2 all'ingresso del PAM8403 (punta = L, anello = R, corpo = GND) |
| 1 | alimentatore micro-USB 5,1 V 2,5 A, oppure powerbank con uscita USB-A da almeno 2,4 A |
| 1 | microSD da almeno 8 GB |
| - | cavetti Dupont femmina per la GPIO, faston da 4,8 mm per i pulsanti |
| 12 | inserti in ottone a caldo M4 larghi 6 mm, lunghi 6 (o 4) mm (fori da 5,6 × 6,5): nei tubi sotto il piano, per le viti della vasca |
| 4 | inserti in ottone a caldo M3 × 5 × 4 (tipo Voron: Ø5 in testa, lunghi 4 mm; fori da 4,4 × 4,5): nei tubi sotto il piano, per le barre |
| 12 | viti M4 × 30 a testa cilindrica bombata (DIN 7985): da sotto la vasca, dentro le colonnine, negli inserti dei tubi del piano |
| 8 | viti M3 × 10 a testa cilindrica bombata (DIN 7985): barre → tubi del piano e barre → telaio del display |
| 6 | viti M3 × 10 a testa svasata piana (DIN 965): encoder → piano, dall'alto, a filo del piano; nell'encoder entrano 6 mm |
| 4 | rondelle M12 (24 × 13 × 2,5), due per manopola: fanno da volano |

Collegamenti e configurazione degli encoder: [deploy/raspberry/README.md](../../deploy/raspberry/README.md),
schema degli encoder ottici (`pulses_per_revolution: 600`, `debounce_us: 0`).

## Montaggio

1. Inserti a caldo nei tubi sotto il piano (12 M4 per le viti della vasca, 4 M3 per le barre), con
   la punta del saldatore a circa 230-240 °C per il PETG. Sopra gli inserti restano 4,5 mm di piano
   (4 sopra quelli delle barre).
2. Appoggiare le due metà del piano a faccia in giù, accostate alla giunta, e incollare da sotto la
   cornice del vetro: il labbro entra nell'apertura e allinea le metà, la flangia va incollata sotto
   il piano. La cornice sta a cavallo della giunta e unisce le due metà.
3. Incollare anelli, lettere di DASH e indicatori nelle sedi del piano e delle manopole, e il logo
   nelle sedi del fianco della vasca. Le lettere che stanno a cavallo della giunta si incollano dopo
   aver unito le metà.
4. Mettere il display nell'apertura dall'alto, con il vetro sul labbro della cornice, e avvitare sotto
   le quattro barre corte, una per angolo: al telaio del display (asola, sulla borchia del foro) e
   al tubo del piano. Sotto le teste delle viti le barre hanno dei rialzi, così le M3 × 10 non
   toccano il fondo dei fori. Le barre tengono il vetro contro la cornice: si stringono senza forzare,
   perché la cornice è solo incollata. Il centro del telaio resta libero per la scheda del display
   e il Pi, con i loro connettori.
5. Encoder da sotto, con 3 viti dall'alto ciascuno; SELECT e USE con il dado; DASH si aggancia a
   scatto nel suo foro; il Raspberry dietro al display, sui suoi distanziali.
6. Vasca: calare la metà G2 sulla G1 dall'alto, facendo entrare le code di rondine nelle sedi.
   Avvitare la presa alla sua placca e infilare la placca dall'alto nelle guide del fianco
   posteriore. Infilare dall'alto gli altoparlanti nelle guide dei fianchi corti, con il cono verso
   le feritoie. Il bordo appoggia su due distanziali della parete, così la membrana resta a 1,5 mm
   dalla plastica; le costole sul labbro si schiacciano e li tengono fermi,
   senza vibrare. Se il bordo è più sottile della gola (5,7 mm), un anello di gommapiuma adesiva
   sul bordo, dalla parte del labbro, prende il gioco.
7. Cablare, appoggiare il piano sulla vasca e avvitarlo da sotto con le 12 viti M4 × 30, che passano
   dentro le colonnine; le teste stanno nelle sedi in fondo alle colonnine.
8. Rondelle nella sede sotto la manopola, poi il mozzo scelto da sotto, attraverso le rondelle,
   incollato nella sede dentata: la flangia del mozzo chiude le rondelle nella sede. Poi le manopole
   sugli alberi, senza grano. Infine i piedini sotto la vasca.

## Da verificare prima di stampare

- **Spessore del vetro** (`vetro_sp`, ora 1,1 mm): il disegno ufficiale non lo quota. Si misura
  col calibro e si cambia il parametro: il labbro della cornice si rifà da solo.
- **Raggio degli angoli del vetro** (ora 6,5 mm: non è quotato, sugli esemplari si misura 6,5-7 mm) e **fori M3 del telaio**: le asole delle
  barre assorbono ±4 mm in lunghezza, non in larghezza.
- **Altezza delle borchie dei fori M3** (ora 2,5 mm dal dietro del telaio, cioè 8,46 mm dal vetro):
  le barre appoggiano lì. Se sporgono meno, le barre tirano giù il display e il vetro scende sotto
  il piano: una rondella M3 tra barra e borchia. Se sporgono di più, le barre spingono il vetro
  fuori dalla cornice: una rondella tra barra e tubo.
- **Spessore del piano attorno a DASH** (ora 3 mm): i venditori danno i Sanwa OBSF-30 per pannelli
  da 2 a 3,7-4 mm. Conta la distanza tra il sotto della ghiera e i denti dei ganci.
- **Foro dell'albero nei mozzi**: disegnato su un albero Ø6 con il taglio a 2,1 mm dall'asse (poco
  più di 5 mm dal lato tondo), più il gioco del mozzo. Se nessuno dei cinque mozzi va bene, si
  cambiano i giochi.
- **Fori degli inserti** (ora Ø5,6 per gli M4 larghi 6 mm e Ø4,4 per gli M3 × 5 × 4, come da CNC
  Kitchen e ruthex): con altre marche conviene provare l'inserto in un foro di prova prima di
  stampare il piano.
- **Spessore degli altoparlanti** (ora 5,4 mm, lo spessore totale dichiarato): conta quello nei 2 mm
  esterni, dove li tiene il labbro delle guide. Se è più sottile, un anello di gommapiuma sul bordo
  prende il gioco; oppure si adattano le guide allo spessore misurato.
- **Presa di alimentazione**: la placca micro-USB è per una prolunga con le viti a 28 mm. Con
  un'altra presa si usa o si rifà un'altra placca: il resto della console non cambia.
- **Encoder**: misure dei venditori (corpo Ø38 × 35,5, collare Ø20 × 5, albero Ø6 × 13 con il taglio a poco più di 5 mm dal lato tondo,
  fori M3 sul cerchio Ø30).
