(* ===================================================================== *)
(* FILE          : Net.sml                                               *)
(* DESCRIPTION   : Implementation of term nets, from the group at ICL.   *)
(*                 Thanks! A term net is a database, keyed by terms.     *)
(*                 Term nets were initially implemented by Larry Paulson *)
(*                 for Cambridge LCF.                                    *)
(*                                                                       *)
(* AUTHOR        : Somebody in the ICL group.                            *)
(* DATE          : August 26, 1991                                       *)
(* MODIFIED      : Sept 5, 1992, to use deBruijn representation          *)
(* Modified      : September 23, 1997, Ken Larsen                        *)
(* Reimplemented : July 17, 1999, Konrad Slind                           *)
(* ===================================================================== *)

structure Net :> Net =
struct

open Lib;

fun ERR function message = 
Exception.HOL_ERR{origin_structure = "Nut",
                  origin_function = function,
                  message = message};

local val dummy = Term.mk_var{Name ="dummy",Ty = Type.mk_vartype"'x"}
      val break_abs_ref = ref (fn _:Term.term => {Bvar=dummy,Body=dummy})
in
  val _ = Term.Net_init break_abs_ref
  val break_abs = !break_abs_ref
end;

type term = Term.term;

(*---------------------------------------------------------------------------*
 *   Tags corresponding to the underlying term constructors.                 *
 *---------------------------------------------------------------------------*)

datatype label = V | Cnst of string | Cmb | Lam;

(*---------------------------------------------------------------------------*
 *    Term nets.                                                             *
 *---------------------------------------------------------------------------*)

