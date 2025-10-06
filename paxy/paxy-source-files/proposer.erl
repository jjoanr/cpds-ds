-module(proposer).
-export([start/6]).

-define(timeout, 2000).
-define(backoff, 10).

start(Name, Proposal, Acceptors, Sleep, PanelId, Main) ->
  spawn(fun() -> init(Name, Proposal, Acceptors, Sleep, PanelId, Main) end).

init(Name, Proposal, Acceptors, Sleep, PanelId, Main) ->
  timer:sleep(Sleep),
  Begin = erlang:monotonic_time(),
  Round = order:first(Name),
  {Decision, LastRound} = round(Name, ?backoff, Round, Proposal, Acceptors, PanelId),
  End = erlang:monotonic_time(),
  Elapsed = erlang:convert_time_unit(End-Begin, native, millisecond),
  io:format("[Proposer ~w] DECIDED ~w in round ~w after ~w ms~n", 
             [Name, Decision, LastRound, Elapsed]),
  Main ! done,
  PanelId ! stop.

% Paxos run
round(Name, Backoff, Round, Proposal, Acceptors, PanelId) ->
  io:format("[Proposer ~w] Phase 1: round ~w proposal ~w~n", 
             [Name, Round, Proposal]),
  % Update gui
  PanelId ! {updateProp, "Round: " ++ io_lib:format("~p", [Round]), Proposal},
  case ballot(Name, Round, Proposal, Acceptors, PanelId) of
    {ok, Value} ->
      {Value, Round};
    abort ->
      timer:sleep(rand:uniform(Backoff)),
      Next = order:inc(Round),
      round(Name, (2*Backoff), Next, Proposal, Acceptors, PanelId)
  end.

% Run phase 1 (prepare) and 2 (accept)
ballot(Name, Round, Proposal, Acceptors, PanelId) ->
  prepare(Round, Acceptors), % Multicast preapre message to acceptors
  Quorum = (length(Acceptors) div 2) + 1, % Define majority
  MaxVoted = order:null(), % will track highest previously voted value
  case collect(Quorum, Round, MaxVoted, Proposal) of % Collect promises to the prepare messages
    {accepted, Value} ->  % Send accept requests, majority achieved for promises
      io:format("[Proposer ~w] Phase 2: round ~w proposal ~w (was ~w)~n", 
                 [Name, Round, Value, Proposal]),
      % update gui
      PanelId ! {updateProp, "Round: " ++ io_lib:format("~p", [Round]), Value},
      accept(Round, Value, Acceptors), %s send accept req
      case vote(Quorum, Round) of % Wait for votes (responses to accept req)
        ok -> % Consensus reached
          {ok, Value};
        abort ->
          abort
      end;
    abort ->
      abort
  end.

% Base case: quorum of promises collected (majority of promises)
collect(0, _, _, Proposal) ->
  {accepted, Proposal}; % return proposal (or highest value seen)
% Recursive case: still need more promises
collect(N, Round, MaxVoted, Proposal) -> % Collects promises from acceptors
  receive 
    {promise, Round, _, na} ->  % Recieved promise, acceptor did not accept anything yet
      collect(N-1, Round, MaxVoted, Proposal);
    {promise, Round, Voted, Value} -> % Received promise with a prev value
      case order:gr(Voted, MaxVoted) of
        true ->
          collect(N-1, Round, Voted, Value); % Acceptor voted higher round, use its value
        false ->
          collect(N-1, Round, MaxVoted, Proposal) % Keep current maxvoted
      end;
    {promise, _, _,  _} -> % Promise from another round, ignore
      collect(N, Round, MaxVoted, Proposal);
    {sorry, {prepare, Round}} -> % Rejected prepare, doesnt count for majority
      collect(N, Round, MaxVoted, Proposal);
    {sorry, _} -> % ignore other sorry msgs
      collect(N, Round, MaxVoted, Proposal)
  after ?timeout -> % Timeout if not majority of promises collected
    abort
  end.

% Base case: majority (quorum) of votes achieved
vote(0, _) ->
  ok;
% Recursive case: still need more votes
vote(N, Round) ->
  receive
    {vote, Round} ->
      vote(N-1, Round); % Received vote from acceptor, count it towards quorum
    {vote, _} ->
      vote(N, Round); % Vote from another round, ignore
    {sorry, {accept, Round}} ->
      vote(N, Round); % Rejected accept, doesnt count for majority
    {sorry, _} ->
      vote(N, Round) % Ignore
  after ?timeout ->
    abort % Timeout if quorum not reached
  end.

prepare(Round, Acceptors) ->
  Fun = fun(Acceptor) -> 
    send(Acceptor, {prepare, self(), Round}) 
  end,
  lists:foreach(Fun, Acceptors).

accept(Round, Proposal, Acceptors) ->
  Fun = fun(Acceptor) -> 
    send(Acceptor, {accept, self(), Round, Proposal}) 
  end,
  lists:foreach(Fun, Acceptors).

send(Name, Message) ->
  Name ! Message.
