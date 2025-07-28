// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../Lib/Erc721/ERC721Common.sol";

contract MetalendPremiumUser is ERC721Common {
    bool public burnAllowed;

    constructor(string memory name, string memory symbol, string memory baseTokenURI) 
        ERC721Common(name, symbol, baseTokenURI) { }

    /**
     * @dev Override `ERC721-_mintFor`. 
     *
     * Disallow minting from users without the MINTER role.
     */
    function _mintFor(address to) public virtual override returns (uint256 _tokenId) {
        require(hasRole(MINTER_ROLE, _msgSender()), "ERC721PresetMinterPauserAutoId: must have minter role to mint");
        return super._mintFor(to);
    }

    /**
     * @dev Override `ERC721-burn`.
     *
     * Burning is gated by burnAllowed flag.
     */
    function burn(uint256 _tokenId) public virtual override {
        require(burnAllowed, "Burning tokens is currently disabled");
        super.burn(_tokenId);
    }

    /**
     * @dev Toggle burnAllowed flag.
     *
     * Can only be called by the MINTER role.
     */
    function toggleBurnAllowed() public {
        require(hasRole(MINTER_ROLE, _msgSender()), "Must have minter role to toggle burn support");
        burnAllowed = !burnAllowed;
    }
}
