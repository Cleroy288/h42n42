[%%client
open Js_of_ocaml
open Js_of_ocaml_lwt
open Types

(* File Header: drag.eliom
   @functions: get_board_coords, heal_creet, drop_creet, attach_drag *)

(* ** get_board_coords **
   Translates viewport mouse coordinates into logical board coordinates,
   accounting for any CSS scaling of the board. *)
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
   Sick creet dropped in the hospital becomes healthy again. *)
let heal_creet (c : creet) : unit =
  if c.alive && c.state = Sick then begin
    c.state <- Healthy;
    c.diam <- Config.base_diam;
    let current_angle : float = atan2 c.vy c.vx in
    let spd : float = Creet.get_creet_speed c in
    c.vx <- cos current_angle *. spd;
    c.vy <- sin current_angle *. spd;
    Creet.render_creet c
  end

(* ** drop_creet **
   Releases a dragged creet: clamps it inside the board and heals it if
   its center landed inside the hospital zone. *)
let drop_creet (c : creet) : unit =
  c.dragging <- false;
  c.x <- max 0.0 (min (Config.board_w -. c.diam) c.x);
  c.y <- max 0.0 (min (Config.board_h -. c.diam) c.y);
  let (_, cy) : float * float = center c in
  let in_hospital : bool = cy >= (Config.board_h -. Config.hospital_h) in
  if in_hospital && c.state = Sick then
    heal_creet c;
  Creet.render_creet c

(* ** wait_mouse_leave_window **
   Resolves only when the mouse truly leaves the browser viewport,
   ignoring bubbled mouseout events from internal element boundaries. *)
let rec wait_mouse_leave_window (doc_el : Dom_html.element Js.t) : unit Lwt.t =
  let%lwt ev = Lwt_js_events.mouseout doc_el in
  let left_window : bool =
    Js.Optdef.case ev##.relatedTarget
      (fun () -> true)
      (fun opt -> Js.Opt.case opt (fun () -> true) (fun _ -> false))
  in
  if left_window then Lwt.return_unit else wait_mouse_leave_window doc_el

(* ** attach_drag **
   Binds mouse listeners so grabbable creets can be dragged; the drag
   ends on mouseup or when the pointer leaves the window. *)
let attach_drag (c : creet) : unit =
  Lwt.async (fun () ->
    Lwt_js_events.mousedowns c.el (fun ev _ ->
      if Creet.is_grabbable c then begin
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
              c.x <- max 0.0 (min (Config.board_w -. c.diam) (cur_mx -. offset_x));
              c.y <- max 0.0 (min (Config.board_h -. c.diam) (cur_my -. offset_y));
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
