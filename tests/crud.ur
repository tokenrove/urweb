con colMeta' = fn t :: Type => {Show : t -> xbody}
con colMeta = fn cols :: {Type} => $(Top.mapTT colMeta' cols)

functor Make(M : sig
        con cols :: {Type}
        constraint [Id] ~ cols
        val tab : sql_table ([Id = int] ++ cols)

        val title : string

        val cols : colMeta cols
end) = struct

open constraints M
val tab = M.tab

fun list () =
        rows <- query (SELECT * FROM tab AS T)
                (fn (fs : {T : $([Id = int] ++ M.cols)}) acc => return <body>
                        {acc}
                        <tr>
                                <td>{txt _ fs.T.Id}</td>
                                {foldTR2 [idT] [colMeta'] [fn _ => xtr]
                                        (fn (nm :: Name) (t :: Type) (rest :: {Type}) =>
                                                [[nm] ~ rest] =>
                                                fn v funcs acc =>
                                                <tr>
                                                        <td>{funcs.Show v}</td>
                                                        {acc}
                                                </tr>)
                                        <tr></tr>
                                        [M.cols] (fs.T -- #Id) M.cols}
                        </tr>
                </body>) <body></body>;
        return <html><head>
                <title>List</title>

                </head><body>

                <h1>List</h1>

                <table border={1}>
                <tr> <th>ID</th> </tr>
                {rows}
                </table>
        </body></html>

fun main () : transaction page = return <html><head>
        <title>{cdata M.title}</title>
        </head><body>
        <h1>{cdata M.title}</h1>

        <li> <a link={list ()}>List all rows</a></li>
</body></html>

end
