[%%client
open Js_of_ocaml

(* File Header: types.eliom
   @structures: state, creet, world, dom_refs
   @functions: center, radius, touching, count_by_state, get_time *)

(* ** state **
   Health and behavioural condition of a creet. *)
type state = Healthy | Sick | Berserk | Mean

(* ** creet **
   Creature entity: DOM element, physics, state and its Lwt threads. *)
type creet = {
  id : int;
  el : Dom_html.divElement Js.t;
  mutable x : float;
  mutable y : float;
  mutable vx : float;
  mutable vy : float;
  mutable diam : float;
  mutable state : state;
  mutable dragging : bool;
  mutable alive : bool;
  mutable next_turn : float;
  mutable threads : unit Lwt.t list;
}

(* ** world **
   Global mutable simulation state. *)
type world = {
  mutable creets : creet list;
  mutable over : bool;
  mutable next_id : int;
  mutable sys_threads : unit Lwt.t list;
}

let active_world : world = {
  creets = [];
  over = false;
  next_id = 0;
  sys_threads = [];
}

(* ** dom_refs **
   References to top-level DOM nodes, bound once at startup. *)
type dom_refs = {
  mutable board_el : Dom_html.element Js.t option;
  mutable creatures_el : Dom_html.element Js.t option;
  mutable gameover_el : Dom_html.element Js.t option;
}

let dom_nodes : dom_refs = {
  board_el = None;
  creatures_el = None;
  gameover_el = None;
}

(* ** center **
   Geometric center of a creet. *)
let center (c : creet) : float * float =
  (c.x +. (c.diam /. 2.0), c.y +. (c.diam /. 2.0))

(* ** radius ** *)
let radius (c : creet) : float = c.diam /. 2.0

(* ** touching **
   True when the bounding circles of two creets overlap. *)
let touching (a : creet) (b : creet) : bool =
  let (ax, ay) = center a in
  let (bx, by) = center b in
  let dx = ax -. bx in
  let dy = ay -. by in
  let rad_sum = radius a +. radius b in
  (dx *. dx) +. (dy *. dy) < rad_sum *. rad_sum

(* ** count_by_state **
   Number of living creets in the given state. *)
let count_by_state (target_state : state) : int =
  List.length
    (List.filter (fun (c : creet) -> c.alive && c.state = target_state) active_world.creets)

(* ** get_time **
   Wall clock time in seconds. *)
let get_time () : float =
  let date_obj : Js.date Js.t = new%js Js.date_now in
  Js.to_float date_obj##getTime /. 1000.0
]
