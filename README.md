# gamejutsu-contracts
GameJutsu framework to create on-chain arbiters for state channel based games

### Polygon mainnet contracts
Arbiter 👩🏽‍⚖️
https://polygonscan.com/address/0xc403667a1c550BFB365Aba91a5A6400308042378

TicTacToeRules ❎0️⃣ 
https://polygonscan.com/address/0xC6F81d6610A0b1bcb8cC11d50602D490b7624a96

CheckersRules 🙾🙾🙾🙾
https://polygonscan.com/address/0x8DA101325D14Afda3C0fF92F11e3f73d286b2776

### Entities
- The arbiter is a contract that is deployed on the blockchain and is used to resolve disputes between players.

## Differences with Magmo's ForceMove

### Movers and turns    

ForceMove protocol: the mover is fully determined by the turn number
> definition of `State::mover` introduces an important design decision of the ForceMove protocol:
> that the mover is fully determined by the turn number. Informally, using the fact that 
> `s.turnNum` must be incremented by 1, this rule states that players must take turns in a cyclical order.

GameJutsu protocol: the mover is determined by the game rules

### Simplifications
* Outcomes: win/loss or draw, in case of a draw the funds are split between the players

[//]: # (### Memos)
[//]: # (alternate moves)
