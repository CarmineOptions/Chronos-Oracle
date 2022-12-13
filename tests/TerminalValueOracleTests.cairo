%lang starknet

from src.ITerminalValueOracle import ITerminalValueOracle
from openzeppelin.token.erc20.IERC20 import IERC20
from starkware.cairo.common.uint256 import Uint256, uint256_le
from src.terminal_value_oracle.structs import Update, Request, Reward
from examples.template_example import EMPIRIC_ORACLE_ADDRESS


namespace TerminalValueOracleTests {

    func deploy_setup{syscall_ptr: felt*, range_check_ptr}() {
        alloc_locals;

        tempvar admin_address;
        tempvar proxy_addr;
        tempvar eth_addr;
        %{

            context.admin_address = 123
            context.requesters_address = 321
            context.keepers_address = 213

            context.terminal_value_oracle_hash = declare(
                "src/terminal_value_oracle/main.cairo"
            ).class_hash       

            context.proxy_addr = deploy_contract(
                "src/proxy_contract/proxy.cairo",
                [context.terminal_value_oracle_hash, 0, 0]
            ).contract_address

            context.middleware_addr = deploy_contract(
                "examples/template_example.cairo"
            ).contract_address

            # Mints 1 ETH to requesters address
            context.eth_address = deploy_contract(
                "lib/cairo_contracts/src/openzeppelin/token/erc20/presets/ERC20Mintable.cairo",
                [1, 1, 18, 1 * 10**18, 0, context.requesters_address, context.admin_address]
            ).contract_address
            
            ids.proxy_addr = context.proxy_addr
            ids.admin_address = context.admin_address
            ids.eth_addr = context.eth_address

        %}

        ITerminalValueOracle.initializer(proxy_addr, admin_address);

        %{
            stop_prank_eth = start_prank(context.requesters_address, context.eth_address)
        %}

        let max_127bit_number = 0x80000000000000000000000000000000;
        let approve_amt = Uint256(low = max_127bit_number, high = max_127bit_number);
        IERC20.approve(contract_address=eth_addr, spender=proxy_addr, amount=approve_amt);

        %{
            stop_prank_eth()
        %}
        
            return ();
        }

    func test_register_request{syscall_ptr: felt*, range_check_ptr}() {
        alloc_locals;

        tempvar middleware_addr;
        tempvar proxy_addr;
        tempvar eth_addr;
        %{
            ids.middleware_addr = context.middleware_addr
            ids.proxy_addr = context.proxy_addr
            ids.eth_addr = context.eth_address

            stop_prank_oracle = start_prank(
                context.requesters_address,
                context.proxy_addr
            )
            
            stop_warp_1 = warp(0, target_contract_address=ids.proxy_addr)
        %}


        let reward_1 = Uint256(
            low = 100000000000000000,
            high = 0
        );

        // Register request
        let (idx_1) = ITerminalValueOracle.register_request(
            proxy_addr,
            10,
            middleware_addr,
            eth_addr,
            reward_1
        );

        // Assert it has been written in index 0 since it's first Request
        assert idx_1 = 0;

        let (usable_idx_1) = ITerminalValueOracle.get_active_requests_usable_index(proxy_addr, 0);

        // Assert that usable idx is 1
        assert usable_idx_1 = 1;

        let reward_2 = Uint256(
            low = 200000000000000000,
            high = 0
        );

        // Register second request
        let (idx_2) = ITerminalValueOracle.register_request(
            proxy_addr,
            20,
            middleware_addr,
            eth_addr,
            reward_2
        );

        // Assert it's been written at index 1 since it's second request
        assert idx_2 = 1;

        let (usable_idx_2) = ITerminalValueOracle.get_active_requests_usable_index(proxy_addr, 0);

        // Assert that usable idx is 1
        assert usable_idx_2 = 2;

        // Assert that the requests are stored correctly
        // Assert first request
        let reward_struct_1 = Reward (
            eth_addr,
            reward_1
        );

        let request_1 = Request (
            10,
            middleware_addr,
            reward_struct_1
        );

        let (stored_request_1) = ITerminalValueOracle.get_active_request(proxy_addr, 0);
        assert stored_request_1 = request_1;

        // Assert second request
        let reward_struct_2 = Reward (
            eth_addr,
            reward_2
        );

        let request_2 = Request (
            20,
            middleware_addr,
            reward_struct_2
        );

        let (stored_request_2) = ITerminalValueOracle.get_active_request(proxy_addr, 1);
        assert stored_request_2 = request_2;

        %{
            stop_prank_oracle()
            stop_warp_1()
        %}

        return ();
    }

