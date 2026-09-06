[%%client
open Js_of_ocaml
open Js_of_ocaml_lwt
open Eliom_content.Html.D
open Types

(* File Header: game.eliom
   @functions: spawn_one, show_gameover, game_over, start_game *)

(* ** spawn_one **
   Creates a creature, binds drag listeners and starts its life loop. *)
let spawn_one ?x ?y () : creet =
  let c : creet = Creet.make_creet ?x ?y () in
  Drag.attach_drag c;
  Creet.run_creet c;
  c

(* ** show_gameover **
   Fills and displays the GAME OVER overlay with a restart button. *)
let show_gameover () : unit =
  match dom_nodes.gameover_el with
  | None -> ()
  | Some modal_node ->
      let restart_btn =
        button ~a:[a_class ["btn"]; a_button_type `Button] [txt "PLAY AGAIN"]
      in
      let dom_btn : Dom_html.buttonElement Js.t =
        Eliom_content.Html.To_dom.of_button restart_btn
      in
      Lwt.async (fun () ->
        Lwt_js_events.clicks dom_btn (fun _ _ ->
          Dom_html.window##.location##reload;
          Lwt.return_unit));
      let content =
        div
          ~a:[a_class ["gameover-box"]]
          [h1 [txt "GAME OVER"]; restart_btn]
      in
      modal_node##.innerHTML := Js.string "";
      Eliom_content.Html.Manip.appendChild
        (Eliom_content.Html.Of_dom.of_element modal_node)
        content;
      modal_node##.classList##remove (Js.string "hidden")

(* ** game_over **
   Stops the simulation: cancels system threads, freezes every creet in
   place and shows the GAME OVER overlay. *)
let game_over () : unit =
  if not active_world.over then begin
    active_world.over <- true;
    List.iter Lwt.cancel active_world.sys_threads;
    active_world.sys_threads <- [];
    List.iter
      (fun (c : creet) ->
        List.iter Lwt.cancel c.threads;
        c.threads <- [])
      active_world.creets;
    show_gameover ()
  end

(* ** start_game **
   Spawns the initial population and launches the three system threads:
   spawner, progressive difficulty, and the game-over watchdog. *)
let start_game () : unit =
  active_world.creets <- [];
  active_world.over <- false;
  Config.speed_mult := 1.0;

  for _ = 1 to Config.initial_creets do
    ignore (spawn_one ())
  done;

  (* Spawner: a new creet appears while at least one healthy remains *)
  let spawner_thread : unit Lwt.t =
    let rec loop () : unit Lwt.t =
      let%lwt () = Lwt_js.sleep Config.spawn_interval in
      if not active_world.over then begin
        if count_by_state Healthy > 0 then
          ignore (spawn_one ());
        loop ()
      end else Lwt.return_unit
    in
    loop ()
  in

  (* Difficulty: after a grace period, speed increases regularly *)
  let difficulty_thread : unit Lwt.t =
    let rec loop () : unit Lwt.t =
      let%lwt () = Lwt_js.sleep Config.accel_period in
      if not active_world.over then begin
        Config.speed_mult := !Config.speed_mult *. (1.0 +. Config.accel_step);
        loop ()
      end else Lwt.return_unit
    in
    let%lwt () = Lwt_js.sleep Config.grace_period in
    if not active_world.over then loop () else Lwt.return_unit
  in

  (* Watchdog: game over as soon as no healthy creet remains *)
  let watchdog_thread : unit Lwt.t =
    let rec loop () : unit Lwt.t =
      let%lwt () = Lwt_js_events.request_animation_frame () in
      if not active_world.over then begin
        if count_by_state Healthy = 0 then begin
          game_over ();
          Lwt.return_unit
        end else
          loop ()
      end else Lwt.return_unit
    in
    loop ()
  in

  active_world.sys_threads <- [spawner_thread; difficulty_thread; watchdog_thread]
]
