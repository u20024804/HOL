signature constrFamiliesLib =
sig
  include Abbrev


  (**********************)
  (* Constructors       *)
  (**********************)

  (* A constructor is a combination of a term with
     a list of names for all it's arguments *)
  type constructor 

  (* [mk_constructor c arg_names] generate a constructor [c]
     with argument names [arg_names] *)
  val mk_constructor : term -> string list -> constructor

  (* check whether a constructor has no arguments *)
  val constructor_is_const : constructor -> bool

  (* [mk_constructor_term vs constr] construct a term 
     corresponding to [constr]. For the arguments
     variables are generated. These variables are
     distinct from the ones provided in the argument [vs].
     The resulting term as well the used argument vars are
     returned. *)
  val mk_constructor_term : term list -> constructor -> (term * term list)

  (* We usually consider lists of constructors. It is an abstract
     type that should only be used via [make_constructorList]. *)
  type constructorList

  (* [mk_constructorList exh constrs] makes a new constructorList.
     [exh] states whether the list is exhaustive, i.e. wether all values
     of the type can be constructed  via a constructor in this list *)
  val mk_constructorList : bool -> constructor list -> constructorList


  (************************)
  (* Constructor Families *)
  (************************)

  (* a constructor family is a list of constructors,
     a case-split function and various theorems *)
  type constructorFamily

  (* Get the rewrites stored in a constructor family, these
     are theorems that use that all constructors are distinct
     to each other and injective. *)
  val constructorFamily_get_rewrites : constructorFamily -> thm

  (* Get the case-split theorem for the family. *)
  val constructorFamily_get_case_split : constructorFamily -> thm

  (* If the constructor family is exhaustive, a theorem stating
     this exhaustiveness. *)
  val constructorFamily_get_nchotomy_thm_opt : constructorFamily -> thm option


  (* [mk_constructorFamily (constrL, case_split_tm, tac)]
     make a new constructor family. It consists of the constructors
     [constrL], the case split constant [case_split_tm]. The
     resulting proof obligations are proofed by tactic [tac]. *)
  val mk_constructorFamily : constructorList * term * tactic -> constructorFamily

  (* [get_constructorFamily_proofObligations] returns the
     proof obligations that occur when creating a new constructor family 
     via [mk_constructorFamily]. *) 
  val get_constructorFamily_proofObligations : constructorList * term -> term

  (* [set_constructorFamily] sets the proof obligations that occur when
     ruung [mk_constructorFamily] using goalStack. *)
  val set_constructorFamily : constructorList * term -> Manager.proofs

  (* [constructorFamily_of_typebase ty] extracts the constructor family
     for the given type [ty] from typebase. *)
  val constructorFamily_of_typebase : hol_type -> constructorFamily
 

  (************************)
  (* Compile DBs          *)
  (************************)

  (* A compile database combines constructor families,
     an ssfrag and arbitrary compilation funs. *) 
     

  (* A compilation fun gets a column, i.e. a list of
     terms together with a list of free variables in this term.
     For this column a expansion theorem of the form
     ``!ff x. ff x = ...``
     and an ssfrag should be returned. *)
  type pmatch_compile_fun = (term list * term) list -> (thm * simpLib.ssfrag) option

  (* A database for pattern compilation *)
  type pmatch_compile_db = {
    pcdb_compile_funs  : pmatch_compile_fun list,
    pcdb_constrFams    : (constructorFamily list) TypeNet.typenet,
    pcdb_ss            : simpLib.ssfrag
  }

  (* empty db *)
  val empty : pmatch_compile_db 

  (* a default db implemented as a reference *)
  val thePmatchCompileDB : pmatch_compile_db ref

  (* A database represents essentially a compile fun. 
     This functions combines all the contents of a db to
     turn it into a compile fun. *)
  val pmatch_compile_db_compile : pmatch_compile_db -> pmatch_compile_fun

  (* add a compile fun to a db *)
  val pmatch_compile_db_add_compile_fun :
     pmatch_compile_db -> pmatch_compile_fun -> pmatch_compile_db

  (* add a constructorFamily to a db *)
  val pmatch_compile_db_add_constrFam :
     pmatch_compile_db -> constructorFamily -> pmatch_compile_db

  (* add a ssfrag to a db *)
  val pmatch_compile_db_add_ssfrag :
     pmatch_compile_db -> simpLib.ssfrag -> pmatch_compile_db

  (* add a compile_fun to default db *)
  val pmatch_compile_db_register_compile_fun : pmatch_compile_fun -> unit
  (* add a constructor family to default db *)
  val pmatch_compile_db_register_constrFam : constructorFamily -> unit

  (* add a ssfrag to default db *)
  val pmatch_compile_db_register_ssfrag : simpLib.ssfrag -> unit


  (************************)
  (* Compile Funs         *)
  (************************)
  
  (* Compilation fun that turns a column of literals into
     a large if-then-else case distinction. It is
     present automatically in the default db. *)
  val literals_compile_fun : pmatch_compile_fun

end
