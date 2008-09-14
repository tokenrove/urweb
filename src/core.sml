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

structure Core = struct

type 'a located = 'a ErrorMsg.located

datatype kind' =
         KType
       | KArrow of kind * kind
       | KName
       | KRecord of kind
       | KUnit
       | KTuple of kind list

withtype kind = kind' located

datatype con' =
         TFun of con * con
       | TCFun of string * kind * con
       | TRecord of con

       | CRel of int
       | CNamed of int
       | CFfi of string * string
       | CApp of con * con
       | CAbs of string * kind * con

       | CName of string

       | CRecord of kind * (con * con) list
       | CConcat of con * con
       | CFold of kind * kind

       | CUnit

       | CTuple of con list
       | CProj of con * int

withtype con = con' located

datatype datatype_kind = datatype Elab.datatype_kind

datatype patCon =
         PConVar of int
       | PConFfi of {mod : string, datatyp : string, params : string list,
                     con : string, arg : con option, kind : datatype_kind}

datatype pat' =
         PWild
       | PVar of string * con
       | PPrim of Prim.t
       | PCon of datatype_kind * patCon * con list * pat option
       | PRecord of (string * pat * con) list

withtype pat = pat' located

datatype exp' =
         EPrim of Prim.t
       | ERel of int
       | ENamed of int
       | ECon of datatype_kind * patCon * con list * exp option
       | EFfi of string * string
       | EFfiApp of string * string * exp list
       | EApp of exp * exp
       | EAbs of string * con * con * exp
       | ECApp of exp * con
       | ECAbs of string * kind * exp

       | ERecord of (con * exp * con) list
       | EField of exp * con * { field : con, rest : con }
       | EWith of exp * con * exp * { field : con, rest : con }
       | ECut of exp * con * { field : con, rest : con }
       | EFold of kind

       | ECase of exp * (pat * exp) list * { disc : con, result : con }

       | EWrite of exp

       | EClosure of int * exp list

withtype exp = exp' located

datatype export_kind =
         Link
       | Action

datatype decl' =
         DCon of string * int * kind * con
       | DDatatype of string * int * string list * (string * int * con option) list
       | DVal of string * int * con * exp * string
       | DValRec of (string * int * con * exp * string) list
       | DExport of export_kind * int
       | DTable of string * int * con * string
       | DSequence of string * int * string
       | DDatabase of string

withtype decl = decl' located

type file = decl list

end
