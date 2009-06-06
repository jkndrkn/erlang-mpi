-define(ITERATIONS, 24).

-ifdef(debug).
-define(TRACE(Format, Data), io:format(string:concat("TRACE ~p:~p ", Format), [?MODULE, ?LINE] ++ Data)).
-else.
-define(TRACE(Format, Data), void).
-endif.
