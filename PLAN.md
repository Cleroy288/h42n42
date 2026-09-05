

# Plan — H42N42 (Ocsigen/Eliom, client-side OCaml)

> Fiche technique détaillée (structures, signatures, flux, dépendances entre modules) : `SPEC.md`.

## Context

`/Volumes/SSD/PERSO/42/h42n42` ne contient que le sujet (`en.subject.pdf`, v6.0) et le barème (`Intra Projects h42n42 Edit.pdf`). Il faut créer le projet de zéro pour couvrir 100 % de la partie obligatoire **et** les 5 bonus (25 pts), avec un lancement en une commande `docker-compose up --build`.

Décisions actées :
- README + commentaires en **anglais**.
- Fichiers audio **fournis par l'utilisateur** dans `static/audio/` (noms convenus ci-dessous).
- **Aucun build Docker de mon côté** : pas d'OCaml/opam en local → le code est livré non compilé ; la vérification se fait par l'utilisateur (voir § Vérification). Boucle attendue : il colle les erreurs, je corrige.

Stack cible (vérifié sur opam, 2026-09) : Eliom **12.1.0** (≥ 10 exigé), js_of_ocaml ≥ 6.3.2 (≥ 5 exigé), OCaml **5.2** (≥ 4.14 exigé), ocsigenserver 7.x, tyxml 4.6, dune ≥ 3.19.
Base du build : template officiel `eliom-distillery` **`app.lib`** (dune) téléchargé dans `scratchpad/tpl/` (Makefile, Makefile.app, Makefile.options, dune, dune-project, conf.in, tools/gen_dune.ml, tools/check_modules.ml, tools/dune). On le réutilise en le simplifiant (pas de wasm, pas de DB, pas d'avatars, pas de i18n/rpc).

---

## 1. Arborescence livrée

```
h42n42/
├── Dockerfile
├── docker-compose.yml
├── .dockerignore  .gitignore
├── Makefile                 # all / clean / fclean / re / run  (wrappe dune → pas de recompilation inutile)
├── Makefile.options         # PROJECT_NAME, PORT=8080, chemins local/
├── Makefile.app             # rules du template (allégé : sans wasm/install/psql)
├── h42n42.conf.in           # config ocsigenserver (racine, comme exigé)
├── dune-project             # dialect eliom-server (copié du template)
├── README.md
├── src/
│   ├── dune                 # library server + subdir client (js) + gen (copié/adapté du template)
│   ├── tools/{dune,gen_dune.ml,check_modules.ml}
│   ├── h42n42.eliom         # server: service + page ; client: bootstrap
│   ├── config.eliom         # [%%client] paramètres mutables (sliders) + constantes
│   ├── creet.eliom          # [%%client] type creet, création DOM, thread Lwt par creet
│   ├── spatial.eliom        # [%%client] grille de hachage spatial (bonus 5) + naive
│   ├── drag.eliom           # [%%client] drag & drop Lwt_js_events
│   ├── game.eliom           # [%%client] world: spawn, difficulté, game over, pause/reset
│   ├── stats.eliom          # [%%client] stats, score, leaderboard localStorage (bonus 4)
│   ├── audio.eliom          # [%%client] musique + SFX + volumes (bonus 3)
│   └── panel.eliom          # [%%client] control panel + dashboard + FPS (bonus 2/4/5)
└── static/
    ├── css/h42n42.css       # thème, animations, particules, rivière animée, responsive
    ├── img/creet_{healthy,sick,berserk,mean}.svg, river.svg, hospital.svg  (SVG écrits à la main)
    └── audio/               # fournis par l'utilisateur (voir § 6)
```

`gen_dune.ml` lit `../../..` (= racine du dune root du dossier `gen/`). Comme `src/dune` déclare `(dirs tools client gen)` et que `gen/` est sous `src/`, `../../..` depuis `_build/default/src/gen` pointe sur `src/` → les `.eliom` de `src/` sont bien trouvés. Adapter `Makefile.app` : `_build/default/client/` → `_build/default/src/client/`, `_build/default/$(PROJECT_NAME).cm*` → `_build/default/src/`.
Le `Makefile.app` garde `config-files` (copie du `.js` hashé dans `local/var/www/h42n42/`, génération du `.conf` via `sed`). Supprimer : wasm, install.*, run.opt, psql, avatars, `%%DB_*%%`.

`Makefile` (racine) :
```
all:     dune build @h42n42 h42n42.cmxs ; make config-files ; copie static/
run:     ocsigenserver -c local/etc/h42n42/h42n42-test.conf
clean:   dune clean
fclean:  clean + rm -rf local
re:      fclean all
```

## 2. Docker

`Dockerfile` : `FROM ocaml/opam:debian-12-ocaml-5.2` → `apt-get install libgmp-dev libssl-dev libsqlite3-dev pkg-config m4` → `opam install -y eliom ocsipersist-sqlite` (couche cachée, ~15-20 min) → `COPY` sources → `RUN make` → `EXPOSE 8080` → `CMD ["make","run"]`.
`docker-compose.yml` : service `h42n42`, `build: .`, `ports: "8080:8080"`, `restart: unless-stopped`.
`.dockerignore` : `_build local .git`.

`h42n42.conf.in` = template `basic.ppx` (le plus simple) : staticmod, `ocsipersist-sqlite-config` (requis par eliom.server), `eliom.server`, `<static dir=local/var/www/h42n42>`, `<eliommodule module=…/h42n42.cma/>`, `<eliom/>`.

## 3. Partie obligatoire — mapping sujet/barème → implémentation

Page (server, `Eliom_content.Html.D`) : `#board` (aire de jeu 1000×700 px logiques) contenant `#river` (haut, h=80), `#field`, `#hospital` (bas, h=90) ; `#hud` (compteurs), `#gameover` overlay caché, `#panel` (bonus). Tout élément dynamique créé côté client avec `Eliom_content.Html.D.div` + `To_dom.of_div` + `Manip.appendChild` (jamais `Dom_html.createDiv`).

`config.eliom` — refs lues à chaud par les boucles : `speed_mult`, `contam_prob=0.02`, `spawn_interval=4.`, `initial_creets=8`, `berserk_prob=0.10`, `mean_prob=0.10`, `accel_per_min`, `paused`, `optimized_collisions`, `sound_on`.

`creet.eliom` :
```
type state = Healthy | Sick | Berserk | Mean
type t = { id; el; mutable x,y; mutable vx,vy; mutable diameter; base_diam;
           mutable state; mutable dragging; mutable alive; mutable cell;
           mutable sick_since; mutable next_dir_change; thread : unit Lwt.t }
```
- **Thread** : `let rec loop last = request_animation_frame () >>= fun () -> now → dt ; if not paused then step dt ; loop now`. Mouvement time-based (px/s × dt), donc fluide et indépendant du framerate. **Aucun setTimeout/setInterval** ; seul `Lwt_js_events.request_animation_frame` et `Lwt_js.sleep` (Lwt) sont utilisés.
- **Mouvement** : vitesse constante `base_speed × speed_mult × (Sick/Berserk/Mean → 0.85)`, angle aléatoire. Changement de direction aléatoire toutes 2–5 s. Rebond : `vx <- -vx` / `vy <- -vy` **+ clamp** position dans `[0, W-d] × [river_h, H-d]` avec `d` = diamètre courant (un berserk près du bord reste dedans, les creets atteignent bien les bords). Pas de collision creet/creet.
- **Contact** : `dist(c1,c2) < r1 + r2` sur centres/rayons courants (berserk grandi pris en compte).
- **Rivière** : `y < river_h` → Sick immédiat (sauf si `dragging`).
- **Contagion** : à chaque frame, pour un creet Healthy non dragged en contact avec un Sick/Berserk/Mean → `Random.float 1. < contam_prob` → Sick. Le check est fait dans le thread du creet **sain** via `Spatial.neighbors`.
- **Sick → mutation** : `Lwt_js.sleep 10.` en boucle tant que `Sick` : 10 % Berserk sinon 10 % Mean (exclusifs, définitifs).
- **Berserk** : boucle `sleep 10.` → `diameter *= 1.10` ; meurt quand `diameter >= 4 × base` (≈15 paliers ≈ 2 min 30). Non grabbable, non soignable.
- **Mean** : `diameter = 0.85 × base` ; chaque frame vise le Healthy le plus proche (`Spatial.nearest_healthy`) ; meurt après `sleep 60.`. Non grabbable, non soignable.
- **Mort** : `alive <- false`, `Lwt.cancel thread`, retrait DOM + grille, stats.
- **Visuel** : classe CSS `creet healthy|sick|berserk|mean|dragging` + `style.left/top/width/height` ; `data-` rien de plus.

`drag.eliom` (100 % `Lwt_js_events`) : `mousedowns el` → si `state ∈ {Healthy, Sick}` : `dragging <- true` ; `Lwt.pick [mousemoves document ; mouseups document]` ; pendant le drag la position suit la souris **clampée dans `#board`** (donc jamais hors aire, même si la souris sort de la fenêtre) ; `mouseup` : si centre dans `#hospital` et `Sick` → **heal** (Healthy, vitesse normale, couleur d'origine, feedback visuel) ; sinon reprend le mouvement depuis la position déposée. `mouseup` hors fenêtre : capté par `Lwt_js_events.mouseups Dom_html.document`, + `mouseleave` du `document.documentElement` traité comme un drop. Feedback : classe `.dragging` (scale + ombre).

`game.eliom` :
- `start ()` : reset stats, spawn `initial_creets`, lance thread **spawner** (`sleep spawn_interval` ; spawn seulement si `count Healthy > 0`), thread **difficulté** (`sleep 5.` → `speed_mult *= 1 + accel`), thread **watchdog** (frame : si `count Healthy = 0` → game over).
- `game_over ()` : cancel tous les threads, gèle les creets, affiche `#gameover` (« GAME OVER » + stats + score + bouton Restart).
- `pause/resume`, `reset` (cancel + vide `#field` + `start`).
- Difficulté : facile 60 s, puis accélération (+8 %/5 s en Normal) → inéluctable.

`spatial.eliom` : grille `cell = 64 px` (≥ diamètre max ≈ 4×base=…; on prend `cell = max_diameter` calculé), `Hashtbl (cx,cy) → t list`. `update c` (move entre cellules quand `cell` change), `neighbors c` (9 cellules), `nearest_healthy c` (anneaux croissants, fallback scan). `naive_neighbors` = liste complète. Toggle `optimized_collisions` bascule l'un ou l'autre. `// ponytail: ceil grid over quadtree — same big-O gain, 40 lines`.

## 4. Bonus (chacun = 5 pts)

1. **Graphics** : sprites SVG par état (`static/img/`), transitions CSS `transition: background .3s, transform .3s`, `@keyframes pulse` (berserk glow), `box-shadow`, rivière animée (`background-position` keyframes), particules à la contamination (6 petits `div.particle` créés en `Html.D`, retirés après `animationend` via `Lwt_js_events.animationends`), soin = flash vert, responsive (`#board` en `transform: scale(k)` calculé sur `innerWidth`, souris convertie via `getBoundingClientRect`).
2. **Control panel** : `input type=range` (D) pour speed / contam_prob / spawn_interval / initial_creets / berserk_prob / mean_prob, écoutés avec `Lwt_js_events.inputs` → écrivent les refs de `config` (effet immédiat). Boutons Pause/Resume, Reset, mode Easy/Normal/Hard (change `accel_per_min`). Infos live : healthy/sick/berserk/mean, durée, sauvés — rafraîchies par un thread `sleep 0.25`.
3. **Audio** : `Dom_html.createAudio`, musique `loop=true`, SFX rejoués par `cloneNode` (pas de coupure). Contrôles : mute global, volume musique, volume SFX, toggle par catégorie. Démarrage musique au premier clic (autoplay policy). Fichiers attendus (**à fournir**) : `static/audio/music.mp3`, `contaminate.mp3`, `heal.mp3`, `death.mp3`, `gameover.mp3`, `spawn.mp3` (ogg accepté : je lis l'extension depuis `config`). Un fichier absent = silencieux, pas d'erreur.
4. **Stats & score** : `survival_s`, `saved`, `lost`, `max_alive`, `berserk_seen`, `mean_seen` ; `score = survival_s×10 + saved×100 × (saved / max 1 (saved+lost))`. Dashboard toggle (bouton), écran game over détaillé, leaderboard top 5 en `localStorage` (`Dom_html.window##.localStorage`, JSON via `Js._JSON`).
5. **Collisions optimisées** : grille de `spatial.eliom`, toggle naive/optimized, **compteur FPS** (frames comptées dans un thread `sleep 1.`), bouton « Stress +100 » pour la démo. Doc de l'algo dans le README et en tête de `spatial.eliom`.

## 5. README.md (anglais)

Description/objectifs, prérequis (Docker, docker-compose), install, `docker-compose up --build`, `http://localhost:8080`, règles du jeu, contrôles, liste des bonus, algo de la grille spatiale, structure du repo, dev sans Docker (`make`, `make run`).

## 6. Ordre d'exécution

1. Squelette build : copier/adapter template (`dune-project`, `src/dune`, `src/tools/*`, `Makefile*`, `h42n42.conf.in`), `Dockerfile`, `docker-compose.yml`, `.gitignore`, `.dockerignore`, `h42n42.eliom` « hello ». → **checkpoint compile par l'utilisateur**.
2. `config`, `creet`, `spatial` (naive d'abord), `game` : creets qui bougent, rivière, contagion, berserk/mean, spawn, game over.
3. `drag` + hôpital.
4. CSS/sprites (bonus 1), `panel` (bonus 2), `stats` (bonus 4), grille + FPS (bonus 5), `audio` (bonus 3).
5. README, nettoyage, `git init` + premier commit (seulement si demandé).

## 7. Vérification (par l'utilisateur, je n'ai pas OCaml localement)

1. `docker compose up --build` → aucune erreur, page sur `http://localhost:8080`, console navigateur vide.
2. Checklist barème : creets fluides, rebonds corrects, aucun creet hors zone (y compris berserk au bord, drop hors zone/fenêtre), rivière contamine au toucher, pas de contagion sans contact, sick 15 % plus lent, berserk meurt ~2 min 30, mean meurt 60 s et poursuit les sains, berserk/mean non grabbables, soin uniquement par drop à l'hôpital (un sick qui y entre seul n'est pas soigné), plus de spawn sans sain, « GAME OVER » visible, difficulté croissante.
3. `grep -rn "setTimeout\|setInterval\|createDiv\|createElement" src/` → vide. `grep -rn "Lwt_js_events" src/drag.eliom` → tous les events souris.
4. `make` deux fois de suite → seconde invocation ne recompile rien (dune).
5. Bonus : sliders à chaud, pause/reset, mute + volumes séparés, dashboard toggle, écran final + leaderboard, toggle naive/optimized avec FPS à 100+ creets.
