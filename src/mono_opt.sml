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

structure MonoOpt :> MONO_OPT = struct

open Mono
structure U = MonoUtil

fun typ t = t
fun decl d = d

fun exp e =
    case e of
        EPrim (Prim.String s) =>
        let
            val (_, chs) =
                CharVector.foldl (fn (ch, (lastSpace, chs)) =>
                                     let
                                         val isSpace = Char.isSpace ch
                                     in
                                         if isSpace andalso lastSpace then
                                             (true, chs)
                                         else
                                             (isSpace, ch :: chs)
                                     end)
                                 (false, []) s
        in
            EPrim (Prim.String (String.implode (rev chs)))
        end
                                       
      | EStrcat ((EPrim (Prim.String s1), loc), (EPrim (Prim.String s2), _)) =>
        let
            val s =
                if size s1 > 0 andalso size s2 > 0
                   andalso Char.isSpace (String.sub (s1, size s1 - 1))
                   andalso Char.isSpace (String.sub (s2, 0)) then
                    s1 ^ String.extract (s2, 1, NONE)
                else
                    s1 ^ s2
        in
            EPrim (Prim.String s)
        end

      | EStrcat ((EPrim (Prim.String s1), loc), (EStrcat ((EPrim (Prim.String s2), _), rest), _)) =>
        let
            val s =
                if size s1 > 0 andalso size s2 > 0
                   andalso Char.isSpace (String.sub (s1, size s1 - 1))
                   andalso Char.isSpace (String.sub (s2, 0)) then
                    s1 ^ String.extract (s2, 1, NONE)
                else
                    s1 ^ s2
        in
            EStrcat ((EPrim (Prim.String s), loc), rest)
        end

      | EStrcat ((EStrcat (e1, e2), loc), e3) =>
        optExp (EStrcat (e1, (EStrcat (e2, e3), loc)), loc)

      | EWrite (EStrcat (e1, e2), loc) =>
        ESeq ((optExp (EWrite e1, loc), loc),
              (optExp (EWrite e2, loc), loc))

      | EWrite (EFfiApp ("Basis", "attrifyInt", [e]), _) =>
        EFfiApp ("Basis", "attrifyInt_w", [e])
      | EWrite (EFfiApp ("Basis", "attrifyFloat", [e]), _) =>
        EFfiApp ("Basis", "attrifyFloat_w", [e])
      | EWrite (EFfiApp ("Basis", "attrifyString", [e]), _) =>
        EFfiApp ("Basis", "attrifyString_w", [e])

      | _ => e

and optExp e = #1 (U.Exp.map {typ = typ, exp = exp} e)

val optimize = U.File.map {typ = typ, exp = exp, decl = decl}

end
