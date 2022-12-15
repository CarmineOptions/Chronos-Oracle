%lang starknet

from starkware.starknet.common.syscalls import get_contract_address
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_le, assert_not_zero
from starkware.cairo.common.math_cmp import is_le
from starkware.starknet.common.syscalls import get_block_timestamp, get_caller_address
from starkware.cairo.common.uint256 import (
    Uint256,
    uint256_add,
    uint256_sub,
    uint256_le,
)

from openzeppelin.token.erc20.IERC20 import IERC20
from openzeppelin.upgrades.library import Proxy

from src.chronos_oracle.structs import Request, Update, Reward
from src.chronos_oracle.IMiddlewareContract import IMiddlewareContract
from src.chronos_oracle.proxy_utils import (
    initializer,
    upgrade,
    getAdmin,
    setAdmin,
    getImplementationHash,
)

// Event that is emitted when new Request is registered
@event
func RequestRegistered(
    idx: felt,
    maturity: felt,
    requested_address: felt,
    reward_token_address: felt,
    reward_token_amount: Uint256
) {
}

// Contains the latest update for given Request
@storage_var
func latest_updates(request_info: Request) -> (latest_update: Update) {
}

// Contains all of the requests
@storage_var
func requests(ids: felt) -> (request: Request) {
}

// Contains last index of requests storage_var
@storage_var
func requests_usable_idx() -> (last_idx: felt) {
}

// Getter for active Requests based on the index
// Usefull for iteration over all active requests
@view
func get_request{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    idx: felt
) -> (request_info: Request) {
    let (request_info) = requests.read(idx);
    return (request_info, );
}

// Getter for latest update based on the Request
@view
func get_latest_update{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    request: Request
) -> (latest_update: Update) {
    let latest_update = latest_updates.read(request);
    return latest_update;
}

// Getter for requests usable index
@view
func get_requests_usable_idx{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (last_idx: felt) {
    let last_idx = requests_usable_idx.read();
    return last_idx;
}

// Function for incrementing requests last index by one
func increment_requests_last_index{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    let (last_idx) = requests_usable_idx.read();
    let new_idx = last_idx + 1;

    requests_usable_idx.write(new_idx);
    return ();
}


// Function for updating the value 
// This is what the updater will be calling
@external 
func update_value{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(request: Request) {
    alloc_locals;

    // Assert that maturity is not reached yet 
    let (current_block_time) = get_block_timestamp();
    with_attr error_message("This request has already expired") {
        assert_le(current_block_time, request.maturity);
    }
    
    // Get new value    
    let (new_value) = IMiddlewareContract.get_new_value(
        request.requested_address
    );

    // Construct new Update and write it to storage_var
    let (updater_address) = get_caller_address();
    let new_update = Update (
        new_value,
        updater_address,
        current_block_time
    );

    latest_updates.write(
        request,
        new_update
    );
    
    return();
}

// Function for registering new Request
@external 
func register_request{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    maturity: felt,
    requested_address: felt,
    reward_token_address: felt,
    reward_amount: Uint256,
) -> (idx: felt) {
    alloc_locals;

    // Assert that requested maturity hasn't already expired
    let (current_block_time) = get_block_timestamp();
    with_attr error_message("Can't register Request with expired maturity") {
        assert_le(current_block_time, maturity);
    }

    // Create Reward struct
    let reward = Reward (
        reward_token_address,
        reward_amount
    );

    // Create new Request
    let request = Request (
        maturity,
        requested_address,
        reward
    );

    // Get usable index for new request and write it there
    let (usable_idx) = get_requests_usable_idx();

    requests.write(
        usable_idx,
        request
    );  
    
    // Increment last index of requests
    increment_requests_last_index();

    // Move reward from the caller to contract
    let (caller_address) = get_caller_address();
    let (own_address) = get_contract_address();
    IERC20.transferFrom(
        contract_address = reward_token_address,
        sender = caller_address,
        recipient = own_address,
        amount = reward_amount
    );

    RequestRegistered.emit(
        idx = usable_idx,
        maturity = maturity,
        requested_address = requested_address,
        reward_token_address = reward_token_address,
        reward_token_amount = reward_amount
    );

    return (usable_idx,);
}

// Function for cashing out, used by the last updater
// the Request has expired
@external
func cashout_last_update{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(idx: felt) {
    alloc_locals;

    let (request) = get_request(idx);

    // Assert that Request has already expired
    let (current_block_time) = get_block_timestamp();
    with_attr error_message("Request isn't expired yet") {
        assert_le(request.maturity, current_block_time);
    }

    // Assert that caller is the last updater
    let (latest_update) = latest_updates.read(request);
    let (caller_address) = get_caller_address();
    with_attr error_message("Caller isn't the last updater"){
        assert caller_address = latest_update.updater_address;
    }

    with_attr error_message("The latest update is empty") {
        let update_sum = latest_update.value + latest_update.updater_address + latest_update.time_of_update;      
        assert_not_zero(update_sum);
    }

    // Pay the reward
    IERC20.transfer(
        contract_address = request.reward.token_addr,
        recipient = latest_update.updater_address,
        amount = request.reward.amount
    );

    return();
}
