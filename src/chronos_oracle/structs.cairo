%lang starknet

from starkware.cairo.common.uint256 import Uint256


// Reward struct, containing information about the reward
struct Reward {
    token_addr: felt,
    amount: Uint256,
}

// The Request struct containing information about the request
struct Request {
    is_active: felt,
    maturity: felt,
    requested_address: felt,
    reward: Reward,
}

// The Update struct containig the updated value and the updater's address
struct Update {
    value: felt,
    updater_address: felt,
    time_of_update: felt,
}
