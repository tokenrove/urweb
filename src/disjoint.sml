(* Copyright (c) 2008, Adam Chlipala
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * - Redistributions of source code must retain the above copyright notice,
 *   this list of conditions and the following disclaimer.
 * - Redistributions in binary form must reproduce the above copyright notice,
 *   this list of conditions and the following disclaimer in the documentation
 *   and/or other materials provided with the distribution.
 * - The names of contributors may not be used to endorse or promote products
 *   derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR 
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 *)

structure Disjoint :> DISJOINT = struct

open Elab
open ElabOps

datatype piece =
         NameC of string
       | NameR of int
       | NameN of int
       | NameM of int * string list * string
       | RowR of int
       | RowN of int
       | RowM of int * string list * string

fun p2s p =
    case p of
        NameC s => "NameC(" ^ s ^ ")"
      | NameR n => "NameR(" ^ Int.toString n ^ ")"
      | NameN n => "NameN(" ^ Int.toString n ^ ")"
      | NameM (n, _, s) => "NameR(" ^ Int.toString n ^ ", " ^ s ^ ")"
      | RowR n => "RowR(" ^ Int.toString n ^ ")"
      | RowN n => "RowN(" ^ Int.toString n ^ ")"
      | RowM (n, _, s) => "RowR(" ^ Int.toString n ^ ", " ^ s ^ ")"

fun pp p = print (p2s p ^ "\n")

structure PK = struct

type ord_key = piece

fun join (o1, o2) =
    case o1 of
        EQUAL => o2 ()
      | v => v

fun joinL f (os1, os2) =
    case (os1, os2) of
        (nil, nil) => EQUAL
      | (nil, _) => LESS
      | (h1 :: t1, h2 :: t2) =>
        join (f (h1, h2), fn () => joinL f (t1, t2))
      | (_ :: _, nil) => GREATER

fun compare (p1, p2) =
    case (p1, p2) of
        (NameC s1, NameC s2) => String.compare (s1, s2)
      | (NameR n1, NameR n2) => Int.compare (n1, n2)
      | (NameN n1, NameN n2) => Int.compare (n1, n2)
      | (NameM (n1, ss1, s1), NameM (n2, ss2, s2)) =>
        join (Int.compare (n1, n2),
           fn () => join (String.compare (s1, s2), fn () =>
                                                      joinL String.compare (ss1, ss2)))
      | (RowR n1, RowR n2) => Int.compare (n1, n2)
      | (RowN n1, RowN n2) => Int.compare (n1, n2)
      | (RowM (n1, ss1, s1), RowM (n2, ss2, s2)) =>
        join (Int.compare (n1, n2),
           fn () => join (String.compare (s1, s2), fn () =>
                                                      joinL String.compare (ss1, ss2)))

      | (NameC _, _) => LESS
      | (_, NameC _) => GREATER

      | (NameR _, _) => LESS
      | (_, NameR _) => GREATER

      | (NameN _, _) => LESS
      | (_, NameN _) => GREATER

      | (NameM _, _) => LESS
      | (_, NameM _) => GREATER

      | (RowR _, _) => LESS
      | (_, RowR _) => GREATER

      | (RowN _, _) => LESS
      | (_, RowN _) => GREATER

end

structure PS = BinarySetFn(PK)
structure PM = BinaryMapFn(PK)

type env = PS.set PM.map

type goal = ErrorMsg.span * ElabEnv.env * env * Elab.con * Elab.con

val empty = PM.empty

fun nameToRow (c, loc) =
    (CRecord ((KUnit, loc), [((c, loc), (CUnit, loc))]), loc)

fun pieceToRow (p, loc) =
    case p of
        NameC s => nameToRow (CName s, loc)
      | NameR n => nameToRow (CRel n, loc)
      | NameN n => nameToRow (CNamed n, loc)
      | NameM (n, xs, x) => nameToRow (CModProj (n, xs, x), loc)
      | RowR n => (CRel n, loc)
      | RowN n => (CNamed n, loc)
      | RowM (n, xs, x) => (CModProj (n, xs, x), loc)

datatype piece' =
         Piece of piece
       | Unknown of con

fun pieceEnter p =
    case p of
        NameR n => NameR (n + 1)
      | RowR n => RowR (n + 1)
      | _ => p

