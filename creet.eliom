[%%client
open Js_of_ocaml
open Js_of_ocaml_lwt
open Eliom_content.Html.D
open Types

(* File Header: creet.eliom
   @structures: creet_lifecycle
   @functions: make_creet, render_creet, get_creet_speed, is_grabbable, step_creet, run_creet, contaminate_creet, die_creet *)

(* ** is_grabbable **
   Checks whether a creature is allowed to be picked up by the player.
   @param c: creature to evaluate
   @res 1: boolean true if healthy or regular sick
   @edge cases: berserk and mean creatures cannot be grabbed per rules
   @error conditions: none *)
let is_grabbable (c : creet) : bool =
  c.alive && (c.state = Healthy || c.state = Sick)

(* ** get_creet_speed **
   Calculates active velocity magnitude for a creature based on state and multipliers.
   @param c: creature to evaluate
   @res 1: floating point speed in pixels per second
   @edge cases: sick creatures move 15% slower
   @error conditions: none *)
let get_creet_speed (c : creet) : float =
  let factor : float = if c.state = Healthy then 1.0 else Config.sick_speed_factor in
  !Config.speed_base *. !Config.speed_mult *. factor

(* ** render_creet **
   Updates CSS transform and positioning styles on the creature DOM element.
   @param c: creature to render
   @res 1: unit confirming DOM update
   @edge cases: preserves dragging class when active
   @error conditions: none *)
let render_creet (c : creet) : unit =
  let st : Dom_html.cssStyleDeclaration Js.t = c.el##.style in
  st##.left := Js.string (Printf.sprintf "%.1fpx" c.x);
  st##.top := Js.string (Printf.sprintf "%.1fpx" c.y);
  st##.width := Js.string (Printf.sprintf "%.1fpx" c.diam);
  st##.height := Js.string (Printf.sprintf "%.1fpx" c.diam);
  let state_class : string =
    match c.state with
    | Healthy -> "healthy"
    | Sick -> "sick"
    | Berserk -> "berserk"
    | Mean -> "mean"
  in
  let drag_suffix : string = if c.dragging then " dragging" else "" in
  c.el##.className := Js.string ("creet " ^ state_class ^ drag_suffix)

(* ** sleep_unpaused **
   Lwt sleep utility that pauses countdown during active game pause.
   @param duration: target seconds to wait
   @res 1: Lwt promise resolving after unpaused elapsed duration
   @edge cases: checks paused flag every 100ms
   @error conditions: none *)
let rec sleep_unpaused (duration : float) : unit Lwt.t =
  if duration <= 0.0 then Lwt.return_unit
  else
    let%lwt () = Lwt_js.sleep 0.1 in
    let remaining : float = if !Config.paused then duration else duration -. 0.1 in
    sleep_unpaused remaining

(* ** die_creet **
   Terminates creature life cycle, cancels threads, and triggers exit animation.
   @param c: creature to terminate
   @res 1: unit confirming termination
   @edge cases: safely handles DOM detachment and cancels background timers
   @error conditions: none *)
let die_creet (c : creet) : unit =
  if c.alive then begin
    c.alive <- false;
    List.iter Lwt.cancel c.threads;
    c.threads <- [];
    Spatial.remove_from_grid c;
    active_world.creets <- List.filter (fun (o : creet) -> o.id <> c.id) active_world.creets;
    c.el##.classList##add (Js.string "dying");
    emit_event (Died c);
    Lwt.async (fun () ->
      let%lwt () = Lwt_js.sleep 0.4 in
      (match dom_nodes.creatures_el with
      | Some parent ->
          (try parent##removeChild (c.el :> Dom.node Js.t) |> ignore with _ -> ())
      | None -> ());
      Lwt.return_unit)
  end

(* ** trigger_berserk **
   Evolves sick creature into Berserk with recurring growth loop.
   @param c: creature going berserk
   @res 1: unit confirming mutation
   @edge cases: dies when reaching 4x base diameter
   @error conditions: none *)
let trigger_berserk (c : creet) : unit =
  c.state <- Berserk;
  emit_event (Mutated c);
  render_creet c;
  let rec growth_loop () : unit Lwt.t =
    let%lwt () = sleep_unpaused Config.berserk_tick in
    if c.alive && c.state = Berserk then begin
      let (cx, cy) : float * float = center c in
      c.diam <- c.diam *. Config.berserk_growth;
      c.x <- max 0.0 (min (Config.board_w -. c.diam) (cx -. (c.diam /. 2.0)));
      c.y <- max 0.0 (min (Config.board_h -. c.diam) (cy -. (c.diam /. 2.0)));
      Spatial.update_grid c;
      render_creet c;
      if c.diam >= (Config.base_diam *. Config.berserk_max) then begin
        die_creet c;
        Lwt.return_unit
      end else
        growth_loop ()
    end else Lwt.return_unit
  in
  let growth_thread : unit Lwt.t = growth_loop () in
  c.threads <- growth_thread :: c.threads

(* ** trigger_mean **
   Evolves sick creature into Mean predator with 60-second expiration.
   @param c: creature becoming mean
   @res 1: unit confirming mutation
   @edge cases: shrinks to 85% base size and expires after 1 minute
   @error conditions: none *)
let trigger_mean (c : creet) : unit =
  c.state <- Mean;
  c.diam <- Config.base_diam *. Config.mean_size_factor;
  emit_event (Mutated c);
  Spatial.update_grid c;
  render_creet c;
  let lifetime_thread : unit Lwt.t =
    let%lwt () = sleep_unpaused Config.mean_lifetime in
    if c.alive && c.state = Mean then die_creet c;
    Lwt.return_unit
  in
  c.threads <- lifetime_thread :: c.threads

(* ** contaminate_creet **
   Infects healthy creature and launches 10-second mutation evaluation timer.
   @param c: creature to contaminate
   @res 1: unit confirming infection
   @edge cases: ignores already infected or actively dragged creatures
   @error conditions: none *)
let contaminate_creet (c : creet) : unit =
  if c.alive && c.state = Healthy && not c.dragging then begin
    c.state <- Sick;
    emit_event (Contaminated c);
    render_creet c;
    let rec mutation_loop () : unit Lwt.t =
      let%lwt () = sleep_unpaused Config.mutation_tick in
      if c.alive && c.state = Sick then begin
        let roll_berserk : float = Random.float 1.0 in
        if roll_berserk < !Config.berserk_prob then
          (trigger_berserk c; Lwt.return_unit)
        else
          let roll_mean : float = Random.float 1.0 in
          if roll_mean < !Config.mean_prob then
            (trigger_mean c; Lwt.return_unit)
          else
            mutation_loop ()
      end else Lwt.return_unit
    in
    let timer_thread : unit Lwt.t = mutation_loop () in
    c.threads <- timer_thread :: c.threads
  end

(* ** step_creet **
   Executes physics, collisions, infection, and boundary clamping for one time delta.
   @param c: creature stepping forward
   @param t: current timestamp
   @param dt: delta time in seconds
   @res 1: unit confirming step completion
   @edge cases: clamps strictly to bounds [0, W - d] x [0, H - d]
   @error conditions: none *)
let step_creet (c : creet) (t : float) (dt : float) : unit =
  (* Step 1: Steering and target direction *)
  if c.state = Mean then begin
    match Spatial.find_nearest_healthy c with
    | None -> ()
    | Some target ->
        let (cx, cy) : float * float = center c in
        let (tx, ty) : float * float = center target in
        let target_angle : float = atan2 (ty -. cy) (tx -. cx) in
        let spd : float = get_creet_speed c in
        c.vx <- cos target_angle *. spd;
        c.vy <- sin target_angle *. spd
  end else if t >= c.next_turn then begin
    let angle : float = Random.float (2.0 *. Float.pi) in
    let spd : float = get_creet_speed c in
    c.vx <- cos angle *. spd;
    c.vy <- sin angle *. spd;
    c.next_turn <- t +. Config.dir_change_min +. (Random.float (Config.dir_change_max -. Config.dir_change_min))
  end else begin
    let current_speed : float = get_creet_speed c in
    let angle : float = atan2 c.vy c.vx in
    c.vx <- cos angle *. current_speed;
    c.vy <- sin angle *. current_speed
  end;

  (* Step 2: Displacement *)
  c.x <- c.x +. (c.vx *. dt);
  c.y <- c.y +. (c.vy *. dt);

  (* Step 3: Wall bounce and strict boundary clamping *)
  if c.x < 0.0 then begin
    c.x <- 0.0;
    c.vx <- abs_float c.vx
  end else if c.x > (Config.board_w -. c.diam) then begin
    c.x <- Config.board_w -. c.diam;
    c.vx <- -. (abs_float c.vx)
  end;

  if c.y < 0.0 then begin
    c.y <- 0.0;
    c.vy <- abs_float c.vy
  end else if c.y > (Config.board_h -. c.diam) then begin
    c.y <- Config.board_h -. c.diam;
    c.vy <- -. (abs_float c.vy)
  end;

  (* Step 4: River touch infection *)
  if c.state = Healthy && c.y < Config.river_h then
    contaminate_creet c;

  (* Step 5: Creature-to-creature contact transmission *)
  if c.state = Healthy then begin
    let neighbors : creet list = Spatial.query_neighbors c in
    let touched_infected : bool =
      List.exists
        (fun (o : creet) ->
          o.state <> Healthy && not o.dragging && touching c o)
        neighbors
    in
    if touched_infected && (Random.float 1.0 < !Config.contam_prob) then
      contaminate_creet c
  end;

  (* Step 6: Synchronize spatial grid and render *)
  Spatial.update_grid c;
  render_creet c

(* ** run_creet **
   Starts dedicated Lwt animation loop for a single creature.
   @param c: creature to activate
   @res 1: unit confirming thread activation
   @edge cases: catches cancellation and unbinds smoothly
   @error conditions: none *)
let run_creet (c : creet) : unit =
  let rec life_loop (last_t : float) : unit Lwt.t =
    let%lwt () = Lwt_js_events.request_animation_frame () in
    let curr_t : float = get_time () in
    let dt : float = min 0.05 (curr_t -. last_t) in
    if c.alive then begin
      if not !Config.paused && not c.dragging then
        step_creet c curr_t dt;
      life_loop curr_t
    end else Lwt.return_unit
  in
  let life_thread : unit Lwt.t =
    Lwt.catch
      (fun () -> life_loop (get_time ()))
      (function
      | Lwt.Canceled -> Lwt.return_unit
      | exn -> Lwt.fail exn)
  in
  c.threads <- life_thread :: c.threads

(* ** make_creet **
   Instantiates creature entity, TyXML element, and initializes physics.
   @param x_opt: optional explicit X coordinate
   @param y_opt: optional explicit Y coordinate
   @res 1: initialized creet record
   @edge cases: spawns strictly in playable field zone away from river and hospital
   @error conditions: none *)
let make_creet ?x ?y () : creet =
  active_world.next_id <- active_world.next_id + 1;
  let creet_id : int = active_world.next_id in
  let d : float = Config.base_diam in
  let spawn_x : float =
    match x with
    | Some px -> px
    | None -> Random.float (Config.board_w -. d)
  in
  let spawn_y : float =
    match y with
    | Some py -> py
    | None ->
        Config.river_h +. (Random.float (Config.board_h -. Config.river_h -. Config.hospital_h -. d))
  in
  let angle : float = Random.float (2.0 *. Float.pi) in
  let spd : float = !Config.speed_base *. !Config.speed_mult in
  let div_elt : [> Html_types.div ] elt =
    div
      ~a:[
        a_class ["creet"; "healthy"];
        a_style (Printf.sprintf "left:%.1fpx; top:%.1fpx; width:%.1fpx; height:%.1fpx;" spawn_x spawn_y d d)
      ]
      []
  in
  let dom_div : Dom_html.divElement Js.t = Eliom_content.Html.To_dom.of_div div_elt in
  (match dom_nodes.creatures_el with
  | Some field_node ->
      Eliom_content.Html.Manip.appendChild (Eliom_content.Html.Of_dom.of_element field_node) div_elt
  | None -> ());
  let new_creet : creet = {
    id = creet_id;
    el = dom_div;
    x = spawn_x;
    y = spawn_y;
    vx = cos angle *. spd;
    vy = sin angle *. spd;
    diam = d;
    state = Healthy;
    dragging = false;
    alive = true;
    cell = None;
    next_turn = get_time () +. Config.dir_change_min +. (Random.float 2.0);
    threads = [];
  } in
  Spatial.update_grid new_creet;
  active_world.creets <- new_creet :: active_world.creets;
  emit_event (Spawned new_creet);
  new_creet
]