    func test_update_request{syscall_ptr: felt*, range_check_ptr}() {
        alloc_locals;

        tempvar middleware_addr;
        tempvar proxy_addr;
        tempvar eth_addr;
        tempvar keepers_address;
        %{
            ids.middleware_addr = context.middleware_addr
            ids.proxy_addr = context.proxy_addr
            ids.eth_addr = context.eth_address
            ids.keepers_address = context.keepers_address

            stop_prank_oracle = start_prank(
                context.keepers_address,
                context.proxy_addr
            )
            
        %}

        // Create reward structs
        // Create first struct
        let rew_1 = Uint256(
            low = 100000000000000000,
            high = 0
        );
        let reward_struct_1 = Reward (
            eth_addr,
            rew_1
        );
        let request_1 = Request (
            10,
            middleware_addr,
            reward_struct_1
        );

        // Create second request
        let rew_2 = Uint256(
            low = 200000000000000000,
            high = 0
        );
        let reward_struct_2 = Reward (
            eth_addr,
            rew_2
        );
        let request_2 = Request (
            20,
            middleware_addr,
            reward_struct_2
        );

        // Fetch latest updates before updating
        let (latest_update_1_1) = ITerminalValueOracle.get_latest_update(proxy_addr, request_1);
        let (latest_update_2_1) = ITerminalValueOracle.get_latest_update(proxy_addr, request_2);

        assert latest_update_1_1.value = 0;
        assert latest_update_2_1.value = 0;

        assert latest_update_1_1.updater_address = 0;
        assert latest_update_2_1.updater_address = 0;

        %{
            stop_mock_current_price_1 = mock_call(
                ids.EMPIRIC_ORACLE_ADDRESS, "get_spot_median", [140000000000, 8, 0, 0]  # mock current ETH price at 1400
            )
            stop_warp_1 = warp(0, target_contract_address=ids.proxy_addr)
        %}

        // Update values
        ITerminalValueOracle.update_value(proxy_addr, request_1);
        ITerminalValueOracle.update_value(proxy_addr, request_2);

        // Fetch latest updates after updating
        let (latest_update_1_2) = ITerminalValueOracle.get_latest_update(proxy_addr, request_1);
        let (latest_update_2_2) = ITerminalValueOracle.get_latest_update(proxy_addr, request_2);

        assert latest_update_1_2.value = 140000000000;
        assert latest_update_2_2.value = 140000000000;

        assert latest_update_1_2.updater_address = keepers_address;
        assert latest_update_2_2.updater_address = keepers_address;

        assert latest_update_1_2.time_of_update = 0;
        assert latest_update_2_2.time_of_update = 0;

        %{
            stop_mock_current_price_1()
            stop_warp_1()

            stop_mock_current_price_2 = mock_call(
                ids.EMPIRIC_ORACLE_ADDRESS, "get_spot_median", [150000000000, 8, 0, 0]  # mock current ETH price at 1500
            )
            stop_warp_2 = warp(5, target_contract_address=ids.proxy_addr)
        %}

        // Update values again
        ITerminalValueOracle.update_value(proxy_addr, request_1);
        ITerminalValueOracle.update_value(proxy_addr, request_2);

        // Fetch latest updates after updating again
        let (latest_update_1_3) = ITerminalValueOracle.get_latest_update(proxy_addr, request_1);
        let (latest_update_2_3) = ITerminalValueOracle.get_latest_update(proxy_addr, request_2);

        assert latest_update_1_3.value = 150000000000;
        assert latest_update_2_3.value = 150000000000;

        assert latest_update_1_3.updater_address = keepers_address;
        assert latest_update_2_3.updater_address = keepers_address;

        assert latest_update_1_3.time_of_update = 5;
        assert latest_update_2_3.time_of_update = 5;

        %{
            stop_mock_current_price_2()
            stop_warp_2()
            stop_prank_oracle()
        %}

        return ();
    }

