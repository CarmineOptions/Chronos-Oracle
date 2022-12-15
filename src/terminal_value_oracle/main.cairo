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

from src.terminal_value_oracle.structs import Request, Update, Reward
from src.terminal_value_oracle.proxy_utils import (
    initializer,
    upgrade,
    getAdmin,
    setAdmin,
    getImplementationHash,
)

// Contract interface for the middleware contracts
@contract_interface
namespace IMiddlewareContract {
    func get_new_value() -> (new_value: felt) {
    }
}

// Contains the latest update for given Request
@storage_var
func latest_updates(request_info: Request) -> (latest_update: Update) {
}

// Contains the current requests that are not expired or cashed out
@storage_var
func active_requests(idx: felt) -> (request_info: Request) {
}

// Contains requests that are already cashed out
@storage_var
func cashed_out_requests(idx: felt) -> (request_info: Request) {
}

// Getter for active Requests based on the index
// Usefull for iteration over all active requests
@view
func get_active_request{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    idx: felt
) -> (request_info: Request) {
    let request_info = active_requests.read(idx);
    return request_info;
}

// Getter for cashed out Requests based on the index
// Usefull for iteration over all cashed out requests
@view
func get_cashed_out_request{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    idx: felt
) -> (request_info: Request) {
    let request_info = cashed_out_requests.read(idx);
    return request_info;
}

// Getter for latest update based on the Request
@view
func get_latest_update{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    request: Request
) -> (latest_update: Update) {
    let latest_update = latest_updates.read(request);
    return latest_update;
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
    with_attr error_message("Can't setup Request with expired maturity") {
        assert_le(current_block_time, maturity);
    }

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
    let (usable_idx) = get_active_requests_usable_index(0);

    active_requests.write(
        usable_idx,
        request
    );

    // Move reward from the caller to contract
    let (caller_address) = get_caller_address();
    let (own_address) = get_contract_address();
    IERC20.transferFrom(
        contract_address = reward_token_address,
        sender = caller_address,
        recipient = own_address,
        amount = reward_amount
    );

    return (usable_idx,);
}

// Function for cashing out, used by the last updater after from starkware.cairo.common.math import abs_value, assert_not_zero
// the Request has expired
@external
func cashout_last_update{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(idx: felt) {
    alloc_locals;

    let (request) = get_active_request(idx);

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

    // Delete request, since it has been paid
    deactivate_request(idx);

    return();
}

// Function for getting the first unused index in active requests storage_var
@view
func get_active_requests_usable_index{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr
}(
    starting_index: felt
) -> (usable_index: felt) {
    // Returns lowest index that does not contain any request
    alloc_locals;

    // Read request at provided index
    let (request) = active_requests.read(starting_index);

    // Make sure it is not an empty Request, since that would mean the end of
    // list is reached, in that case, return the index, since it is usable
    let request_sum = request.maturity + request.requested_address;
    if (request_sum == 0) {
        return (usable_index = starting_index);
    }
    
    // Continue to the next index until the end is reached
    let (usable_index) = get_active_requests_usable_index(starting_index + 1);

    return (usable_index = usable_index);
}

// Function for getting the first unused index in cashed_out requests storage_var
@view
func get_cashed_out_requests_usable_index{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr
}(
    starting_index: felt
) -> (usable_index: felt) {
    // Returns lowest index that does not contain any request
    alloc_locals;

    // Read request at provided index
    let (request) = cashed_out_requests.read(starting_index);

    // Make sure it is not an empty Request, since that would mean the end of
    // list is reached, in that case, return the index, since it is usable
    let request_sum = request.maturity + request.requested_address;
    if (request_sum == 0) {
        return (usable_index = starting_index);
    }
    
    // Continue to the next index until the end is reached
    let (usable_index) = get_cashed_out_requests_usable_index(starting_index + 1);

    return (usable_index = usable_index);
}

// Function for removing the request after it has been cashed out
func deactivate_request{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    index: felt
) {
    alloc_locals;

    // Read the request to be deactivated
    let (request_to_deactivate) = active_requests.read(index);

    // Get available index in cashed_out_requests
    let (available_cashed_out_index) = get_cashed_out_requests_usable_index(0);

    // Write new deactivated request to cashed_out_requests storage_var
    cashed_out_requests.write(
        available_cashed_out_index,
        request_to_deactivate
    );

    // Create active Request containing zeros and write it at the index in active requests
    let zero_reward = Reward(0, Uint256(0, 0));
    let zero_request = Request(0, 0, zero_reward);
    active_requests.write(index, zero_request);

    // Shift remaining active Requests to the left so there is not gap
    shift_active_requests(index);

    return ();
}

// Function for shifting requests to the left
func shift_active_requests{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    index: felt
) {
    alloc_locals;

    // Read request at given index, assert it contains zeros
    let (old_request) = active_requests.read(index);
    let old_request_sum = old_request.maturity + old_request.requested_address;
    assert old_request_sum = 0;

    // Read request at the next index, if it contains zeros as well, it means we're
    // at the end of the list
    let (next_request) = active_requests.read(index + 1);
    let next_request_sum = next_request.maturity + next_request.requested_address;
    if (next_request_sum == 0) {
        return();
    }

    // Write next Request at current index and zero Request at next index
    let zero_reward = Reward(0, Uint256(0, 0));
    let zero_request = Request(0, 0, zero_reward);
    
    active_requests.write(index, next_request);
    active_requests.write(index + 1, zero_request);

    // Continue to the next index
    shift_active_requests(index + 1);

    return ();
}
