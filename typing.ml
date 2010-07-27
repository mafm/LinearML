open Utils
open Neast

exception Unify of Pos.t * Pos.t

let o s = output_string stdout s ; print_newline() ; flush stdout

module Debug = struct
  open Tast

  let id o (_, x) = o (Ident.debug x)

  let rec type_expr o (_, ty) = type_expr_ o ty
  and type_expr_ o ty = 
    let k = type_expr o in
    match ty with
    | Tdef l -> 
	let l = ISet.fold (fun x y -> x :: y) l [] in
	o "Tdef(" ; List.iter (fun x -> o (Ident.debug x) ; o " ") l ; o ")"
    | Tundef _ -> o "Tundef"
    | Tany -> o "Tany"
    | Tprim v -> value o v
    | Tvar x -> o "Tvar" ; o "(" ;  id o x ; o ")"
    | Tid x -> o "Tid" ; o "(" ;  id o x ; o ")"
    | Tapply (ty, tyl) -> o "Tapply" ; o "(" ;  id o ty ; o "," ; list o tyl; o ")"
    | Tfun (ty1, ty2) -> o "Tfun" ; o "(" ;  list o ty1 ; o "->" ; list o ty2; o ")"
    | Talgebric vl -> o "Talgebric" ; o "[" ; imiter (variant o) vl ; o "]"
    | Trecord fdl -> o "Trecord" ; o "{" ;  imiter (field o) fdl; o "}"
    | Tabs (idl, ty) -> o "Tabs" ; o "(" ; tvar o idl ; o ": " ; k ty; o ")"
(*    | Tdecl x -> o "Tdecl" ; o "(" ; id o x ; o ")" *)

  and tvar o = function
    | [] -> assert false
    | [x] -> id o x
    | x :: rl -> id o x ; o "," ; tvar o rl

  and list o (_, x) = list_ o x
  and list_ o = function
    | [] -> assert false
    | [x] -> type_expr o x
    | x :: rl -> type_expr o x ; o "," ; list_ o rl

  and variant o (x, y) = 
    id o x ; o " of " ; 
    list o y ;
    o "|"

  and value o = function
  | Tunit -> o "Tunit"
  | Tbool -> o "Tbool"
  | Tchar -> o "Tchar"
  | Tint32 -> o "Tint32"
  | Tfloat -> o "Tfloat"

  and field o (x, y) = id o x ; o ":" ; list o y ; o ";"

  let o = output_string stdout
  let nl o = o "\n"
  let type_expr ty = type_expr o ty ; nl o
  let type_expr_list ty = list o ty ; nl o

end


module FreeVars = struct

  let rec type_expr t (_, ty) = type_expr_ t ty

  and type_expr_ t = function
    | Tundef _
    | Tany
    | Tprim _ 
    | Tid _ -> t
    | Tvar (_, x) -> ISet.add x t

    | Tapply (_, (_, tyl)) -> 
	List.fold_left type_expr t tyl

    | Tfun ((_, tyl1), (_, tyl2)) -> 
	let t = List.fold_left type_expr t tyl1 in
	List.fold_left type_expr t tyl2

    | Tdef _
    | Talgebric _ 
    | Trecord _ 
    | Tabs _ -> assert false

end

module Env = struct

  let rec make mdl = 
    let env = List.fold_left module_ IMap.empty mdl in
    env

  and module_ env md = 
    List.fold_left decl env md.md_decls 

  and decl env = function
    | Dtype tdl -> List.fold_left type_expr env tdl
    | Dval ((p, x), tyl1, tyl2) -> IMap.add x (p, Tfun (tyl1, tyl2)) env

  and type_expr env ((_, x) as tid, ((_, ty_) as ty)) = 
    match ty_ with
    | Trecord vm 
    | Talgebric vm -> algebric env [] tid vm
    | Tabs (pl, (_, Talgebric vm)) 
    | Tabs (pl, (_, Trecord vm)) -> algebric env pl tid vm
    | _ -> IMap.add x ty env

  and algebric env pl tid vm =
    IMap.fold (variant pl tid) vm env

  and variant pl tid _ ((p, x), tyl) env = 
    match pl with
    | [] -> IMap.add x (p, Tfun (tyl, (fst tid, [fst tid, Tid tid]))) env
    | _ -> 
	let fvs = List.fold_left FreeVars.type_expr ISet.empty (snd tyl) in
	let argl = List.map (tvar fvs) pl in
	let argl = p, argl in
	let v_ty = p, Tfun (tyl, (fst tid, [p, Tapply (tid, argl)])) in
	IMap.add x v_ty env

  and tvar fvs ((p, x) as id) =
    p, if ISet.mem x fvs 
    then Tvar id
    else Tany
