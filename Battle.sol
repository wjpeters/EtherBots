pragma solidity ^0.4.17;

contract Battle {
    // This struct does not exist outside the context of a battle

    // the name of the battle type
    function name() external view returns (string);
    // the number of robots currently battling
    function playerCount() external view returns (uint count);
    // creates a new battle, with a submitted user string for initial input/
    function createBattle(uint[] partIds, bytes32 commit, uint64 duration) external;
    // cancels the battle at battleID
    function cancelBattle(uint battleID) external;

    // TODO: parameters for these: as generic as possible
    // favour over-reporting/flexibility
    event BattleCreated(uint indexed battleID, address indexed starter);
    event BattleStage(uint indexed battleID);
    event BattleEnded(uint indexed battleID, address indexed winner);
    event BattleConcluded(uint indexed battleID);
    event BattlePropertyChanged(string name, uint previous, uint value);
}
