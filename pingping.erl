-module(pingping).
-export([run/2]).

-include("imb.hrl").

run(R, D) ->
    ?TRACE("pingping: ~p ~p~n", [R, size(D)]),
    P1 = spawn(fun() -> pingping(D) end),
    P2 = spawn(fun() -> pingping(D) end),
    TimeStart = imb:time_microseconds(),
    P1 ! {init, self(), P2, R},
    P2 ! {init, self(), P1, R},
    imb:finalize(P1),
    imb:finalize(P2),
    TimeEnd = imb:time_microseconds(),
    TimeEnd - TimeStart.

pingping(Data) ->
    receive
        {init, _From, Dest, R} ->
            ?TRACE("INIT: pid: ~p from: ~p data: ~p repetition: ~p ~n", [self(), _From, size(Data), R]),
            Dest ! {self(), R - 1, _From},
            pingping(Data);
        {_From, R, Parent} when R =:= 0 ->
            ?TRACE("RECV: pid: ~p from: ~p data: ~p repetition: ~p ~n", [self(), _From, size(Data), R]),
            Parent ! {done, self()};
        {_From, R, Parent} ->
            ?TRACE("RECV: pid: ~p from: ~p data: ~p repetition: ~p ~n", [self(), _From, size(Data), R]),
            _From ! {self(), R - 1, Parent},
            pingping(Data)
    end.