end
open Neast

module TMap = Map.Make (CompareType)

type env = {
    tenv: type_expr IMap.t ;
    defs: def IMap.t ;
  }

type acc = {
    fcall: type_expr_list IMap.t ;
    mem: type_expr_list TMap.t ;
  }

let rec tundef (_, tyl) = tundef_ tyl
and tundef_ tyl = 
  match tyl with
  | [] -> false
  | (_, Tundef _) :: _ -> true
  | (_, Tapply (_, l)) :: rl -> tundef l || tundef_ rl
  | _ :: rl -> tundef_ rl

let add_used ((_, x), _) _ acc =
  ISet.add x acc

let check_used uset (id, _, _) = 
  if not (ISet.mem (snd id) uset) 
  then Error.unused (fst id) 
  else ()

let filter_undef x rty (acc1, acc2) = 
  if tundef rty
  then x :: acc1, acc2
  else acc1, TMap.add x rty acc2

let rec program mdl = 
  let tenv = Env.make mdl in
  List.map (module_ tenv) mdl
  
and module_ tenv md = 
  let env = { tenv = tenv ; defs = IMap.empty } in
  let env = List.fold_left def env md.md_defs in
  let acc = { fcall = IMap.empty ; mem = TMap.empty } in
  let acc = List.fold_left (decl env) acc md.md_decls in
  o "phase1" ;
  let used = TMap.fold add_used acc.mem ISet.empty in
  List.iter (check_used used) md.md_defs ;
  let undef_l, mem = TMap.fold filter_undef acc.mem ([], TMap.empty) in 
  let acc = { fcall = IMap.empty ; mem = mem } in
  let acc = List.fold_left (retype env) acc undef_l in
  o "phase2" ;
  (* Re-type all with function calls solved *)
  let acc = List.fold_left (decl env) acc md.md_decls in
  (* Remember: it doesn't mean it's well typed at this point *)
  o "phase3" ;
  acc

and def env (((p, x), al, b) as d) = 
  let tenv = IMap.add x (p, Tdef (ISet.singleton x)) env.tenv in
  let defs = IMap.add x d env.defs in
  { tenv = tenv ; defs = defs }

and retype env acc (fid, ty) = 
  let p = fst fid in
  let acc, (p, rty) = apply env acc p fid ty in
  acc

and decl env acc = function
  | Dtype _ -> acc
  | Dval (fid, tyl, rty) ->
      let p = fst fid in
      let acc, rty = apply_def env acc p fid tyl rty in
      o (Ident.debug (snd fid)) ;
      Debug.type_expr_list rty ;
      { acc with fcall = IMap.empty }

and pat env (p, pl) (p2, tyl) = 
  match pl with
  | [_,l] -> 
      (try List.fold_right2 pat_el l tyl env
      with Invalid_argument _ -> 
	let p2, _ = Pos.list tyl in
	Error.arity p p2
      )
  | _ -> failwith "TODO pat"

and pat_el (_, p) ty env = 
  match p with
  | Pany -> env
  | Pid (_, x) -> IMap.add x ty env 
  | _ -> failwith "TODO pat"
(*  | Pvalue of value
  | Pvariant of id * pat
  | Precord of pat_field list *)

and expr_list env acc (p, el) = 
  let acc, tyl = expr_list_ env acc el in
  acc, (p, tyl)

