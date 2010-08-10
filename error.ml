open Utils


let err x = output_string stderr x ; output_string stderr "\n"
let pos x = err (Pos.string x)

let lexing_error lb = 
  err (Pos.string (Pos.make lb)) ;
  err "Error: Lexing error\n" ;
  exit 1

let syntax_error lb = 
  err (Pos.string (Pos.make lb)) ;
  err "Error: Syntax error\n" ;
  exit 2

let multiple_module_def pos1 pos2 = 
  pos pos1 ;
  err "Error: module has multiple definitions" ;
  err "Was previously defined here:" ;
  pos pos2 ;
  exit 3

let unbound_name p id = 
  pos p ;
  err ("Error: Unbound name "^id) ;
  exit 4

let multiple_def p id = 
  pos p ;
  err ("Error: "^id^" defined multiple times") ;
  exit 5

let type_arity_mismatch p1 p2 (_, id) n1 n2 = 
  pos p1 ;
  err ("Error: trying to apply "^ string_of_int n2^
       " arguments to "^ id) ;
  pos p2 ;
  err (id^" was declared with "^string_of_int n1^
       " arguments") ;
  exit 6

let application_to_primitive_type p id = 
  pos p ;
  err ("Error: "^id^" is a primitive type without arguments") ;
  exit 7

let expected_function p = 
  pos p ;
  err ("Expected Function") ;
  exit 8

let undefined_sig p v = 
  pos p ;
  err ("Value "^v^" has no definition") ;
  exit 9

let cycle kind p id rl = 
  let id = Ident.to_string id in
  pos p ;
  err ("The "^kind^" "^id^" is cyclic\n") ;
  err ("Through this path:") ;
  List.iter (fun (p, _) -> pos p) rl ;
  exit 10

let cycle kind pl =
  match pl with
  | [] -> assert false
  | (p, id) :: rl -> cycle kind p id rl

let type_expects_arguments (p, x) n pdef = 
  let x = Ident.to_string x in
  let n = string_of_int n in
  pos p ;
  err ("The type "^x^" expects "^n^" arguments") ;
  err ("Its definition is given here: ") ;
  pos pdef

let not_expecting_arguments px x pdef = 
  let x = Ident.to_string x in
  pos px ;
  err ("The type "^x^" doesn't expect any arguments") ;
  err ("Its definition is given here") ;
  pos pdef ;
  exit 2

let type_arity px x size1 size2 pdef = 
  let x = Ident.to_string x in
  let size1 = string_of_int size1 in
  let size2 = string_of_int size2 in
  pos px ;
  err ("The type "^x^" expects "^size2^" arguments not "^size1) ;
  err ("Its definition is given here") ;
  pos pdef ;
  exit 2


let pbar_arity p1 n1 p2 n2 =
  let n1 = string_of_int n1 in
  let n2 = string_of_int n2 in
  pos p1 ;
  err ("This pattern matches a tuple of "^n1^" element(s)") ;
  pos p2 ;
  err ("While this one has "^n2^" element(s)") ;
  err ("They should have the same arity") ;
  exit 2

let no_tuple p =
  pos p ;
  err "Wasn't expecting a tuple" ;
  exit 2

let no_tuple_for_type_app p px =
  pos px ;
  err ("This type is not an abbreviation") ;
  pos p ;
  err "You cannot pass a tuple as argument" ;
  exit 2

let tuple_too_big p = 
  pos p ;
  err "This tuple has more than 100 elements, use a record instead" ;
  exit 2

let not_pointer_type p_id p = 
  pos p ;
  err "This type is not a pointer" ;
  pos p_id ;
  err "It can only be applied to a type defined in the same module" ;
  exit 2


let infinite_loop p = 
  pos p ;
  err "This function call probably doesn't terminate" ;
  exit 2

let arity p1 p2 = 
  pos p1 ;
  err "Arity" ;
  pos p2 ;
  exit 2

let unused p = 
  pos p ;
  err "Unused" ;
  exit 2

let unify p1 p2 = 
  pos p1 ;
  err "This expression must have the same type as" ;
  pos p2 ;
  err "this expression" ;
  exit 2

let expected_numeric p =
  pos p ;
  err "Expected a numeric type" ;
  exit 2

let expected_function p = 
  pos p ;
  err ("Expected Function") ;
  exit 8


let recursive_type p =
  pos p ;
  err ("Recursive type") ;
  exit 8

let expected_bool p =
  pos p ;
  err "Expected bool" ;
  exit 2

let unused_branch p = 
  pos p ;
  err "This branch is unused" ;
  exit 2

let missing_fields p s = 
  pos p ;
  err "Some fields are missing" ;
  err s ;
  exit 2

let forgot_fields p l =
  pos p ;
  err "Some fields are missing" ;
  List.iter (Printf.fprintf stderr "%s\n") l ;
  exit 2

let useless p = 
  pos p ;
  err "All the fields are already captured" ;
  exit 2

let not_exhaustive p f = 
  pos p ;
  err "This pattern-matching is not exhaustive" ;
  err "Here is an example of a value that is not matched: " ;
  f stderr ;
  exit 2

let not_exhaustive_no_example p = 
  pos p ;
  err "This pattern-matching is not exhaustive" ;
  exit 2

let pat_too_general p f = 
  pos p ;
  err "This pattern is too general" ;
  err "It captures the case: " ;
  f stderr ;
  err "Which has been captured already" ;
  exit 2
  
