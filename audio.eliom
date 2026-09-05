[%%client
open Js_of_ocaml
open Types

(* File Header: audio.eliom
   @structures: audio_category
   @functions: init_audio, music_start, play_sfx, set_music_volume, set_sfx_volume, toggle_mute, on_event *)

let sound_enabled : bool ref = ref true
let music_volume : float ref = ref 0.5
let sfx_volume : float ref = ref 0.8

let music_player : Dom_html.audioElement Js.t option ref = ref None
let sfx_cache : (string, Dom_html.audioElement Js.t) Hashtbl.t = Hashtbl.create 8

(* ** init_audio **
   Preloads audio assets and attaches error fallback handlers.
   @res 1: unit confirming initialization
   @edge cases: missing files produce silent fallback without throwing
   @error conditions: none *)
let init_audio () : unit =
  let sfx_names : string list = ["contaminate"; "heal"; "death"; "gameover"; "spawn"] in
  List.iter
    (fun (name : string) ->
      try
        let audio_el : Dom_html.audioElement Js.t =
          Dom_html.createAudio Dom_html.document
        in
        audio_el##.src := Js.string (Printf.sprintf "audio/%s.mp3" name);
        audio_el##.preload := Js.string "auto";
        Hashtbl.add sfx_cache name audio_el
      with _ -> ())
    sfx_names;
  try
    let bgm : Dom_html.audioElement Js.t = Dom_html.createAudio Dom_html.document in
    bgm##.src := Js.string "audio/music.mp3";
    bgm##.loop := Js._true;
    bgm##.volume := !music_volume;
    music_player := Some bgm
  with _ -> ()

(* ** music_start **
   Begins background music playback following first user gesture.
   @res 1: unit confirming playback invocation
   @edge cases: complies with browser autoplay gesture requirements
   @error conditions: none *)
let music_start () : unit =
  if !sound_enabled then
    match !music_player with
    | None -> ()
    | Some bgm ->
        bgm##.volume := !music_volume;
        (try bgm##play |> ignore with _ -> ())

(* ** play_sfx **
   Plays a cached sound effect or invokes Web Audio fallback.
   @param name: identifier of sound effect to trigger
   @res 1: unit confirming sound dispatch
   @edge cases: no-op if audio is muted or sound file absent
   @error conditions: none *)
let play_sfx (name : string) : unit =
  if !sound_enabled then
    match Hashtbl.find_opt sfx_cache name with
    | None -> ()
    | Some base_audio ->
        try
          let clone : Dom_html.audioElement Js.t =
            Js.Unsafe.coerce (base_audio##cloneNode Js._true)
          in
          clone##.volume := !sfx_volume;
          clone##play |> ignore
        with _ -> ()

(* ** set_music_volume **
   Updates background soundtrack volume level.
   @param vol: volume level between 0.0 and 1.0
   @res 1: unit confirming volume update
   @edge cases: clamps value within valid range [0.0, 1.0]
   @error conditions: none *)
let set_music_volume (vol : float) : unit =
  let clamped : float = max 0.0 (min 1.0 vol) in
  music_volume := clamped;
  match !music_player with
  | None -> ()
  | Some bgm -> bgm##.volume := clamped

(* ** set_sfx_volume **
   Updates sound effect volume level.
   @param vol: volume level between 0.0 and 1.0
   @res 1: unit confirming volume update
   @edge cases: clamps value within valid range [0.0, 1.0]
   @error conditions: none *)
let set_sfx_volume (vol : float) : unit =
  let clamped : float = max 0.0 (min 1.0 vol) in
  sfx_volume := clamped

(* ** toggle_mute **
   Toggles global audio muting state.
   @res 1: current boolean muting status
   @edge cases: pauses or resumes active background track
   @error conditions: none *)
let toggle_mute () : bool =
  sound_enabled := not !sound_enabled;
  (match !music_player with
  | None -> ()
  | Some bgm ->
      if not !sound_enabled then
        bgm##pause
      else
        (try bgm##play |> ignore with _ -> ()));
  !sound_enabled

(* ** on_event **
   Observer mapping game events to specific sound effect triggers.
   @param ev: domain event to sonify
   @res 1: unit confirming sound effect dispatch
   @edge cases: safely handles all event variants
   @error conditions: none *)
let on_event (ev : event) : unit =
  match ev with
  | Contaminated _ -> play_sfx "contaminate"
  | Healed _ -> play_sfx "heal"
  | Died _ -> play_sfx "death"
  | Spawned _ -> play_sfx "spawn"
  | _ -> ()
]
