# H42N42 — Fiche technique

Complément de `PLAN.md`. Décrit : les structures, chaque fonction nécessaire (signature + rôle), les flux de chaque intégration, et comment les modules interagissent.

Convention : tout le code de jeu est côté client (`[%%client ...]`). Seul `h42n42.eliom` a une section serveur (le service qui rend la page). Un seul `[%%shared]` : rien (pas de RPC).

---

## 0. Graphe de dépendances des modules (ordre de compilation)

OCaml interdit les cycles ⇒ l'état partagé et le type `creet` vivent dans un module **feuille** (`types`). Les modules « hauts » (game, panel) orchestrent ; les modules « bas » (creet, spatial, audio, stats) ne connaissent jamais `game`.

```
config ──► types ──┬──► spatial ──┐
                   ├──► audio     │
                   ├──► stats     ├──► creet ──► drag ──► game ──► panel ──► h42n42
                   └──► fx  ──────┘                        ▲
                                                           └── stats, audio, spatial, config
```

| Module | Dépend de | Fournit |
|---|---|---|
| `config` | — | refs de paramètres (sliders), constantes géométriques |
| `types` | config | `state`, `creet`, `world` (état global mutable), `Ev` hooks |
| `spatial` | types | grille de hachage + fallback naïf |
| `audio` | config | `play`, `music_start`, volumes |
| `stats` | types | compteurs, score, leaderboard |
| `fx` | types | particules, flashs (bonus 1) |
| `creet` | types, config, spatial, audio, stats, fx | création, thread de vie, mutations, mort |
| `drag` | types, config, creet, audio, stats, fx | drag & drop, soin à l'hôpital |
| `game` | tous ci-dessus | start / spawner / difficulté / watchdog / game over / pause / reset |
| `panel` | game, config, stats, spatial, audio | control panel, dashboard, FPS |
| `h42n42` | panel, game, config | page HTML (serveur) + bootstrap client |

---

## 1. `config.eliom` — paramètres

Toutes les valeurs modifiables à chaud par le panel sont des `ref` lues **à chaque frame** par les boucles (aucune copie locale) ⇒ effet immédiat sans restart (bonus 2).

```ocaml
(* géométrie logique, en px ; le board est ensuite mis à l'échelle en CSS *)
let board_w    = 1000.   let board_h   = 700.
let river_h    = 80.     let hospital_h = 90.
let base_diam  = 40.

(* paramètres live *)
let speed_base      = ref 90.    (* px/s *)
let speed_mult      = ref 1.0    (* difficulté, monte avec le temps *)
let contam_prob     = ref 0.02   (* par frame en contact *)
let spawn_interval  = ref 4.0    (* s *)
let initial_creets  = ref 8
let berserk_prob    = ref 0.10
let mean_prob       = ref 0.10
let accel_step      = ref 0.08   (* +8 % de speed_mult tous les accel_period *)
let accel_period    = 5.0        (* s *)
let grace_period    = 60.0       (* s sans accélération *)

let sick_speed_factor = 0.85
let berserk_growth    = 1.10     let berserk_tick = 10.0   let berserk_max = 4.0
let mean_size_factor  = 0.85     let mean_lifetime = 60.0
let mutation_tick     = 10.0
let dir_change_min    = 2.0      let dir_change_max = 5.0

(* toggles *)
let paused              = ref false
let optimized_collision = ref true
let difficulty : [`Easy|`Normal|`Hard] ref = ref `Normal
let set_difficulty d = difficulty := d; accel_step := (match d with `Easy -> 0.04 | `Normal -> 0.08 | `Hard -> 0.15)
```

---

## 2. `types.eliom` — structures et état global

```ocaml
type state = Healthy | Sick | Berserk | Mean

