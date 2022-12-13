%lang starknet 

const EMPIRIC_ORACLE_ADDRESS = 0x012fadd18ec1a23a160cc46981400160fbf4a7a5eed156c4669e39807265bcd4;
const EMPIRIC_ETH_USD_KEY = 19514442401534788;

@contract_interface
namespace IEmpiricOracle {
    func get_spot_median(pair_id: felt) -> (
        price: felt, decimals: felt, last_updated_timestamp: felt, num_sources_aggregated: felt
    ) {
    }
}

@view
func get_new_value{syscall_ptr: felt*, range_check_ptr}() -> (new_value: felt) {
    alloc_locals;

    let (
        price, decimals, last_updated_timestamp, num_sources_aggregated
    ) = IEmpiricOracle.get_spot_median(EMPIRIC_ORACLE_ADDRESS, EMPIRIC_ETH_USD_KEY);

    return(price,);
}
