#include "IFactory.ligo"

// TODO:
//  - add veto update in invest/divest 
const circlePeriod : int = 3 // 1474560
const vetoPeriod : int = 7889229;

type transfer_type is TransferType of michelson_pair(address, "from", michelson_pair(address, "to", nat, "value"), "")
type token_lookup_type is TokenLookupType of (address * address * nat)
type use_type is UseType of (nat * dexAction) 

function initializeExchange (const p : dexAction ; const s : dex_storage ; const this: address) :  (list(operation) * dex_storage) is
block {
  var operations : list(operation) := list[];
    case p of
    | InitializeExchange(tokenAmount) -> {
        if s.invariant =/= 0n 
          or s.totalShares =/= 0n 
          or Tezos.amount < 1mutez 
          or tokenAmount < 1n 
          or Tezos.amount > 500000000tz then failwith("Dex/non-allowed") else skip ; 
        s.tokenPool := tokenAmount;
        s.tezPool := Tezos.amount / 1mutez;
        s.invariant := s.tezPool * s.tokenPool;
        s.shares[Tezos.sender] := 1000n;
        s.totalShares := 1000n;
        
         // update user loyalty
        s.currentCircle.lastUpdate := Tezos.now;
        s.circleLoyalty[Tezos.sender] := record reward = 0n; loyalty = 0n; lastCircle = 0n; lastCircleUpdate = Tezos.now; end;  
        operations := transaction(
          TransferType(Tezos.sender, (this, tokenAmount)), 
          0mutez, 
          case (Tezos.get_entrypoint_opt("%transfer", s.tokenAddress) : option(contract(transfer_type))) of Some(contr) -> contr
            | None -> (failwith("01"):contract(transfer_type))
          end
          ) # operations;
    }
    | TezToTokenPayment(n) -> failwith("00")
    | TokenToTezPayment(n) -> failwith("00")
    | InvestLiquidity(n) -> failwith("00")
    | DivestLiquidity(n) -> failwith("00")
    | SetVotesDelegation(n) -> failwith("00")
    | Vote(n) -> failwith("00")
    | Veto(n) -> failwith("00")
    | WithdrawProfit(n) -> failwith("00")
    end
} with (operations, s)

function setVotesDelegation (const p : dexAction ; const s : dex_storage ; const this: address) :  (list(operation) * dex_storage) is
block {
  case p of
  | InitializeExchange(tokenAmount) -> failwith("00")
  | TezToTokenPayment(n) -> failwith("00")
  | TokenToTezPayment(n) -> failwith("00")
  | InvestLiquidity(n) -> failwith("00")
  | DivestLiquidity(n) -> failwith("00")
  | SetVotesDelegation(args) -> 
     if Tezos.sender = args.account then skip
     else block {
        const src: vote_info = case s.voters[Tezos.sender] of None -> record allowances = (set [] : set(address)); candidate = (None:option(key_hash)) end 
           | Some(v) -> v 
           end ;
        if Set.size(src.allowances) >= 5n and args.isAllowed then failwith("Dex/many-voter-delegates") else {
           src.allowances := if args.isAllowed then Set.add (args.account, src.allowances) else Set.remove (args.account, src.allowances) ;
           s.voters[Tezos.sender] := src;
        };
     }
  | Vote(n) -> failwith("00")
  | Veto(n) -> failwith("00")
  | WithdrawProfit(n) -> failwith("00")
  end
} with ((nil:list(operation)), s)

