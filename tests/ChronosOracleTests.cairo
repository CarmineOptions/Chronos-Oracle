%lang starknet

from starkware.cairo.common.uint256 import Uint256, uint256_le
from starkware.cairo.common.bool import TRUE, FALSE

from openzeppelin.token.erc20.IERC20 import IERC20

from src.IChronosOracle import IChronosOracle
from src.chronos_oracle.structs import Update, Request, Reward
from examples.template_example import EMPIRIC_ORACLE_ADDRESS

namespace ChronosOracleTests {

    func deploy_setup{syscall_ptr: felt*, range_check_ptr}() {
        alloc_locals;

        tempvar admin_address;
        tempvar proxy_addr;
        tempvar eth_addr;
        %{

            context.admin_address = 123
            context.requesters_address = 321
            context.keepers_address = 213

            context.chronos_oracle_hash = declare(
                "src/chronos_oracle/main.cairo"
            ).class_hash       

            context.proxy_addr = deploy_contract(
                "src/proxy_contract/proxy.cairo",
                [context.chronos_oracle_hash, 0, 0]
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

        IChronosOracle.initializer(proxy_addr, admin_address);

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

            # Expect RequestRegistered events
            expect_events(
                # First Request
                {
                    "name" : "RequestRegistered",
                    "data" : [0, 10, context.middleware_addr, context.eth_address, 100000000000000000, 0]
                },
                # Seconds Request
                {
                    "name" : "RequestRegistered",
                    "data" : [1, 20, context.middleware_addr, context.eth_address, 200000000000000000, 0]
                },
            )

        %}


        let reward_1 = Uint256(
            low = 100000000000000000,
            high = 0
        );

        // Assert that first usable index is 0
        let (usable_idx_0) = IChronosOracle.get_requests_usable_idx(proxy_addr);

        // Assert that usable idx is 1
        assert usable_idx_0 = 0;

        // Register request
        let (idx_1) = IChronosOracle.register_request(
            proxy_addr,
            10,
            middleware_addr,
            eth_addr,
            reward_1
        );

        // Assert it has been written in index 0 since it's first Request
        assert idx_1 = 0;

        let (usable_idx_1) = IChronosOracle.get_requests_usable_idx(proxy_addr);

        // Assert that usable idx is 1
        assert usable_idx_1 = 1;

        let reward_2 = Uint256(
            low = 200000000000000000,
            high = 0
        );

        // Register second request
        let (idx_2) = IChronosOracle.register_request(
            proxy_addr,
            20,
            middleware_addr,
            eth_addr,
            reward_2
        );

        // Assert it's been written at index 1 since it's second request
        assert idx_2 = 1;

        let (usable_idx_2) = IChronosOracle.get_requests_usable_idx(proxy_addr);

        // Assert that usable idx is 1
        assert usable_idx_2 = 2;

        // Assert that the requests are stored correctly
        // Assert first request
        let reward_struct_1 = Reward (
            eth_addr,
            reward_1
        );

        let request_1 = Request (
            TRUE,
            10,
            middleware_addr,
            reward_struct_1
        );

        let (stored_request_1) = IChronosOracle.get_request(proxy_addr, 0);
        assert stored_request_1 = request_1;

        // Assert second request
        let reward_struct_2 = Reward (
            eth_addr,
            reward_2
        );

        let request_2 = Request (
            TRUE,
            20,
            middleware_addr,
            reward_struct_2
        );

        let (stored_request_2) = IChronosOracle.get_request(proxy_addr, 1);
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
            TRUE,
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
            TRUE,
            20,
            middleware_addr,
            reward_struct_2
        );

        // Fetch latest updates before updating
        let (latest_update_1_1) = IChronosOracle.get_latest_update(proxy_addr, request_1);
        let (latest_update_2_1) = IChronosOracle.get_latest_update(proxy_addr, request_2);

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
        IChronosOracle.update_value(proxy_addr, request_1);
        IChronosOracle.update_value(proxy_addr, request_2);

        // Fetch latest updates after updating
        let (latest_update_1_2) = IChronosOracle.get_latest_update(proxy_addr, request_1);
        let (latest_update_2_2) = IChronosOracle.get_latest_update(proxy_addr, request_2);

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
        IChronosOracle.update_value(proxy_addr, request_1);
        IChronosOracle.update_value(proxy_addr, request_2);

        // Fetch latest updates after updating again
        let (latest_update_1_3) = IChronosOracle.get_latest_update(proxy_addr, request_1);
        let (latest_update_2_3) = IChronosOracle.get_latest_update(proxy_addr, request_2);

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

        // Create first request
        let rew_1 = Uint256(
            low = 100000000000000000,
            high = 0
        );
        let reward_struct_1 = Reward (
            eth_addr,
            rew_1
        );
        let request_1 = Request (
            FALSE,
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
            FALSE,
            20,
            middleware_addr,
            reward_struct_2
        );

        // Expire first request
        IChronosOracle.cashout_last_update(proxy_addr, 0);

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

        // Expire second request at index 1
        IChronosOracle.cashout_last_update(proxy_addr, 1);

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

        // Test that active requests usable index is 2
        let (usable_idx) = IChronosOracle.get_requests_usable_idx(proxy_addr);
        assert usable_idx = 2;
        
        // Assert that the requests are not active
        let (stored_request_1) = IChronosOracle.get_request(proxy_addr, 0);
        assert stored_request_1.is_active = FALSE;

        let (stored_request_2) = IChronosOracle.get_request(proxy_addr, 1);
        assert stored_request_2.is_active = FALSE;
        
        %{
            stop_warp_1()
            stop_prank_oracle()
        %}
        return ();
    }

    func test_expire_request_again{syscall_ptr: felt*, range_check_ptr}() {
        tempvar proxy_addr;

        %{
            ids.proxy_addr = context.proxy_addr
            stop_prank_oracle = start_prank(
                context.keepers_address,
                context.proxy_addr
            )
            
            # Set time to after expiry of first request
            stop_warp_1 = warp(11, target_contract_address=ids.proxy_addr)

            expect_revert(error_message = "Request has already been cashed out")
        %}

        // Expire first request
        IChronosOracle.cashout_last_update(proxy_addr, 0);

        return ();
    }

}