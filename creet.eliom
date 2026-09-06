[%%client
open Js_of_ocaml
open Js_of_ocaml_lwt
open Eliom_content.Html.D
open Types

(* File Header: creet.eliom
   @functions: is_grabbable, get_creet_speed, render_creet, die_creet,
   trigger_berserk, trigger_mean, contaminate_creet, find_nearest_healthy,
   step_creet, run_creet, make_creet *)

(* ** is_grabbable **
   Only healthy and sick creets can be picked up. *)
let is_grabbable (c : creet) : bool =
  c.alive && (c.state = Healthy || c.state = Sick)

(* ** get_creet_speed **
   Velocity magnitude: base speed, difficulty multiplier, and the 15%
   slowdown for infected creets. *)
let get_creet_speed (c : creet) : float =
  let factor : float = if c.state = Healthy then 1.0 else Config.sick_speed_factor in
  Config.speed_base *. !Config.speed_mult *. factor

(* ** render_creet **
   Pushes position, size and state class to the DOM element. *)
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

(* ** die_creet **
   Cancels the creature's threads and removes it from world and DOM. *)
let die_creet (c : creet) : unit =
  if c.alive then begin
    c.alive <- false;
    List.iter Lwt.cancel c.threads;
    c.threads <- [];
    active_world.creets <- List.filter (fun (o : creet) -> o.id <> c.id) active_world.creets;
    match dom_nodes.creatures_el with
    | Some parent ->
        (try parent##removeChild (c.el :> Dom.node Js.t) |> ignore with _ -> ())
    | None -> ()
  end

(* ** trigger_berserk **
   Sick creet becomes Berserk: grows 10% every tick and dies upon
   reaching 4x the base diameter. *)
let trigger_berserk (c : creet) : unit =
  c.state <- Berserk;
  render_creet c;
  let rec growth_loop () : unit Lwt.t =
    let%lwt () = Lwt_js.sleep Config.berserk_tick in
    if c.alive && c.state = Berserk then begin
      let (cx, cy) : float * float = center c in
      c.diam <- c.diam *. Config.berserk_growth;
      c.x <- max 0.0 (min (Config.board_w -. c.diam) (cx -. (c.diam /. 2.0)));
      c.y <- max 0.0 (min (Config.board_h -. c.diam) (cy -. (c.diam /. 2.0)));
      render_creet c;
      if c.diam >= (Config.base_diam *. Config.berserk_max) then begin
        die_creet c;
        Lwt.return_unit
      end else
        growth_loop ()
    end else Lwt.return_unit
  in
  c.threads <- growth_loop () :: c.threads

(* ** trigger_mean **
   Sick creet becomes Mean: shrinks to 85% and dies after 60 seconds. *)
let trigger_mean (c : creet) : unit =
  c.state <- Mean;
  c.diam <- Config.base_diam *. Config.mean_size_factor;
  render_creet c;
  let lifetime_thread : unit Lwt.t =
    let%lwt () = Lwt_js.sleep Config.mean_lifetime in
    if c.alive && c.state = Mean then die_creet c;
    Lwt.return_unit
  in
  c.threads <- lifetime_thread :: c.threads

(* ** contaminate_creet **
   Healthy creet becomes Sick, then rolls for a mutation (berserk or
   mean) every mutation tick while still sick. *)
let contaminate_creet (c : creet) : unit =
  if c.alive && c.state = Healthy && not c.dragging then begin
    c.state <- Sick;
    render_creet c;
    let rec mutation_loop () : unit Lwt.t =
      let%lwt () = Lwt_js.sleep Config.mutation_tick in
      if c.alive && c.state = Sick then begin
        if Random.float 1.0 < Config.berserk_prob then
          (trigger_berserk c; Lwt.return_unit)
        else if Random.float 1.0 < Config.mean_prob then
          (trigger_mean c; Lwt.return_unit)
        else
          mutation_loop ()
      end else Lwt.return_unit
    in
    c.threads <- mutation_loop () :: c.threads
  end

(* ** find_nearest_healthy **
   Closest healthy creet, used by Mean predators to chase targets. *)
let find_nearest_healthy (predator : creet) : creet option =
  let (px, py) : float * float = center predator in
  let best : creet option ref = ref None in
  let min_dist_sq : float ref = ref infinity in
  List.iter
    (fun (target : creet) ->
      if target.alive && target.state = Healthy then begin
        let (tx, ty) : float * float = center target in
        let dx : float = px -. tx in
        let dy : float = py -. ty in
        let dist_sq : float = (dx *. dx) +. (dy *. dy) in
        if dist_sq < !min_dist_sq then begin
          min_dist_sq := dist_sq;
          best := Some target
        end
      end)
    active_world.creets;
  !best

(* ** step_creet **
   One physics step: steering, displacement, wall bounce, river
   infection and contact contagion. *)
let step_creet (c : creet) (t : float) (dt : float) : unit =
  (* Step 1: Steering — mean creets chase, others wander randomly *)
  if c.state = Mean then begin
    match find_nearest_healthy c with
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
    let spd : float = get_creet_speed c in
    let angle : float = atan2 c.vy c.vx in
    c.vx <- cos angle *. spd;
    c.vy <- sin angle *. spd
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

  (* Step 4: River touch = instant infection *)
  if c.state = Healthy && c.y < Config.river_h then
    contaminate_creet c;

  (* Step 5: Contact with an infected creet = probabilistic contagion *)
  if c.state = Healthy then begin
    let touched_infected : bool =
      List.exists
        (fun (o : creet) ->
          o.alive && o.id <> c.id && o.state <> Healthy && not o.dragging && touching c o)
        active_world.creets
    in
    if touched_infected && (Random.float 1.0 < Config.contam_prob) then
      contaminate_creet c
  end;

  render_creet c

(* ** run_creet **
   Per-creature animation loop (one Lwt thread per creet). *)
let run_creet (c : creet) : unit =
  let rec life_loop (last_t : float) : unit Lwt.t =
    let%lwt () = Lwt_js_events.request_animation_frame () in
    let curr_t : float = get_time () in
    let dt : float = min 0.05 (curr_t -. last_t) in
    if c.alive then begin
      if not c.dragging then step_creet c curr_t dt;
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
   Creates the creature record and its DOM element, spawning in the
   neutral field zone (between river and hospital). *)
let make_creet ?x ?y () : creet =
  active_world.next_id <- active_world.next_id + 1;
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
  let spd : float = Config.speed_base *. !Config.speed_mult in
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
    id = active_world.next_id;
    el = dom_div;
    x = spawn_x;
    y = spawn_y;
    vx = cos angle *. spd;
    vy = sin angle *. spd;
    diam = d;
    state = Healthy;
    dragging = false;
    alive = true;
    next_turn = get_time () +. Config.dir_change_min +. (Random.float 2.0);
    threads = [];
  } in
  active_world.creets <- new_creet :: active_world.creets;
  new_creet
]