fun enter denv =
    PM.foldli (fn (p, pset, denv') =>
                  PM.insert (denv', pieceEnter p, PS.map pieceEnter pset))
    PM.empty denv

fun prove1 denv (p1, p2) =
    case (p1, p2) of
        (NameC s1, NameC s2) => s1 <> s2
      | _ =>
        case PM.find (denv, p1) of
            NONE => false
          | SOME pset => PS.member (pset, p2)

fun decomposeRow (env, denv) c =
    let
        fun decomposeName (c, (acc, gs)) =
            let
                val (cAll as (c, _), gs') = hnormCon (env, denv) c

                val acc = case c of
                              CName s => Piece (NameC s) :: acc
                            | CRel n => Piece (NameR n) :: acc
                            | CNamed n => Piece (NameN n) :: acc
                            | CModProj (m1, ms, x) => Piece (NameM (m1, ms, x)) :: acc
                            | _ => Unknown cAll :: acc
            in
                (acc, gs' @ gs)
            end

        fun decomposeRow (c, (acc, gs)) =
            let
                val (cAll as (c, _), gs') = hnormCon (env, denv) c
                val gs = gs' @ gs
            in
                case c of
                    CRecord (_, xcs) => foldl (fn ((x, _), acc_gs) => decomposeName (x, acc_gs)) (acc, gs) xcs
                  | CConcat (c1, c2) => decomposeRow (c1, decomposeRow (c2, (acc, gs)))
                  | CRel n => (Piece (RowR n) :: acc, gs)
                  | CNamed n => (Piece (RowN n) :: acc, gs)
                  | CModProj (m1, ms, x) => (Piece (RowM (m1, ms, x)) :: acc, gs)
                  | _ => (Unknown cAll :: acc, gs)
            end
    in
        decomposeRow (c, ([], []))
    end

and assert env denv (c1, c2) =
    let
        val (ps1, gs1) = decomposeRow (env, denv) c1
        val (ps2, gs2) = decomposeRow (env, denv) c2

        val unUnknown = List.mapPartial (fn Unknown _ => NONE | Piece p => SOME p)
        val ps1 = unUnknown ps1
        val ps2 = unUnknown ps2

        (*val () = print "APieces1:\n"
        val () = app pp ps1
        val () = print "APieces2:\n"
        val () = app pp ps2*)

        fun assertPiece ps (p, denv) =
            let
                val pset = Option.getOpt (PM.find (denv, p), PS.empty)
                val ps = case p of
                             NameC _ => List.filter (fn NameC _ => false | _ => true) ps
                           | _ => ps
                val pset = PS.addList (pset, ps)
            in
                PM.insert (denv, p, pset)
            end

        val denv = foldl (assertPiece ps2) denv ps1
    in
        (foldl (assertPiece ps1) denv ps2, gs1 @ gs2)
    end

and prove env denv (c1, c2, loc) =
    let
        val (ps1, gs1) = decomposeRow (env, denv) c1
        val (ps2, gs2) = decomposeRow (env, denv) c2

        val hasUnknown = List.exists (fn Unknown _ => true | _ => false)
        val unUnknown = List.mapPartial (fn Unknown _ => NONE | Piece p => SOME p)
    in
        if hasUnknown ps1 orelse hasUnknown ps2 then
            [(loc, env, denv, c1, c2)]
        else
            let
                val ps1 = unUnknown ps1
                val ps2 = unUnknown ps2

            in
                (*print "Pieces1:\n";
                app pp ps1;
                print "Pieces2:\n";
                app pp ps2;*)

                foldl (fn (p1, rem) =>
                          foldl (fn (p2, rem) =>
                                    if prove1 denv (p1, p2) then
                                        rem
                                    else
                                        (loc, env, denv, pieceToRow (p1, loc), pieceToRow (p2, loc)) :: rem) rem ps2)
                      (gs1 @ gs2) ps1
            end
    end

and hnormCon (env, denv) c =
    let
        val cAll as (c, loc) = ElabOps.hnormCon env c

        fun doDisj (c1, c2, c) =
            let
                val (c, gs) = hnormCon (env, denv) c
            in
                (c, prove env denv (c1, c2, loc) @ gs)
            end
    in
        case c of
            CDisjoint cs => doDisj cs
          | TDisjoint cs => doDisj cs
          | _ => (cAll, [])
    end

end