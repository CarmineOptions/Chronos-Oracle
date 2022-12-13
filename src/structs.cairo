%lang starknet

from starkware.cairo.common.uint256 import Uint256

// The Request struct containing information about the request
struct Request {
    maturity: felt,
    requested_address: felt,
    reward: Uint256,
}

// The Update struct containig the updated value and the updater's address
struct Update {
    value: felt,
    updater_address: felt,
    time_of_update: felt,
}