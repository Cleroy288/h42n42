# H42N42 — Viral Ecosystem Simulation

> An interactive web-based biological ecosystem simulation built with **OCaml**, **Eliom**, **TyXML**, and **Lwt**, demonstrating client-side concurrency, event-driven drag and drop, and optimized spatial partitioning.

Developed to fulfill **100% of the mandatory requirements** and all **5 bonuses (25/25 bonus points)** per the 42 Network specification (`en.subject.pdf` v6.0).

---

## Table of Contents
1. [Project Overview](#project-overview)
2. [Game Rules & Mechanics](#game-rules--mechanics)
3. [Implemented Bonuses (25 Pts)](#implemented-bonuses-25-pts)
4. [Technical Architecture & Clean Code](#technical-architecture--clean-code)
5. [Spatial Partitioning Algorithm (Bonus 5)](#spatial-partitioning-algorithm-bonus-5)
6. [Prerequisites & Installation](#prerequisites--installation)
7. [Running with Docker Compose](#running-with-docker-compose)
8. [Local Development (Without Docker)](#local-development-without-docker)
9. [Project Directory Structure](#project-directory-structure)

---

## Project Overview

In **H42N42**, players observe and manage a population of living digital creatures called **Creets** inhabiting an ecosystem under threat from a terrifying contagious virus. 

The environment consists of:
- **The River (Top 80px)**: A treacherous watercourse contaminated by the virus. Any healthy creature that touches the river instantly contracts the disease.
- **The Field (Center 530px)**: The main living area where creatures roam, collide, and interact.
- **The Hospital (Bottom 90px)**: A medical sanctuary where players can manually drag and drop sick creatures to cure them and return them safely to the field.

Players must act as epidemiological caretakers, picking up sick creatures and transferring them to the hospital before mutations occur, while managing increasing viral density and progressive difficulty.

---

## Game Rules & Mechanics

### 1. Creature Types & States
- **Healthy Creets (Green)**: Happy, uninfected creatures roaming the field.
- **Sick Creets (Red)**: Infected creatures that move **15% slower** (`sick_speed_factor = 0.85`). Touching a sick creature risks transmitting the virus to healthy ones.
- **Berserk Creets (Purple / Crimson)**: Every 10 seconds of illness, a sick creature has a **10% chance** to mutate into a Berserk monster. Berserk creatures grow **10% larger every 10 seconds** (expanding their contamination radius) and **die automatically when reaching 4× their initial size** (~2 minutes 30 seconds). **Berserk creatures cannot be grabbed or healed**.
- **Mean Creets (Black / Amber)**: Every 10 seconds of illness, a sick creature has a **10% chance** to mutate into a predatory Mean creature. Mean creatures shrink slightly (85% base size) and **actively hunt down the nearest healthy creature** to infect it. They **die automatically after 60 seconds**. **Mean creatures cannot be grabbed or healed**.

### 2. Contamination Mechanics
- **River Contact**: Immediate contamination upon touching `y < 80px` while healthy and not currently being dragged.
- **Creet Contact**: Accurate Euclidean distance detection ($dist(c_1, c_2) < r_1 + r_2$). Touching an infected creature triggers a contamination check based on the active `contam_prob` parameter.
- **Immunity During Dragging**: A creature currently being dragged by the player is invulnerable to contagion.

### 3. Drag and Drop & Hospital Cures
- Players can pick up any **Healthy** or **Sick** creature by clicking and holding the mouse.
- Mouse movement is normalized against viewport dimensions and responsive scaling.
- **Strict Boundary Clamping**: Creatures are strictly clamped to the playing field (`[0, W - d] × [0, H - d]`). Releasing a creature outside the board or browser window cleanly returns it to the nearest edge without escaping.
- **Hospital Healing**: Sick creatures are cured **only when dropped by the player inside the hospital**. A sick creature that wanders into the hospital on its own while roaming is **not** cured.

### 4. Spawner, Difficulty & Game Over
- **Spawner**: Automatically introduces new creatures at configurable intervals (`spawn_interval`). **No new creatures spawn if there are no healthy creatures remaining**.
- **Difficulty Curve**: After an initial 60-second grace period, creature speed progressively accelerates every 5 seconds (+8% in Normal mode), creating an escalating challenge.
- **Game Over**: When all healthy creatures are eliminated (or all living creatures perish), the game halts immediately, displaying an unambiguous **"GAME OVER"** modal with final statistics and local leaderboard rankings.

---

## Implemented Bonuses (25 Pts)

### 🎨 Bonus 1 — Advanced Graphics & Visual Effects (5 pts)
- **Custom Vector Sprites**: Hand-crafted SVGs for Healthy, Sick, Berserk, and Mean creatures, plus custom River and Hospital artwork.
- **CSS Animations**: Smooth rotation/shake animations for sick creatures, glowing pulsating aura (`@keyframes berserkPulse`) for berserk creatures, and smooth scale transitions during drag and drop.
- **Dynamic Particle Effects**: TyXML-generated particle bursts radiating from infected creatures upon contamination.
- **Animated Background**: Seamlessly flowing river texture using CSS keyframe background scrolling.
- **Responsive Layout**: Dynamic scaling adapting the 1000×700px board to fit smaller display viewports while preserving aspect ratio.

### 🎛️ Bonus 2 — Interactive Control Panel (5 pts)
- **Live Parameter Sliders**: Real-time adjustment of `Movement Speed`, `Contamination Probability`, `Spawn Interval`, `Initial Creets`, `Berserk Probability`, and `Mean Probability`. Changes take effect **immediately without restarting**.
- **Control Buttons**: Pause / Resume, Reset Game, and difficulty presets (**Easy**, **Normal**, **Hard**).
- **Real-Time Telemetry HUD**: Live counters displaying current counts of Healthy, Sick, Berserk, and Mean creatures, total elapsed time, saved creatures, and FPS.

### 🔊 Bonus 3 — Sound Effects & Audio (5 pts)
- **Continuous Background Music**: Looping ambient soundtrack compliant with browser autoplay policies (starts smoothly on first player click).
- **Key Event Sound Effects**: Distinct audio cues for contamination, healing, creature death, new spawns, and game over.
- **Audio Controls**: Global mute toggle and independent volume sliders for music and sound effects.
- **Resilient Fallback**: Missing or blocked audio files are handled gracefully without application crashes.

### 📊 Bonus 4 — Statistics & Scoring System (5 pts)
- **Comprehensive Telemetry**: Tracks total survival duration, creatures saved, creatures lost to infection, cure efficiency percentage, and max concurrent living population.
- **Scoring Formula**:
  $$\text{Score} = (\text{Survival Duration} \times 10) + \left(\text{Saved} \times 100 \times \frac{\text{Saved}}{\max(1, \text{Saved} + \text{Lost})}\right)$$
- **Toggleable Dashboard**: Slide-out panel detailing live metrics during gameplay.
- **Local Leaderboard**: Top 5 high scores persisted in browser `localStorage`.
- **Game Over Summary**: Complete post-game report displaying stats and high scores.

### ⚡ Bonus 5 — Optimized Collision Detection (5 pts)
- **Spatial Hash Grid Algorithm**: Reduces collision computation from $O(n^2)$ down to $O(k \cdot n)$.
- **Demonstration Toggle**: Control panel button to switch dynamically between **Grid Spatial Hashing** and **Naive $O(n^2)$** collision detection.
- **Real-Time FPS Counter**: Accurately measures frames per second to demonstrate fluid 60 FPS performance under load.
- **"+100 Stress Test" Button**: Instant spawn of 100 creatures to stress-test the spatial partitioning engine.

---

## Technical Architecture & Clean Code

### Strict Compliance with Subject Rules
1. **Lwt Concurrency**: Each creature is driven by its own dedicated Lwt promise loop using `Lwt_js_events.request_animation_frame` and delta-time physics. **Zero usage of `setTimeout` or `setInterval`**.
2. **TyXML DOM Generation**: All dynamic DOM nodes are constructed using `Eliom_content.Html.D` and typed combinators. **Zero usage of `Dom_html.createDiv` or `createElement`**.
3. **Mouse Events**: Drag-and-drop interactions are programmed strictly through `Lwt_js_events` (`mousedowns`, `mousemoves`, `mouseup`, `mouseleave`).
4. **Idempotent Build System**: The `Makefile` wraps Dune's dependency graph, ensuring that running `make` consecutively performs no redundant recompilations.

---

## Spatial Partitioning Algorithm (Bonus 5)

### Problem Statement
In a naive collision detection approach with $n$ creatures, testing every creature against every other creature requires $\frac{n(n - 1)}{2} = O(n^2)$ distance evaluations per animation frame. With $n = 100$, this results in ~5,000 distance checks per frame (300,000 checks per second at 60 FPS), causing severe CPU throttling.

### Solution: Uniform 2D Spatial Hash Grid
1. **Grid Geometry**:
   - The logical board ($1000 \times 700\text{ px}$) is subdivided into square buckets of size:
     $$\text{cell\_size} = \text{base\_diam} \times \text{berserk\_max} = 40.0 \times 4.0 = 160.0\text{ px}$$
2. **Guaranteed Bounding Principle**:
   - Because no creature can ever exceed $160\text{ px}$ in diameter, two colliding creatures can only reside in the same cell or across immediately adjacent cells.
3. **Lookup Complexity**:
   - For any creature at center $(c_x, c_y)$, its cell coordinate is:
     $$\text{cell} = \left(\left\lfloor \frac{c_x}{\text{cell\_size}} \right\rfloor, \left\lfloor \frac{c_y}{\text{cell\_size}} \right\rfloor\right)$$
   - Collision detection only inspects the $3 \times 3$ neighborhood (9 cells total), querying only local candidates.
4. **Complexity Reduction**:
   - Computational complexity drops to $O(k \cdot n)$, where $k \ll n$ is the local density per cell bucket. The game easily sustains 60 FPS with 100+ active creatures.

---

## Prerequisites & Installation

- **Docker** (version 20.10+ recommended)
- **Docker Compose** (v2 or `docker-compose`)

---

## Running the Application

To build and launch everything in one single command:

```bash
make
```

*(If OCaml/Dune is not installed locally on your host machine, `make` automatically builds and starts the application via Docker Compose seamlessly).*

Alternatively, you can run Docker Compose directly:
```bash
docker compose up --build
```

Once launched, open your web browser and navigate to:
```
http://localhost:8080
```

To stop the application:
```bash
make clean   # or docker compose down
```

---

## Local Development (With OCaml & Dune Installed)

If you have an OCaml/Opam environment configured locally:

1. **Prerequisites**:
   ```bash
   opam switch create 5.2.0
   opam install -y dune eliom ocsipersist-sqlite
   ```

2. **Build and Run**:
   ```bash
   # Compile project and prepare runtime directory
   make

   # Launch Ocsigen server
   make run
   ```

3. **Clean Build Artifacts**:
   ```bash
   make clean   # Clean dune compilation cache
   make fclean  # Remove all local runtime directories and build files
   make re      # Full clean rebuild
   ```

---

## Project Directory Structure

```
h42n42/
├── Dockerfile                  # OCaml 5.2 + Eliom container build definition
├── docker-compose.yml          # One-command orchestration mapping port 8080
├── .dockerignore               # Optimized Docker build context exclusions
├── .gitignore                  # Git repository ignore rules
├── Makefile                    # Standard rules: all, clean, fclean, re, run
├── Makefile.options            # Project constants, paths, and port configurations
├── Makefile.app                # Packaging, dune invocation, and server config generator
├── h42n42.conf.in              # Ocsigen server XML configuration template
├── dune-project                # Dune 3.14+ project configuration with eliom-server dialect
├── README.md                   # Comprehensive documentation and evaluation guide
├── src/
│   ├── dune                    # Server library and client executable build rules
│   ├── tools/
│   │   ├── dune                # PPX client compiler rule
│   │   ├── gen_dune.ml         # Dynamic generator for client ml rules from .eliom
│   │   ├── check_modules.ml    # Module linkage and interface validation script
│   │   └── sort_deps.ml        # Topological dependency sorter
│   ├── config.eliom            # Live mutable references and geometric constants
│   ├── types.eliom             # Domain types (state, creet, world) and event bus
│   ├── spatial.eliom           # Spatial hash grid and naive collision fallback (Bonus 5)
│   ├── fx.eliom                # Particle bursts and visual flash animations (Bonus 1)
│   ├── audio.eliom             # Music loop, SFX engine, and volume controls (Bonus 3)
│   ├── stats.eliom             # Metrics calculation, score, and localStorage leaderboard (Bonus 4)
│   ├── creet.eliom             # Creature lifecycle, per-creet Lwt thread, mutations, death
│   ├── drag.eliom              # Drag-and-drop mechanics using Lwt_js_events, hospital healing
│   ├── game.eliom              # Spawner loop, difficulty acceleration, watchdog, pause/reset
│   ├── panel.eliom             # Control panel UI, real-time sliders, HUD, game over modal (Bonus 2)
│   └── h42n42.eliom            # Server-side TyXML page template and client bootstrap
└── static/
    ├── css/
    │   └── h42n42.css          # Cohesive visual theme, river animation, glowing pulse
    ├── img/
    │   ├── creet_healthy.svg   # Custom SVG sprite for healthy creet
    │   ├── creet_sick.svg      # Custom SVG sprite for sick creet
    │   ├── creet_berserk.svg   # Custom SVG sprite for berserk creet
    │   ├── creet_mean.svg      # Custom SVG sprite for mean creet
    │   ├── river.svg           # Flowing river ripple pattern
    │   └── hospital.svg        # Hospital cross emblem
    └── audio/
        └── README.md           # Instructions for adding optional custom audio files
```
