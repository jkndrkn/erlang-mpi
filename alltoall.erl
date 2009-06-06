-module(alltoall).
-compile(export_all).

-include("imb.hrl").

run(Repetitions, Data, Processes) ->
    TimeStart = imb:time_microseconds(),
    Threads = [spawn(fun() -> loop(Data) end) || _X <- lists:seq(1, Processes)],
    [Thread ! {init, Repetitions, Threads, self()} || Thread <- Threads],
    TimeEndList = finalize(Threads),
    [TimeEnd - TimeStart || TimeEnd <- TimeEndList].

loop(Data) ->
    receive
        {init, Reps, Threads, Parent} ->
            ?TRACE(
                "INIT: pid: ~p reps: ~p parent: ~p threads: ~p data: ~p\n", 
                [self(), Reps, Parent, Threads, size(Data)]
            ),
            alltoall(Threads, Data, self(), Reps),
            Parent ! {done, self()}
    end.

finalize(Processes) ->
    finalize(Processes, []).

finalize(Processes, Times) ->
    receive
        {done, From} ->
            TimeEnd = imb:time_microseconds(),
            IsValid = lists:member(From, Processes),
            if 
                IsValid and ((length(Times) + 1) =:= length(Processes)) ->
                    ?TRACE("DONE (final): from: ~p time: ~p times: ~p~n", [From, TimeEnd, Times]),
                    [TimeEnd | Times];
                IsValid ->
                    ?TRACE("DONE: from: ~p time: ~p times: ~p~n", [From, TimeEnd, Times]),
                    finalize(Processes, [TimeEnd | Times]);
                true ->
                    finalize(Processes, Times)
            end
    end.

alltoall(_, _, _, 0) ->
    done;
alltoall(Threads, Data, Sender, Reps) ->
    scatter(Threads, Data, Sender),
    _DataRemote = gather(Threads),
    ?TRACE(
        "ALLTOALL(~p): pid: ~p data-remote: ~p\n", 
        [Reps, self(), _DataRemote]
    ),
    alltoall(Threads, Data, Sender, Reps - 1).

scatter(Destinations, Data, Sender) ->
    [Destination ! {message, Data, Sender} || Destination <- Destinations].

gather(Sources) ->
    gather(Sources, []).

gather(Sources, Data) when length(Sources) =:= 0 -> 
    Data;
gather([From | Sources], Data) ->
    receive
        {message, DataRemote, From} ->
            ?TRACE(
                "RECV: pid: ~p from: ~p sources: ~p data-remote: ~p data-total: ~p\n", 
                [self(), From, Sources, size(DataRemote), Data]
            ),
            gather(Sources, [{From, DataRemote} | Data])
    end.
