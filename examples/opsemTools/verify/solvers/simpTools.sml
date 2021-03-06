(*=============================================================== *)
(* Some tools to do term simplifications.

   Used by the symbolic execution or by RUN, with constraint solver
   or SMT solver.
*)
(*=============================================================== *)


open HolKernel Parse boolLib newOpsemTheory
     relationTheory   arithmeticTheory
     computeLib bossLib;


(*==================================================== *)


(* --------------------------------------------------- *)
(* Functions to execute the small-step semantics       *)
(* --------------------------------------------------- *)

(* --------------------------------------------------- *)
(* Function to get the result of an equational theorem *)
(* --------------------------------------------------- *)
fun getThm thm =
  snd(dest_comb(concl(thm)));


(* --------------------------------------------------- *)
(* Function to get the next state and the next instruction
   list when executing an instruction on a given state *)
(* --------------------------------------------------- *)
fun nextStep instList state =
    let val tm = getThm (EVAL ``STEP1 (^instList, ^state)``);
      val (i,s) = dest_comb(tm);
      val newList = snd(dest_comb(i));
      val newState = snd(dest_comb(s));
      val outCome = fst(dest_comb(s));
    in
       if outCome = ``ERROR``
       then raise HOL_ERR {message="ERROR outcome in next state function",
		origin_function ="next ",
		origin_structure ="simpTools"}
       else (newList,newState)
     end;

(* --------------------------------------------------- *)
(* Function to evaluate a condition on the current state
   using the semantics of Boolean operators            *)
(* --------------------------------------------------- *)

fun evalCond cond st =
  let val (_,evalCond) = strip_comb(concl(EVAL ``beval ^cond ^st``))
  in
    el 2 evalCond
  end;

(*==================================================== *)

(* --------------------------------------------------- *)
(* Functions to handle post and pre conditions         *)
(* --------------------------------------------------- *)


(* --------------------------------------------------- *)
(* functions to transform JML bounded forall statement *)
(* --------------------------------------------------  *)

(* conversion rule to rewrite a bounded for all term
   as a conjunction *)

(* A bug has been corrected. When the term has the form "p ==> q"
   "strip_comb ant" raises a Bind exception.
   So Bind exception has been handled and propagate a HOL_ERR
   exception (to works correctly when using TOP_DEPTH_CONV).
*)
fun boundedForALL_ONCE_CONV tm =
 let val (vars,body) = strip_forall tm
     val (ant,con) = dest_imp body
     val (_,[lo,hi]) = strip_comb ant
 in
   if hi = Term(`0:num`)
   then (EVAL THENC SIMP_CONV std_ss []) tm
   else CONV_RULE
         (RHS_CONV EVAL)
         (BETA_RULE
          (SPEC
            (mk_abs(lo,con))
            (Q.GEN `P` (CONV_RULE EVAL (SPEC hi BOUNDED_FORALL_THM)))))
 end
 handle Bind =>
	raise HOL_ERR {message="imply in boundedForALL_ONCE_CONV",
		       origin_function ="boundedForALL_ONCE_CONV ",
		       origin_structure ="simpTools"};


val boundedForAll_CONV =
 TOP_DEPTH_CONV boundedForALL_ONCE_CONV THENC REWRITE_CONV [];

(* take a term t and converts it according to
    boundedForAll_CONV *)
fun rewrBoundedForAll tm =
    getThm (boundedForAll_CONV tm)
    handle UNCHANGED => tm;



(* --------------------------------------------------- *)
(* function to eliminate  ``T`` from conjunctions.
   It is required because the current Java implementation
   that takes a XML tree to build the CSP
   doesn't consider Booleans.
   So if precondition is ``T`` then the XML tag is empty
*)
(* --------------------------------------------------- *)
fun mkSimplConj t1 t2 =
  getThm (EVAL ``^t1 /\ ^t2``);



(*---------------------------------------------------------*)
(* Tool for applying De Morgan's laws at the top level to a
negated conjunction terms. For each term which is
an implication, apply NOT_IMP_CONJ theorem:

NOT_CONJ_IMP_CONV  ``~((A1 ==> B1) /\ ... /\ (An ==> Bn) /\ TM)`` =
 |- (A1 /\ ~B1) \/ ... \/ (An /\ ~Bn) \/ ~TM
*)

(* ---------------------------------------------------------*)
local

   val DE_MORGAN_AND_THM = METIS_PROVE [] ``!A:bool B:bool. ~(A/\B) = (~A) \/ (~B) ``

in

fun NOT_CONJ_IMP_CONV tm =
 let val tm1 = dest_neg tm
 in
  if is_imp_only tm1
   then let val (tm2,tm3) = dest_imp tm1
        in
         SPECL [tm2,tm3] NOT_IMP
        end
   else
     if is_conj tm1
     then let val (tm2,tm3) = dest_conj tm1
        in
            if is_imp_only tm2
            then let val (tm4,tm5) = dest_imp tm2
              in
                CONV_RULE
                (RAND_CONV(RAND_CONV NOT_CONJ_IMP_CONV))
                (SPECL [tm4,tm5,tm3] NOT_IMP_CONJ)
             end
            else
               CONV_RULE
                (RAND_CONV(RAND_CONV NOT_CONJ_IMP_CONV))
                (SPECL [tm2,tm3] DE_MORGAN_AND_THM)
        end
      else REFL tm
  end
  handle HOL_ERR t  =>
     (print "HOL_ERR in NOT_CONJ_IMP_CONV";
      REFL tm
     )
end;


(* --------------------------------------------------- *)
(* function to take the negation of the postcondition
   using NOT_CONJ_IMP_CONV *)
(* --------------------------------------------------- *)
fun takeNegPost post =
 let val n = mk_neg(post);
   in
     if is_conj(post) orelse is_imp_only(post)
     then
     (* build the negation using De Morgan laws at one level *)
         getThm (NOT_CONJ_IMP_CONV n)
     else
       (* case where post is not an implication *)
       n
     handle HOL_ERR t  =>
       (print "HOL_ERR in takeNegPost";
        n
        )
   end;



(* --------------------------------------------------- *)
(* evaluate precondition on initial state *)
(* --------------------------------------------------- *)
fun evalPre t st =
   rewrBoundedForAll(getThm (EVAL ``^t ^st``));

(* modify the initial state to take into
   account equalities of the form "x = l" where x is a variable
   and l is a constant *)
(*TODO
fun computeStateFromPre pre s =
  *)

(* --------------------------------------------------- *)
(* function to evaluate the postcondition.
   st1 is the state before execution of the program
   st2 is the state after execution of the program
*)
(* --------------------------------------------------- *)



(* has been modified for examples with bmcStraight *)
local

fun simpConv tm =
  getThm(SIMP_CONV (srw_ss()) [] tm)
  handle UNCHANGED
     => tm;

in


fun evalPost t st1 st2 =
  let val p = getThm (EVAL ``^t ^st1``);
   val pp =  if (is_abs(p))
             then getThm (EVAL ``^p ^st2``)
             else p
   (* added for examples with bmcStraight *)
   (* val ppp = simpConv pp*)
   in
     let val r = rewrBoundedForAll pp
     in
       r
     end
     handle Bind =>
	    (print "\nbind error in evalPost\n";
	     pp
	    )
     handle UNCHANGED =>
	     pp
     handle HOL_ERR s =>
	    (print "\nHOL_ERR in evalPost";
	     t
	    )
   end
end;