and expr_list_ env acc el =
  match el with
  | [] -> acc, []
  | (p, Eapply (x, el)) :: rl ->
      let acc, rl = expr_list_ env acc rl in
      let acc, tyl = expr_list env acc el in
      let acc, rty = apply env acc p x tyl in
      acc, snd rty @ rl

  | (_, Eif (e1, el1, el2)) :: rl -> 
      let acc, rl = expr_list_ env acc rl in
      let acc, _ = expr env acc e1 in (* TODO check bool *)
      let acc, tyl1 = expr_list env acc el1 in
      let acc, tyl2 = expr_list env acc el2 in     
      let acc, tyl = unify_list env acc tyl1 tyl2 in
      acc, snd tyl @ rl

  | (_, Elet (argl, e1, e2)) :: rl -> 
      let acc, rl = expr_list_ env acc rl in
      let acc, tyl = expr_list env acc e1 in
      let env = { env with tenv = pat env.tenv argl tyl } in 
      let acc, tyl = expr_list env acc e2 in
      acc, (snd tyl) @ rl

  | (_, Efield (e, (_, x))) :: rl -> 
      let acc, rl = expr_list_ env acc rl in
      let acc, rectype = expr env acc e in
      let fdtype = IMap.find x env.tenv in 
      let acc, tyl = proj env acc rectype fdtype in
      acc, (snd tyl) @ rl

  | e :: rl ->
      let acc, tyl = expr_list_ env acc rl in
      let acc, ty = expr_ env acc e in
      acc, ty :: tyl

and expr env acc ((p, _) as e) = 
  let acc, el = expr_list env acc (p, [e]) in
  match snd el with
  | [] -> assert false
  | [x] -> acc, x
  | _ -> Error.no_tuple p

and expr_ env acc (p, e) =
  match e with

  | Eid (_, x) -> acc, (p, snd (IMap.find x env.tenv))
  | Evalue v -> acc, (p, Tprim (value v))
  | Evariant (x, el) -> variant env acc (x, el)

  | Ebinop (Ast.Eseq, ((p, _) as e1), e2) -> 
      let acc, ty1 = expr env acc e1 in
      let acc, ty1 = unify_el env acc ty1 (p, Tprim Tunit) in
      expr env acc e2

  | Ebinop (bop, e1, e2) -> 
      let acc, ty1 = expr env acc e1 in
      let acc, ty2 = expr env acc e2 in
      let acc, _ = unify_el env acc ty1 ty2 in
      let acc, ty = binop env acc bop p ty1 ty2 in
      acc, ty

  | Euop (Ast.Euminus, e) -> expr env acc e

  | Erecord fdl -> 
      let acc, fdl = lfold (variant env) acc fdl in
      List.fold_left 
	(fun (acc, rty) ty -> 
	  unify_el env acc rty ty) 
	(acc, (p, Tany))
	fdl

  | _ -> failwith "TODO expr"

(* 
  | Ematch of expr list * (pat * expr list) list
 *)

and variant env acc (x, el) = 
  let p = Pos.btw (fst x) (fst el) in
  let acc, tyl = expr_list env acc el in
  let acc, rty = apply env acc p x tyl in
  match rty with 
  | _, [x] -> acc, x 
  | _ -> assert false

and proj env acc ty fty = 
  match ty, fty with
  | (_, Tapply ((_, x1), argl1)), (_, Tfun (ty, (_, [_, Tapply ((_, x2), argl2)]))) ->
      if x1 <> x2
      then failwith "TODO proj" ;
      let acc, subst = instantiate_list env acc IMap.empty argl2 argl1 in
      replace_list subst env acc ty
  | _ -> failwith "TODO proj"

and binop env acc bop p ty1 ty2 = 
  match bop with
  | Ast.Eeq 
  | Ast.Elt
  | Ast.Elte
  | Ast.Egt
  | Ast.Egte -> acc, (p, Tprim Tbool)
  | Ast.Eplus
  | Ast.Eminus
  | Ast.Estar -> unify_el env acc ty1 ty2
  | Ast.Eseq -> assert false
  | Ast.Ederef -> assert false

