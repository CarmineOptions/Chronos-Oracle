%lang starknet

from starkware.cairo.common.uint256 import Uint256
from src.structs import Request, Update

@contract_interface
namespace ITerminalValueOracle {

    func get_active_request(idx: felt) -> (request_info: Request) {
    }

    func get_cashed_out_request(idx: felt) -> (request_info: Request) {
    }
    
    func get_latest_update(request: Request) -> (latest_update: Update) {
    }    

    func update_value(request: Request){
    }

    func register_request(maturity: felt, requested_address: felt, reward: Uint256) {
    }
    
    func cashout_last_update(idx: felt) {
    }    
    
    func get_active_requests_usable_index(starting_index: felt) -> (usable_index: felt) {
    }
    
    func get_cashed_out_requests_usable_index(starting_index: felt) -> (usable_index: felt) {
    }

}
