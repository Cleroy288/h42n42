[%%client
open Js_of_ocaml
open Js_of_ocaml_lwt
open Types

(* File Header: drag.eliom
   @structures: drag_interaction
   @functions: get_board_coords, attach_drag, heal_creet, drop_creet *)

(* ** get_board_coords **
   Translates raw viewport mouse event coordinates into logical board coordinates.
   @param ev: mouse event containing clientX and clientY
   @res 1: tuple of (board_x, board_y) normalized coordinates
   @edge cases: handles CSS scaling transforms using getBoundingClientRect
   @error conditions: defaults to 1.0 scale if bounding box is unmeasured *)
let get_board_coords (ev : Dom_html.mouseEvent Js.t) : float * float =
  match dom_nodes.board_el with
  | None -> (float_of_int ev##.clientX, float_of_int ev##.clientY)
  | Some board ->
      let rect : Dom_html.clientRect Js.t = board##getBoundingClientRect in
      let scale : float =
        let w : float = Js.Optdef.get rect##.width (fun () -> rect##.right -. rect##.left) in
        if w > 0.0 then w /. Config.board_w else 1.0
      in
      let bx : float = (float_of_int ev##.clientX -. rect##.left) /. scale in
      let by : float = (float_of_int ev##.clientY -. rect##.top) /. scale in
      (bx, by)

(* ** heal_creet **
   Restores a sick creature to healthy condition when dropped in hospital.
   @param c: creature being cured
   @res 1: unit confirming cure
   @edge cases: resets diameter to baseline and normalizes velocity
   @error conditions: none *)
let heal_creet (c : creet) : unit =
  if c.alive && c.state = Sick then begin
    c.state <- Healthy;
    c.diam <- Config.base_diam;
    let current_angle : float = atan2 c.vy c.vx in
    let spd : float = Creet.get_creet_speed c in
    c.vx <- cos current_angle *. spd;
    c.vy <- sin current_angle *. spd;
    emit_event (Healed c);
    Creet.render_creet c
  end

(* ** drop_creet **
   Handles creature release, checks for hospital healing, and clamps position.
   @param c: creature being released
   @res 1: unit confirming release
   @edge cases: clamped inside board edges even if released outside window
   @error conditions: none *)
let drop_creet (c : creet) : unit =
  c.dragging <- false;
  (* Strict boundary clamping upon release *)
  c.x <- max 0.0 (min (Config.board_w -. c.diam) c.x);
  c.y <- max 0.0 (min (Config.board_h -. c.diam) c.y);
  (* Check if center landed inside hospital *)
  let (_, cy) : float * float = center c in
  let in_hospital : bool = cy >= (Config.board_h -. Config.hospital_h) in
  if in_hospital && c.state = Sick then
    heal_creet c;
  Spatial.update_grid c;
  Creet.render_creet c

(* ** wait_mouse_leave_window **
   Resolves only when the mouse truly leaves the browser viewport, ignoring
   the bubbled mouseout events fired when crossing internal element boundaries.
   @param doc_el: root document element to watch
   @res 1: promise resolving once the pointer has left the window
   @edge cases: mouseout bubbles on every child transition, so relatedTarget
     must be checked (null/undefined only when the pointer left the document)
   @error conditions: none *)
let rec wait_mouse_leave_window (doc_el : Dom_html.element Js.t) : unit Lwt.t =
  let%lwt ev = Lwt_js_events.mouseout doc_el in
  let left_window : bool =
    Js.Optdef.case ev##.relatedTarget
      (fun () -> true)
      (fun opt -> Js.Opt.case opt (fun () -> true) (fun _ -> false))
  in
  if left_window then Lwt.return_unit else wait_mouse_leave_window doc_el

(* ** attach_drag **
   Attaches Lwt_js_events mouse listeners to a creature for drag and drop.
   @param c: creature to attach drag listeners to
   @res 1: unit confirming event binding
   @edge cases: exclusively uses Lwt_js_events (no raw DOM listeners)
   @error conditions: none *)
let attach_drag (c : creet) : unit =
  Lwt.async (fun () ->
    Lwt_js_events.mousedowns c.el (fun ev _ ->
      if Creet.is_grabbable c && not !Config.paused then begin
        Dom.preventDefault ev;
        c.dragging <- true;
        Creet.render_creet c;
        let (mx, my) : float * float = get_board_coords ev in
        let offset_x : float = mx -. c.x in
        let offset_y : float = my -. c.y in
        let doc : Dom_html.document Js.t = Dom_html.document in
        let doc_el = doc##.documentElement in
        let%lwt () =
          Lwt.pick [
            Lwt_js_events.mousemoves doc (fun move_ev _ ->
              let (cur_mx, cur_my) : float * float = get_board_coords move_ev in
              let target_x : float = cur_mx -. offset_x in
              let target_y : float = cur_my -. offset_y in
              c.x <- max 0.0 (min (Config.board_w -. c.diam) target_x);
              c.y <- max 0.0 (min (Config.board_h -. c.diam) target_y);
              Spatial.update_grid c;
              Creet.render_creet c;
              Lwt.return_unit);
            (let%lwt _ = Lwt_js_events.mouseup doc in Lwt.return_unit);
            wait_mouse_leave_window doc_el;
          ]
        in
        drop_creet c;
        Lwt.return_unit
      end else Lwt.return_unit))
]