    func test_expire_requests{syscall_ptr: felt*, range_check_ptr}() {
        alloc_locals;
    
        tempvar proxy_addr;
        tempvar eth_addr;
        tempvar keepers_address;
        tempvar middleware_addr;

        %{
            ids.middleware_addr = context.middleware_addr
            ids.proxy_addr = context.proxy_addr
            ids.eth_addr = context.eth_address
            ids.keepers_address = context.keepers_address

            stop_prank_oracle = start_prank(
                context.keepers_address,
                context.proxy_addr
            )
            # Set time to after expiry of first request
            stop_warp_1 = warp(11, target_contract_address=ids.proxy_addr)
        %}

        // Create reward structs
        // Create first struct
        let rew_1 = Uint256(
            low = 100000000000000000,
            high = 0
        );
        let reward_struct_1 = Reward (
            eth_addr,
            rew_1
        );
        let request_1 = Request (
            10,
            middleware_addr,
            reward_struct_1
        );

        // Create second request
        let rew_2 = Uint256(
            low = 200000000000000000,
            high = 0
        );
        let reward_struct_2 = Reward (
            eth_addr,
            rew_2
        );
        let request_2 = Request (
            20,
            middleware_addr,
            reward_struct_2
        );

        // Create zero'd request
        let rew_3 = Uint256(
            low = 0,
            high = 0
        );
        let reward_struct_3 = Reward (
            0,
            rew_3
        );
        let request_3 = Request (
            0,
            0,
            reward_struct_3
        );

        // Expire first request
        ITerminalValueOracle.cashout_last_update(proxy_addr, 0);
        
        // Read the cashed out request at first index
        let (cashed_1) = ITerminalValueOracle.get_cashed_out_request(proxy_addr, 0);
        assert cashed_1 = request_1;
        
        // Read active request at first index to assert it is the seconds one since it's been moved to the left 
        let (active_1) = ITerminalValueOracle.get_active_request(proxy_addr, 0);
        assert active_1 = request_2;
        
        // Read active request at second index to assert it is zero'd
        let (active_2) = ITerminalValueOracle.get_active_request(proxy_addr, 1);
        assert active_2 = request_3;

        // Assert that keeper received the reward
        let (balance_keeper_1) = IERC20.balanceOf(
            eth_addr,
            keepers_address
        );

        assert balance_keeper_1.low = 100000000000000000;

        // Assert that oracle has only second request worth of ETH left
        let (balance_oracle_1) = IERC20.balanceOf(
            eth_addr,
            proxy_addr
        );

        assert balance_oracle_1.low = 200000000000000000;

        %{
            stop_warp_1()

            # Set time to after expiry of second request
            stop_warp_2 = warp(21, target_contract_address=ids.proxy_addr)
        %}

        // Expire second request which is now stored at index 0
        ITerminalValueOracle.cashout_last_update(proxy_addr, 0);
        
        // Read the cashed out request at second index
        let (cashed_2) = ITerminalValueOracle.get_cashed_out_request(proxy_addr, 1);
        assert cashed_2 = request_2;

        // Read active request at first index to assert it is zero'd
        let (active_3) = ITerminalValueOracle.get_active_request(proxy_addr, 0);
        assert active_3 = request_3;

        // Assert that keeper received the reward
        let (balance_keeper_2) = IERC20.balanceOf(
            eth_addr,
            keepers_address
        );
        assert balance_keeper_2.low = 300000000000000000;

        // Assert that oracle has none ETH left
        let (balance_oracle_2) = IERC20.balanceOf(
            eth_addr,
            proxy_addr
        );
        assert balance_oracle_2.low = 0;

        return ();
    }
    
}