type creet = {
  id            : int;
  el            : Dom_html.divElement Js.t;      (* To_dom.of_div, créé avec Html.D *)
  mutable x     : float;  mutable y : float;     (* coin haut-gauche, px logiques *)
  mutable vx    : float;  mutable vy : float;    (* px/s, norme = vitesse courante *)
  mutable diam  : float;
  mutable state : state;
  mutable dragging : bool;
  mutable alive : bool;
  mutable cell  : (int * int) option;            (* cellule courante dans la grille *)
  mutable next_turn : float;                     (* timestamp (s) du prochain changement de cap *)
  mutable threads : unit Lwt.t list;             (* boucle de vie + timers (mutation, croissance, mean) *)
}

(* état global du monde : une seule instance, mutable *)
type world = {
  mutable creets   : creet list;
  mutable started_at : float;   (* s, Js.date now /. 1000. *)
  mutable elapsed  : float;     (* s, hors pause *)
  mutable over     : bool;
  mutable next_id  : int;
  mutable sys_threads : unit Lwt.t list;  (* spawner, difficulté, watchdog, hud *)
}
let world = { creets = []; started_at = 0.; elapsed = 0.; over = false; next_id = 0; sys_threads = [] }

(* helpers géométriques *)
let center c = (c.x +. c.diam /. 2., c.y +. c.diam /. 2.)
let radius c = c.diam /. 2.
let touching a b =
  let (ax,ay) = center a and (bx,by) = center b in
  let dx = ax -. bx and dy = ay -. by in
  dx *. dx +. dy *. dy < (radius a +. radius b) ** 2.
let count st = List.length (List.filter (fun c -> c.alive && c.state = st) world.creets)
let now () = Js.to_float (new%js Js.date_now)##getTime /. 1000.