function redelegate (const voter : address; const candidate : key_hash; const prevShare : nat; const share : nat; var s: dex_storage) :  (dex_storage) is
block {
  case s.vetos[candidate] of None -> skip
    | Some(c) -> if c > Tezos.now then failwith ("Dex/veto-candidate") else remove candidate from map s.vetos
  end;
  const voterInfo : vote_info = record allowances = (set [] : set(address)); candidate = Some(candidate); end;
  case s.voters[voter] of None -> skip
    | Some(v) -> {
      case v.candidate of None -> skip | Some(c) -> {
        if s.totalVotes < prevShare then failwith ("Dex/invalid-shares") else {
          s.totalVotes := abs(s.totalVotes - prevShare);
          s.votes[c]:= abs(get_force(c, s.votes) - prevShare);
          v.candidate := Some(candidate);

        } ;
      } end;
      voterInfo := v;
    }
    end;    
  if Tezos.sender = voter or voterInfo.allowances contains Tezos.sender then {
    s.voters[voter]:= voterInfo;
    s.totalVotes := s.totalVotes + share;
    const newVotes: nat = (case s.votes[candidate] of  None -> 0n | Some(v) -> v end) + share;
    s.votes[candidate]:= newVotes;
    if case s.delegated of None -> True 
      | Some(delegated) ->
        if (case s.votes[delegated] of None -> 0n | Some(v) -> v end) > newVotes then True else False
      end
    then {
      s.delegated := Some(candidate);
    } else skip ;
  } else failwith ("Dex/vote-not-permitted");
} with (s)

function vote (const p : dexAction ; const s : dex_storage; const this: address) :  (list(operation) * dex_storage) is
block {
  case p of
  | InitializeExchange(tokenAmount) -> failwith("00")
  | TezToTokenPayment(n) -> failwith("00")
  | TokenToTezPayment(n) -> failwith("00")
  | InvestLiquidity(n) -> failwith("00")
  | DivestLiquidity(n) -> failwith("00")
  | SetVotesDelegation(n) -> failwith("00")
  | Vote(args) -> 
      case s.shares[args.voter] of None -> failwith ("Dex/no-shares")
      | Some(share) -> {
        case s.vetos[args.candidate] of None -> skip
          | Some(c) -> if c > Tezos.now then failwith ("Dex/veto-candidate") else remove args.candidate from map s.vetos
        end; 
        const voterInfo : vote_info = record allowances = (set [] : set(address)); candidate = Some(args.candidate); end;
        case s.voters[args.voter] of None -> skip
          | Some(v) -> 
            case v.candidate of None -> voterInfo := v 
              | Some(c) -> {
                if s.totalVotes < share then failwith ("Dex/invalid-shares") else {
                  s.totalVotes := abs(s.totalVotes - share);
                  s.votes[c]:= abs(get_force(c, s.votes) - share);
                  voterInfo := v;
                };
              } end
          end;    
        if Tezos.sender = args.voter or voterInfo.allowances contains Tezos.sender then {
          voterInfo.candidate := Some(args.candidate);
          s.voters[args.voter]:= voterInfo;
          s.totalVotes := s.totalVotes + share;
          const newVotes: nat = (case s.votes[args.candidate] of  None -> 0n | Some(v) -> v end) + share;
          s.votes[args.candidate]:= newVotes;
          if case s.delegated of None -> True 
            | Some(delegated) ->
              if (case s.votes[delegated] of None -> 0n | Some(v) -> v end) > newVotes then False else True
            end
          then
          {
             s.delegated := Some(args.candidate);
          } else skip ;
        } else failwith ("Dex/vote-not-permitted");
      }
      end
  | Veto(n) -> failwith("00")
  | WithdrawProfit(n) -> failwith("00")
  end
} with ((nil:list(operation)), s)

