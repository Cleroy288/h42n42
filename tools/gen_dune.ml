let with_suffixes nm l f =
  List.iter
    (fun suffix ->
      if Filename.check_suffix nm suffix then f (Filename.chop_suffix nm suffix))
    l

let handle_file_client nm =
  if Filename.check_suffix nm ".pp.eliom" then ()
  else if Filename.check_suffix nm ".pp.eliomi" then ()
  else
    with_suffixes nm [ ".eliom"; ".tsv" ] (fun nm ->
        Printf.printf
          "(rule (target %s.ml) (deps ../%s.eliom)\n\
          \  (action\n\
          \    (with-stdout-to %%{target}\n\
          \      (chdir .. (run tools/eliom_ppx_client.exe --as-pp -server-cmo \
           %%{cmo:../%s} --impl %s.eliom)))))\n"
          nm nm nm nm);
  if Filename.check_suffix nm ".eliomi" then
    let nm = Filename.chop_suffix nm ".eliomi" in
    Printf.printf
      "(rule (target %s.mli) (deps ../%s.eliomi)\n\
      \  (action\n\
      \    (with-stdout-to %%{target}\n\
      \      (chdir .. (run tools/eliom_ppx_client.exe --as-pp --intf \
       %%{deps})))))\n"
      nm nm

let find_source_dir () =
  let candidates = [
    "../../../../src";
    "../../../src";
    "../../src";
    "../src";
    "..";
    "../../..";
    "."
  ] in
  let has_eliom dir =
    try
      Sys.readdir dir |> Array.to_list
      |> List.exists (fun f -> Filename.check_suffix f ".eliom")
    with _ -> false
  in
  match List.find_opt has_eliom candidates with
  | Some d -> d
  | None -> ".."

let () =
  let src_dir = find_source_dir () in
  Sys.readdir src_dir
  |> Array.to_list |> List.sort compare
  |> List.filter (fun nm -> nm.[0] <> '.')
  |> List.iter handle_file_client