and value = function
  | Nast.Eunit -> Tunit
  | Nast.Ebool _ -> Tbool
  | Nast.Eint _ -> Tint32
  | Nast.Efloat _ -> Tfloat
  | Nast.Echar _ -> Tchar
  | Nast.Estring _ -> assert false

and unify_list env acc ((p1, tyl1) as l1) ((p2, tyl2) as l2) = 
  if tundef l1
  then acc, l2
  else if tundef l2
  then acc, l1
  else if List.length tyl1 <> List.length tyl2
  then Error.arity p1 p2
  else try 
    let acc, tyl = lfold2 (unify_el env) acc tyl1 tyl2 in
    acc, (p1, tyl)
  with Unify (ep1, ep2) ->
    Error.pos p1 ;
    Error.pos p2 ;
    Error.pos ep1 ;
    Error.pos ep2 ;
    exit 2
  
and unify_el env acc ty1 ty2 = 
  match ty1, ty2 with
  | (p, Tdef ids), (_, Tfun (tyl, rty))
  | (_, Tfun (tyl, rty)), (p, Tdef ids) ->
      (* TODO not sure about the position *)
      let idl = ISet.fold (fun x acc -> (p, x) :: acc) ids [] in
      let acc, rty = apply_def_list env acc p idl tyl rty in
      acc, (p, Tfun (tyl, rty))

  | (p, Tapply ((_, x) as id, tyl1)), (_, Tapply ((_, y), tyl2)) when x = y -> 
      let acc, tyl = unify_list env acc tyl1 tyl2 in 
      acc, (p, Tapply (id, tyl))

  | (p, Tfun (tyl1, tyl2)), (_, Tfun (tyl3, tyl4)) ->
      let acc, tyl1 = unify_list env acc tyl1 tyl3 in
      let acc, tyl2 = unify_list env acc tyl2 tyl4 in
      acc, (p, Tfun (tyl1, tyl2))
     
  | (p, _), _ -> 
      let ty = unify_el_ env acc ty1 ty2 in
      acc, (p, ty)

and unify_el_ env acc (p1, ty1) (p2, ty2) =
  match ty1, ty2 with
  | Tundef, Tundef -> Tundef
  | Tundef, ty
  | ty, Tundef -> ty
  | Tany, ty 
  | ty, Tany -> ty
  | Tprim x, Tprim y when x = y -> ty1
  | Tvar (_, x), Tvar (_, y) when x = y -> ty1
  | Tid x, Tid y when x = y -> ty1
  | Tdef s1, Tdef s2 -> Tdef (ISet.union s1 s2)
  | Talgebric _, _ | _, Talgebric _
  | Trecord _, _ | _, Trecord _
  | Tabs _, _ | _, Tabs _ -> assert false
  | _ -> raise (Unify (p1, p2))

and apply env acc p ((fp, x) as fid) tyl = 
  match IMap.find x env.tenv with
  | (_, Tfun (tyl1, tyl2)) -> 
      if IMap.mem x acc.fcall
      then begin 
	let prev_tyl = IMap.find x acc.fcall in
	let acc, tyl = unify_list env acc tyl prev_tyl in
	acc, TMap.find (fid, prev_tyl) acc.mem
      end
      else begin
	let acc, subst = instantiate_list env acc IMap.empty tyl1 tyl in
	let acc, rty = replace_list subst env acc tyl2 in
	let fcall = IMap.add x tyl acc.fcall in
	let mem = TMap.add (fid, tyl) rty acc.mem in
	let acc = { fcall = fcall ; mem = mem } in
	acc, rty
      end

  | (_, Tdef ids) -> 
      let rty = p, [p, Tundef] in
      let idl = ISet.fold (fun x acc -> (p, x) :: acc) ids [] in
      apply_def_list env acc p idl tyl rty

  | p2, _ -> Error.expected_function_not fp p2