function veto (const p : dexAction ; const s : dex_storage; const this: address) :  (list(operation) * dex_storage) is
block {
  var operations: list(operation) := list[];
  case p of
  | InitializeExchange(tokenAmount) -> failwith("00")
  | TezToTokenPayment(n) -> failwith("00")
  | TokenToTezPayment(n) -> failwith("00")
  | InvestLiquidity(n) -> failwith("00")
  | DivestLiquidity(n) -> failwith("00")
  | SetVotesDelegation(n) -> failwith("00")
  | Vote(n) -> failwith("00")
  | Veto(voter) -> 
    case s.shares[voter] of None -> failwith ("Dex/no-voter")
    | Some(share) -> {
      const src : vote_info = case s.voters[voter] of None -> record allowances = (set [] : set(address)); candidate = (None: option(key_hash)); end
      | Some(src) -> src
      end;
      if Tezos.sender = voter or src.allowances contains Tezos.sender then {
        var newShare: nat := case s.vetoVoters[voter] of None -> share
          | Some(prev) ->
            if share > prev then abs(share - prev) else (failwith ("Dex/old-shares") : nat)
          end;
        s.veto := s.veto + newShare;
        if s.veto > s.totalVotes / 2n then {
            s.veto := 0n;
            case s.currentDelegated of None -> failwith ("Dex/no-delegated")
            | Some(c) -> {
              s.vetos[c] := Tezos.now + vetoPeriod;
              s.currentDelegated := (None: option(key_hash));
              operations := set_delegate(s.currentDelegated) # operations;
              s.vetoVoters := (big_map end : big_map(address, nat));
            }
            end;
        } else skip ;
        s.vetoVoters[voter] := share;
      } else failwith ("Dex/vote-not-permitted");
    }
    end
  | WithdrawProfit(n) -> failwith("00")
  end
} with (operations, s)

function tezToToken (const p : dexAction ; const s : dex_storage; const this: address) :  (list(operation) * dex_storage) is
block {
  var operations: list(operation) := list[];
  case p of
  | InitializeExchange(tokenAmount) -> failwith("00")
  | TezToTokenPayment(args) -> 
    if Tezos.amount / 1mutez > 0n and args.amount > 0n then {
      s.tezPool := s.tezPool + Tezos.amount / 1mutez;
      const newTokenPool : nat = s.invariant / abs(s.tezPool - Tezos.amount / 1mutez / s.feeRate);
      const tokensOut : nat = abs(s.tokenPool - newTokenPool);
        if tokensOut >= args.amount then {
          s.tokenPool := newTokenPool;
          s.invariant := s.tezPool * newTokenPool;
          operations :=  transaction(
            TransferType(this, (args.receiver, tokensOut)), 
            0mutez, 
            case (Tezos.get_entrypoint_opt("%transfer", s.tokenAddress) : option(contract(transfer_type))) of Some(contr) -> contr
              | None -> (failwith("01"):contract(transfer_type))
            end
            ) # operations;
      } else failwith("Dex/high-min-out");
    } else failwith("Dex/wrong-params")
  | TokenToTezPayment(n) -> failwith("00")
  | InvestLiquidity(n) -> failwith("00")
  | DivestLiquidity(n) -> failwith("00")
  | SetVotesDelegation(n) -> failwith("00")
  | Vote(n) -> failwith("00")
  | Veto(voter) -> failwith("00")
  | WithdrawProfit(n) -> failwith("00")
  end
} with (operations, s)

function tokenToTez (const p : dexAction ; const s : dex_storage; const this: address) :  (list(operation) * dex_storage) is
block {
  var operations: list(operation) := list[];
  case p of
  | InitializeExchange(tokenAmount) -> failwith("00")
  | TezToTokenPayment(n) -> failwith("00")
  | TokenToTezPayment(args) -> 
    if args.amount > 0n and args.minOut > 0n then {
      s.tokenPool := s.tokenPool + args.amount;
      const newTezPool : nat = s.invariant / abs(s.tokenPool - args.amount / s.feeRate);
      const tezOut : nat = abs(s.tezPool - newTezPool);

      if tezOut >= args.minOut then {
        s.tezPool := newTezPool;
        s.invariant := newTezPool * s.tokenPool;
        operations:= list transaction(
          TransferType(Tezos.sender, (this, args.amount)), 
          0mutez, 
          case (Tezos.get_entrypoint_opt("%transfer", s.tokenAddress) : option(contract(transfer_type))) of Some(contr) -> contr
            | None -> (failwith("01"):contract(transfer_type))
          end); 
          transaction(unit, args.minOut * 1mutez, (get_contract(args.receiver) : contract(unit))); end;
      } else failwith("Dex/high-min-tez-out");
  
    } else failwith("Dex/wrong-params")
  | InvestLiquidity(n) -> failwith("00")
  | DivestLiquidity(n) -> failwith("00")
  | SetVotesDelegation(n) -> failwith("00")
  | Vote(n) -> failwith("00")
  | Veto(voter) -> failwith("00")
  | WithdrawProfit(n) -> failwith("00")
  end
} with (operations, s)

