%lang starknet

from starkware.cairo.common.uint256 import Uint256
from src.chronos_oracle.structs import Request, Update

@contract_interface
namespace IChronosOracle {

    func get_request(idx: felt) -> (request_info: Request) {
    }

    func get_latest_update(request: Request) -> (latest_update: Update) {
    }    

    func update_value(request: Request){
    }

    func register_request(maturity: felt, requested_address: felt, reward_token_address: felt, reward_amount: Uint256) -> (idx: felt) {
    }
    
    func cashout_last_update(idx: felt) {
    }    
    
    func get_requests_usable_idx() -> (usable_idx: felt) {
    }
    
    func initializer(proxy_admin: felt) {
    }

    func upgrade(new_implementation: felt) {
    }

    func getAdmin() -> (address: felt) {
    }

    func setAdmin(address: felt) {
    }
    
    func getImplementationHash() -> (implementation_hash: felt) {
    }

}
