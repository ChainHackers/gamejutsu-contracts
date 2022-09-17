/*
  ________                           ____.       __
 /  _____/_____    _____   ____     |    |__ ___/  |_  ________ __
/   \  ___\__  \  /     \_/ __ \    |    |  |  \   __\/  ___/  |  \
\    \_\  \/ __ \|  Y Y  \  ___//\__|    |  |  /|  |  \___ \|  |  /
 \______  (____  /__|_|  /\___  >________|____/ |__| /____  >____/
        \/     \/      \/     \/                          \/
https://gamejutsu.app
*/
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/utils/cryptography/ECDSA.sol";
import "../interfaces/IGameJutsuRules.sol";
import "../interfaces/IGameJutsuArbiter.sol";

/**
    @title GameJutsu Arbiter
    @notice gets cheaters bang to rights
    @notice ETHOnline2022 submission by ChainHackers
    @notice 2 players only for now to make it doable during the hackathon
    @notice Major source of inspiration: https://magmo.com/force-move-games.pdf
    @author Gene A. Tsvigun
    @author Vic G. Larson
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


    struct Timeout {
        uint256 startTime;
        SignedGameMove signedMove;
        uint256 stake;
    }

    mapping(uint256 => Game) public games;
    mapping(uint256 => Timeout) public timeouts;
    uint256 public nextGameId;


    event GamesStarted(uint256 gameId, uint256 stake, address[2] players);
    event GameFinished(uint256 gameId, address winner, address loser, bool isDraw);
    event PlayerDisqualified(uint256 gameId, address player);
    event PlayerResigned(uint256 gameId, address player);
    event GameProposed(uint256 gameId, uint256 stake, address proposer);
    event SessionAddressRegistered(uint256 gameId, address player, address sessionAddress);

    constructor() {
        DOMAIN_SEPARATOR = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes("GameJutsu")), keccak256("0.1"), 137, 0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC, bytes32(0x920dfa98b3727bbfe860dd7341801f2e2a55cd7f637dea958edfc5df56c35e4d)));
    }

    //TODO private game proposal - after the hackathon
    function proposeGame(IGameJutsuRules rules, address[] calldata sessionAddresses) payable external returns (uint256 gameId) {
        gameId = nextGameId;
        games[gameId].rules = rules;
        games[gameId].players[msg.sender] = 1;
        games[gameId].playersArray[0] = msg.sender;
        games[gameId].stake = msg.value;
        nextGameId++;
        emit GameProposed(gameId, msg.value, msg.sender);
        if (sessionAddresses.length > 0) {
            for (uint256 i = 0; i < sessionAddresses.length; i++) {
                _registerSessionAddress(gameId, msg.sender, sessionAddresses[i]);
            }
        }
    }


    function acceptGame(uint256 gameId, address[] calldata sessionAddresses) payable external {
        require(games[gameId].players[msg.sender] == 0, "Arbiter: player already in game");
        require(games[gameId].started == false, "Arbiter: game already started");
        require(games[gameId].playersArray[0] != address(0), "Arbiter: game not proposed");
        require(games[gameId].stake <= msg.value, "Arbiter: stake mismatch");
        games[gameId].players[msg.sender] = 2;
        games[gameId].playersArray[1] = msg.sender;
        games[gameId].stake += msg.value;
        games[gameId].started = true;

        emit GamesStarted(gameId, games[gameId].stake, games[gameId].playersArray);
        if (sessionAddresses.length > 0) {
            for (uint256 i = 0; i < sessionAddresses.length; i++) {
                _registerSessionAddress(gameId, msg.sender, sessionAddresses[i]);
            }
        }
    }

    function registerSessionAddress(uint256 gameId, address sessionAddress) external {
        require(games[gameId].players[msg.sender] > 0, "Arbiter: player not in game");
        require(games[gameId].started == true, "Arbiter: game not started");
        _registerSessionAddress(gameId, msg.sender, sessionAddress);
    }

    function finishGame(SignedGameMove[] calldata signedMoves) external returns (address winner){
        require(_isSignedByAllPlayers(signedMoves[0]), "Arbiter: first move not signed by all players");
        address signer = recoverAddress(signedMoves[1].gameMove, signedMoves[1].signatures[0]);
        require(signer == signedMoves[1].gameMove.player, "Arbiter: first signature must belong to the player making the move");

        uint256 gameId = signedMoves[0].gameMove.gameId;
        require(_isGameOn(gameId), "Arbiter: game not active");
        require(signedMoves[1].gameMove.gameId == gameId, "Arbiter: game ids mismatch");
        require(signedMoves[1].gameMove.nonce == signedMoves[0].gameMove.nonce + 1, "Arbiter: nonce mismatch");
        require(_isValidGameMove(signedMoves[1].gameMove), "Arbiter: invalid game move");
        require(keccak256(signedMoves[0].gameMove.newState) == keccak256(signedMoves[1].gameMove.oldState), "Arbiter: game state mismatch");

        IGameJutsuRules.GameState memory newState = IGameJutsuRules.GameState(gameId, signedMoves[1].gameMove.nonce + 1, signedMoves[1].gameMove.newState);
        IGameJutsuRules rules = games[gameId].rules;
        require(rules.isFinal(newState), "Arbiter: game state not final");
        for (uint8 i = 0; i < NUM_PLAYERS; i++) {
            if (rules.isWin(newState, i)) {
                address winner = games[gameId].playersArray[i];
                address loser = games[gameId].playersArray[1 - i];
                _finishGame(gameId, winner, loser, false);
                return winner;
            }
        }
        _finishGame(gameId, address(0), address(0), true);
        return address(0);
    }

    function resign(uint256 gameId) external {
        require(_isGameOn(gameId), "Arbiter: game not active");
        require(games[gameId].players[msg.sender] != 0, "Arbiter: player not in game");
        uint8 playerIndex = games[gameId].players[msg.sender] - 1;
        address winner = games[gameId].playersArray[1 - playerIndex];
        address loser = games[gameId].playersArray[playerIndex];
        _finishGame(gameId, winner, loser, false);
        emit PlayerResigned(gameId, msg.sender);
    }

    //TODO add dispute move version based on comparison to previously signed moves
    function disputeMove(SignedGameMove calldata signedMove) external {
        require(signedMove.signatures.length > 0, "Arbiter: no signatures");
        GameMove calldata gm = signedMove.gameMove;
        address recoveredAddress = recoverAddress(gm, signedMove.signatures[0]);
        require(recoveredAddress == gm.player, "Arbiter: first signature must belong to the player making the move");
        require(!_isValidGameMove(gm), "Arbiter: valid move disputed");

        Game storage game = games[gm.gameId];
        require(game.started && !game.finished, "Arbiter: game not started yet or already finished");
        require(game.players[gm.player] != 0, "Arbiter: player not in game");

        disqualifyPlayer(gm.gameId, gm.player);
    }

    function disputeMoveWithHistory(SignedGameMove[2] calldata signedMoves) external {
        //TODO
    }

    function recoverAddress(GameMove calldata gameMove, bytes calldata signature) public view returns (address){
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

    function isPlayer(uint256 gameId, address player) external view returns (bool) {//TODO remove
        return games[gameId].players[player] != 0;
    }

    function getPlayerFromSignedGameMove(SignedGameMove calldata signedGameMove) external view returns (address) {
        return signedGameMove.gameMove.player;
    } //TODO remove


    /**
    @notice first move must be signed by both players
       */
    function initTimeout(SignedGameMove[2] calldata signedMove) payable external {
        //    TODO
    }

    function resolveTimeout(SignedGameMove calldata signedMove) external {
        //TODO extract common code to modifiers
        require(signedMove.signatures.length > 0, "Arbiter: no signatures");
        uint256 gameId = signedMove.gameMove.gameId;
        require(timeouts[gameId].startTime != 0, "Arbiter: timeout not started");
        require(timeouts[gameId].startTime + DEFAULT_TIMEOUT >= block.timestamp, "Arbiter: timeout expired");
        require(_isValidGameMove(signedMove.gameMove), "Arbiter: invalid signed move");

        Timeout storage timeout = timeouts[gameId];
        require(gameStatesEqual(
                IGameJutsuRules.GameState(timeout.signedMove.gameMove.gameId, timeout.signedMove.gameMove.nonce, timeout.signedMove.gameMove.newState),
                IGameJutsuRules.GameState(signedMove.gameMove.gameId, signedMove.gameMove.nonce, signedMove.gameMove.oldState)),
            "Arbiter: timeout move mismatch");

        address[] memory signers = getSigners(signedMove);
        require(signers.length > 0 && games[gameId].players[signers[1]] != 0, "Arbiter: signer not in game");
        //TODO verify it's signed by exactly the right player
        //TODO add whose move it is to the game state
        timeout.startTime = 0;
        //TODO name it better
    }

    function finalizeTimeout(uint256 gameId) external {
        require(timeouts[gameId].startTime != 0, "Arbiter: timeout not started");
        require(timeouts[gameId].startTime + DEFAULT_TIMEOUT < block.timestamp, "Arbiter: timeout not expired");

        //TODO disqualify the faulty player, end the game, send stake to the winner
    }

    function getPlayers(uint256 gameId) external view returns (address[2] memory){
        return games[gameId].playersArray;
    }

    /**
    @dev checks only state transition validity, all the signatures are checked elsewhere
    */
    function _isValidGameMove(GameMove calldata move) private view returns (bool) {
        Game storage game = games[move.gameId];
        IGameJutsuRules.GameState memory oldGameState = IGameJutsuRules.GameState(move.gameId, move.nonce, move.oldState);
        return keccak256(move.oldState) != keccak256(move.newState) &&
        game.started &&
        !game.finished &&
        game.players[move.player] != 0 &&
        game.rules.isValidMove(oldGameState, game.players[move.player] - 1, move.move) &&
        keccak256(game.rules.transition(oldGameState, game.players[move.player] - 1, move.move).state) == keccak256(move.newState);
    }

    function isValidGameMove(GameMove calldata signedMove) external view returns (bool) {
        return _isValidGameMove(signedMove);
    }

    function disqualifyPlayer(uint256 gameId, address cheater) private {
        require(games[gameId].players[cheater] != 0, "Arbiter: player not in game");
        games[gameId].finished = true;
        address winner = games[gameId].playersArray[0] == cheater ? games[gameId].playersArray[1] : games[gameId].playersArray[0];
        payable(winner).transfer(games[gameId].stake);
        emit GameFinished(gameId, winner, cheater, false);
        emit PlayerDisqualified(gameId, cheater);
    }

    function gameStatesEqual(IGameJutsuRules.GameState memory a, IGameJutsuRules.GameState memory b) private view returns (bool) {
        return a.gameId == b.gameId && a.nonce == b.nonce && keccak256(a.state) == keccak256(b.state);
    }

    function publicGetSigners(SignedGameMove calldata signedMove) external view returns (address[] memory) {
        return getSigners(signedMove);
    }

    function getSigners(SignedGameMove calldata signedMove) private view returns (address[] memory) {//TODO lib
        address[] memory signers = new address[](signedMove.signatures.length);
        for (uint256 i = 0; i < signedMove.signatures.length; i++) {
            signers[i] = recoverAddress(signedMove.gameMove, signedMove.signatures[i]);
        }
        return signers;
    }

    function _isGameOn(uint256 gameId) private view returns (bool) {
        return games[gameId].started && !games[gameId].finished;
    }

    function _isSignedByAllPlayers(SignedGameMove calldata signedMove) private view returns (bool) {
        address[] memory signers = getSigners(signedMove);
        if (signers.length != NUM_PLAYERS) {
            return false;
        }
        for (uint256 i = 0; i < signers.length; i++) {
            if (games[signedMove.gameMove.gameId].players[signers[i]] == 0) {
                return false;
            }
        }
        return true;
    }

    function _finishGame(uint256 gameId, address winner, address loser, bool draw) private {
        games[gameId].finished = true;
        if (draw) {
            uint256 half = games[gameId].stake / 2;
            uint256 theOtherHalf = games[gameId].stake - half;
            payable(games[gameId].playersArray[0]).transfer(half);
            payable(games[gameId].playersArray[1]).transfer(theOtherHalf);
        } else {
            payable(winner).transfer(games[gameId].stake);
        }
        emit GameFinished(gameId, winner, loser, draw);
    }

    function _registerSessionAddress(uint256 gameId, address player, address sessionAddress) private {
        games[gameId].players[sessionAddress] = games[gameId].players[player];
        emit SessionAddressRegistered(gameId, player, sessionAddress);
    }

    modifier firstMoveSignedByAll(SignedGameMove[2] calldata signedMoves) {
        require(_isSignedByAllPlayers(signedMoves[0]), "Arbiter: first move not signed by all players");
        _;
    }

    modifier lastMoveSignedByMover(SignedGameMove[2] calldata signedMoves) {
        address signer = recoverAddress(signedMoves[1].gameMove, signedMoves[1].signatures[0]);
        require(signer == signedMoves[1].gameMove.player, "Arbiter: first signature must belong to the player making the move");
        _;
    }
}
