[%%client
open Js_of_ocaml
open Js_of_ocaml_lwt
open Eliom_content.Html.D
open Types

(* File Header: fx.eliom
   @structures: particle_element
   @functions: spawn_particles, apply_flash, on_event *)

(* ** spawn_particles **
   Generates TyXML particle burst elements upon creature contamination.
   @param c: creature at center of infection burst
   @res 1: unit confirming particle generation
   @edge cases: silently returns if field DOM node is uninitialized
   @error conditions: none *)
let spawn_particles (c : creet) : unit =
  match dom_nodes.creatures_el with
  | None -> ()
  | Some field_node ->
      let (cx, cy) : float * float = center c in
      let num_particles : int = 8 in
      for i = 0 to num_particles - 1 do
        let angle : float = (float_of_int i *. (2.0 *. Float.pi)) /. float_of_int num_particles in
        let dist : float = 40.0 +. (Random.float 25.0) in
        let dx : float = cos angle *. dist in
        let dy : float = sin angle *. dist in
        let p_elt : [> Html_types.div ] elt =
          div
            ~a:[
              a_class ["particle"];
              a_style (Printf.sprintf "left:%.1fpx; top:%.1fpx; --dx:%.1fpx; --dy:%.1fpx;" cx cy dx dy)
            ]
            []
        in
        let dom_p : Dom_html.divElement Js.t = Eliom_content.Html.To_dom.of_div p_elt in
        Eliom_content.Html.Manip.appendChild (Eliom_content.Html.Of_dom.of_element field_node) p_elt;
        Lwt.async (fun () ->
          let%lwt () = Lwt_js.sleep 0.6 in
          (try field_node##removeChild (dom_p :> Dom.node Js.t) |> ignore with _ -> ());
          Lwt.return_unit)
      done

(* ** apply_flash **
   Temporarily adds visual feedback CSS class to creature element.
   @param c: creature to highlight
   @param flash_class: CSS animation class to attach
   @res 1: unit confirming flash execution
   @edge cases: catches DOM detachment errors gracefully
   @error conditions: none *)
let apply_flash (c : creet) (flash_class : string) : unit =
  c.el##.classList##add (Js.string flash_class);
  Lwt.async (fun () ->
    let%lwt () = Lwt_js.sleep 0.5 in
    c.el##.classList##remove (Js.string flash_class);
    Lwt.return_unit)

(* ** on_event **
   Observer callback mapping gameplay domain events to visual FX.
   @param ev: domain event to inspect
   @res 1: unit confirming visual trigger
   @edge cases: handles all event variants safely
   @error conditions: none *)
let on_event (ev : event) : unit =
  match ev with
  | Contaminated c -> spawn_particles c
  | Healed c -> apply_flash c "flash-heal"
  | Mutated c -> apply_flash c "flash-mutate"
  | _ -> ()
]
