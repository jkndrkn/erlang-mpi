-module(pingpong).
-export([run/2]).

-include("imb.hrl").

run(R, D) ->
    ?TRACE("pingpong: ~p ~p~n", [R, size(D)]),
    Pong = spawn(fun() -> pong() end),
    TimeStart = imb:time_microseconds(),
    ping(R, D, Pong),
    TimeEnd = imb:time_microseconds(),
    TimeEnd - TimeStart.

ping(0, _, _) ->
    done;
ping(R, D, Pong) ->
    Pong ! {self(), D},
    receive
        {Pong, D} ->
            ?TRACE("PING: from: ~p data: ~p repetition: ~p~n", [Pong, size(D), R]),
            ping(R - 1, D, Pong)
    end.

pong() ->
    receive
        {From, D} ->
            ?TRACE("PONG: from: ~p data: ~p ~n", [From, size(D)]),
            From ! {self(), D},
            pong()
    end.
