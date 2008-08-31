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

(* Remove unused definitions from a file *)

structure Shake :> SHAKE = struct

open Core

structure U = CoreUtil

structure IS = IntBinarySet
structure IM = IntBinaryMap

type free = {
     con : IS.set,
     exp : IS.set
}

val dummye = (EPrim (Prim.String ""), ErrorMsg.dummySpan)

fun shake file =
    let
        val (page_es, table_cs) =
            List.foldl
                (fn ((DExport (_, n), _), (page_es, table_cs)) => (n :: page_es, table_cs)
                  | ((DTable (_, _, c, _), _), (page_es, table_cs)) => (page_es, c :: table_cs)
                  | (_, acc) => acc) ([], []) file

        val (cdef, edef) = foldl (fn ((DCon (_, n, _, c), _), (cdef, edef)) => (IM.insert (cdef, n, [c]), edef)
                                   | ((DDatatype (_, n, _, xncs), _), (cdef, edef)) =>
                                     (IM.insert (cdef, n, List.mapPartial #3 xncs), edef)
                                   | ((DVal (_, n, t, e, _), _), (cdef, edef)) => (cdef, IM.insert (edef, n, (t, e)))
                                   | ((DValRec vis, _), (cdef, edef)) =>
                                     (cdef, foldl (fn ((_, n, t, e, _), edef) => IM.insert (edef, n, (t, e))) edef vis)
                                   | ((DExport _, _), acc) => acc
                                   | ((DTable (_, n, c, _), _), (cdef, edef)) =>
                                     (cdef, IM.insert (edef, n, (c, dummye))))
                                 (IM.empty, IM.empty) file

        fun kind (_, s) = s

        fun con (c, s) =
            case c of
                CNamed n =>
                if IS.member (#con s, n) then
                    s
                else
                    let
                        val s' = {con = IS.add (#con s, n),
                                  exp = #exp s}
                    in
                        case IM.find (cdef, n) of
                            NONE => s'
                          | SOME cs => foldl (fn (c, s') => shakeCon s' c) s' cs
                    end
              | _ => s

        and shakeCon s = U.Con.fold {kind = kind, con = con} s

        fun exp (e, s) =
            case e of
                ENamed n =>
                if IS.member (#exp s, n) then
                    s
                else
                    let
                        val s' = {exp = IS.add (#exp s, n),
                                  con = #con s}
                    in
                        case IM.find (edef, n) of
                            NONE => s'
                          | SOME (t, e) => shakeExp (shakeCon s' t) e
                    end
              | _ => s

        and shakeExp s = U.Exp.fold {kind = kind, con = con, exp = exp} s

        val s = {con = IS.empty, exp = IS.addList (IS.empty, page_es)}

        val s = foldl (fn (n, s) =>
                          case IM.find (edef, n) of
                              NONE => raise Fail "Shake: Couldn't find 'val'"
                            | SOME (t, e) => shakeExp (shakeCon s t) e) s page_es

        val s = foldl (fn (c, s) => shakeCon s c) s table_cs
    in
        List.filter (fn (DCon (_, n, _, _), _) => IS.member (#con s, n)
                      | (DDatatype (_, n, _, _), _) => IS.member (#con s, n)
                      | (DVal (_, n, _, _, _), _) => IS.member (#exp s, n)
                      | (DValRec vis, _) => List.exists (fn (_, n, _, _, _) => IS.member (#exp s, n)) vis
                      | (DExport _, _) => true
                      | (DTable _, _) => true) file
    end

end
