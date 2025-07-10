// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

contract DLP is ERC20PresetMinterPauser {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bool public transferable = false; // Flag to control transferability
    mapping(address => bool) private whitelistedAddresses; // Mapping for whitelisted addresses

    event TransferableStatusChanged(bool newStatus);
    event AddressWhitelisted(address account);
    event AddressRemovedFromWhitelist(address account);

    constructor(
        string memory tokenName,
        string memory tokenSymbol
    ) ERC20PresetMinterPauser(tokenName, tokenSymbol) {
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "Caller is not an admin");
        _;
    }

    function toggleTransferable() external onlyAdmin {
        require(
            !transferable,
            "Transferability cannot be disabled once enabled"
        );
        transferable = true; // Once enabled, it stays enabled
        emit TransferableStatusChanged(transferable);
    }

    // Add an address to the whitelist
    function addToWhitelist(address account) external onlyAdmin {
        whitelistedAddresses[account] = true;
        emit AddressWhitelisted(account);
    }

    // Remove an address from the whitelist
    function removeFromWhitelist(address account) external onlyAdmin {
        whitelistedAddresses[account] = false;
        emit AddressRemovedFromWhitelist(account);
    }

    // Check if an address is whitelisted
    function isWhitelisted(address account) public view returns (bool) {
        return whitelistedAddresses[account];
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, amount);

        // Skip checks for minting and burning
        if (from == address(0) || to == address(0)) {
            return;
        }

        // Enforce transfer rules based on the transferable flag
        if (!transferable) {
            require(
                isWhitelisted(to),
                "Token transfers are restricted to whitelisted addresses"
            );
        }
    }
}