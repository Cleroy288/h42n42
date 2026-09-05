[%%client
(* File Header: config.eliom
   @structures: difficulty_mode
   @functions: set_difficulty, reset_defaults *)

(* ** Config Constants **
   Fixed geometric constants and default operational thresholds. *)
let board_w : float = 1000.0
let board_h : float = 700.0
let river_h : float = 80.0
let hospital_h : float = 90.0
let base_diam : float = 40.0

let sick_speed_factor : float = 0.85
let berserk_growth : float = 1.10
let berserk_tick : float = 10.0
let berserk_max : float = 4.0
let mean_size_factor : float = 0.85
let mean_lifetime : float = 60.0
let mutation_tick : float = 10.0
let dir_change_min : float = 2.0
let dir_change_max : float = 5.0
let grace_period : float = 60.0
let accel_period : float = 5.0

(* ** Config Live References **
   Dynamic parameters modified in real time via the control panel. *)
let speed_base : float ref = ref 90.0
let speed_mult : float ref = ref 1.0
let contam_prob : float ref = ref 0.02
let spawn_interval : float ref = ref 4.0
let initial_creets : int ref = ref 8
let berserk_prob : float ref = ref 0.10
let mean_prob : float ref = ref 0.10
let accel_step : float ref = ref 0.08
let paused : bool ref = ref false
let optimized_collision : bool ref = ref true

type difficulty_mode = Easy | Normal | Hard
let current_difficulty : difficulty_mode ref = ref Normal

(* ** set_difficulty **
   Updates active difficulty preset and adjusts acceleration rate.
   @param mode: selected difficulty preset
   @res 1: unit indicating state update completion
   @edge cases: applies immediately to next difficulty tick
   @error conditions: none *)
let set_difficulty (mode : difficulty_mode) : unit =
  (* Step 1: Assign current difficulty mode *)
  current_difficulty := mode;
  (* Step 2: Set speed acceleration step according to mode *)
  (match mode with
  | Easy -> accel_step := 0.04
  | Normal -> accel_step := 0.08
  | Hard -> accel_step := 0.15)

(* ** reset_defaults **
   Restores all game configuration parameters to baseline values.
   @res 1: unit confirming baseline restoration
   @edge cases: called when game is reset
   @error conditions: none *)
let reset_defaults () : unit =
  (* Step 1: Reset speed multipliers and probabilities *)
  speed_base := 90.0;
  speed_mult := 1.0;
  contam_prob := 0.02;
  spawn_interval := 4.0;
  initial_creets := 8;
  berserk_prob := 0.10;
  mean_prob := 0.10;
  accel_step := 0.08;
  (* Step 2: Unpause game and set standard difficulty *)
  paused := false;
  current_difficulty := Normal
]
