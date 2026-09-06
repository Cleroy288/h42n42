# H42N42

Simulation of a creet population fighting a virus, written entirely with
**Ocsigen / Eliom / Lwt / Js_of_ocaml** (client-side simulation, server only
renders the page).

## Rules

- Creets move randomly on the board and bounce off the edges.
- The blue **river** at the top infects any healthy creet that touches it.
- A **sick** creet is 15% slower and can infect a healthy creet on contact
  (2% chance per contact frame).
- Every 10 s, a sick creet may mutate:
  - **Berserk** (10%): grows 10% every 10 s and dies at 4x its base size.
  - **Mean** (10%): shrinks to 85%, chases healthy creets, dies after 60 s.
- Drag & drop a sick creet into the green **hospital** to heal it
  (berserk and mean creets cannot be grabbed).
- A new creet spawns every 4 s while at least one healthy creet remains.
- After 60 s, the simulation speeds up by 8% every 5 s.
- When no healthy creet remains: **GAME OVER**.

## Modules

| File | Role |
|---|---|
| `config.eliom` | Constants and simulation parameters |
| `types.eliom` | `creet` / `world` types, geometry helpers |
| `creet.eliom` | Creature lifecycle: movement, infection, mutations, death |
| `drag.eliom` | Drag & drop and hospital healing |
| `game.eliom` | Spawner, difficulty, watchdog, game over |
| `h42n42.eliom` | Server page + client bootstrap |

## Run

With Docker (recommended, no local OCaml needed):

```sh
make            # docker compose up --build
```

With a local opam switch (dune, eliom < 12, ocsigen-ppx-rpc, ocsipersist-sqlite):

```sh
make run        # build + start ocsigenserver on port 8080
```

Then open http://localhost:8080/.
