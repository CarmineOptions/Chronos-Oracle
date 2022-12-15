%lang starknet

from tests.ChronosOracleTests import ChronosOracleTests

from starkware.cairo.common.cairo_builtins import HashBuiltin

@external
func __setup__{syscall_ptr: felt*, range_check_ptr}(){
    ChronosOracleTests.deploy_setup();
    return ();
}

@external
func test_chronos_oracle{syscall_ptr: felt*, range_check_ptr}(){

    ChronosOracleTests.test_register_request();
    ChronosOracleTests.test_update_request();
    ChronosOracleTests.test_expire_requests();

    return ();
}
