-module(mergesort).
-compile(export_all).
%-export([run/2]).

-ifdef(debug).
-define(TRACE(Format, Data), io:format(string:concat("TRACE ~p:~p ", Format), [?MODULE, ?LINE] ++ Data)).
-else.
-define(TRACE(Format, Data), void).
-endif.

run(Dimensions, M) ->
    TimeStart = time_microseconds(),
    DataSize = round(math:pow(2, Dimensions)) * M,
    random_seed(Dimensions + DataSize),
    Data = [random_value(DataSize) || _ <- lists:seq(1, DataSize)],
    Result = mergesort_exec(Data, Dimensions),
    ?TRACE("RESULT FINAL: ~p", [Result]),
    ResultFlat = lists:flatten([R || {_, R} <- lists:keysort(1, Result)]),
    TimeEnd = time_microseconds(),
    TimeElapsed = TimeEnd - TimeStart,
    io:format("data: ~p~n result: ~p~n time: ~.2f us~n", [Data, ResultFlat, TimeElapsed]).

mergesort_exec(Data, 0) ->
    mergesort(Data);
mergesort_exec(Data, Dimensions) ->
    UniqueID = time_microseconds(),
    ProcessesTotal = dimensions_to_processes(Dimensions),
    Processes = create_processes(Dimensions, ProcessesTotal, Data),
    WorkerIDs = [IDs || {IDs, _} <- Processes],
    WorkerPids = [Pids || {_, Pids} <- Processes],
    [Process ! {init, self(), WorkerPids, UniqueID} || {_, Process} <- Processes],
    finalize(WorkerIDs, WorkerPids).

mergesort(Data) when length(Data) =< 1 ->
    Data;
mergesort(Data) ->
    {Left, Right} = split(Data),
    merge(mergesort(Left), mergesort(Right)).

merge([], Result) ->
    Result;
merge(Result, []) ->
    Result;
merge(Left, Right) ->
    [LeftFirst | LeftRest] = Left,
    [RightFirst | RightRest] = Right,
    case LeftFirst =< RightFirst of
        true ->
            [LeftFirst | merge(LeftRest, Right)];
        false ->
            [RightFirst | merge(Left, RightRest)]
    end.

destinations(SenderID, Dimensions, WorkerPids) ->
    DestIDs = [SenderID bxor round(math:pow(2, X)) || X <- lists:seq(0, Dimensions - 1)],
    DestPids = [lists:sublist(WorkerPids, S + 1, 1) || S <- DestIDs],
    [{DestID, DestPid} || {DestID, [DestPid]} <- lists:zip(DestIDs, DestPids)].

compare_exchange_decode(SenderID, Dimension) ->
    case (SenderID band round(math:pow(2, Dimension - 1))) > 0 of
        true ->
            high;
        false ->
            low
    end.

compare_exchange(MyID, Destinations, Dimensions, Data, ID) ->
    compare_exchange(MyID, Destinations, Dimensions, 1, Data, ID, 0).

compare_exchange(_, [], _, _, Data, _, _) ->
    Data;
compare_exchange(MyID, [{DestID, Dest} | Destinations], Dimensions, Dimension, Data, ID, Strobe) ->
    Mode = compare_exchange_decode(MyID, Dimension),
    ?TRACE(
        "CE: myid: ~p(~p) dim: ~p/~p dest: ~p(~p) mode: ~p~n", 
        [MyID, self(), Dimension, Dimensions, DestID, Dest, Mode]
    ),
    {Low, High} = {Data, Data},
    case Mode of
        high ->
            Result = compare_exchange_high(High, Dest, DestID, ID, Strobe);
        low ->
            Result = compare_exchange_low(Low, Dest, DestID, ID, Strobe)
    end,
    compare_exchange(MyID, Destinations, Dimensions, Dimension + 1, Result, ID, Strobe + 1).

compare_exchange_high(High, Dest, _DestID, ID, Strobe) ->
    ?TRACE("CE-HIGH: High: ~p Dest: ~p DestID: ~p self: ~p~n", [High, Dest, _DestID, self()]),
    Dest ! {ce_high, High, self(), ID, Strobe},
    receive
        {ce_low, Low, _From, ID, Strobe} ->
            {_, Result} = split(merge(Low, High)),
            ?TRACE("CE-HIGH-Result:~n Low: ~p~n High: ~p~n Result: ~p~n", [Low, High, Result])
    end,
    Result.

