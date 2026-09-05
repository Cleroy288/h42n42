[%%client
open Js_of_ocaml
open Js_of_ocaml_lwt
open Eliom_content.Html.D
open Types

(* File Header: panel.eliom
   @structures: control_panel_ui
   @functions: make_num_input, make_int_input, make_btn, make_btn_dyn, build_panel, update_hud, show_gameover *)

(* ** make_num_input **
   Constructs a labeled number input updating a float reference on each edit.
   @param on_change: optional callback invoked immediately on value change
   @param label_text: display name of parameter
   @param min_val: minimum accepted value
   @param max_val: maximum accepted value
   @param step_val: increment used by the input's arrows
   @param target_ref: mutable float reference to update
   @res 1: TyXML div element containing the labeled input
   @edge cases: typed values are clamped to [min_val, max_val]
   @error conditions: handles string parsing exceptions safely *)
let make_num_input
    ?on_change
    (label_text : string)
    (min_val : float)
    (max_val : float)
    (step_val : float)
    (target_ref : float ref) : [> Html_types.div ] elt =
  let num_input : [> Html_types.input ] elt =
    input
      ~a:[
        a_input_type `Number;
        a_value (Printf.sprintf "%g" !target_ref);
        Unsafe.string_attrib "min" (Printf.sprintf "%g" min_val);
        Unsafe.string_attrib "max" (Printf.sprintf "%g" max_val);
        Unsafe.string_attrib "step" (Printf.sprintf "%g" step_val);
      ]
      ()
  in
  let dom_input : Dom_html.inputElement Js.t = Eliom_content.Html.To_dom.of_input num_input in
  Lwt.async (fun () ->
    Lwt_js_events.inputs dom_input (fun _ _ ->
      (try
         let v : float = float_of_string (Js.to_string dom_input##.value) in
         let v : float = Float.max min_val (Float.min max_val v) in
         target_ref := v;
         (match on_change with Some fn -> fn v | None -> ())
       with _ -> ());
      Lwt.return_unit));
  div
    ~a:[a_class ["field-row"]]
    [label [txt label_text]; num_input]

(* ** make_int_input **
   Constructs a labeled integer number input updating an int reference.
   @param label_text: parameter label
   @param min_val: integer minimum
   @param max_val: integer maximum
   @param target_ref: integer mutable reference
   @res 1: TyXML div element
   @edge cases: typed values are clamped to [min_val, max_val]
   @error conditions: catches int_of_string exceptions *)
let make_int_input
    (label_text : string)
    (min_val : int)
    (max_val : int)
    (target_ref : int ref) : [> Html_types.div ] elt =
  let num_input : [> Html_types.input ] elt =
    input
      ~a:[
        a_input_type `Number;
        a_value (string_of_int !target_ref);
        Unsafe.string_attrib "min" (string_of_int min_val);
        Unsafe.string_attrib "max" (string_of_int max_val);
        Unsafe.string_attrib "step" "1";
      ]
      ()
  in
  let dom_input : Dom_html.inputElement Js.t = Eliom_content.Html.To_dom.of_input num_input in
  Lwt.async (fun () ->
    Lwt_js_events.inputs dom_input (fun _ _ ->
      (try
         let v : int = int_of_string (Js.to_string dom_input##.value) in
         let v : int = max min_val (min max_val v) in
         target_ref := v
       with _ -> ());
      Lwt.return_unit));
  div
    ~a:[a_class ["field-row"]]
    [label [txt label_text]; num_input]

(* ** make_btn **
   Constructs a static button with Lwt_js_events click binding.
   @param caption: button label text
   @param cls: CSS styling classes
   @param on_click: callback function executed on click
   @res 1: TyXML button element
   @edge cases: uses exclusively Lwt_js_events.clicks
   @error conditions: none *)
let make_btn (caption : string) (cls : string list) (on_click : unit -> unit) : [> Html_types.button ] elt =
  let btn_elt : [> Html_types.button ] elt =
    button ~a:[a_class ("btn" :: cls); a_button_type `Button] [txt caption]
  in
  let dom_btn : Dom_html.buttonElement Js.t = Eliom_content.Html.To_dom.of_button btn_elt in
  Lwt.async (fun () ->
    Lwt_js_events.clicks dom_btn (fun _ _ ->
      on_click ();
      Lwt.return_unit));
  btn_elt

(* ** make_btn_dyn **
   Constructs a button whose text label can be updated dynamically via DOM reference on click.
   @param initial_caption: initial button label text
   @param cls: CSS styling classes
   @param on_click: callback function receiving the button DOM element
   @res 1: TyXML button element
   @edge cases: uses exclusively Lwt_js_events.clicks
   @error conditions: none *)
let make_btn_dyn (initial_caption : string) (cls : string list) (on_click : Dom_html.buttonElement Js.t -> unit) : [> Html_types.button ] elt =
  let btn_elt : [> Html_types.button ] elt =
    button ~a:[a_class ("btn" :: cls); a_button_type `Button] [txt initial_caption]
  in
  let dom_btn : Dom_html.buttonElement Js.t = Eliom_content.Html.To_dom.of_button btn_elt in
  Lwt.async (fun () ->
    Lwt_js_events.clicks dom_btn (fun _ _ ->
      on_click dom_btn;
      Lwt.return_unit));
  btn_elt

(* References to live HUD text elements for zero-reallocation updates *)
let hud_healthy_span : Dom_html.element Js.t option ref = ref None
let hud_sick_span : Dom_html.element Js.t option ref = ref None
let hud_berserk_span : Dom_html.element Js.t option ref = ref None
let hud_mean_span : Dom_html.element Js.t option ref = ref None
let hud_saved_span : Dom_html.element Js.t option ref = ref None
let hud_time_span : Dom_html.element Js.t option ref = ref None
let hud_fps_span : Dom_html.element Js.t option ref = ref None

(* ** update_hud **
   Updates DOM values of live counters without destroying nodes.
   @res 1: unit confirming counter refresh
   @edge cases: checks node availability safely
   @error conditions: none *)
let update_hud () : unit =
  let set_text opt_node text =
    match !opt_node with
    | Some el -> el##.textContent := Js.some (Js.string text)
    | None -> ()
  in
  set_text hud_healthy_span (string_of_int (count_by_state Healthy));
  set_text hud_sick_span (string_of_int (count_by_state Sick));
  set_text hud_berserk_span (string_of_int (count_by_state Berserk));
  set_text hud_mean_span (string_of_int (count_by_state Mean));
  set_text hud_saved_span (string_of_int Stats.session_stats.saved);
  set_text hud_time_span (Printf.sprintf "%.1fs" active_world.elapsed);
  set_text hud_fps_span (string_of_int !Game.current_fps)

(* ** show_gameover **
   Populates and displays the game over overlay modal upon extinction of healthy creets.
   @res 1: unit confirming modal display
   @edge cases: formats leaderboard into styled TyXML table
   @error conditions: none *)
let show_gameover () : unit =
  match dom_nodes.gameover_el with
  | None -> ()
  | Some modal_node ->
      let final_score : int = Stats.calculate_score () in
      let eff_pct : int = int_of_float (Stats.calculate_efficiency () *. 100.0) in
      let lb_entries : Stats.leaderboard_entry list = Stats.get_leaderboard () in
      let lb_rows =
        List.mapi
          (fun i (e : Stats.leaderboard_entry) ->
            tr [
              td [txt (Printf.sprintf "#%d" (i + 1))];
              td [txt e.date_str];
              td [txt (Printf.sprintf "%.1fs" e.duration_s)];
              td [txt (string_of_int e.score_val)];
            ])
          lb_entries
      in
      let restart_btn =
        make_btn "PLAY AGAIN" ["btn-primary"] (fun () -> Game.reset_game ())
      in
      let modal_content =
        div
          ~a:[a_class ["gameover-container"]]
          [
            h1 ~a:[a_class ["gameover-title"]] [txt "GAME OVER"];
            div
              ~a:[a_class ["gameover-stats-box"]]
              [
                div
                  ~a:[a_class ["gameover-score-row"]]
                  [
                    span [txt "FINAL SCORE"];
                    span ~a:[a_class ["gameover-score-value"]] [txt (string_of_int final_score)];
                  ];
                div
                  ~a:[a_class ["dash-row"]]
                  [span [txt "Survival Time:"]; span [txt (Printf.sprintf "%.1fs" active_world.elapsed)]];
                div
                  ~a:[a_class ["dash-row"]]
                  [span [txt "Creets Saved:"]; span [txt (string_of_int Stats.session_stats.saved)]];
                div
                  ~a:[a_class ["dash-row"]]
                  [span [txt "Creets Lost:"]; span [txt (string_of_int Stats.session_stats.lost)]];
                div
                  ~a:[a_class ["dash-row"]]
                  [span [txt "Cure Efficiency:"]; span [txt (Printf.sprintf "%d%%" eff_pct)]];
                div
                  ~a:[a_class ["dash-row"]]
                  [span [txt "Max Concurrent Alive:"]; span [txt (string_of_int Stats.session_stats.max_alive)]];
                h3 ~a:[a_class ["panel-section-title"]; a_style "margin-top:12px;"] [txt "TOP SCORES (LOCAL)"];
                table
                  ~a:[a_class ["leaderboard-table"]]
                  (tr [th [txt "Rank"]; th [txt "Date"]; th [txt "Time"]; th [txt "Score"]] :: lb_rows);
              ];
            div ~a:[a_style "display:flex; justify-content:center;"] [restart_btn];
          ]
      in
      modal_node##.innerHTML := Js.string "";
      Eliom_content.Html.Manip.appendChild
        (Eliom_content.Html.Of_dom.of_element modal_node)
        modal_content;
      modal_node##.classList##remove (Js.string "hidden")

(* ** build_panel **
   Assembles control panel, sliders, buttons, and launches HUD refresh loop.
   @res 1: unit confirming panel assembly
   @edge cases: binds Game.on_game_over_hook
   @error conditions: none *)
let build_panel () : unit =
  Game.on_game_over_hook := show_gameover;
  match dom_nodes.panel_el with
  | None -> ()
  | Some panel_node ->
      (* 1. HUD Display Grid *)
      let make_hud_card lbl cls =
        let val_el = span ~a:[a_class ["hud-value"; cls]] [txt "0"] in
        let card =
          div
            ~a:[a_class ["hud-card"]]
            [span ~a:[a_class ["hud-label"]] [txt lbl]; val_el]
        in
        (card, Eliom_content.Html.To_dom.of_element val_el)
      in
      let card_h, span_h = make_hud_card "Healthy" "hud-healthy" in
      let card_s, span_s = make_hud_card "Sick" "hud-sick" in
      let card_b, span_b = make_hud_card "Berserk" "hud-berserk" in
      let card_m, span_m = make_hud_card "Mean" "hud-mean" in
      let card_saved, span_saved = make_hud_card "Saved" "hud-healthy" in
      let card_time, span_time = make_hud_card "Time" "hud-time" in
      let card_fps, span_fps = make_hud_card "FPS" "hud-fps" in

      hud_healthy_span := Some span_h;
      hud_sick_span := Some span_s;
      hud_berserk_span := Some span_b;
      hud_mean_span := Some span_m;
      hud_saved_span := Some span_saved;
      hud_time_span := Some span_time;
      hud_fps_span := Some span_fps;

      let hud_section =
        div
          [
            h3 ~a:[a_class ["panel-section-title"]] [txt "Live Population & Telemetry"];
            div ~a:[a_class ["hud-grid"]] [card_h; card_s; card_b; card_m; card_saved; card_time; card_fps];
          ]
      in

      (* 2. Parameter Inputs Section *)
      let in_speed = make_num_input "Movement Speed (px/s)" 30.0 250.0 5.0 Config.speed_base in
      let in_contam = make_num_input "Contamination Chance" 0.005 0.10 0.005 Config.contam_prob in
      let in_spawn = make_num_input "Spawn Interval (s)" 1.0 10.0 0.5 Config.spawn_interval in
      let in_init = make_int_input "Initial Creets" 2 30 Config.initial_creets in
      let in_berserk = make_num_input "Berserk Chance (10s)" 0.0 0.50 0.05 Config.berserk_prob in
      let in_mean = make_num_input "Mean Chance (10s)" 0.0 0.50 0.05 Config.mean_prob in

      let params_section =
        div
          [
            h3 ~a:[a_class ["panel-section-title"]] [txt "Simulation Parameters (Live)"];
            div ~a:[a_style "display:flex; flex-direction:column; gap:6px;"] [
              in_speed;
              in_contam;
              in_spawn;
              in_init;
              in_berserk;
              in_mean;
            ];
          ]
      in

      (* 3. Game Control Buttons with Dynamic Labels *)
      let pause_btn =
        make_btn_dyn "Pause" ["btn-primary"] (fun btn ->
          let is_paused = Game.toggle_pause () in
          btn##.textContent := Js.some (Js.string (if is_paused then "Resume" else "Pause")))
      in
      let reset_btn = make_btn "Reset Game" ["btn-danger"] (fun () -> Game.reset_game ()) in
      let btn_easy = make_btn "Mode: Easy" [] (fun () -> Config.set_difficulty Config.Easy) in
      let btn_norm = make_btn "Mode: Normal" [] (fun () -> Config.set_difficulty Config.Normal) in
      let btn_hard = make_btn "Mode: Hard" [] (fun () -> Config.set_difficulty Config.Hard) in

      (* 4. Bonus 5: Collisions & Stress *)
      let toggle_grid_btn =
        make_btn_dyn "Grid Hash: ON" [] (fun btn ->
          Config.optimized_collision := not !Config.optimized_collision;
          btn##.textContent :=
            Js.some (Js.string (if !Config.optimized_collision then "Grid Hash: ON" else "Naive O(n²): ON")))
      in
      let stress_btn = make_btn "+100 Stress Test" [] (fun () -> Game.stress_test 100) in

      (* 5. Bonus 3: Audio Controls *)
      let mute_btn =
        make_btn_dyn "Sound: ON" [] (fun btn ->
          let sound_on = Audio.toggle_mute () in
          btn##.textContent := Js.some (Js.string (if sound_on then "Sound: ON" else "Sound: MUTED")))
      in
      let in_music_vol =
        make_num_input ~on_change:Audio.set_music_volume "Music Volume" 0.0 1.0 0.05 Audio.music_volume
      in
      let in_sfx_vol =
        make_num_input ~on_change:Audio.set_sfx_volume "SFX Volume" 0.0 1.0 0.05 Audio.sfx_volume
      in

      (* 6. Bonus 4: Statistics Dashboard Drawer *)
      let dash_div = div ~a:[a_id "dashboard"; a_class ["hidden"]] [] in
      let dom_dash : Dom_html.element Js.t = Eliom_content.Html.To_dom.of_element dash_div in
      let dash_toggle_btn =
        make_btn "Toggle Dashboard" [] (fun () ->
          dom_dash##.classList##toggle (Js.string "hidden") |> ignore;
          let eff : int = int_of_float (Stats.calculate_efficiency () *. 100.0) in
          let sc : int = Stats.calculate_score () in
          dom_dash##.innerHTML :=
            Js.string
              (Printf.sprintf
                 "<strong>DETAILED METRICS</strong><br/>Score: %d | Efficiency: %d%%<br/>Lost to Virus: %d<br/>Berserk Seen: %d | Mean Seen: %d"
                 sc eff Stats.session_stats.lost Stats.session_stats.berserk_seen Stats.session_stats.mean_seen))
      in

      let actions_section =
        div
          [
            h3 ~a:[a_class ["panel-section-title"]] [txt "Controls & Actions"];
            div ~a:[a_class ["btn-grid"]] [pause_btn; reset_btn; btn_easy; btn_norm; btn_hard; dash_toggle_btn];
            h3 ~a:[a_class ["panel-section-title"]; a_style "margin-top:10px;"] [txt "Spatial Partitioning & Stress"];
            div ~a:[a_class ["btn-grid"]] [toggle_grid_btn; stress_btn];
            h3 ~a:[a_class ["panel-section-title"]; a_style "margin-top:10px;"] [txt "Audio Controls"];
            div ~a:[a_class ["btn-grid"]] [mute_btn];
            div ~a:[a_style "margin-top:8px; display:flex; flex-direction:column; gap:6px;"] [in_music_vol; in_sfx_vol];
            dash_div;
          ]
      in

      let full_panel = div [hud_section; params_section; actions_section] in
      panel_node##.innerHTML := Js.string "";
      Eliom_content.Html.Manip.appendChild (Eliom_content.Html.Of_dom.of_element panel_node) full_panel;

      (* Launch periodic HUD update thread *)
      Lwt.async (fun () ->
        let rec hud_loop () : unit Lwt.t =
          let%lwt () = Lwt_js.sleep 0.25 in
          update_hud ();
          hud_loop ()
        in
        hud_loop ())
]
