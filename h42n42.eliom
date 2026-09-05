[%%server
open Eliom_content.Html.D

(* Module exports for check_modules.ml validation *)
module Config = Config
module Types = Types
module Spatial = Spatial
module Fx = Fx
module Audio = Audio
module Stats = Stats
module Creet = Creet
module Drag = Drag
module Game = Game
module Panel = Panel

module H42n42_app = Eliom_registration.App (struct
  let application_name = "h42n42"
  let global_data_path = None
end)
]

[%%client
open Js_of_ocaml
open Js_of_ocaml_lwt

(* Module exports for check_modules.ml validation *)
module Config = Config
module Types = Types
module Spatial = Spatial
module Fx = Fx
module Audio = Audio
module Stats = Stats
module Creet = Creet
module Drag = Drag
module Game = Game
module Panel = Panel

module Main = struct
  (* ** get_elem **
     Retrieves a DOM element by ID and converts Js.Opt to OCaml option. *)
  let get_elem (id : string) : Dom_html.element Js.t option =
    let doc = Dom_html.document in
    Js.Opt.to_option (doc##getElementById (Js.string id))

  (* ** init **
     Initializes client subsystems, binds DOM nodes, sets responsive scaling, and starts game. *)
  let init () : unit =
    (* Step 1: Register DOM container nodes from document *)
    Types.dom_nodes.board_el <- get_elem "board";
    Types.dom_nodes.creatures_el <- get_elem "creatures";
    Types.dom_nodes.river_el <- get_elem "river";
    Types.dom_nodes.hospital_el <- get_elem "hospital";
    Types.dom_nodes.panel_el <- get_elem "panel";
    Types.dom_nodes.gameover_el <- get_elem "gameover";

    (* Step 2: Responsive board scaling *)
    (match Types.dom_nodes.board_el with
    | None -> ()
    | Some dom_board ->
        let update_scale () : unit =
          let win_w : float = float_of_int Dom_html.window##.innerWidth in
          let s : float =
            if win_w < 1440.0 then
              max 0.5 (min 1.0 ((win_w -. 440.0) /. 1000.0))
            else 1.0
          in
          dom_board##.style##.transform := Js.string (Printf.sprintf "scale(%.3f)" s)
        in
        update_scale ();
        Lwt.async (fun () ->
          Lwt_js_events.onresizes (fun _ _ ->
            update_scale ();
            Lwt.return_unit)));

    (* Step 3: Audio preloading and autoplay unlocking gesture *)
    Audio.init_audio ();
    let doc : Dom_html.document Js.t = Dom_html.document in
    Lwt.async (fun () ->
      let%lwt _ = Lwt_js_events.click doc in
      Audio.music_start ();
      Lwt.return_unit);

    (* Step 4: Build UI and launch simulation *)
    Panel.build_panel ();
    Game.start_game ()
end
]

[%%server
let river_elt = div ~a:[a_id "river"] []
let field_elt = div ~a:[a_id "field"] []
let hospital_elt = div ~a:[a_id "hospital"] []
let creatures_elt = div ~a:[a_id "creatures"] []
let board_elt = div ~a:[a_id "board"] [river_elt; field_elt; hospital_elt; creatures_elt]
let board_wrapper = div ~a:[a_id "board-wrapper"] [board_elt]
let panel_elt = div ~a:[a_id "panel"] []
let gameover_elt = div ~a:[a_id "gameover"; a_class ["hidden"]] []
let game_container = div ~a:[a_id "game-container"] [board_wrapper; panel_elt; gameover_elt]

let header_elt =
  header
    ~a:[a_class ["app-header"]]
    [
      div
        ~a:[a_class ["logo-container"]]
        [
          span ~a:[a_class ["logo-badge"]] [txt "H42N42"];
          div
            [
              div ~a:[a_class ["app-title"]] [txt "Viral Ecosystem Simulation"];
              div ~a:[a_class ["app-subtitle"]] [txt "Ocsigen / Eliom / Lwt Client-Side Simulation"];
            ];
        ];
    ]

let page_content = body [header_elt; game_container]

let main_service =
  Eliom_service.create
    ~path:(Eliom_service.Path [])
    ~meth:(Eliom_service.Get Eliom_parameter.unit)
    ()

let () =
  H42n42_app.register
    ~service:main_service
    (fun () () ->
      let _ = [%client (Main.init () : unit)] in
      Lwt.return
        (Eliom_tools.D.html
           ~title:"H42N42 — Viral Ecosystem Simulation"
           ~css:[["css"; "h42n42.css"]]
           page_content))
]
