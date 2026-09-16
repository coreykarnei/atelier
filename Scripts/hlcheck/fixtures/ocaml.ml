(* Dense OCaml fixture for the highlight harness. *)
(** Doc comment: the [Geometry] module and friends. *)

open Printf
include Stdlib.List
module M = Map.Make (String)
module type SHAPE = sig
  val area : float -> float
end

[@@@warning "-32"]

type kind = Circle | Square of int | Tagged of { tag : string; weight : float }
type 'a tree = Leaf | Node of 'a tree * 'a * 'a tree
type point = { x : float; mutable y : float; label : string option } [@@deriving show]
type shape = [ `Circle of float | `Rect of float * float ]

exception Bad_shape of string

external c_sqrt : float -> float = "caml_sqrt_float"

let pi = 3.14159
let big = 1_000_000
let hex = 0xFF and bin = 0b1010 and oct = 0o17
let neg = -42
let sci = 6.02e23
let flag = true and other = false
let ch = 'a' and nl = '\n'
let greeting = "hello\t\"world\"\n"
let quoted = {|raw "quoted" string|}
let tagged = {js|alert("hi")|js}
let fmt () = printf "%d items at %.2f%%\n" 3 99.5
let unit_val = ()
let one = 1. and e3 = 2e3 and hexf = 0x1p-3
let labeled = add ~x:1 ~y:2 ?scale:(Some 3)
let out = stdout
let ( +: ) a b = a + b
let wild = match lst with _ -> ()

let rec factorial n = if n <= 1 then 1 else n * factorial (n - 1)

let add ?(scale = 1) ~x ~y = (x + y) * scale

let area ~(radius : float) : float = pi *. radius *. radius

let describe = function
  | Circle -> "circle"
  | Square n when n > 10 -> sprintf "big square %d" n
  | Square _ -> "square"
  | Tagged { tag; weight = _ } -> tag

let classify = fun k -> match k with
  | Circle | Square _ -> `Simple
  | Tagged _ -> `Complex

let point = { x = 1.0; y = 2.0; label = Some "origin" }
let () = point.y <- point.y +. 1.0
let px = point.x

let loop () =
  for i = 0 to 9 do
    print_int i
  done;
  for j = 9 downto 0 do ignore j done;
  while false do () done

let safe_div a b =
  try
    if b = 0 then raise (Bad_shape "zero") else a / b
  with
  | Bad_shape msg -> failwith msg
  | Division_by_zero -> invalid_arg "div"

let piped = [ 1; 2; 3 ] |> List.map (fun v -> v * 2) |> List.length
let applied = print_endline @@ string_of_int piped
let arr = [| 1; 2 |]
let first = arr.(0)
let lst = 1 :: 2 :: []
let concat = "a" ^ "b" and cat_list = [ 1 ] @ [ 2 ]
let cmp = pi >= 3.0 && flag || not other
let r = ref 0
let () = r := !r + 1; incr r
let assigned = r.contents
let lazy_v = lazy (factorial 5)

let ( let* ) o f = match o with Some v -> f v | None -> None
let bound = let* v = Some 1 in Some (v + 1)

class counter init = object (self)
  val mutable count = init
  method get = count
  method incr = count <- count + 1; self#get
  initializer count <- 0
end

class virtual base = object
  inherit counter 0
  method virtual name : string
  method private secret = 1
end

let c = new counter 0
let n = c#get

let assertion = assert (n = 0)
let ext = [%test 1 + 2]
let annotated = (fun x -> x) [@inline]
let typed : int M.t = M.empty
let with_as = match lst with hd :: _ as whole -> List.length whole | [] -> 0
let rng = match ch with 'a' .. 'z' -> true | _ -> false
let localmod = let module L = List in L.rev lst
let begin_end = begin 1 end
let seq = 1; 2
;;
