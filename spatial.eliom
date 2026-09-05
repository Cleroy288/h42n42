[%%client
open Types

(* File Header: spatial.eliom
   @algorithm: Spatial Hash Grid Partitioning
   The board area (1000x700 px) is partitioned into a uniform 2D grid.
   Cell dimensions are defined as exactly cell_size = base_diam * berserk_max = 160.0 px.
   Because no creature can ever exceed this maximum diameter, any pair of colliding creatures
   must reside either within the identical cell or across directly adjacent neighboring cells.
   Consequently, checking collisions for creature C requires inspecting only the 9 surrounding cells
   (3x3 window around C's cell key), reducing algorithmic time complexity from O(n^2) to O(k * n),
   where k is the local creature density per cell.
   @structures: grid_table
   @functions: key_for_creet, remove_from_grid, update_grid, clear_grid, query_neighbors, find_nearest_healthy *)

let cell_size : float = Config.base_diam *. Config.berserk_max

let spatial_grid : (int * int, creet list ref) Hashtbl.t = Hashtbl.create 64

(* ** key_for_creet **
   Determines 2D integer cell coordinates for a creature based on its center.
   @param c: creature to position in the spatial grid
   @res 1: integer tuple (cell_x, cell_y)
   @edge cases: floor division accommodates boundary values
   @error conditions: none *)
let key_for_creet (c : creet) : int * int =
  let (cx, cy) : float * float = center c in
  let cell_x : int = int_of_float (floor (cx /. cell_size)) in
  let cell_y : int = int_of_float (floor (cy /. cell_size)) in
  (cell_x, cell_y)

(* ** remove_from_grid **
   Detaches a creature from its currently registered grid cell.
   @param c: creature to deregister
   @res 1: unit confirming removal
   @edge cases: handles creature with None cell safely
   @error conditions: none *)
let remove_from_grid (c : creet) : unit =
  (match c.cell with
  | None -> ()
  | Some old_key ->
      let bucket_opt : creet list ref option = Hashtbl.find_opt spatial_grid old_key in
      (match bucket_opt with
      | None -> ()
      | Some bucket ->
          bucket := List.filter (fun (item : creet) -> item.id <> c.id) !bucket);
      c.cell <- None)

(* ** update_grid **
   Updates creature grid registration whenever it moves to a new cell.
   @param c: creature whose position changed
   @res 1: unit confirming grid synchronization
   @edge cases: skips re-hashing if creature remains in identical cell
   @error conditions: none *)
let update_grid (c : creet) : unit =
  let new_key : int * int = key_for_creet c in
  let needs_update : bool =
    match c.cell with
    | Some k when k = new_key -> false
    | _ -> true
  in
  if needs_update then begin
    remove_from_grid c;
    let bucket : creet list ref =
      match Hashtbl.find_opt spatial_grid new_key with
      | Some b -> b
      | None ->
          let new_bucket : creet list ref = ref [] in
          Hashtbl.add spatial_grid new_key new_bucket;
          new_bucket
    in
    bucket := c :: !bucket;
    c.cell <- Some new_key
  end

(* ** clear_grid **
   Clears all spatial grid buckets and releases memory upon reset.
   @res 1: unit confirming hash table clearance
   @edge cases: invoked when resetting world state
   @error conditions: none *)
let clear_grid () : unit =
  Hashtbl.clear spatial_grid

(* ** query_neighbors **
   Retrieves potential collision candidates using spatial grid or naive scan.
   @param c: subject creature seeking nearby neighbors
   @res 1: list of neighboring creatures eligible for collision
   @edge cases: toggles dynamically between O(k) grid and O(n) naive mode
   @error conditions: none *)
let query_neighbors (c : creet) : creet list =
  if not !Config.optimized_collision then
    (* Naive O(n) fallback: scan all living creatures *)
    List.filter (fun (o : creet) -> o.alive && o.id <> c.id) active_world.creets
  else begin
    (* Optimized O(k) grid: inspect 3x3 surrounding cells *)
    let (cx, cy) : int * int = key_for_creet c in
    let candidate_acc : creet list ref = ref [] in
    for dx = -1 to 1 do
      for dy = -1 to 1 do
        let target_key : int * int = (cx + dx, cy + dy) in
        match Hashtbl.find_opt spatial_grid target_key with
        | None -> ()
        | Some bucket ->
            List.iter
              (fun (neighbor : creet) ->
                if neighbor.alive && neighbor.id <> c.id then
                  candidate_acc := neighbor :: !candidate_acc)
              !bucket
      done
    done;
    !candidate_acc
  end

(* ** find_nearest_healthy **
   Locates the closest healthy creature to a mean predator creature.
   @param predator: mean creature hunting healthy targets
   @res 1: optional closest healthy creet, or None if none exist
   @edge cases: returns None if all healthy creatures are extinct
   @error conditions: none *)
let find_nearest_healthy (predator : creet) : creet option =
  let (px, py) : float * float = center predator in
  let best_creet : creet option ref = ref None in
  let min_dist_sq : float ref = ref infinity in
  List.iter
    (fun (target : creet) ->
      if target.alive && target.state = Healthy then begin
        let (tx, ty) : float * float = center target in
        let dx : float = px -. tx in
        let dy : float = py -. ty in
        let dist_sq : float = (dx *. dx) +. (dy *. dy) in
        if dist_sq < !min_dist_sq then begin
          min_dist_sq := dist_sq;
          best_creet := Some target
        end
      end)
    active_world.creets;
  !best_creet
]
