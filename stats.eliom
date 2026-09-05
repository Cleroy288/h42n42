[%%client
open Js_of_ocaml
open Types

(* File Header: stats.eliom
   @structures: game_stats, leaderboard_entry
   @functions: reset_stats, calculate_efficiency, calculate_score, on_event, get_leaderboard, save_score *)

(* ** game_stats **
   Internal state tracking all metrics during a playthrough.
   ==> Aggregates survival duration, cures, losses, and mutations *)
type game_stats = {
  mutable saved : int;
  mutable lost : int;
  mutable max_alive : int;
  mutable berserk_seen : int;
  mutable mean_seen : int;
}

let session_stats : game_stats = {
  saved = 0;
  lost = 0;
  max_alive = 0;
  berserk_seen = 0;
  mean_seen = 0;
}

type leaderboard_entry = {
  date_str : string;
  score_val : int;
  duration_s : float;
}

(* ** reset_stats **
   Clears all session counters to zero on new game startup.
   @res 1: unit confirming stats reset
   @edge cases: resets max_alive to initial creature count
   @error conditions: none *)
let reset_stats () : unit =
  session_stats.saved <- 0;
  session_stats.lost <- 0;
  session_stats.max_alive <- !Config.initial_creets;
  session_stats.berserk_seen <- 0;
  session_stats.mean_seen <- 0

(* ** calculate_efficiency **
   Computes ratio of saved creatures against total infection casualties.
   @res 1: floating point efficiency ratio between 0.0 and 1.0
   @edge cases: defaults to 1.0 if no infections or cures have occurred
   @error conditions: none *)
let calculate_efficiency () : float =
  let total : float = float_of_int (session_stats.saved + session_stats.lost) in
  if total <= 0.0 then 1.0
  else float_of_int session_stats.saved /. total

(* ** calculate_score **
   Calculates aggregate player score based on duration, cures, and efficiency.
   @res 1: integer score value
   @edge cases: score is never negative
   @error conditions: none *)
let calculate_score () : int =
  let time_pts : float = active_world.elapsed *. 10.0 in
  let eff : float = calculate_efficiency () in
  let save_pts : float = float_of_int session_stats.saved *. 100.0 *. eff in
  int_of_float (time_pts +. save_pts)

(* ** on_event **
   Updates running session statistics upon domain event reception.
   @param ev: domain event to log
   @res 1: unit confirming metric update
   @edge cases: evaluates max_alive dynamically on creature spawn
   @error conditions: none *)
let on_event (ev : event) : unit =
  match ev with
  | Healed _ -> session_stats.saved <- session_stats.saved + 1
  | Contaminated _ -> session_stats.lost <- session_stats.lost + 1
  | Mutated c ->
      if c.state = Berserk then session_stats.berserk_seen <- session_stats.berserk_seen + 1
      else if c.state = Mean then session_stats.mean_seen <- session_stats.mean_seen + 1
  | Spawned _ ->
      let current_alive : int =
        List.length (List.filter (fun (item : creet) -> item.alive) active_world.creets)
      in
      if current_alive > session_stats.max_alive then
        session_stats.max_alive <- current_alive
  | _ -> ()

(* ** get_leaderboard **
   Reads top 5 stored scores from browser localStorage.
   @res 1: list of parsed leaderboard entries
   @edge cases: returns empty list if storage is absent or malformed
   @error conditions: catches JS storage exceptions gracefully *)
let get_leaderboard () : leaderboard_entry list =
  try
    let storage_opt : Dom_html.storage Js.t Js.optdef = Dom_html.window##.localStorage in
    match Js.Optdef.to_option storage_opt with
    | None -> []
    | Some storage ->
        let raw_val : Js.js_string Js.t Js.opt = storage##getItem (Js.string "h42n42_lb") in
        (match Js.Opt.to_option raw_val with
        | None -> []
        | Some js_str ->
            let str : string = Js.to_string js_str in
            let lines : string list = String.split_on_char '\n' str in
            List.filter_map
              (fun (line : string) ->
                match String.split_on_char ';' line with
                | [d; s; dur] ->
                    Some {
                      date_str = d;
                      score_val = int_of_string s;
                      duration_s = float_of_string dur;
                    }
                | _ -> None)
              lines)
  with _ -> []

(* ** save_score **
   Inserts current game score into localStorage leaderboard, keeping top 5.
   @res 1: unit confirming leaderboard persistence
   @edge cases: truncates leaderboard to top 5 highest scores
   @error conditions: catches localStorage quota or access errors *)
let save_score () : unit =
  try
    let current_score : int = calculate_score () in
    let date_now : Js.date Js.t = new%js Js.date_now in
    let date_str : string =
      Printf.sprintf "%02d/%02d %02d:%02d"
        (date_now##getMonth + 1)
        date_now##getDate
        date_now##getHours
        date_now##getMinutes
    in
    let new_entry : leaderboard_entry = {
      date_str;
      score_val = current_score;
      duration_s = active_world.elapsed;
    } in
    let existing : leaderboard_entry list = get_leaderboard () in
    let combined : leaderboard_entry list = new_entry :: existing in
    let sorted : leaderboard_entry list =
      List.sort (fun a b -> compare b.score_val a.score_val) combined
    in
    let top_five : leaderboard_entry list =
      let rec take n lst =
        match (n, lst) with
        | (0, _) | (_, []) -> []
        | (n, x :: xs) -> x :: take (n - 1) xs
      in
      take 5 sorted
    in
    let serialized : string =
      String.concat "\n"
        (List.map
           (fun e -> Printf.sprintf "%s;%d;%.1f" e.date_str e.score_val e.duration_s)
           top_five)
    in
    let storage_opt : Dom_html.storage Js.t Js.optdef = Dom_html.window##.localStorage in
    match Js.Optdef.to_option storage_opt with
    | None -> ()
    | Some storage ->
        storage##setItem (Js.string "h42n42_lb") (Js.string serialized)
  with _ -> ()
]
