[%%client
open Js_of_ocaml
open Js_of_ocaml_lwt
open Types

(* File Header: game.eliom
   @structures: game_orchestrator
   @functions: spawn_one, start_game, pause_game, resume_game, toggle_pause, reset_game, game_over, stress_test *)

let on_game_over_hook : (unit -> unit) ref = ref (fun () -> ())
let frame_counter : int ref = ref 0
let current_fps : int ref = ref 60

(* ** spawn_one **
   Constructs a creature, binds drag-and-drop listeners, and starts its Lwt life loop.
   @param x: optional explicit X spawn position
   @param y: optional explicit Y spawn position
   @res 1: spawned and running creet record
   @edge cases: binds drag listeners and launches animation thread
   @error conditions: none *)
let spawn_one ?x ?y () : creet =
  let c : creet = Creet.make_creet ?x ?y () in
  Drag.attach_drag c;
  Creet.run_creet c;
  c

(* ** game_over **
   Terminates game session, freezes creatures in place, and opens game over modal.
   @res 1: unit confirming game over sequence
   @edge cases: persists final score to localStorage and freezes creets on board
   @error conditions: none *)
let game_over () : unit =
  if not active_world.over then begin
    active_world.over <- true;
    (* Cancel system orchestration threads *)
    List.iter Lwt.cancel active_world.sys_threads;
    active_world.sys_threads <- [];
    (* Freeze all creet threads in place *)
    List.iter
      (fun (c : creet) ->
        List.iter Lwt.cancel c.threads;
        c.threads <- [])
      active_world.creets;
    (* Save score and play sound *)
    Stats.save_score ();
    Audio.play_sfx "gameover";
    (* Invoke UI hook *)
    !on_game_over_hook ()
  end

(* ** pause_game **
   Pauses movement loops and game timers.
   @res 1: unit confirming pause
   @edge cases: sets config paused reference to true
   @error conditions: none *)
let pause_game () : unit =
  Config.paused := true

(* ** resume_game **
   Resumes unpaused game simulation.
   @res 1: unit confirming resume
   @edge cases: sets config paused reference to false
   @error conditions: none *)
let resume_game () : unit =
  Config.paused := false

(* ** toggle_pause **
   Inverts current pause state.
   @res 1: current boolean pause status
   @edge cases: toggles smoothly without resetting timers
   @error conditions: none *)
let toggle_pause () : bool =
  Config.paused := not !Config.paused;
  !Config.paused

(* ** stress_test **
   Spawns multiple creatures simultaneously to demonstrate spatial grid optimization.
   @param count: number of creatures to introduce
   @res 1: unit confirming stress test spawn
   @edge cases: capped to 200 for safety
   @error conditions: none *)
let stress_test (count : int) : unit =
  let n : int = min 200 count in
  for _ = 1 to n do
    ignore (spawn_one ())
  done

(* ** start_game **
   Initializes fresh session, launches spawner, difficulty scaling, and watchdog.
   @res 1: unit confirming startup
   @edge cases: cancels prior threads and repopulates field
   @error conditions: none *)
let start_game () : unit =
  (* Step 1: Reset observers and systems *)
  reset_listeners ();
  register_listener Stats.on_event;
  register_listener Audio.on_event;
  register_listener Fx.on_event;
  Spatial.clear_grid ();
  Stats.reset_stats ();

  (* Step 2: Initialize world container *)
  active_world.creets <- [];
  active_world.started_at <- get_time ();
  active_world.elapsed <- 0.0;
  active_world.over <- false;
  Config.speed_mult := 1.0;
  Config.paused := false;

  (* Step 3: Spawn initial population *)
  for _ = 1 to !Config.initial_creets do
    ignore (spawn_one ())
  done;

  (* Step 4: Spawner thread *)
  let spawner_thread : unit Lwt.t =
    let rec loop () : unit Lwt.t =
      let%lwt () = Creet.sleep_unpaused !Config.spawn_interval in
      if not active_world.over then begin
        if count_by_state Healthy > 0 then
          ignore (spawn_one ());
        loop ()
      end else Lwt.return_unit
    in
    loop ()
  in

  (* Step 5: Progressive difficulty scaling thread *)
  let difficulty_thread : unit Lwt.t =
    let rec loop () : unit Lwt.t =
      let%lwt () = Creet.sleep_unpaused Config.accel_period in
      if not active_world.over then begin
        Config.speed_mult := !Config.speed_mult *. (1.0 +. !Config.accel_step);
        loop ()
      end else Lwt.return_unit
    in
    let%lwt () = Creet.sleep_unpaused Config.grace_period in
    if not active_world.over then loop () else Lwt.return_unit
  in

  (* Step 6: Watchdog and FPS tracking loop *)
  let watchdog_thread : unit Lwt.t =
    let rec loop (last_t : float) : unit Lwt.t =
      let%lwt () = Lwt_js_events.request_animation_frame () in
      let curr_t : float = get_time () in
      let dt : float = min 0.05 (curr_t -. last_t) in
      if not active_world.over then begin
        if not !Config.paused then
          active_world.elapsed <- active_world.elapsed +. dt;
        frame_counter := !frame_counter + 1;
        if count_by_state Healthy = 0 then begin
          game_over ();
          Lwt.return_unit
        end else
          loop curr_t
      end else Lwt.return_unit
    in
    loop (get_time ())
  in

  (* Step 7: FPS timer thread *)
  let fps_thread : unit Lwt.t =
    let rec loop () : unit Lwt.t =
      let%lwt () = Lwt_js.sleep 1.0 in
      current_fps := !frame_counter;
      frame_counter := 0;
      if not active_world.over then loop () else Lwt.return_unit
    in
    loop ()
  in

  active_world.sys_threads <- [spawner_thread; difficulty_thread; watchdog_thread; fps_thread]

(* ** reset_game **
   Clears playing field and restarts the simulation with fresh state.
   @res 1: unit confirming game reset
   @edge cases: removes all existing DOM creet elements
   @error conditions: none *)
let reset_game () : unit =
  (* Cancel all system threads *)
  List.iter Lwt.cancel active_world.sys_threads;
  active_world.sys_threads <- [];
  (* Cancel all creature threads *)
  List.iter
    (fun (c : creet) ->
      c.alive <- false;
      List.iter Lwt.cancel c.threads)
    active_world.creets;
  (* Clear field DOM *)
  (match dom_nodes.creatures_el with
  | Some field_node ->
      field_node##.innerHTML := Js.string ""
  | None -> ());
  (* Hide Game Over modal *)
  (match dom_nodes.gameover_el with
  | Some modal ->
      modal##.classList##add (Js.string "hidden")
  | None -> ());
  (* Restart clean session *)
  start_game ()
]