compare_exchange_low(Low, Dest, _DestID, ID, Strobe) ->
    ?TRACE("CE-LOW: Low: ~p Dest: ~p DestID: ~p self: ~p~n", [Low, Dest, _DestID, self()]),
    Dest ! {ce_low, Low, self(), ID, Strobe},
    receive
        {ce_high, High, _From, ID, Strobe} ->
            {Result, _} = split(merge(Low, High)),
            ?TRACE("CE-LOW-Result:~n Low: ~p~n High: ~p~n Result: ~p~n", [Low, High, Result])
    end,
    Result.

create_processes(Dimensions, Processes, Data) ->
    DataDistribution = data_distribution(Data, Processes),
    [
        {ID, spawn(fun() -> worker(ID, D, Dimensions) end)} 
            || 
        {ID, D} <- lists:zip(lists:seq(0, Processes - 1), DataDistribution)
    ].


data_distribution(Data, Processes) ->
    data_distribution(Data, Processes, [], 1).

data_distribution(_, Processes, DataDistributed, _) when length(DataDistributed) =:= Processes ->
    DataDistributed;
data_distribution(Data, Processes, DataDistributed, Index) ->
    FragmentSize = length(Data) div Processes,
    Fragment = lists:sublist(Data, Index, FragmentSize),
    data_distribution(Data, Processes, [Fragment | DataDistributed], Index + FragmentSize).

dimensions_to_processes(Dimensions) ->
    round(math:pow(2, Dimensions)).

worker(MyID, Data, Dimensions) ->
    receive
        {init, Parent, WorkerPids, ID} -> 
            Destinations = destinations(MyID, Dimensions, WorkerPids),
            ?TRACE("WORKER: myid: ~p(~p) destinations: ~p~n", [MyID, self(), Destinations]),
            Result = compare_exchange(MyID, Destinations, Dimensions, mergesort(Data), ID),
            ?TRACE("SENDING: myid: ~p(~p) ~p~n", [MyID, self(), Result]),
            Parent ! {done, Result, MyID, self()}
    end.

samples_calc(SamplesTotal, ProcNum, ProcTotal) when ProcNum < ProcTotal ->
    SamplesBase = SamplesTotal div ProcTotal,
    SamplesRemainder = SamplesTotal rem ProcTotal,
    if
        ProcNum < SamplesRemainder ->
            SamplesBase + 1;
        true ->
            SamplesBase
    end.

finalize(IDs, Pids) ->
    %?TRACE("Processes: ~p ~p~n", [IDs, Pids]),
    finalize(IDs, Pids, []).

finalize([], _, Results) ->
    Results;
finalize(Processes, Pids, Results) ->
    receive
        {done, Result, MyID, From} ->
            [Process | ProcessRemainder] = Processes,
            %?TRACE("HIT: process: ~p myid: ~p~n", [Process, MyID]),
            IsValid = lists:member(From, Pids),
            if 
                IsValid and (length(Results) + 1 =:= length(Processes)) ->
                    %?TRACE("DONE (final): from: ~p result: ~p results: ~p~n", [From, Result, Results]),
                    %?TRACE("length(results): ~p length(processes): ~p~n", [length(Results), length(Processes)]),
                    [{MyID, Result} | Results];
                IsValid ->
                    %?TRACE("DONE: from: ~p result: ~p results: ~p~n", [From, Result, Results]),
                    %?TRACE("length(results): ~p length(processes): ~p~n", [length(Results), length(Processes)]),
                    finalize(ProcessRemainder, Pids, [{MyID, Result} | Results]);
                true ->
                    finalize(Processes, Pids, Results)
            end
    end.

random_seed(X) ->
    {S1, S2, S3} = now(),
    random:seed(S1 + X, S2 + X, S3 + X).

random_value(DataSize) ->
    round(random:uniform() * DataSize).

split(Data) ->
    Midpoint = length(Data) div 2,
    Left = lists:sublist(Data, Midpoint),
    Right = lists:nthtail(Midpoint, Data),
    {Left, Right}.

time_microseconds() ->
    {MS, S, US} = now(),
    (MS * 1.0e+12) + (S * 1.0e+6) + US.
