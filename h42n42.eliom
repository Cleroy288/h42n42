[%%server
open Eliom_content.Html.D

(* Module exports for check_modules.ml validation *)
module Config = Config
module Types = Types
module Creet = Creet
module Drag = Drag
module Game = Game

module H42n42_app = Eliom_registration.App (struct
  let application_name = "h42n42"
  let global_data_path = None
end)
]

[%%client
(* Module exports for check_modules.ml validation *)
module Config = Config
module Types = Types
module Creet = Creet
module Drag = Drag
module Game = Game

module Main = struct
  (* ** get_elem **
     Retrieves a DOM element by ID as an OCaml option. *)
  let get_elem (id : string) : Js_of_ocaml.Dom_html.element Js_of_ocaml.Js.t option =
    Js_of_ocaml.Js.Opt.to_option
      (Js_of_ocaml.Dom_html.document##getElementById (Js_of_ocaml.Js.string id))

  (* ** init **
     Binds DOM nodes and starts the simulation. *)
  let init () : unit =
    Types.dom_nodes.board_el <- get_elem "board";
    Types.dom_nodes.creatures_el <- get_elem "creatures";
    Types.dom_nodes.gameover_el <- get_elem "gameover";
    Game.start_game ()
end
]

[%%server
let river_elt = div ~a:[a_id "river"] []
let field_elt = div ~a:[a_id "field"] []
let hospital_elt = div ~a:[a_id "hospital"] []
let creatures_elt = div ~a:[a_id "creatures"] []
let board_elt = div ~a:[a_id "board"] [river_elt; field_elt; hospital_elt; creatures_elt]
let gameover_elt = div ~a:[a_id "gameover"; a_class ["hidden"]] []

let page_content =
  body
    [
      h1 ~a:[a_class ["app-title"]] [txt "H42N42"];
      board_elt;
      gameover_elt;
    ]

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
           ~title:"H42N42"
           ~css:[["css"; "h42n42.css"]]
           page_content))
]
