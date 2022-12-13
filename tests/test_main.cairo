%lang starknet

from tests.TerminalValueOracleTests import TerminalValueOracleTests

from starkware.cairo.common.cairo_builtins import HashBuiltin

from src.ITerminalValueOracle import ITerminalValueOracle

@external
func __setup__{syscall_ptr: felt*, range_check_ptr}(){
    TerminalValueOracleTests.deploy_setup();
    return ();
}

@external
func test_terminal_value_oracle{syscall_ptr: felt*, range_check_ptr}(){

    TerminalValueOracleTests.test_register_request();
    TerminalValueOracleTests.test_update_request();
    TerminalValueOracleTests.test_expire_requests();

    return ();
}
