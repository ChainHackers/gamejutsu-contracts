// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/utils/cryptography/ECDSA.sol";
import "../interfaces/IGameJutsuRules.sol";
import "../interfaces/IGameJutsuArbiter.sol";

/**
    @notice 2 players only
*/
contract Arbiter is IGameJutsuArbiter {
    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)");
    bytes32 public immutable DOMAIN_SEPARATOR;
    /// @notice The EIP-712 typehash for the game move struct used by the contract
    bytes32 public constant GAME_MOVE_TYPEHASH = keccak256("GameMove(uint256 gameId,uint256 nonce,address player,bytes oldState,bytes newState,bytes move)");

    uint256 public DEFAULT_TIMEOUT = 5 minutes;
    uint256 public DEFAULT_TIMEOUT_STAKE = 0.1 ether;
    uint256 public NUM_PLAYERS = 2;

    struct Game {
        IGameJutsuRules rules;
        uint256 stake;
        bool started;
        bool finished;
        mapping(address => bool) players;
        address[2] playersArray;
    }

    struct Timeout {
        uint256 startTime;
        SignedGameMove signedMove;
        uint256 stake;
    }

    mapping(uint256 => Game) public games;
    mapping(uint256 => Timeout) public timeouts;
    uint256 public nextGameId;


    event StartGame(uint256 gameId);

    constructor() {
        DOMAIN_SEPARATOR = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes("GameJutsu")), keccak256("0.1"), 137, 0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC, bytes32(0x920dfa98b3727bbfe860dd7341801f2e2a55cd7f637dea958edfc5df56c35e4d)));
    }

    //TODO private game proposal - after the hackathon
    //TODO should gameId be in Game?
    function proposeGame(IGameJutsuRules rules) payable external returns (uint256 gameId) {
        gameId = nextGameId;
        games[gameId].rules = rules;
        games[gameId].players[msg.sender] = true;
        games[gameId].playersArray[0] = msg.sender;
        games[gameId].stake = msg.value;
        nextGameId++;
    }


    function acceptGame(uint256 gameId) payable external {
        require(games[gameId].players[msg.sender] == false, "Arbiter: player already in game");
        require(games[gameId].started == false, "Arbiter: game already started");
        require(games[gameId].stake <= msg.value, "Arbiter: stake mismatch");
        games[gameId].players[msg.sender] = true;
        games[gameId].playersArray[1] = msg.sender;
        games[gameId].stake += msg.value;
        games[gameId].started = true;

        emit StartGame(gameId);
    }

    function disputeMove(SignedGameMove calldata signedMove) external {
        require(signedMove.signatures.length > 0, "Arbiter: no signatures");
        GameMove calldata gm = signedMove.gameMove;
        address recoveredAddress = recoverAddress(gm, signedMove.signatures[0]);
        require(recoveredAddress == gm.player, "Arbiter: invalid signature");
        games[gm.gameId].players[gm.player] = false;

        //        require(!_isValidSignedMove(signedMove), "Arbiter: valid signed move disputed");
        //        require(games[signedMove.oldGameState.gameId].started && !games[signedMove.oldGameState.gameId].finished, "Arbiter: game not started or finished");

        //        bytes32 signedHash = ECDSA.toEthSignedMessageHash(abi.encode(signedMove.oldGameState, signedMove.newGameState, signedMove.move));
        //        uint256 gameId = signedMove.oldGameState.gameId;
        //        for (uint256 i = 0; i < NUM_PLAYERS; i++) {
        //            //TODO consider using other signatures
        //            address signer = ECDSA.recover(signedHash, signedMove.signatures[i]);
        //            if (games[gameId].players[signer]) {
        //                disqualifyPlayer(gameId, signer);
        //                return;
        //            }
        //        }
    }


    function recoverAddress(GameMove calldata gameMove, bytes calldata signature) public view returns(address){
//        https://codesandbox.io/s/gamejutsu-moves-eip712-no-nested-types-p5fnzf?file=/src/index.js
        bytes32 structHash = keccak256(abi.encode(
                GAME_MOVE_TYPEHASH,
                gameMove.gameId,
                gameMove.nonce,
                gameMove.player,
                keccak256(gameMove.oldState),
                keccak256(gameMove.newState),
                keccak256(gameMove.move)
            ));
        bytes32 digest = ECDSA.toTypedDataHash(DOMAIN_SEPARATOR, structHash);
        return ECDSA.recover(digest, signature);
    }

    function isPlayer(uint256 gameId, address player) external view returns (bool) { //TODO remove
        return games[gameId].players[player];
    }

    function getPlayerFromSignedGameMove(SignedGameMove calldata signedGameMove) external view returns (address) {
        return signedGameMove.gameMove.player;
    } //TODO remove

    //
    //    /**
    //        @notice only can be used for moved signed by both players
    //        TODO add a way to init timeout with only one signature
    //    */
    //    function initMoveTimeout(SignedMove calldata signedMove) payable external {
    //        require(signedMove.signatures.length == 2, "Arbiter: no signatures");
    //
    //        uint256 gameId = signedMove.oldGameState.gameId;
    //        for (uint256 i = 0; i < NUM_PLAYERS; i++) {
    //            bytes32 signedHash = ECDSA.toEthSignedMessageHash(abi.encode(signedMove.oldGameState, signedMove.newGameState, signedMove.move));
    //            //TODO move to lib
    //            address signer = ECDSA.recover(signedHash, signedMove.signatures[i]);
    //            require(games[gameId].players[signer], "Arbiter: signer not in game");
    //        }
    //
    //        //TODO extract common code to modifiers
    //        require(games[signedMove.oldGameState.gameId].started && !games[signedMove.oldGameState.gameId].finished, "Arbiter: game not started or finished");
    //        require(_isValidSignedMove(signedMove), "Arbiter: invalid signed move");
    //        require(msg.value >= DEFAULT_TIMEOUT_STAKE, "Arbiter: stake mismatch");
    //        require(timeouts[signedMove.oldGameState.gameId].startTime == 0, "Arbiter: timeout already started");
    //
    //        timeouts[gameId].startTime = block.timestamp;
    //        timeouts[gameId].signedMove = signedMove;
    //        timeouts[gameId].stake = msg.value;
    //    }
    //
    //    function resolveTimeout(SignedMove calldata signedMove) external {
    //        //TODO extract common code to modifiers
    //        require(signedMove.signatures.length > 0, "Arbiter: no signatures");
    //        uint256 gameId = signedMove.oldGameState.gameId;
    //        require(timeouts[gameId].startTime != 0, "Arbiter: timeout not started");
    //        require(timeouts[gameId].startTime + DEFAULT_TIMEOUT >= block.timestamp, "Arbiter: timeout expired");
    //        require(_isValidSignedMove(signedMove), "Arbiter: invalid signed move");
    //
    //        Timeout storage timeout = timeouts[gameId];
    //        require(gameStatesEqual(
    //                timeout.signedMove.newGameState,
    //                signedMove.oldGameState), "Arbiter: timeout move mismatch");
    //
    //        address[] memory signers = getSigners(signedMove);
    //        require(signers.length > 0 && games[gameId].players[signers[1]], "Arbiter: signer not in game");
    //        //TODO verify it's signed by exactly the right player
    //        //TODO add whose move it is to the game state
    //        timeout.startTime = 0;
    //        //TODO name it better
    //    }
    //
    //    function finalizeTimeout(uint256 gameId) external {
    //        require(timeouts[gameId].startTime != 0, "Arbiter: timeout not started");
    //        require(timeouts[gameId].startTime + DEFAULT_TIMEOUT < block.timestamp, "Arbiter: timeout not expired");
    //
    //        //TODO disqualify the faulty player, end the game, send stake to the winner
    //    }
    //
    function getPlayers(uint256 gameId) external view returns (address[2] memory){
        return games[gameId].playersArray;
    }
    //
    //    /**
    //        @dev checks only state transition validity, all the signatures are checked elsewhere
    //    */
    //    function _isValidSignedMove(SignedMove calldata signedMove) private view returns (bool) {
    //        uint256 gid = signedMove.oldGameState.gameId;
    //        return gid == signedMove.newGameState.gameId &&
    //        signedMove.oldGameState.nonce + 1 == signedMove.newGameState.nonce &&
    //        keccak256(signedMove.oldGameState.state) != keccak256(signedMove.newGameState.state) &&
    //        games[gid].started &&
    //        !games[gid].finished &&
    //        games[gid].rules.isValidMove(signedMove.oldGameState, signedMove.move) &&
    //        keccak256(games[gid].rules.transition(signedMove.oldGameState, signedMove.move).state) == keccak256(signedMove.newGameState.state);
    //    }
    //
    //    function isValidSignedMove(SignedMove calldata signedMove) external view returns (bool) {
    //        return _isValidSignedMove(signedMove);
    //    }
    //
    //    function disqualifyPlayer(uint256 gameId, address player) private {
    //        require(games[gameId].players[player], "Arbiter: player not in game");
    //        games[gameId].finished = true;
    //        address winner = games[gameId].playersArray[0] == player ? games[gameId].playersArray[1] : games[gameId].playersArray[0];
    //        payable(winner).transfer(games[gameId].stake);
    //    }
    //
    //    function gameStatesEqual(IGameJutsuRules.GameState storage a, IGameJutsuRules.GameState calldata b) private view returns (bool) {
    //        return a.gameId == b.gameId && a.nonce == b.nonce && keccak256(a.state) == keccak256(b.state);
    //    }
    //
    //    function getSigners(SignedMove calldata signedMove) private pure returns (address[] memory) {//TODO lib
    //        address[] memory signers = new address[](signedMove.signatures.length);
    //        for (uint256 i = 0; i < signedMove.signatures.length; i++) {
    //            bytes32 signedHash = ECDSA.toEthSignedMessageHash(abi.encode(signedMove.oldGameState, signedMove.newGameState, signedMove.move));
    //            signers[i] = ECDSA.recover(signedHash, signedMove.signatures[i]);
    //        }
    //        return signers;
    //    }
}
