; Generato da paddws-c64 params (rust/c64): non modificare a mano.
; Parametri del core Rust con Tuning::c64(): Fx Q16.16, reciproci Q8.24, tick a 50 Hz.
P_TICK_HZ              = $00000032   ; tick al secondo
P_WIDTH                = $01400000   ; campo
P_HEIGHT               = $00C80000   ; 
P_BALL_R               = $00020000   ; raggio della palla
P_BALL_R_BOOST         = $00030000   ; con il boost EVO
P_BALL_R_FWD           = $00020000   ; con il boost dello scatto
P_SERVE_UNIT           = $00007D71   ; velocità unitaria della battuta
P_SERVE_TICKS          = $00000019   ; attesa della battuta
P_PAD_HALF_W           = $00020000   ; metà larghezza della racchetta
P_PAD_H                = $00210000   ; altezza della racchetta
P_PAD_START            = $00140000   ; x della racchetta sinistra a casa
P_PAD_FWD              = $00500000   ; x della racchetta sinistra avanzata
P_PAD_MAX              = $0007599A   ; velocità massima
P_PAD_ACC              = $00002D29   ; accelerazione
P_PAD_FACC             = $00009687   ; accelerazione rapida
P_PAD_DECEL            = $00012D0E   ; frenata
P_PAD_STOP             = $00001EB8   ; sotto questa velocità si ferma
P_PAD_INV_HALF         = $000F83E1   ; Q8.24: 1 / metà altezza
P_WALL_INV_HALF        = $00028F5C   ; Q8.24: 1 / metà altezza del muro
P_BOOST_MUL            = $00020000   ; boost EVO
P_BOOST_FWD_MUL        = $00018000   ; boost dello scatto
P_BOOST_LEVELS         = $00000009   ; livelli dell'area boost
; altezza dell'area boost per livello
.define T_BOOST_H $00080000, $00060000, $00050000, $00040000, $00030000, $00020000, $00020000, $00010000, $00010000
; Q8.24: 1 / metà altezza dell'area boost per livello
.define T_BOOST_INV $00400000, $00555555, $00666666, $00800000, $00AAAAAB, $01000000, $01000000, $02000000, $02000000
; accelerazione della palla a ogni colpo, singolo, per difficoltà
.define T_KSPEED_1P $00010CCD, $0001199A, $00012666, $00014000
; velocità massima della palla, singolo
.define T_MAX_1P $0003EB85, $0004E666, $0005E148, $0007599A
; in due
.define T_KSPEED_2P $00012666, $00014000, $00014000, $00014CCD
; 
.define T_MAX_2P $0002F0A4, $0003EB85, $0004E666, $0005E148
; NEXT
.define T_KSPEED_NEXT $00010F5C, $0001199A, $000123D7, $00012E14
; 
.define T_MAX_NEXT $00036E14, $0004E666, $000563D7, $00065EB8
; NEXT
P_CAP_HALF             = $00050000   ; metà lato della capsula
P_CAP_SPEED            = $0001399A   ; velocità orizzontale della capsula
P_CAP_DRIFT            = $000025A2   ; deriva verticale
P_CAP_MARGIN           = $00140000   ; fascia in alto senza capsule (riserve)
P_SPAWN_TICKS          = $000000C8   ; tick tra due capsule
P_SPAWN_JITTER         = $00000032   ; più una parte casuale
P_SUPER_ODDS           = $00000008   ; una capsula su N è SUPER
P_SUPER_CUT            = $00002000   ; capsula: 16 bit casuali sotto questo valore = SUPER
P_BULLET_CUT           = $00003000   ; sotto questo = BULLET, sopra = bonus scelto
P_BULLET_RAMP          = $0000000D   ; rampa di entrata del BULLET, dallo scatto
P_BULLET_ZONE          = $00A00000   ; BULLET: scatta con la palla nella metà campo di chi lo attiva
P_BULLET_SHIFT         = $00000001   ; passo v - (v >> shift) dopo la rampa
P_BULLET_RSHIFT        = $00000002   ; e nella rampa
P_ENC_HAND_STEP        = $0008D1EC   ; passo dell'encoder prima del rallentamento
P_SLOW_TICKS           = $00000032   ; alone di SLOW
P_COOLDOWN             = $00000064   ; pausa tra due bonus
P_HITSTOP              = $00000008   ; fermo del SUPER con hit-stop
P_SMASH_MUL            = $00023333   ; 
P_SLOW_MUL             = $0000A666   ; 
P_SLOW_BACK            = $000189D9   ; SLOW: al colpo di chi l'ha usato (inverso di P_SLOW_MUL)
P_SUPER_MUL            = $00033333   ; 
P_CURVE_ACCEL          = $00002D29   ; 
P_STEER_ACCEL          = $00002D29   ; 
P_ARCADE_COOLDOWN      = $0000004B   ; ARCADE: pausa tra due bonus
P_ARCADE_SPAWN         = $00000096   ; ARCADE: tick tra due capsule
P_ARCADE_SHARE         = $00000002   ; ARCADE: capsule su 3 che vanno a lui
P_HAMMER_MUL           = $00014000   ; 
P_RUSH_MUL             = $00012666   ; RUSH: tiro dalla posizione avanzata
P_TWIST_TRANSFER       = $00008000   ; 
P_BLASTER_SHOTS        = $00000004   ; colpi del caricatore
P_BLASTER_GAP          = $0000000A   ; pausa tra due colpi
P_BLASTER_RELOAD       = $00000096   ; ricarica dal primo colpo
P_SHOT_SPEED           = $0006DC29   ; 
P_BLASTER_BAND         = $00030000   ; metà della fascia dei due colpi
P_BARRIER_X            = $00080000   ; GUARDIAN: x della barriera (lato sinistro)
P_PAD_MAX_SPEED        = $0007599A   ; velocità massima della racchetta (grafica di TWIST)
P_GUARDIAN_X           = $00080000   ; barriera dal bordo
P_GUARDIAN_TOP         = $00B40000   ; inizio del muro (sotto la banda delle riserve)
P_GUARDIAN_B1          = $00900000   ; confini tra i settori del muro
P_GUARDIAN_B2          = $006C0000   ; 
P_GUARDIAN_B3          = $00480000   ; 
P_GUARDIAN_B4          = $00240000   ; 
P_SUPER_METER_MAX      = $00000040   ; mosse speciali: barra piena (unità intere)
P_SUPER_COST           = $00000020   ; costo di una mossa (un settore)
P_SUPER_GAIN_HIT       = $00000002   ; barra: a ogni colpo
P_SUPER_GAIN_DASH      = $00000004   ; con lo scatto che intercetta la palla
P_SUPER_GAIN_CONCEDED  = $00000008   ; per un punto subito
P_SUPER_STRAIGHT_SHIFT = $00000000   ; STRAIGHT SHOT: boost += boost >> (shift + 2 - livello)
P_GHOST_PERIOD         = $00000014   ; GHOST: si vede ghost_visible tick ogni ghost_period
P_GHOST_VISIBLE        = $00000005   ; 
; tipi di racchetta (0-6, 7 senza tipo): altezza
.define T_KIND_H $001B0000, $00280000, $00210000, $00210000, $00250000, $001C0000, $001B0000, $00210000
; Q8.24: 1 / metà altezza
.define T_KIND_INV $0012F685, $000CCCCD, $000F83E1, $000F83E1, $000DD67D, $00124925, $0012F685, $000F83E1
; velocità massima e accelerazioni
.define T_KIND_MAX $0007599A, $0005E148, $00058333, $0007599A, $0007599A, $0007599A, $0007599A, $0007599A
; 
.define T_KIND_ACC $00002D29, $00002420, $000021DE, $00002D29, $00002D29, $00002D29, $00002D29, $00002D29
; 
.define T_KIND_FACC $00009687, $0000786C, $000070E5, $00009687, $00009687, $00009687, $00009687, $00009687
; x dello scatto in avanti (racchetta sinistra)
.define T_KIND_FWD $00500000, $00500000, $00500000, $00500000, $00500000, $006E0000, $00500000, $00500000
; con la racchetta avanzata
.define T_KIND_FMAX $0007599A, $0005E148, $00058333, $0007599A, $0007599A, $000873D7, $0007599A, $0007599A
; 
.define T_KIND_FWACC $00002D29, $00002420, $000021DE, $00002D29, $00002D29, $000033EF, $00002D29, $00002D29
; 
.define T_KIND_FWFACC $00009687, $0000786C, $000070E5, $00009687, $00009687, $0000AD1B, $00009687, $00009687
; spostamento massimo con l'encoder (0 = nessun limite)
.define T_KIND_STEP $00000000, $00070E56, $00069D71, $00000000, $00000000, $00000000, $00000000, $00000000
; CPU: previsione del punto d'arrivo a passi di un tick, al massimo:
P_PREDICT_MAX          = 213
P_ARRIVAL_MAX          = 213
P_CPU_LEVELS           = 11
P_CPU_RETURN           = 15   ; tick da avanzata, palla che si allontana, prima di tornare
P_CPU_BULLET_SHIFT     = 4   ; BULLET con la palla a meno di |dx| << shift
; tempo di reazione (tick)
.define T_CPU_REACTION 15, 14, 12, 10, 17, 15, 13, 13, 12, 13, 12
; usa il rapido
.define T_CPU_FAST 0, 1, 1, 1, 0, 0, 1, 1, 1, 1, 1
; prevede il punto d'arrivo
.define T_CPU_PREDICT 0, 1, 1, 1, 0, 0, 1, 1, 1, 1, 1
; scatto: una probabilità su N per tick (0 = mai)
.define T_CPU_FWD_ODDS 0, 13, 6, 3, 0, 0, 42, 33, 25, 23, 19
; NEXT: bonus, una probabilità su N per tick
.define T_CPU_BONUS_ODDS 100, 50, 25, 13, 100, 83, 75, 63, 50, 38, 29
; CPU per livello: palle mancate apposta, per mille
.define T_CPU_MISS $000000C8, $00000172, $0000012C, $000000DC, $000000F0, $000000C8, $000000AF, $000000B9, $000000A0, $000000AA, $000000AF
; errore di mira massimo
.define T_CPU_MAX_ERROR $000C8000, $000D5555, $000BAAAA, $000A0000, $000E2AAA, $000D5555, $000C8000, $000C8000, $000BAAAA, $000C8000, $000BAAAA
; distanza entro cui reagisce
.define T_CPU_REACT $00A00000, $01000000, $01200000, $01400000, $00900000, $00A00000, $00D00000, $00E00000, $00F00000, $00F99999, $01066666
; Q8.24: 1 / velocità massima della palla in Classic ed EVO, per difficoltà
.define T_CPU_INV_SPEED $00571323, $00414E60, $00343EB6, $002B8992
; in NEXT
.define T_CPU_INV_SPEED_NEXT $004AA2BF, $00343EB6, $002F7ED0, $0028303C
; CHALLENGE (rust/core/src/challenge.rs)
CH_LEVELS              = 7
CH_HIT                 = 10
CH_BOOST               = 40
CH_SUPER               = 100
CH_POINT               = 100
CH_WIN                 = 1000
CH_PERFECT             = 2000
CH_RALLY_STEP          = 4
CH_MAX_MULT            = 8
CH_TABLE               = 10
; livelli: racchetta della CPU
.define T_RUNG_KIND 0, 3, 2, 1, 4, 5, 6
; livello della CPU
.define T_RUNG_CPU 4, 5, 6, 7, 8, 9, 10
; velocità della palla (difficoltà con NORMAL)
.define T_RUNG_SPEED 0, 0, 0, 1, 1, 1, 2
; punti per vincere
.define T_RUNG_POINTS 5, 5, 5, 5, 5, 5, 5
; bonus della CPU, 3 per livello
.define T_RUNG_LOADOUT 2, 3, 1, 3, 6, 2, 1, 0, 2, 0, 2, 4, 1, 4, 3, 1, 6, 0, 4, 6, 1
; classifica iniziale: iniziali, punti (4 byte), livello
.define T_TABLE 80, 87, 83, 32, 78, 0, 0, 7, 80, 87, 83, 80, 70, 0, 0, 7, 80, 87, 83, 128, 62, 0, 0, 6, 80, 87, 83, 176, 54, 0, 0, 5, 80, 87, 83, 224, 46, 0, 0, 5, 80, 87, 83, 16, 39, 0, 0, 4, 80, 87, 83, 64, 31, 0, 0, 3, 80, 87, 83, 112, 23, 0, 0, 3, 80, 87, 83, 160, 15, 0, 0, 2, 80, 87, 83, 208, 7, 0, 0, 1