and apply_def_list env acc p idl tyl rty = 
  List.fold_left 
    (fun (acc, rty) fid -> 
      apply_def env acc p fid tyl rty) 
    (acc, rty) 
    idl
    
and apply_def env acc p fid tyl rty = 
  try acc, TMap.find (fid, tyl) acc.mem
  with Not_found -> 
    let undef = p, [p, Tundef] in (* TODO better pos *)
    let acc = { acc with mem = TMap.add (fid, tyl) undef acc.mem } in
    let (_, argl, el) = IMap.find (snd fid) env.defs in
    let env = { env with tenv = pat env.tenv argl tyl } in 
    let acc, new_rty = expr_list env acc el in
    let acc = { acc with mem = TMap.add (fid, tyl) new_rty acc.mem } in
    unify_list env acc new_rty rty

and instantiate_list env acc subst (p1, tyl1) (p2, tyl2) = 
  if List.length tyl1 <> List.length tyl2
  then Error.arity p1 p2
  else List.fold_left2 (instantiate env) (acc, subst) tyl1 tyl2
            
and instantiate env (acc, subst) (p2, ty1) (p, ty2) = 
  match ty1, ty2 with
  | (Tany | Tundef), _
  | _, (Tany | Tundef) -> acc, subst
  | Tprim ty1, Tprim ty2 when ty1 = ty2 -> acc, subst
  | Tvar (_, x), _ -> 
      (try instantiate env (acc, subst) (IMap.find x subst) (p, ty2)
      with Not_found -> acc, IMap.add x (p, ty2) subst)
  | Tapply ((_, x), tyl1), Tapply ((_, y), tyl2) when x = y ->
      instantiate_list env acc subst tyl1 tyl2

  | Tfun (tyl, rty1), Tdef ids ->
      let idl = ISet.fold (fun x acc -> (p, x) :: acc) ids [] in
      let rty = p, [p, Tundef] in
      let acc, rty2 = apply_def_list env acc p idl tyl rty in
      instantiate_list env acc subst rty1 rty2

  | Tdef _, _ -> assert false
  | Tfun (tyl1, tyl3), Tfun (tyl2, tyl4) ->
      let acc, subst = instantiate_list env acc subst tyl1 tyl2 in
      let acc, subst = instantiate_list env acc subst tyl3 tyl4 in
      acc, subst

  | Talgebric _, _ | _, Talgebric _ -> assert false
  | Trecord _, _ | _, Trecord _ -> assert false
  | Tabs _, _ | _, Tabs _ -> assert false
  | ty1, ty2 -> 
      o "Instantiate\n" ;
      Debug.type_expr (p2, ty1) ;
      Debug.type_expr (p2, ty2) ;
      Error.unify p2 p

and replace subst env acc (p, ty) = 
  match ty with
  | Tundef _ as x -> acc, (p, x)
  | Tvar (p, x) -> 
      (try 
	let ty = IMap.find x subst in
	(match ty with
	| _, Tvar (_, y) when x = y -> acc, ty
	| _ -> 
	    if ISet.mem x (FreeVars.type_expr ISet.empty ty)
	    then assert false (* TODO get rid of this *)
	    else replace subst env acc ty)
      with Not_found -> acc, (p, Tvar (p, x)))
  | Tapply (x, (p, tyl)) -> 
      let acc, tyl = lfold (replace subst env) acc tyl in
      let tyl = p, tyl in
      acc, (p, Tapply (x, tyl))

  | Tfun (tyl1, tyl2) -> 
      let acc, tyl1 = replace_list subst env acc tyl1 in
      let acc, tyl2 = replace_list subst env acc tyl2 in
      acc, (p, Tfun (tyl1, tyl2))

  | Tabs (l, ty) -> 
      let acc, ty = replace subst env acc ty in
      acc, (p, Tabs (l, ty) )
  | Talgebric _ 
  | Trecord _ -> assert false
  | _ -> acc, (p, ty)

and replace_list subst env acc (p, tyl) = 
  let acc, tyl = lfold (replace subst env) acc tyl in
  let tyl = p, tyl in
  acc, tyl
