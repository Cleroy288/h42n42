[%%client
open Js_of_ocaml

(* File Header: types.eliom
   @structures: state, creet, world, event, dom_refs
   @functions: center, radius, touching, count_by_state, get_time, emit_event, register_listener, reset_listeners *)

(* ** state **
   Enumeration of creature health and behavioural conditions.
   ==> Defines the current physical and viral state of a Creet
   @ Healthy: normal creature unaffected by virus
   @ Sick: infected creature moving slower and contagious
   @ Berserk: aggressive mutating creature growing in diameter
   @ Mean: predatory creature actively hunting healthy Creets *)
type state = Healthy | Sick | Berserk | Mean

(* ** creet **
   Primary creature entity record containing position, physics and state.
   ==> Encapsulates creature DOM representation, physics and threads
   @ id: unique sequential identifier
   @ el: DOM div element representing creature on screen
   @ x, y: logical coordinate of top-left corner
   @ vx, vy: velocity vector in pixels per second
   @ diam: active diameter in pixels
   @ state: current health or mutation state
   @ dragging: flag indicating user is actively moving creature
   @ alive: flag indicating creature is active in world
   @ cell: current spatial hash grid coordinate
   @ next_turn: timestamp for next direction change
   @ threads: list of active Lwt promises for this creature *)
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
  mutable cell : (int * int) option;
  mutable next_turn : float;
  mutable threads : unit Lwt.t list;
}

(* ** world **
   Global mutable simulation state container.
   ==> Stores active creatures list, timers, and system tasks
   @ creets: list of all existing creatures
   @ started_at: epoch timestamp when current session began
   @ elapsed: active simulation duration in seconds excluding pauses
   @ over: boolean flag marking game termination
   @ next_id: autoincrement counter for creature identification
   @ sys_threads: list of background orchestration threads *)
type world = {
  mutable creets : creet list;
  mutable started_at : float;
  mutable elapsed : float;
  mutable over : bool;
  mutable next_id : int;
  mutable sys_threads : unit Lwt.t list;
}

let active_world : world = {
  creets = [];
  started_at = 0.0;
  elapsed = 0.0;
  over = false;
  next_id = 0;
  sys_threads = [];
}

(* ** event **
   Domain event notifications dispatched across decoupled game modules.
   ==> Broadcasts key gameplay occurrences to stats, audio, and visual fx
   @ Contaminated: creature contracted virus
   @ Healed: sick creature cured at hospital
   @ Died: berserk or mean creature expired
   @ Spawned: new creature introduced into field
   @ Mutated: sick creature evolved into berserk or mean *)
type event =
  | Contaminated of creet
  | Healed of creet
  | Died of creet
  | Spawned of creet
  | Mutated of creet

let event_listeners : (event -> unit) list ref = ref []

(* ** dom_refs **
   Container holding references to top-level TyXML DOM nodes.
   ==> Shared container avoiding document lookups
   @ board_el: main game board node
   @ creatures_el: full-board layer holding creets and particles
   @ river_el: infection river node
   @ hospital_el: healing sanctuary node
   @ panel_el: sidebar control panel node
   @ gameover_el: termination modal overlay node *)
type dom_refs = {
  mutable board_el : Dom_html.element Js.t option;
  mutable creatures_el : Dom_html.element Js.t option;
  mutable river_el : Dom_html.element Js.t option;
  mutable hospital_el : Dom_html.element Js.t option;
  mutable panel_el : Dom_html.element Js.t option;
  mutable gameover_el : Dom_html.element Js.t option;
}

let dom_nodes : dom_refs = {
  board_el = None;
  creatures_el = None;
  river_el = None;
  hospital_el = None;
  panel_el = None;
  gameover_el = None;
}

(* ** center **
   Computes geometric center coordinates of a creature.
   @param c: creature to evaluate
   @res 1: tuple of (cx, cy) coordinates
   @edge cases: handles any positive diameter value
   @error conditions: none *)
let center (c : creet) : float * float =
  let cx : float = c.x +. (c.diam /. 2.0) in
  let cy : float = c.y +. (c.diam /. 2.0) in
  (cx, cy)

(* ** radius **
   Computes current radius of a creature.
   @param c: creature to inspect
   @res 1: radius in pixels
   @edge cases: accounts for berserk growth
   @error conditions: none *)
let radius (c : creet) : float =
  let r : float = c.diam /. 2.0 in
  r

(* ** touching **
   Evaluates Euclidean collision between two creatures.
   @param a: first creature
   @param b: second creature
   @res 1: boolean true if bounding circles overlap
   @edge cases: uses squared distance to optimize math
   @error conditions: none *)
let touching (a : creet) (b : creet) : bool =
  let (ax, ay) : float * float = center a in
  let (bx, by) : float * float = center b in
  let dx : float = ax -. bx in
  let dy : float = ay -. by in
  let dist_sq : float = (dx *. dx) +. (dy *. dy) in
  let rad_sum : float = radius a +. radius b in
  dist_sq < (rad_sum *. rad_sum)

(* ** count_by_state **
   Counts active living creatures matching a target health state.
   @param target_state: state to filter for
   @res 1: integer count of living matching creatures
   @edge cases: ignores dead or terminated creatures
   @error conditions: none *)
let count_by_state (target_state : state) : int =
  let matching : creet list =
    List.filter (fun (c : creet) -> c.alive && c.state = target_state) active_world.creets
  in
  List.length matching

(* ** get_time **
   Retrieves current high-resolution wall clock time in seconds.
   @res 1: floating point timestamp in seconds
   @edge cases: wraps Js.date_now
   @error conditions: none *)
let get_time () : float =
  let date_obj : Js.date Js.t = new%js Js.date_now in
  let ms : float = Js.to_float date_obj##getTime in
  ms /. 1000.0

(* ** emit_event **
   Dispatches a domain event to all registered observers.
   @param ev: event to publish
   @res 1: unit confirming broadcast
   @edge cases: invokes callbacks synchronously
   @error conditions: none *)
let emit_event (ev : event) : unit =
  let observers : (event -> unit) list = !event_listeners in
  List.iter (fun (fn : event -> unit) -> fn ev) observers

(* ** register_listener **
   Subscribes an observer callback to gameplay domain events.
   @param fn: listener function receiving events
   @res 1: unit confirming subscription
   @edge cases: prepends to listener list
   @error conditions: none *)
let register_listener (fn : event -> unit) : unit =
  event_listeners := fn :: !event_listeners

(* ** reset_listeners **
   Clears all event subscriptions on new game session start.
   @res 1: unit confirming listener list reset
   @edge cases: called during world reinitialization
   @error conditions: none *)
let reset_listeners () : unit =
  event_listeners := []
]
