pragma solidity ^0.4.17;

import "./Battle.sol";

contract Tournament {

    function name() external view returns(string); 

    event TournamentOpen(uint id, address creator, uint16 players);
    event TournamentBracket(uint id, address creator, address[] bracket);
    event TournamentMatch(uint id, uint battleId, address winner);
    event TournamentClosed(uint id, address[]results);
}

//a battle-royale esque tournament
//
contract SingleEliminationTournament is Tournament {

    function name() external view returns(string) {
        return "Single Elim";
    }

    TournamentBattle[] tournaments;

    struct TournamentBattle {
        Battle[] battles;
        uint8 requiredParticipants;
        uint entryFee;
        address[] participants;
        address[] bracket;
        uint64 bracketCreationBlock;
    }

    function SingleEliminationTournament() public {

    }

    // Tournaments should be inherently deflationary
    // can have up to 256 participants
    function createTournament(Battle _battle, uint8 _count, uint _fee) external {
        tournaments.push(TournamentBattle({
            entryFee: _fee,
            requiredParticipants: _count,
            bracket: new address[](0),
            participants: new address[](0),
            battleContract: _battle,
            bracketCreationBlock: 0
        }));
    }

    // must be called once
    // need to stop this being manipulated by one player
    // should resist collusion s.t. if one player is not co-operating
    // it is infeasible to create predictably stacked tournaments
    function createBracket(uint256 _tournamentId) external {
        TournamentBattle storage tournament = tournaments[_tournamentId];
        // tournament must be full
        require(tournament.participants.length == tournament.requiredParticipants);
        require(tournament.bracketCreationBlock == 0);
        tournament.bracketCreationBlock = uint64(block.number);

    }

    // call to reveal the bracket
    // can be called by anyone
    function revealBracket(uint256 _tournamentId) external {
        TournamentBattle storage tournament = tournaments[_tournamentId];
        // tournament must be full
        require(tournament.participants.length == tournament.requiredParticipants);
        require(tournament.bracketCreationBlock != 0);
        require(tournament.bracketCreationBlock < now);
        // if the bracket was created more than 64 blocks ago
        // just reset the process
        // don't have to worry about gaming when any player can call it 
        if (tournament.bracketCreationBlock + 64 < now) {
            tournament.bracketCreationBlock = 0;
            return;
        }
        bytes32 rand = block.blockhash(tournament.bracketCreationBlock + 1);
        // pick someone at random
        tournament.bracket = _shuffle(tournament.participants, rand);


        TournamentBracket(_tournamentId, msg.sender, tournament.bracket);
    }

    function _shuffle(address[] participants, bytes32 rand) pure internal returns (address[]) {
        address[] memory shuffled = new address[](participants.length);
        for (uint i = 0; i < participants.length; i++) {
            uint pos = uint(keccak256(rand, participants[i], i)) % participants.length;
            // will always find an open spot eventually
            for (uint j = pos; j < participants.length;) {
                if (shuffled[j] != address(0)) {
                    shuffled[j] = participants[i];
                    break;
                }
                // wrap around
                j = j < participants.length - 1 ? (j + 1) : 0;
            }
        }
    }

    function joinTournament(uint256 _tId) external payable {
        TournamentBattle storage tournament = tournaments[_tId];
        require(msg.value >= tournament.entryFee);
        // give refunds if over-spent
        if (msg.value > tournament.entryFee) {
            msg.sender.transfer(msg.value-tournament.entryFee);
        }
        // can't join a full tournament
        require(tournament.participants.length < tournament.requiredParticipants);
        // can't join a tournament twice
        for (uint i = 0; i < tournament.participants.length; i++) {
            address p = tournament.participants[i];
            require(msg.sender != p);
        }
        tournament.participants.push(msg.sender);
    }

    function reportResult(uint _tId, uint _bId) external {
       /* TournamentBattle storage tournament = tournaments[_tId];

        // require the correct participants
    
        // require the correct tournament id
        Battle b = tournament.batte

        // winner progresses - no draws!!
        address win = b.winnerOf(_bid);
        tournament.bracket[_bId] = win;
        */
    }

    function withdrawFromTournament(uint256 _tId) external {
        // can be called without cost up until bracket release?
    }

}