function investLiquidity (const p : dexAction ; const s : dex_storage; const this: address) :  (list(operation) * dex_storage) is
block {
  var operations: list(operation) := list[];
  case p of
  | InitializeExchange(tokenAmount) -> failwith("00")
  | TezToTokenPayment(n) -> failwith("00")
  | TokenToTezPayment(n) -> failwith("00")
  | InvestLiquidity(minShares) -> {
    const sharesPurchased : nat = (Tezos.amount / 1mutez) * s.totalShares / s.tezPool;
    if minShares > 0n and sharesPurchased >= minShares then skip else failwith("Dex/wrong-params");
    s.currentCircle.totalLoyalty := s.currentCircle.totalLoyalty + abs(Tezos.now - s.currentCircle.lastUpdate) * s.totalShares;
    s.currentCircle.lastUpdate := Tezos.now;
    const tokensRequired : nat = sharesPurchased * s.tokenPool / s.totalShares;
    if tokensRequired = 0n then failwith("Dex/dangerous-rate") else {
      const share : nat = case s.shares[Tezos.sender] of | None -> 0n | Some(share) -> share end;
      // update user loyalty
      var userCircle : user_circle_info := case s.circleLoyalty[Tezos.sender] of None -> record reward = 0n; loyalty = 0n; lastCircle = s.currentCircle.counter; lastCircleUpdate = Tezos.now; end
        | Some(c) -> c
      end;
      if userCircle.lastCircle =/= s.currentCircle.counter then {
        var circle : circle_info := get_force(userCircle.lastCircle, s.circles);
        userCircle.reward := userCircle.reward + circle.reward * (userCircle.loyalty + share * abs(circle.nextCircle - userCircle.lastCircleUpdate)) / circle.totalLoyalty;
        userCircle.loyalty := 0n;
        userCircle.lastCircleUpdate := circle.start;
      } else skip ;
      if s.currentCircle.counter - userCircle.lastCircle > 1 then {
        const lastFullCircle : circle_info = get_force(abs(s.currentCircle.counter - 1n), s.circles);
        const lastUserCircle : circle_info = get_force(userCircle.lastCircle, s.circles);
        userCircle.reward := userCircle.reward + share * abs(lastFullCircle.circleCoefficient - lastUserCircle.circleCoefficient);
      } else skip ;
      userCircle.loyalty := userCircle.loyalty + share * abs(Tezos.now-userCircle.lastCircleUpdate);
      userCircle.lastCircleUpdate := Tezos.now;
      userCircle.lastCircle := s.currentCircle.counter;
      s.circleLoyalty[Tezos.sender] := userCircle;
      s.shares[Tezos.sender] := share + sharesPurchased;
      s.tezPool := s.tezPool + Tezos.amount / 1mutez;
      s.tokenPool := s.tokenPool + tokensRequired;
      s.invariant := s.tezPool * s.tokenPool;
      s.totalShares := s.totalShares + sharesPurchased;
      operations := transaction(TransferType(Tezos.sender, (this, tokensRequired)), 
        0mutez, 
        case (Tezos.get_entrypoint_opt("%transfer", s.tokenAddress) : option(contract(transfer_type))) of Some(contr) -> contr
          | None -> (failwith("01"):contract(transfer_type))
        end
      ) # operations;
      case s.voters[Tezos.sender] of None -> skip
        | Some(v) -> { 
          case v.candidate of None -> skip 
          | Some(candidate) -> {
            case s.vetos[candidate] of None -> skip
              | Some(c) -> if c > Tezos.now then failwith ("Dex/veto-candidate") else
                remove candidate from map s.vetos
            end;
            if s.totalVotes < share then failwith ("Dex/invalid-shares") else {
              s.totalVotes := abs(s.totalVotes - share);
              s.votes[candidate]:= abs(get_force(candidate, s.votes) - share);
              v.candidate := Some(candidate);
            } ;
            s.voters[Tezos.sender]:= v;
            s.totalVotes := s.totalVotes + share + sharesPurchased;
            const newVotes: nat = (case s.votes[candidate] of  None -> 0n | Some(v) -> v end) + share + sharesPurchased;
            s.votes[candidate]:= newVotes;
            if case s.delegated of None -> True 
              | Some(delegated) ->
                if (case s.votes[delegated] of None -> 0n | Some(v) -> v end) > newVotes then True else False
              end
            then {
              s.delegated := Some(candidate);
            } else skip ;
          } end;
        } end;
    }; 
  }
  | DivestLiquidity(n) -> failwith("00")
  | SetVotesDelegation(n) -> failwith("00")
  | Vote(n) -> failwith("00")
  | Veto(voter) -> failwith("00")
  | WithdrawProfit(n) -> failwith("00")
  end
} with (operations, s)

