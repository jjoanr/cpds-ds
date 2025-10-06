-module(acceptor).
-export([start/2]).

start(Name, PanelId) ->
  spawn(fun() -> init(Name, PanelId) end).
        
init(Name, PanelId) ->
  Promised = order:null(), 
  Voted = order:null(),
  Value = na,
  acceptor(Name, Promised, Voted, Value, PanelId).

acceptor(Name, Promised, Voted, Value, PanelId) ->
  receive
    {prepare, Proposer, Round} ->
      case order:gr(Round, Promised) of % If recv prepare round is > than promised round
        true ->
          Proposer ! {promise, Round, Voted, Value}, % Respond to the proposer with promise             
          io:format("[Acceptor ~w] Phase 1: promised ~w voted ~w colour ~w~n",
              [Name, Round, Voted, Value]),
          % Update gui
          Colour = case Value of na -> {0,0,0}; _ -> Value end,
          PanelId ! {updateAcc, "Voted: " ++ io_lib:format("~p", [Voted]), 
                     "Promised: " ++ io_lib:format("~p", [Round]), Colour},
          acceptor(Name, Round, Voted, Value, PanelId); % Update promised to the new round
        false ->
          Proposer ! {sorry, {prepare, Round}}, % Respond to the proposer that we cannot promise
          acceptor(Name, Promised, Voted, Value, PanelId) % Keep already promised
      end;
    {accept, Proposer, Round, Proposal} ->
      case order:goe(Round, Promised) of
        true -> % Greater or equal than promised, vote for round
          Proposer ! {vote, Round}, % Send to proposer we voted for his round
          case order:goe(Round, Voted) of
            true -> % If new voted round is the highest, save value
              io:format("[Acceptor ~w] Phase 2: promised ~w voted ~w colour ~w~n",
                  [Name, Promised, Round, Proposal]),
              % Update gui
              PanelId ! {updateAcc, "Voted: " ++ io_lib:format("~p", [Round]), 
                         "Promised: " ++ io_lib:format("~p", [Promised]), Proposal},
              acceptor(Name, Promised, Round, Proposal, PanelId); % Update new highest voted round and value
            false -> % We have voted already for a higher round, do not update value with new one
              acceptor(Name, Promised, Voted, Value, PanelId)
          end;                            
        false -> % We cannot vote
          Proposer ! {sorry, {accept, Round}}, % Respond we cannot vote for his round
          acceptor(Name, Promised, Voted, Value, PanelId) % Dont updte anything
      end;
    stop ->
      PanelId ! stop,
      ok
  end.