datatype 'a net = LEAF of (term * 'a) list
                | NODE of (label * 'a net) list;


val empty = NODE [];

fun is_empty (NODE []) = true 
  | is_empty    _      = false;

(*---------------------------------------------------------------------------*
 * Determining the top constructor of a term. The following is a bit         *
 * convoluted, since doing a dest_abs requires a full traversal to replace   *
 * the bound variable with a free one. Therefore we make a separate checks   *
 * for abstractions.                                                         *
 *---------------------------------------------------------------------------*)

local open Term 
in
fun label_of tm =
   if is_abs tm then Lam else 
   if Term.is_bvar tm then V 
   else case Term.dest_term tm
         of CONST{Name,...} => Cnst Name
          | COMB _ => Cmb
          | VAR  _ => V
          | LAMB _ => raise ERR "label_of" "supposedly inaccessible pattern"
end

fun net_assoc label =
 let fun get (LEAF _) = raise ERR "net_assoc" "LEAF: no children"
       | get (NODE subnets) = 
            case assoc1 label subnets 
             of NONE => empty 
              | SOME (_,net) => net
 in 
     get
 end;


fun match tm net =
 let fun mtch tm net =
      let val label = label_of tm
          val child = net_assoc label net
          val Vnet = net_assoc V net
          val nets = 
            case label
             of V => []
              | Cnst _ => [child] 
              | Lam => mtch (#Body(break_abs tm)) child
              | Cmb => let val {Rator,Rand} = Term.dest_comb tm
                       in itlist(append o mtch Rand)
                                (mtch Rator child) [] end
      in 
         itlist (fn NODE [] => I | net => cons net) nets [Vnet]
      end
 in
   itlist (fn LEAF L => append (map #2 L) | _ => I)
          (mtch tm net) []
 end;

(*---------------------------------------------------------------------------
        Finding the elements mapped by a term in a term net.
 ---------------------------------------------------------------------------*)

fun index x net =
let
 fun appl  _   _  (LEAF L) = SOME L
   | appl defd tm (NODE L) =
     let val label = label_of tm
     in case assoc1 label L
         of NONE => NONE
          | SOME (_,net) => 
             case label
              of Lam => appl defd (#Body (break_abs tm)) net
               | Cmb => let val {Rator,Rand} = Term.dest_comb tm
                        in appl (Rand::defd) Rator net end
               |  _  => let fun exec_defd [] (NODE _) = raise ERR "appl" 
                                 "NODE: should be at a LEAF instead"
                              | exec_defd [] (LEAF L) = SOME L
                              | exec_defd (h::rst) net =  appl rst h net
                        in 
                          exec_defd defd net
                        end 
     end
in
  case appl [] x net
   of SOME L => (map #2 L)
    | NONE   => []
end;

(*---------------------------------------------------------------------------*
 *        Adding to a term net.                                              *
 *---------------------------------------------------------------------------*)

fun overwrite (p as (a,_)) = 
  let fun over [] = [p]
        | over ((q as (x,_))::rst) = 
            if (a=x) then p::rst else q::over rst
  in over 
  end;

fun insert (p as (tm,_)) N = 
let fun enter _ _  (LEAF _) = raise ERR "insert" "LEAF: cannot insert"
   | enter defd tm (NODE subnets) =
      let val label = label_of tm
          val child = 
             case assoc1 label subnets of NONE => empty | SOME (_,net) => net
          val new_child = 
            case label
             of Cmb => let val {Rator,Rand} = Term.dest_comb tm
                       in enter (Rand::defd) Rator child end
              | Lam => enter defd (#Body (break_abs tm)) child
              | _   => let fun exec [] (LEAF L)  = LEAF(p::L)
                             | exec [] (NODE _)  = LEAF[p]
                             | exec (h::rst) net = enter rst h net
                       in 
                          exec defd child 
                       end
      in 
         NODE (overwrite (label,new_child) subnets)
      end
in enter [] tm N
end;


(*---------------------------------------------------------------------------
     Removing an element from a term net. It is not an error if the 
     element is not there.
 ---------------------------------------------------------------------------*)

fun split_assoc P =
 let fun split front [] = raise ERR "split_assoc" "not found"
       | split front (h::t) =
          if P h then (rev front,h,t) else split (h::front) t
 in 
    split []
 end;


fun delete (tm,P) N =
let fun del [] = []
      | del ((p as (x,q))::rst) = 
          if Term.aconv x tm andalso P q then del rst else p::del rst
 fun remv  _   _ (LEAF L) = LEAF(del L)
   | remv defd tm (NODE L) =
     let val label = label_of tm
         fun pred (x,_) = (x=label)
         val (left,(_,childnet),right) = split_assoc pred L
         val childnet' = 
           case label
            of Lam => remv defd (#Body (break_abs tm)) childnet
             | Cmb => let val {Rator,Rand} = Term.dest_comb tm
                      in remv (Rand::defd) Rator childnet end
             |  _  => let fun exec_defd [] (NODE _) = raise ERR "remv" 
                                "NODE: should be at a LEAF instead"
                            | exec_defd [] (LEAF L) = LEAF(del L)
                            | exec_defd (h::rst) net =  remv rst h net
                      in 
                        exec_defd defd childnet
                      end
         val childnetl = 
           case childnet' of NODE [] => [] | LEAF [] => [] | y => [(label,y)]
     in   
       NODE (List.concat [left,childnetl,right])
     end
in
  remv [] tm N handle Exception.HOL_ERR _ => N
end;

fun filter P = 
 let fun filt (LEAF L) = LEAF(List.filter (fn (x,y) => P y) L)
       | filt (NODE L) = 
          NODE (itlist  (fn (l,n) => fn list => 
                 case filt n 
                  of LEAF [] => list
                   | NODE [] => list
                   |   n'    => (l,n')::list) L [])
 in
    filt
 end;

fun listItems0 (LEAF L) = L
  | listItems0 (NODE L) = rev_itlist (append o listItems0 o #2) L [];

fun union net1 net2 = rev_itlist insert (listItems0 net1) net2;

fun listItems net = map #2 (listItems0 net);

fun map f (LEAF L) = LEAF (List.map (fn (x,y) => (x, f y)) L)
  | map f (NODE L) = NODE (List.map (fn (l,net) => (l,map f net)) L);

fun itnet f (LEAF L) b = itlist f (List.map #2 L) b
  | itnet f (NODE L) b = itlist (itnet f) (List.map #2 L) b;

fun size net = itnet (fn x => fn y => y+1) net 0;


(*---------------------------------------------------------------------------
                Compatibility mode.
 ---------------------------------------------------------------------------*)

fun get_tip_list (LEAF L) = L
  | get_tip_list (NODE _) = [];

fun get_edge label =
   let fun get (NODE edges) = 
              (case (Lib.assoc1 label edges)
                 of SOME (_,net) => net
                  | NONE => empty)
         | get (LEAF _) = raise ERR "get_edge" "tips have no edges"
   in get
   end;

fun net_update elem =
let fun update _ _ (LEAF _) = raise ERR "net_update" "cannot update a tip"
      | update defd tm (net as (NODE edges)) =
           let fun exec_defd [] net = LEAF (elem::get_tip_list net)
                 | exec_defd (h::rst) net = update rst h net
               val label = label_of tm
               val child = get_edge label net
               val new_child = 
                 case label
                   of Cmb => let val {Rator, Rand} = Term.dest_comb tm
                             in update (Rator::defd) Rand child
                             end
                    | Lam => update defd (#Body(break_abs tm)) child
                    | _   => exec_defd defd child 
           in NODE (overwrite (label,new_child) edges)
           end
in  update
end;

fun enter (tm,elem) net = net_update (tm,elem) [] tm net;

fun follow tm net =
 let val nets = 
       case (label_of tm)
       of (label as Cnst _) => [get_edge label net] 
        | V   => [] 
        | Lam => follow (#Body(break_abs tm)) (get_edge Lam net)
        | Cmb => let val {Rator,Rand} = Term.dest_comb tm
                 in Lib.itlist(fn i => fn A => (follow Rator i @ A))
                              (follow Rand (get_edge Cmb net)) []
                 end
 in Lib.gather (not o is_empty) (get_edge V net::nets)
 end;

fun lookup tm net = 
 itlist (fn (LEAF L) => (fn A => (List.map #2 L @ A)) | (NODE _) => I)
        (follow tm net)  [];

end (* Net *)
