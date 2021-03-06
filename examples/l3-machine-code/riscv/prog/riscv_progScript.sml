open HolKernel boolLib bossLib
open stateLib set_sepTheory progTheory riscv_stepTheory

val () = new_theory "riscv_prog"

(* ------------------------------------------------------------------------ *)

val _ = stateLib.sep_definitions "riscv" []
          (List.map Lib.list_of_singleton
             ["c_update", "log", "totalCore", "done", "clock", "c_tlb",
              "c_instret", "c_cycles", "c_UCSR", "c_SCSR", "c_ReserveLoad",
              "c_HCSR", "c_ExitCode"])
          riscv_stepTheory.NextRISCV_def

val riscv_instr_def = Define`
   riscv_instr (a, i: word32) =
   { (riscv_c_MEM8 a, riscv_d_word8 ((7 >< 0) i));
     (riscv_c_MEM8 (a + 1w), riscv_d_word8 ((15 >< 8) i));
     (riscv_c_MEM8 (a + 2w), riscv_d_word8 ((23 >< 16) i));
     (riscv_c_MEM8 (a + 3w), riscv_d_word8 ((31 >< 24) i)) }`;

val riscv_proj_def = DB.definition "riscv_proj_def"

val RISCV_MODEL_def = Define`
  RISCV_MODEL =
    (STATE riscv_proj, NEXT_REL (=) NextRISCV, riscv_instr,
     ($= :riscv_state -> riscv_state -> bool), K F : riscv_state -> bool)`

val RISCV_IMP_SPEC = Theory.save_thm ("RISCV_IMP_SPEC",
  stateTheory.IMP_SPEC
  |> Q.ISPECL [`riscv_proj`, `NextRISCV`, `riscv_instr`]
  |> REWRITE_RULE [GSYM RISCV_MODEL_def]
  )

val RISCV_IMP_TEMPORAL = Theory.save_thm ("RISCV_IMP_TEMPORAL",
  temporal_stateTheory.IMP_TEMPORAL
  |> Q.ISPECL [`riscv_proj`, `NextRISCV`, `riscv_instr`,
               `(=) : riscv_state -> riscv_state -> bool`,
               `K F : riscv_state -> bool`]
  |> REWRITE_RULE [GSYM RISCV_MODEL_def]
  )

(* ------------------------------------------------------------------------ *)

val riscv_ID_def = Define`
   riscv_ID id mcsr =
   riscv_exception NoException * riscv_procID id * riscv_c_NextFetch id NONE *
   riscv_c_MCSR id mcsr * cond (mcsr.mstatus.VM = 0w)`

val riscv_ID_PC_def = Define`
  riscv_ID_PC id pc = riscv_c_PC id pc * cond (aligned 2 pc)`

(* ------------------------------------------------------------------------
   Specialize to RV64I, core 0
   ------------------------------------------------------------------------ *)

val riscv_RV64I_def = Define`
  riscv_RV64I mcsr = cond (mcsr.mcpuid.ArchBase = 2w) * riscv_ID 0w mcsr`

val riscv_REG_def = Define`riscv_REG  = riscv_c_gpr 0w`
val riscv_PC_def = Define`riscv_PC = riscv_ID_PC 0w`

(* ------------------------------------------------------------------------ *)

val RISCV_PC_INTRO = Q.store_thm("RISCV_PC_INTRO",
   `SPEC m (p1 * riscv_ID_PC c pc) code (p2 * riscv_c_PC c pc') ==>
    (aligned 2 pc ==> aligned 2 pc') ==>
    SPEC m (p1 * riscv_ID_PC c pc) code (p2 * riscv_ID_PC c pc')`,
   REPEAT STRIP_TAC
   \\ FULL_SIMP_TAC std_ss
        [riscv_ID_PC_def, SPEC_MOVE_COND, STAR_ASSOC, SEP_CLAUSES]
   )

val RISCV_TEMPORAL_PC_INTRO = Q.store_thm("RISCV_TEMPORAL_PC_INTRO",
   `TEMPORAL_NEXT m (p1 * riscv_ID_PC c pc) code (p2 * riscv_c_PC c pc') ==>
    (aligned 2 pc ==> aligned 2 pc') ==>
    TEMPORAL_NEXT m (p1 * riscv_ID_PC c pc) code (p2 * riscv_ID_PC c pc')`,
   REPEAT STRIP_TAC
   \\ FULL_SIMP_TAC std_ss
        [riscv_ID_PC_def, temporal_stateTheory.TEMPORAL_NEXT_MOVE_COND,
         STAR_ASSOC, SEP_CLAUSES]
   )

val cond_branch_aligned = Q.store_thm("cond_branch_aligned",
  `(aligned 2 (pc: word64) ==>
    aligned 2
      (if b then
         pc +
         sw2sw (v2w [x0; x21; x1; x2; x3; x4;
                     x5; x6; x17; x18; x19; x20] : word12) << 1
       else pc + 4w)) = (aligned 2 pc /\ b ==> ~x20)`,
  rw [alignmentTheory.aligned_extract]
  \\ blastLib.FULL_BBLAST_TAC
  )

val jal_aligned = Q.store_thm("jal_aligned",
  `(aligned 2 (pc: word64) ==> aligned 2 (pc + sw2sw (a: word20) << 1)) =
   aligned 2 pc ==> ~word_lsb a`,
  rw [alignmentTheory.aligned_extract]
  \\ blastLib.BBLAST_TAC
  )

val jalr_aligned = Q.store_thm("jalr_aligned",
  `~(a: word12) ' 1 /\ (b \/ aligned 2 (v: word64)) /\
   (c ==> aligned 2 (if b then sw2sw a && 0xFFFFFFFFFFFFFFFEw
                     else v + sw2sw a && 0xFFFFFFFFFFFFFFFEw)) =
   ~(a: word12) ' 1 /\ (b \/ aligned 2 (v: word64))`,
  rw [alignmentTheory.aligned_extract]
  \\ blastLib.FULL_BBLAST_TAC
  )

(* ------------------------------------------------------------------------ *)

val c_gpr_frame = Q.store_thm("c_gpr_frame",
  `!c_gpr a b w s x.
     riscv_c_c_gpr a b IN x ==>
     (FRAME_STATE riscv_proj x
         (s with c_gpr := (a =+ (b =+ w) (c_gpr a)) c_gpr) =
      FRAME_STATE riscv_proj x (s with c_gpr := c_gpr))`,
  rw [stateTheory.FRAME_STATE_def, stateTheory.SELECT_STATE_def,
      set_sepTheory.fun2set_def, pred_setTheory.EXTENSION]
  \\ eq_tac
  \\ rw []
  \\ Cases_on `a'`
  \\ rw [combinTheory.APPLY_UPDATE_THM, riscv_proj_def]
  \\ Cases_on `b = c0`
  \\ fs []
  )

(* ------------------------------------------------------------------------ *)

val riscv_opcode_bytes = Theory.save_thm("riscv_opcode_bytes",
   blastLib.BBLAST_PROVE
    ``(d @@ ((c @@ ((b @@ a) : word16)) : word24) = r: word32) =
      (a = ( 7 ><  0) r : word8) /\
      (b = (15 ><  8) r : word8) /\
      (c = (23 >< 16) r : word8) /\
      (d = (31 >< 24) r : word8)``)

val () = export_theory()