function divestLiquidity (const p : dexAction ; const s : dex_storage; const this: address) :  (list(operation) * dex_storage) is
block {
  var operations: list(operation) := list[];
  case p of
  | InitializeExchange(tokenAmount) -> failwith("00")
  | TezToTokenPayment(n) -> failwith("00")
  | TokenToTezPayment(n) -> failwith("00")
  | InvestLiquidity(minShares) -> failwith("00")
  | DivestLiquidity(args) -> {
      const share : nat = case s.shares[Tezos.sender] of | None -> 0n | Some(share) -> share end;
      if args.shares > 0n and args.shares <= share then {
        s.shares[Tezos.sender] := abs(share - args.shares);

        s.currentCircle.totalLoyalty := s.currentCircle.totalLoyalty + abs(Tezos.now - s.currentCircle.lastUpdate) * s.totalShares;
        s.currentCircle.lastUpdate := Tezos.now;

        const tezDivested : nat = s.tezPool * args.shares / s.totalShares;
        const tokensDivested : nat = s.tokenPool * args.shares / s.totalShares;

        if args.minTez > 0n and args.minTokens > 0n and tezDivested >= args.minTez and tokensDivested >= args.minTokens then {
          var userCircle : user_circle_info := get_force(Tezos.sender, s.circleLoyalty);
          if userCircle.lastCircle =/= s.currentCircle.counter then {
            case s.circles[userCircle.lastCircle] of Some(circle) -> {
              userCircle.reward := userCircle.reward + circle.reward * (userCircle.loyalty + share * abs(circle.nextCircle - userCircle.lastCircleUpdate)) / circle.totalLoyalty;
              userCircle.loyalty := 0n;
              userCircle.lastCircleUpdate := circle.start;
            } 
            | None -> failwith("Dex/no-circle")
            end;
          } else skip ;

          if s.currentCircle.counter - userCircle.lastCircle > 1 then 
            case s.circles[abs(s.currentCircle.counter - 1n)] of 
              None -> failwith("Dex/no-full-circle")
              | Some(lastFullCircle) -> case s.circles[userCircle.lastCircle] of 
                None -> failwith("Dex/no-full-circle")
                | Some(lastUserCircle) -> userCircle.reward := userCircle.reward + share * abs(lastFullCircle.circleCoefficient - lastUserCircle.circleCoefficient)
                end
              end
             else skip ;
          userCircle.loyalty := userCircle.loyalty + share * abs(Tezos.now-userCircle.lastCircleUpdate);
          userCircle.lastCircleUpdate := Tezos.now;
          userCircle.lastCircle := s.currentCircle.counter;
          s.circleLoyalty[Tezos.sender] := userCircle;

          s.totalShares := abs(s.totalShares - args.shares);
          s.tezPool := abs(s.tezPool - tezDivested);
          s.tokenPool := abs(s.tokenPool - tokensDivested);
          s.invariant := if s.totalShares = 0n then 0n; else s.tezPool * s.tokenPool;

          case s.voters[Tezos.sender] of None -> skip
            | Some(v) -> {
              case v.candidate of None -> skip | Some(candidate) -> {
                const prevVotes: nat = get_force(candidate, s.votes);
                s.votes[candidate]:= abs(prevVotes - args.shares);
                if prevVotes = args.shares then remove Tezos.sender from map s.voters; else skip ;
              } end;
          } end;
          operations := list transaction(TransferType(this, (Tezos.sender, tokensDivested)), 
            0mutez,          
            case (Tezos.get_entrypoint_opt("%transfer", s.tokenAddress) : option(contract(transfer_type))) of Some(contr) -> contr
              | None -> (failwith("01"):contract(transfer_type))
            end
          ); 
          transaction(unit, tezDivested * 1mutez, (get_contract(Tezos.sender) : contract(unit))); end;
        } else failwith("Dex/wrong-out");
      } else failwith("Dex/wrong-params");
  }
  | SetVotesDelegation(n) -> failwith("00")
  | Vote(n) -> failwith("00")
  | Veto(voter) -> failwith("00")
  | WithdrawProfit(n) -> failwith("00")
  end
} with (operations, s)