(* hooks d'événements : évitent que creet dépende de game/panel.
   game/panel s'abonnent ; creet/drag émettent. *)
type event = Contaminated of creet | Healed of creet | Died of creet | Spawned of creet | Mutated of creet
let listeners : (event -> unit) list ref = ref []
let emit e = List.iter (fun f -> f e) !listeners
let on f = listeners := f :: !listeners
```

`emit` est **synchrone** : audio, stats, fx s'abonnent dans `Game.start` ; les modules bas n'ont qu'à appeler `Types.emit`.

---

## 3. `spatial.eliom` — grille de hachage (bonus 5) + naïf

Cellule = `cell_size = base_diam *. berserk_max` (le plus gros creet possible tient dans une cellule ⇒ 9 cellules suffisent pour tout contact).

```ocaml
let cell_size = Config.(base_diam *. berserk_max)
let grid : ((int*int), creet list ref) Hashtbl.t = Hashtbl.create 64

let key_of c : int * int            (* centre / cell_size, floor *)
let remove c : unit                 (* retire de sa cellule courante (c.cell) *)
let update c : unit                 (* si key_of c <> c.cell : remove + insert ; appelé après chaque move *)
let clear () : unit                 (* reset *)
let neighbors_grid c : creet list   (* les 9 cellules autour, alive, <> c *)
let neighbors_naive c : creet list  (* world.creets alive <> c *)
let neighbors c = if !Config.optimized_collision then neighbors_grid c else neighbors_naive c
let nearest_healthy c : creet option
  (* optimisé : anneaux de cellules croissants jusqu'à trouver ≥1 Healthy, puis min distance ;
     naïf : scan complet. *)
```

Complexité : voisinage O(k) (k = densité locale) vs O(n) ; par frame O(n·k) vs O(n²). Doc de l'algo en tête de fichier (exigé par le barème).

---

## 4. `audio.eliom` — bonus 3

```ocaml
type cat = Music | Sfx
let sound_on   = ref true
let vol_music  = ref 0.5   let vol_sfx = ref 0.8
let sfx_on     = ref true  let music_on = ref true

val load : string -> Dom_html.audioElement Js.t option   (* createAudio "audio/<name>.<ext>" ; None si 404 → silencieux *)
val music_start : unit -> unit     (* loop=true, play ; appelé au 1er clic (autoplay policy) *)
val play : string -> unit          (* cloneNode du sfx préchargé, volume = vol_sfx, play ; no-op si muted *)
val set_volume : cat -> float -> unit
val toggle_mute : unit -> unit
val toggle_cat : cat -> unit
```

Abonnement dans `Game.start` : `Types.on (function Contaminated _ -> play "contaminate" | Healed _ -> play "heal" | Died _ -> play "death" | Spawned _ -> play "spawn" | Mutated _ -> ())` + `play "gameover"` dans `Game.game_over`.
Fichiers : `static/audio/{music,contaminate,heal,death,gameover,spawn}.<ext>` — **fournis par l'utilisateur**, `ext` dans `Config` (`"mp3"` par défaut).

---

## 5. `stats.eliom` — bonus 4

```ocaml
type t = { mutable saved:int; mutable lost:int; mutable max_alive:int;
           mutable berserk_seen:int; mutable mean_seen:int; mutable spawned:int }
let s = { ... }
val reset : unit -> unit
val survival : unit -> float           (* world.elapsed *)
val efficiency : unit -> float         (* saved / max 1 (saved+lost) *)
val score : unit -> int                (* survival*10 + saved*100*efficiency *)
val on_event : Types.event -> unit     (* Healed→saved++, Contaminated→lost++, Mutated→berserk/mean_seen++, Spawned→max_alive *)
val leaderboard : unit -> (string * int * float) list   (* (date, score, survival), top 5, localStorage "h42n42_lb" *)
val push_score : unit -> unit          (* insère, trie, tronque à 5, réécrit localStorage *)
```

localStorage : `Dom_html.window##.localStorage` (Js.Optdef) ; sérialisation JSON manuelle (une ligne par entrée `date;score;survival`) — `// ponytail: CSV-in-a-string, no JSON lib`.

---

## 6. `fx.eliom` — effets visuels (bonus 1)

```ocaml
val particles : creet -> unit
  (* crée 6 div.particle (Html.D) à la position du centre, angle aléatoire via CSS var --dx/--dy,
     appendChild dans #field ; Lwt_js_events.animationend → removeChild *)
val flash : creet -> string -> unit
  (* ajoute la classe (ex "flash-heal"), Lwt_js.sleep 0.4 >>= retire *)
```

Abonné dans `Game.start` : `Contaminated c -> particles c`, `Healed c -> flash c "flash-heal"`, `Mutated c -> flash c "flash-mutate"`.

---

## 7. `creet.eliom` — le cœur

### 7.1 Création

```ocaml
val make : ?x:float -> ?y:float -> unit -> creet
```
1. `id = world.next_id++`.
2. `el = Html.D.div ~a:[a_class ["creet";"healthy"]] [] |> To_dom.of_div`.
3. Position aléatoire dans la zone jouable `[0, W-d] × [river_h, H-hospital_h-d]` (spawn jamais dans la rivière/hôpital) ; angle aléatoire → `vx, vy`.
4. `Manip.appendChild field el` (field = `Of_dom`… on garde une ref D sur `#field` créée côté serveur et passée via `~%`).
5. `Spatial.update c` ; `world.creets <- c :: world.creets`.
6. `Drag.attach c` **non** — cycle : `drag` dépend de `creet`. Solution : `make` retourne le creet, c'est `Game.spawn` qui appelle `Creet.make` puis `Drag.attach` puis `Creet.run`.
7. `Types.emit (Spawned c)`.

### 7.2 Rendu

```ocaml
val render : creet -> unit
  (* el.style.left/top/width/height ← x,y,diam ; className ← "creet " ^ state_class ^ (if dragging " dragging") *)
val speed : creet -> float
  (* !speed_base *. !speed_mult *. (if state = Healthy then 1. else sick_speed_factor) *)
val set_velocity_angle : creet -> float -> unit   (* vx,vy = speed·cos/sin *)
val set_state : creet -> state -> unit           (* change state, retaille (Mean → 0.85·base), re-normalise vx,vy, render, emit *)
```

### 7.3 Boucle de vie (un thread Lwt par creet)

```ocaml
val run : creet -> unit
let run c =
  let rec loop last =
    let%lwt () = Lwt_js_events.request_animation_frame () in
    let t = now () in
    let dt = min 0.05 (t -. last) in          (* clamp : onglet en arrière-plan *)
    if c.alive then begin
      if not !Config.paused && not c.dragging then step c t dt;
      loop t
    end else Lwt.return_unit
  in
  c.threads <- Lwt.catch (fun () -> loop (now ())) (function Lwt.Canceled -> Lwt.return_unit | e -> Lwt.fail e) :: c.threads
```

`step c t dt` :
1. **Cap** : si `t >= c.next_turn` → nouvel angle aléatoire (Healthy/Sick/Berserk), `next_turn <- t + rand(2,5)`. Si `Mean` : `Spatial.nearest_healthy c` → angle vers sa cible (à chaque frame, pas de next_turn).
2. **Re-normalisation** : la vitesse cible dépend de `speed_mult` (live) → recalcul de `vx,vy` à partir de leur angle et de `speed c`.
3. **Déplacement** : `x += vx·dt ; y += vy·dt`.
4. **Rebonds + clamp** (angle d'incidence = réflexion) :
   ```
   if x < 0            then (x <- 0;            vx <- -vx)
   if x > W - diam     then (x <- W - diam;     vx <- -vx)
   if y < 0            then (y <- 0;            vy <- -vy)
   if y > H - diam     then (y <- H - diam;     vy <- -vy)
   ```
   Note : la limite haute est `0` (bord de la rivière incluse dans le board) → le creet **peut** toucher la rivière. Le berserk qui grandit près d'un bord est reclampé chaque frame ⇒ jamais hors zone.
5. **Rivière** : `state = Healthy && y < river_h` → `contaminate c`.
6. **Contagion** : `state = Healthy` → `List.exists (fun o -> o.state <> Healthy && not o.dragging && touching c o) (Spatial.neighbors c)` → `if Random.float 1. < !contam_prob then contaminate c`.
7. `Spatial.update c ; render c`.

### 7.4 Contamination et mutations

```ocaml
val contaminate : creet -> unit
let contaminate c =
  if c.state = Healthy && not c.dragging then begin
    set_state c Sick; emit (Contaminated c);
    c.threads <- mutation_timer c :: c.threads
  end

let rec mutation_timer c =            (* toutes les 10 s tant que Sick *)
  let%lwt () = sleep_unpaused Config.mutation_tick in
  if c.alive && c.state = Sick then
    if Random.float 1. < !berserk_prob then go_berserk c
    else if Random.float 1. < !mean_prob then go_mean c
    else mutation_timer c
  else Lwt.return_unit

let go_berserk c = set_state c Berserk; emit (Mutated c); c.threads <- growth_timer c :: c.threads
let rec growth_timer c =              (* +10 % / 10 s ; meurt à 4× *)
  let%lwt () = sleep_unpaused Config.berserk_tick in
  if c.alive then begin
    c.diam <- c.diam *. Config.berserk_growth;
    (* recentrer : garder le centre fixe → x -= Δ/2, y -= Δ/2, puis clamp *)
    if c.diam >= Config.(base_diam *. berserk_max) then die c else growth_timer c
  end else Lwt.return_unit

let go_mean c = set_state c Mean; emit (Mutated c);
  c.threads <- (let%lwt () = sleep_unpaused Config.mean_lifetime in if c.alive then die c; Lwt.return_unit) :: c.threads
```

`sleep_unpaused d` : boucle `Lwt_js.sleep 0.1` en décomptant `d` seulement si `not !paused` (la pause gèle les timers, sinon un berserk meurt pendant la pause).

Healed (depuis `drag`) : `set_state c Healthy` remet la taille de base et annule le `mutation_timer` (il se termine seul car `state <> Sick`).

### 7.5 Mort

```ocaml
val die : creet -> unit
let die c =
  c.alive <- false;
  List.iter Lwt.cancel c.threads;
  Spatial.remove c;
  world.creets <- List.filter (fun o -> o != c) world.creets;
  (* animation de sortie : classe "dying", Lwt_js.sleep 0.4 puis removeChild *)
  emit (Died c)
```

`grabbable c = c.alive && (c.state = Healthy || c.state = Sick)`.

---

## 8. `drag.eliom` — souris (exclusivement `Lwt_js_events`)

```ocaml
val attach : creet -> unit
let attach c =
  Lwt.async (fun () ->
    Lwt_js_events.mousedowns c.el (fun ev _ ->
      if Creet.grabbable c && not !Config.paused then begin
        Dom.preventDefault ev;
        c.dragging <- true; Creet.render c;
        let offset = (mouse_to_board ev) - (c.x, c.y) in
        let%lwt () = Lwt.pick [
          Lwt_js_events.mousemoves Dom_html.document (fun ev _ -> move c offset ev; Lwt.return_unit);
          Lwt_js_events.mouseup    Dom_html.document >>= fun _ -> Lwt.return_unit;
          Lwt_js_events.mouseleave Dom_html.document##.documentElement >>= fun _ -> Lwt.return_unit ] in
        drop c; Lwt.return_unit
      end else Lwt.return_unit))
```

- `mouse_to_board ev` : `(clientX - rect.left) / scale`, `(clientY - rect.top) / scale` avec `rect = board##getBoundingClientRect` et `scale = rect.width / board_w` (responsive).
- `move c offset ev` : `x,y ← pos - offset` **clampé** dans `[0, W-d] × [0, H-d]` ⇒ un drop hors board / hors fenêtre ramène le creet au bord le plus proche, il reprend sa trajectoire de là (respect des deux exigences : « dropable partout » + « jamais hors zone »). `Spatial.update ; render`.
- `drop c` : `dragging <- false` ; si `in_hospital c` (`center_y > H - hospital_h`) et `state = Sick` → `heal c` ; `render c`.
- `heal c` : `Creet.set_state c Healthy` (taille, vitesse, couleur restaurées) ; `emit (Healed c)`. Un Sick qui **entre seul** dans l'hôpital n'est pas soigné (heal appelé uniquement depuis `drop`).
- Invulnérabilité : `step` ne s'exécute pas quand `dragging`, et `contaminate` refuse si `dragging`. Un creet dragged dans la rivière n'est pas contaminé **pendant** le drag ; au drop dans la rivière, la frame suivante le contamine (comportement attendu).

---

## 9. `game.eliom` — orchestration

```ocaml
val spawn : ?x:float -> ?y:float -> unit -> creet     (* Creet.make → Drag.attach → Creet.run *)
val start : unit -> unit
val pause : unit -> unit / resume / toggle_pause
val reset : unit -> unit
val game_over : unit -> unit
val stress : int -> unit                                (* bonus 5 : spawn n creets pour la démo *)
```

`start ()` :
1. `Types.listeners := []` ; abonne `Stats.on_event`, `Audio.on_event`, `Fx.on_event`, `Panel.on_event` (via un hook fourni par h42n42 pour éviter le cycle game→panel : `Game.extra_listeners : (event->unit) list ref` rempli par `Panel`).
2. `Stats.reset ()`, `Spatial.clear ()`, `world.{creets=[]; over=false; elapsed=0; started_at=now}`, `speed_mult := 1.0`.
3. `for _ = 1 to !initial_creets do spawn () done`.
4. Lance et stocke dans `world.sys_threads` :
   - **spawner** : `loop : sleep_unpaused !spawn_interval → if count Healthy > 0 then spawn () ; loop`. (La valeur de `spawn_interval` est relue à chaque tour → slider effectif.)
   - **difficulty** : `sleep_unpaused grace_period` puis `loop : sleep_unpaused accel_period → speed_mult := !speed_mult *. (1 + !accel_step)`.
   - **clock/watchdog** : `loop : request_animation_frame → if not paused then elapsed += dt ; if count Healthy = 0 then game_over () else loop`.
   - **fps** : compteur incrémenté par le clock, lu/reset toutes les 1 s par Panel.

`game_over ()` : `world.over <- true` ; cancel `sys_threads` ; `List.iter (fun c -> List.iter Lwt.cancel c.threads) world.creets` (creets gelés à l'écran) ; `Stats.push_score ()` ; `Audio.play "gameover"` ; `Panel.show_gameover ()` (via hook `on_game_over : (unit -> unit) ref`).

`reset ()` : cancel tout, `Manip.removeChildren field`, `Manip.removeChildren particles`, `start ()`.

Condition de fin : **0 Healthy vivant** (couvre « tous morts ou contaminés » du sujet ; les Sick restants n'ont plus d'issue puisque le spawn s'arrête ⇒ fin immédiate, message clair).

---

## 10. `panel.eliom` — UI (bonus 2, 4, 5)

Tous les éléments construits avec `Eliom_content.Html.D` côté client et insérés dans `#panel` / `#hud` / `#gameover` (créés vides côté serveur).

```ocaml
val slider : label:string -> min:float -> max:float -> step:float -> float ref -> [> Html_types.div ] elt
  (* input type=range (D) ; Lwt_js_events.inputs → r := float_of_string value ; affiche la valeur *)
val int_slider : ... -> int ref -> ...
val button : string -> (unit -> unit) -> elt          (* Lwt_js_events.clicks *)
val build : unit -> unit
  (* sliders : speed_base, contam_prob, spawn_interval, initial_creets, berserk_prob, mean_prob
     boutons : Pause/Resume, Reset, Easy/Normal/Hard, Stats on/off, Collision naive/grid, Stress +100,
               Mute, sliders vol musique / vol SFX
     zone live : healthy / sick / berserk / mean / elapsed / saved / FPS *)
val hud_loop : unit -> unit Lwt.t     (* sleep 0.25 → met à jour les compteurs (Types.count, Stats, fps) *)
val toggle_dashboard : unit -> unit   (* classe "hidden" sur #dashboard *)
val show_gameover : unit -> unit      (* remplit #gameover : GAME OVER, tableau stats, score, leaderboard, bouton Restart → Game.reset *)
```

Aucun `document.getElementById` pour créer : on récupère les conteneurs serveurs via `~%field_elt` etc. (valeurs D injectées dans le client).

---

## 11. `h42n42.eliom` — page et bootstrap

Serveur :
```ocaml
let%server field    = Html.D.div ~a:[a_id "field"] []
let%server river    = Html.D.div ~a:[a_id "river"] []
let%server hospital = Html.D.div ~a:[a_id "hospital"] []
let%server board    = Html.D.div ~a:[a_id "board"] [river; field; hospital]
let%server panel    = Html.D.div ~a:[a_id "panel"] []
let%server gameover = Html.D.div ~a:[a_id "gameover"; a_class ["hidden"]] []
let%server page ()  = html (head (title …) [css_link …]) (body [board; panel; gameover])
App.register ~service:main_service (fun () () ->
  ignore [%client (Main.init ~%board ~%field ~%panel ~%gameover : unit)];   (* bootstrap client *)
  Lwt.return (page ()))
```

Client `init` : stocke les refs D dans `Types.dom` (record de `elt`), `Panel.build ()`, `Audio.preload ()`, calcule l'échelle responsive (`Lwt_js_events.onresizes` → `board.style.transform = scale(k)`), `Game.start ()`, `Lwt_js_events.click document` une fois → `Audio.music_start ()`.

---

## 12. Flux par intégration (séquences)

**F1 — Chargement** : navigateur → ocsigenserver sert `page()` + `h42n42.js` → `init` → `Panel.build` → `Game.start` → N × `spawn` → chaque creet a son thread `run` + `Drag.attach`.

**F2 — Une frame d'un creet** : `request_animation_frame` → `step` (cap → vitesse → move → bounce/clamp → rivière → contagion via `Spatial.neighbors` → `Spatial.update` → `render`).

**F3 — Contamination** : `step` détecte contact/rivière → `contaminate` → `set_state Sick` (vitesse ×0.85, classe CSS) → `emit Contaminated` → Stats.lost++, Audio "contaminate", Fx.particles → `mutation_timer` démarre (10 s).

**F4 — Mutation** : `mutation_timer` → 10 % Berserk (`growth_timer` : ×1.10/10 s → `die` à 4×) | 10 % Mean (taille 0.85, chasse via `nearest_healthy`, `die` après 60 s) | sinon re-timer.

**F5 — Drag & drop** : `mousedowns el` → `grabbable ?` → `dragging=true` (step suspendu, immunité) → `mousemoves document` clampés → `mouseup|mouseleave` → `drop` → hôpital && Sick ? `heal` (Healthy, base size, emit Healed → Stats.saved++, Audio "heal", Fx.flash) : reprise du mouvement.

**F6 — Spawn** : `spawner` → `count Healthy > 0 ?` → `spawn` → `emit Spawned` → Stats.max_alive, Audio "spawn".

**F7 — Difficulté** : `difficulty` thread → `speed_mult` ↑ → relu par `Creet.speed` à chaque frame → tous les creets accélèrent ; `spawn_interval` libre au slider.

**F8 — Game over** : watchdog `count Healthy = 0` → `game_over` → cancel threads, gel, `Stats.push_score`, Audio "gameover", `Panel.show_gameover` (overlay « GAME OVER » + stats + score + leaderboard + Restart → `Game.reset`).

**F9 — Panel live** : `inputs` slider → écrit la `ref` → lue à la frame/tour suivant. Pause : `paused := true` → `step` sauté, `sleep_unpaused` gelé, drag refusé ; `elapsed` gelé.

**F10 — Collision toggle / FPS** : bouton → `optimized_collision := not` → `Spatial.neighbors` bascule ; `Stress +100` → 100 × `spawn` ; FPS = frames comptées par le clock / s, affiché par `hud_loop`.

---

## 13. CSS (bonus 1) — points d'accroche

- `.creet` : `position:absolute; border-radius:50%; background: url(img/creet_<state>.svg) center/contain; transition: background .3s, transform .2s, box-shadow .3s; box-shadow: 0 4px 8px rgba(0,0,0,.35)`.
- `.creet.healthy|.sick|.berserk|.mean` : sprite + couleur de fond distincte (vert / rouge / brun + `animation: pulse 1s infinite` glow / noir).
- `.creet.dragging` : `transform: scale(1.15); z-index; cursor:grabbing; box-shadow renforcé`.
- `.creet.dying` : `opacity 0 + scale 0` sur `.4s`.
- `.flash-heal`, `.flash-mutate` : keyframes courtes.
- `.particle` : `animation: burst .6s forwards` utilisant `--dx/--dy`.
- `#river` : `background: url(img/river.svg) repeat-x; animation: flow 6s linear infinite` (background-position).
- `#hospital` : image + léger pulse.
- Responsive : `#board { transform-origin: top left; }` échelle posée par JS ; `#panel` en colonne à droite (≥ 1200 px) ou sous le board (`@media`), jamais par-dessus le jeu.

---

## 14. Garde-fous « techniques » du barème

| Exigence | Où c'est garanti |
|---|---|
| 1 thread Lwt par creet, pas de setTimeout | `Creet.run` (`request_animation_frame`), timers `Lwt_js.sleep` ; `grep setTimeout src/` vide |
| Éléments dynamiques en TyXML | seul `Html.D.*` + `To_dom` + `Manip` ; aucun `Dom_html.createX` |
| Souris = Lwt_js_events uniquement | `drag.eliom`, `panel.eliom` (`clicks`, `inputs`, `mousedowns`, `mousemoves`, `mouseup`, `mouseleave`) |
| Message GAME OVER | `Panel.show_gameover` sur `#gameover` (overlay plein écran) |
| Makefile sans recompilation inutile | `dune build` (graphe de deps natif) |
| Jamais hors zone | clamp dans `step` et dans `Drag.move` |
| Pas de spawn sans sain | test dans `spawner` |
| Berserk/mean non grabbables/soignables | `Creet.grabbable`, `heal` uniquement si `Sick` |
