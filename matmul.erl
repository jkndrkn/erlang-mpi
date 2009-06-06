-module(matmul).
%-compile(export_all).
-export([run/4]).

-ifdef(debug).
-define(TRACE(Format, Data), io:format(string:concat("TRACE ~p:~p ", Format), [?MODULE, ?LINE] ++ Data)).
-define(DEBUG(Fun), Fun()).
-else.
-define(TRACE(Format, Data), void).
-define(DEBUG(Fun), void).
-endif.

run(ProcTotal, ARows, ACols, BCols) ->
    TimeStart = time_seconds(),
    A = matrix_init(ARows, ACols, a),
    B = matrix_init(ACols, BCols, b),
    WorkersTotal = workers_total(A, ProcTotal),
    {RowDistributions, RowIds} = matrix_partition(A, WorkersTotal),
    Workers = [
        spawn(fun() -> worker(Rows, B, Id) end) 
            || 
        {_, Rows, Id} <- lists:zip3(lists:seq(1, WorkersTotal), RowDistributions, RowIds)
    ],
    [Worker ! {calc, self()} || Worker <- Workers],
    Result = finalize(RowIds),
    TimeEnd = time_seconds(),
    TimeElapsed = TimeEnd - TimeStart,
    io:format("result:~n"),
    matrix_print(Result, "~6.2f "),
    io:format("time: ~.6f", [TimeElapsed]).

matrix_rows(Matrix) ->
    if
        is_list(hd(Matrix)) ->
            length(Matrix);
        true ->
            1
    end.

workers_total(Matrix, ProcTotal) ->
    MaxWorkers = ProcTotal - 1,
    Rows = matrix_rows(Matrix),
    if
        MaxWorkers > Rows ->
            Rows;
        true ->
            MaxWorkers
    end.
    

worker(A, B, Id) ->
    receive
        {calc, Parent} ->
            Result = matrix_multiply(A, B),
            ?TRACE("CALC(~p): A:~n", [self()]),
            ?DEBUG(fun() -> matrix_print(A, "~6.2f ") end),
            ?TRACE("CALC(~p): B:~n", [self()]),
            ?DEBUG(fun() -> matrix_print(B, "~6.2f ") end),
            ?TRACE("CALC(~p): Result:~n", [self()]),
            ?DEBUG(fun() -> matrix_print(Result, "~6.2f ") end),
            Parent ! {done, Result, Id, self()}
    end.
            
finalize(RowIds) ->
    finalize(RowIds, []).

finalize([Id | RowIds], Results) ->
    receive
        {done, Result, IdRemote, _From} when Id =:= IdRemote ->
                    ?TRACE("DONE: from: ~p id: ~p~n", [_From, Id]),
                    ?TRACE("DONE: result:~n", []),
                    ?DEBUG(fun() -> matrix_print(Result, "~6.2f ") end),
                    finalize(RowIds, lists:append(Result, Results))
    end;
finalize([], Results) ->
    Results.

matrix_init(Rows, Columns, Type) ->
    matrix_init(Rows, Columns, Type, []).

matrix_init(0, _, _, Matrix) ->
    Matrix;
matrix_init(Rows, Columns, a, Matrix) ->
    L = [Rows - 1.0 || _ <- lists:seq(0, Columns - 1)],
    matrix_init(Rows - 1, Columns, a, [L | Matrix]);
matrix_init(Rows, Columns, b, Matrix) ->
    L = [X * 1.0 || X <- lists:seq(0, Columns - 1)],
    matrix_init(Rows - 1, Columns, b, [L | Matrix]).

matrix_multiply(A, B) ->
    ACols = lists:seq(1, length(hd(A))),
    ARows = lists:seq(1, matrix_rows(A)), 
    BCols = lists:seq(1, length(hd(B))),
    [
        [
            lists:sum([mget(A, K, J) * mget(B, J, I) || J <- ACols]) 
            %[io:format("K: ~p I: ~p J: ~p~n", [K, I, J]) || J <- ACols]
                || 
            I <- BCols 
        ] 
            || 
        K <- ARows 
    ].

matrix_print(Matrix) ->
    matrix_print(Matrix, "~p ").
    
matrix_print(Matrix, Format) ->
    Rows = [fun() -> [io:format(Format, [Element]) || Element <- Row], io:format("~n") end || Row <- Matrix],
    [Row() || Row <- Rows].

mget(M, I, J) ->
    lists:nth(J, lists:nth(I, M)).

time_seconds() ->
    {MS, S, US} = now(),
    (MS * 1.0e+6) + S + (US * 1.0e-6).

rows_calc(RowsTotal, ProcNum, ProcTotal) when ProcNum < ProcTotal ->
    RowsBase = RowsTotal div ProcTotal,
    RowsRemainder = RowsTotal rem ProcTotal,
    if
        ProcNum < RowsRemainder ->
            RowsBase + 1;
        true ->
            RowsBase
    end.
    
matrix_partition(Matrix, WorkersTotal) ->
    RowsNum = length(Matrix),
    RowDistributions = [rows_calc(RowsNum, WorkerNum, WorkersTotal) || WorkerNum <- lists:seq(0, WorkersTotal - 1)],
    matrix_partition(Matrix, RowDistributions, [], [], 0).

matrix_partition(Matrix, [Size | RowDistributions], Partitions, RowIds, RowId) ->
    {Partition, Remainder} = lists:split(Size, Matrix), 
    matrix_partition(Remainder, RowDistributions, [Partition | Partitions], [RowId + Size | RowIds], RowId + Size);
matrix_partition([], [], Partitions, RowIds, _) ->
    {Partitions, RowIds}.