function receiveReward (const p : dexAction ; const s : dex_storage ; const this: address) :  (list(operation) * dex_storage) is 
block {
  s.currentCircle.reward := s.currentCircle.reward + Tezos.amount / 1mutez;
  var operations : list(operation) := (nil: list(operation)); 
  if s.currentCircle.nextCircle < Tezos.now then block {
    s.currentCircle.nextCircle := Tezos.now;
    s.currentCircle.circleCoefficient := abs(Tezos.now - s.currentCircle.start) * s.currentCircle.reward / s.currentCircle.totalLoyalty + s.currentCircle.circleCoefficient;
    s.circles[s.currentCircle.counter] := s.currentCircle;
    s.currentCircle.reward := 0n;
    s.currentCircle.counter := s.currentCircle.counter + 1n;
    s.currentCircle.totalLoyalty := 0n;
    s.currentCircle.start := Tezos.now;
    s.currentCircle.nextCircle := Tezos.now + circlePeriod;
    if case s.delegated of None -> False
      | Some(delegated) ->
        case s.currentDelegated of None -> True
          | Some(currentDelegated) -> delegated =/= currentDelegated
        end
      end
    then {
       operations := set_delegate(s.delegated) # operations;
       s.currentDelegated := s.delegated;
       s.vetoVoters := (big_map end : big_map(address, nat));
       s.veto := 0n;
    } else skip ;
  } else skip ;
  s.currentCircle.totalLoyalty := s.currentCircle.totalLoyalty + abs(Tezos.now - s.currentCircle.lastUpdate) * s.totalShares;
  s.currentCircle.lastUpdate := Tezos.now;
} with (operations, s)

function withdrawProfit (const p : dexAction ; const s : dex_storage; const this: address) :  (list(operation) * dex_storage) is
block {
  var operations: list(operation) := list[];
  case p of
  | InitializeExchange(tokenAmount) -> failwith("00")
  | TezToTokenPayment(n) -> failwith("00")
  | TokenToTezPayment(n) -> failwith("00")
  | InvestLiquidity(minShares) -> failwith("00")
  | DivestLiquidity(n) -> failwith("00")
  | SetVotesDelegation(n) -> failwith("00")
  | Vote(n) -> failwith("00")
  | Veto(voter) -> failwith("00")
  | WithdrawProfit(n) -> {
    var userCircle : user_circle_info := get_force(Tezos.sender, s.circleLoyalty);
    var share : nat := get_force(Tezos.sender, s.shares);
    if userCircle.lastCircle =/= s.currentCircle.counter then {
      var circle : circle_info := get_force(userCircle.lastCircle, s.circles);
      userCircle.reward := userCircle.reward + circle.reward * (userCircle.loyalty + share * abs(circle.nextCircle - userCircle.lastCircleUpdate)) / circle.totalLoyalty;
      userCircle.loyalty := 0n;
      userCircle.lastCircleUpdate := circle.start;
    } else skip ;
    if s.currentCircle.counter - userCircle.lastCircle > 1 then {
      const lastFullCircle : circle_info = get_force(abs(s.currentCircle.counter - 1n), s.circles);
      const lastUserCircle : circle_info = get_force(userCircle.lastCircle, s.circles);
      userCircle.reward := userCircle.reward + share * abs(lastFullCircle.circleCoefficient - lastUserCircle.circleCoefficient);
    } else skip ;
    userCircle.loyalty := userCircle.loyalty + share * abs(Tezos.now-userCircle.lastCircleUpdate);
    userCircle.lastCircleUpdate := Tezos.now;
    userCircle.lastCircle := s.currentCircle.counter;
    share := userCircle.reward;
    userCircle.reward := 0n;
    s.circleLoyalty[Tezos.sender] := userCircle;
    operations := transaction(unit, share * 1mutez, (get_contract(n) : contract(unit))) # operations;
  }
  end
} with (operations, s)

