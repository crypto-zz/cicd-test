pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "../../Interface/ERC721Interface.sol";

/**
 * @title Mystic Gene Validator
 * @notice Checks whether an Axie is a Mystic by its gene encoding
 * @author MetaLend
 *
 *
 *
 * Axie contract -> "axie" function
 * - sireId (uint256)
 * - matronId (uint256)
 * - birthDate (uint256)
 * - genes (tuple <uint256> (x, y))
 * - breedcount (uint8)
 * - level (uint16)
 *
 * 11667961 (non-mystic)
 * x - 10855508365998394927922427935567715042248759228317674044947433100505725878794
 * y - 1767065298282497008884989868731331295688508682653146472075214179109192200
 *
 * 1977 (mystic)
 * x - 4820857198531518307888058540508535301036736021094617480970500
 * y - 3775261573542669353758677087094926866886258640520266430239476098826754
 *
 * 5582 (mystic)
 * x - 4820875480630508613826305562772492079513039992161148805857284
 * y - 3883127685082867167169365761511604326568680154825715919621767311688962
 *
 */

 interface IAxie {
    function axie(uint256 axieId) external view returns (
        uint256 sireId,
        uint256 matronId,
        uint256 birthDate,
        uint256[2] memory genes,
        uint8 breedCount,
        uint16 level
    );
}

contract MysticGeneValidator {
    uint256 internal constant _PART_MASK = 2 ** 64 - 1;
    uint256 internal constant _SKIN_MASK = 2**9 - 1;

    IAxie public axieContract;

    constructor(IAxie _axieContract) public {
        axieContract = _axieContract;
    }

    function isMystic(uint256 axieId) public view returns (bool) {
        (,,, uint256[2] memory genes,,) = axieContract.axie(axieId);
        uint256 x = genes[0];
        uint256 y = genes[1];
        return isMystic(x, y);
    }
    
    function isMystic(uint256 x, uint256 y) public pure returns (bool) {
        uint256 partEyes = (x >> (64 * 1)) & _PART_MASK;
        uint256 partMouth = (x >> (64 * 0)) & _PART_MASK;
        uint256 partEars = (y >> (64 * 3)) & _PART_MASK;
        uint256 partHorn = (y >> (64 * 2)) & _PART_MASK;
        uint256 partBack = (y >> (64 * 1)) & _PART_MASK;
        uint256 partTail = (y >> (64 * 0)) & _PART_MASK;

        bool isMysticEyes = isMysticPart(partEyes);
        bool isMysticMouth = isMysticPart(partMouth);
        bool isMysticEars = isMysticPart(partEars);
        bool isMysticHorn = isMysticPart(partHorn);
        bool isMysticBack = isMysticPart(partBack);
        bool isMysticTail = isMysticPart(partTail);
        return isMysticEyes || isMysticMouth || isMysticEars || isMysticHorn || isMysticBack || isMysticTail;
    }

    function getPartSkin(uint256 partGenes) internal pure returns (uint256) {
        return (partGenes >> 39) & _SKIN_MASK;
    }

    function isMysticPart(uint256 partGenes) internal pure returns (bool) {
        return getPartSkin(partGenes) == 1;
    }
}
