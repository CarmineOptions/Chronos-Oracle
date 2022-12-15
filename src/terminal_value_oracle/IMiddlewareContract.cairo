%lang starknet

// Contract interface for the middleware contracts
@contract_interface
namespace IMiddlewareContract {
    func get_new_value() -> (new_value: felt) {
    }
}