function launchExchange (const self : address; const token : address; var s: exchange_storage ) :  (list(operation) * exchange_storage) is
block {
  if s.tokenList contains token then failwith("Factory/exchange-launched") else skip ;
    s.tokenList := Set.add (token, s.tokenList);
    const createDex : (option(key_hash) * tez * full_dex_storage) -> (operation * address) =
    [%Michelson ( {| { UNPPAIIR ;
                      CREATE_CONTRACT 
#include "Dex.tz"
                  ;
                        PAIR } |}
               : (option(key_hash) * tez * full_dex_storage) -> (operation * address))];
  const res : (operation * address) = createDex((None : option(key_hash)), 0tz, record 
    storage = 
       record      
          feeRate = 333n;      
          tezPool = 0n;      
          tokenPool = 0n;      
          invariant = 0n;      
          totalShares = 0n;      
          tokenAddress = token;      
          factoryAddress = self;      
          shares = (big_map end : big_map(address, nat));      
          voters = (big_map end : big_map(address, vote_info));      
          vetos = (big_map end : big_map(key_hash, timestamp));      
          vetoVoters = (big_map end : big_map(address, nat));      
          votes = (big_map end : big_map(key_hash, nat));      
          veto = 0n;      
          delegated = (None: option(key_hash));      
          currentDelegated = (None: option(key_hash));      
          totalVotes = 0n;      
          currentCircle = 
            record         
              reward = 0n;         
              counter = 0n;         
              start = Tezos.now; 
              circleCoefficient = 0n;        
              lastUpdate = Tezos.now;         
              totalLoyalty = 0n;         
              nextCircle = Tezos.now;       
            end;
          circles = (big_map end : big_map(nat, circle_info));      
          circleLoyalty = (big_map end : big_map(address, user_circle_info));   
       end;   
    lambdas = s.lambdas;
    end);
  s.tokenToExchange[token] := res.1;
 } with (list[res.0], s)

function setFunction (const idx: nat; const f: (dexAction * dex_storage * address) -> (list(operation) * dex_storage) ;const s : full_exchange_storage) : full_exchange_storage is
block {
  case s.storage.lambdas[idx] of 
    Some(n) -> failwith("Factory/function-set") 
    | None -> s.storage.lambdas[idx] := f 
  end;
} with s

function middle (const token : address ; var s : full_exchange_storage) :  (list(operation) * full_exchange_storage) is
block {
  const res : (list(operation) * exchange_storage) = case s.lambdas[0n] of 
    Some(f) -> f(Tezos.self_address, token, s.storage)
    | None -> (failwith("Factory/function-not-set"): (list(operation) * exchange_storage)) 
  end;
  s.storage := res.1;
} with (res.0, s)

function main (const p : exchangeAction ; const s : full_exchange_storage) :
  (list(operation) * full_exchange_storage) is case p of
  LaunchExchange(token) -> middle(token, s)
  | SetFunction(args) -> ((nil:list(operation)), if args.index > 9n then (failwith("Factory/wrong-index") : full_exchange_storage) else  setFunction(args.index, args.func, s))
 end
