[%%client
(* File Header: config.eliom
   Geometric constants and simulation parameters. Everything is a plain
   constant except speed_mult, which grows over time (difficulty). *)

(* Board geometry (logical px) *)
let board_w : float = 1000.0
let board_h : float = 700.0
let river_h : float = 80.0
let hospital_h : float = 90.0
let base_diam : float = 40.0

(* Simulation parameters *)
let speed_base : float = 90.0          (* px/s *)
let speed_mult : float ref = ref 1.0   (* difficulty multiplier, grows over time *)
let contam_prob : float = 0.02         (* contagion probability per contact frame *)
let spawn_interval : float = 4.0       (* s between spawns *)
let initial_creets : int = 8
let berserk_prob : float = 0.10        (* chance to mutate on each mutation tick *)
let mean_prob : float = 0.10

(* State behaviour constants *)
let sick_speed_factor : float = 0.85   (* sick creets are 15% slower *)
let berserk_growth : float = 1.10      (* diameter growth per tick *)
let berserk_tick : float = 10.0        (* s between berserk growth steps *)
let berserk_max : float = 4.0          (* dies at 4x base diameter *)
let mean_size_factor : float = 0.85
let mean_lifetime : float = 60.0       (* s before a mean creet dies *)
let mutation_tick : float = 10.0       (* s between mutation rolls while sick *)
let dir_change_min : float = 2.0       (* s range between random direction changes *)
let dir_change_max : float = 5.0

(* Progressive difficulty *)
let grace_period : float = 60.0        (* s without acceleration *)
let accel_period : float = 5.0         (* s between speed increases *)
let accel_step : float = 0.08          (* +8% speed_mult per period *)
]
