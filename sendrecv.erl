-module(sendrecv).
-export([run/3]).
%-compile(export_all).

-include("imb.hrl").

-ifdef(debug_sendrecv).
-define(DEBUG, true).
-else.
-define(DEBUG, false).
-endif.

run(Repetitions, Data, Processes) ->
    Senders = senders_init(Data, Processes, ?DEBUG),
    SendersDestinations = lists:zip(Senders, rotate(Senders)),
    TimeStart = imb:time_microseconds(),
    [Sender ! {init, Repetitions, Processes, Receiver, self()} || {Sender, Receiver} <- SendersDestinations],
    TimeEndList = finalize(Processes, Senders, SendersDestinations, []),
    [TimeEnd - TimeStart || TimeEnd <- TimeEndList].

finalize(P, S, SD, T) ->
    finalize(P, S, SD, T, 0).

finalize(Processes, Senders, SendersDestinations, Times, ProcessCount) ->
    receive
        {done, From} ->
            IsValid = lists:member(From, Senders),
            TimeEnd = imb:time_microseconds(),
            if 
                IsValid and ((ProcessCount + 1) =:= Processes) ->
                    ?TRACE("DONE (final): from: ~p time: ~p times: ~p~n", [From, TimeEnd, Times]),
                    [TimeEnd | Times];
                IsValid ->
                    ?TRACE("DONE: from: ~p time: ~p times: ~p~n", [From, TimeEnd, Times]),
                    finalize(Processes, Senders, SendersDestinations, [TimeEnd | Times], ProcessCount + 1);
                true ->
                    finalize(Processes, Senders, SendersDestinations, Times)
            end
    end.

senders_init(_, Processes, true) ->
    DataDebug = [imb:bytes_generate(X) || X <- lists:seq(1, Processes)],
    [spawn(fun() -> ring(X, X, Datum) end) || {X, Datum} <- lists:zip(lists:seq(1, Processes), DataDebug)];
senders_init(Data, Processes, false) ->
    [spawn(fun() -> ring(X, X, Data) end) || X <- lists:seq(1, Processes)].
    
ring(Dest, Parent, DataLocal) ->
    receive
        {init, Reps, Procs, DestInit, ParentInit} ->
            ?TRACE(
                "RECV (init): pid: ~p reps: ~p procs: ~p dest: ~p parent: ~p data-local: ~p~n", 
                [self(), Reps, Procs, DestInit, ParentInit, size(DataLocal)]
            ),
            ring_send_message(DestInit, Reps, Procs, DataLocal),
            ring(DestInit, ParentInit, DataLocal);
        {message, Reps, _Procs, _DataRemote} when (Reps =:= 0) -> 
            ?TRACE(
                "RECV (done): pid: ~p reps: ~p procs: ~p dest: ~p parent: ~p data-local: ~p data-remote: ~p~n", 
                [self(), Reps, _Procs, Dest, Parent, size(DataLocal), size(_DataRemote)]
            ),
            Parent ! {done, self()},
            void;
        {message, Reps, Procs, _DataRemote} ->
            ?TRACE(
                "RECV: pid: ~p reps: ~p procs: ~p dest: ~p parent: ~p data-local: ~p data-remote: ~p~n", 
                [self(), Reps, Procs, Dest, Parent, size(DataLocal), size(_DataRemote)]
            ),
            ring_send_message(Dest, Reps, Procs, DataLocal),
            ring(Dest, Parent, DataLocal);
        Any ->
            io:format("pid: ~p Any: ~p~n", [self(), Any])
    end.

ring_send_message(Destination, Repetitions, Processes, Data) ->
    Destination ! {message, Repetitions - 1, Processes, Data}.

rotate([]) ->
    [];
rotate([H | T]) ->
    T ++ [H].
