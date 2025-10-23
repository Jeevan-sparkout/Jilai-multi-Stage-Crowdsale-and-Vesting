// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

library JilaiPromoLibrary {
    struct PromoCode {
        string code;
        string description;
        uint8 promoType; // 0: FixedPrice, 1: BonusPercent
        uint256 value;  // Supports decimals (e.g., 5000000 = 0.05 for FixedPrice, 2500 = 25.00% for BonusPercent)
        uint256 expiration;
        bool isActive;
    }

    struct  PromoStorage {
        mapping(string => PromoCode) promoCodes;
        mapping(string => mapping(address => uint256)) promoUsage;
    }

    function addPromoCode(
        PromoStorage storage store,
        string memory _code,
        string memory _description,
        uint8 _promoType,
        uint256 _value,
        uint256 _expiration
    ) internal {
        require(bytes(_code).length > 0 && _expiration > block.timestamp && !store.promoCodes[_code].isActive, "Bad promo");
        require(_promoType <= 1, "Invalid promo type");
        require(_promoType == 0 ? (_value >= 1000000 && _value <= 10000000000) : (_value >= 100 && _value <= 10000), "Bad value");
        store.promoCodes[_code] = PromoCode(_code, _description, _promoType, _value, _expiration, true);
    }

    function updatePromoCode(
        PromoStorage storage store,
        string memory _code,
        string memory _description,
        uint8 _promoType,
        uint256 _value,
        uint256 _expiration,
        string memory _oldCode
    ) internal {
        require(bytes(_code).length > 0 && _expiration > block.timestamp, "Bad promo");
        require(_promoType <= 1, "Invalid promo type");
        require(_promoType == 0 ? (_value >= 1000000 && _value <= 10000000000) : (_value >= 100 && _value <= 10000), "Bad value");
        if (keccak256(abi.encodePacked(_oldCode)) != keccak256(abi.encodePacked(_code))) {
            require(!store.promoCodes[_code].isActive, "Code exists");
            delete store.promoCodes[_oldCode];
        }
        store.promoCodes[_code] = PromoCode(_code, _description, _promoType, _value, _expiration, true);
    }

    function deactivatePromoCode(PromoStorage storage store, string memory _code) internal {
        require(bytes(_code).length > 0, "Invalid promo ID");
        require(store.promoCodes[_code].isActive, "Inactive");
        store.promoCodes[_code].isActive = false;
    }

    function getPromoHistory(PromoStorage storage store, address _user, string memory _code) internal view returns (uint256) {
        require(bytes(_code).length > 0, "Invalid promo ID");
        return store.promoUsage[_code][_user];
    }

    function getPromoCode(PromoStorage storage store, string memory _code) internal view returns (PromoCode memory) {
        require(bytes(_code).length > 0, "Invalid promo code");
        return store.promoCodes[_code];
    }

    function isPromoCodeValid(PromoStorage storage store, string memory _code) internal view returns (bool) {
        if (bytes(_code).length == 0) return false;
        PromoCode memory promo = store.promoCodes[_code];
        return promo.isActive && promo.expiration > block.timestamp;
    }

    function applyPromoCode(
        PromoStorage storage store,
        string memory _promoCode,
        uint256 tokenAmount,
        uint256 rate
    ) internal  returns (uint256 newTokenAmount, uint256 newRate) {
        newTokenAmount = tokenAmount;
        newRate = rate;
        if (bytes(_promoCode).length > 0) {
            PromoCode storage promo = store.promoCodes[_promoCode];
            require(promo.isActive && promo.expiration > block.timestamp, "Bad promo");
            if (promo.promoType == 0) newRate = promo.value;
            else newTokenAmount = tokenAmount * (10000 + promo.value) / 10000; // Updated for decimals
            store.promoUsage[_promoCode][msg.sender]++;
        }
        return (newTokenAmount, newRate);
    }

    function applyPromoCodeView(
        PromoStorage storage store,
        string memory _promoCode,
        uint256 tokenAmount,
        uint256 rate
    ) internal view returns (uint256 newTokenAmount, uint256 newRate) {
        newTokenAmount = tokenAmount;
        newRate = rate;
        if (bytes(_promoCode).length > 0) {
            PromoCode memory promo = store.promoCodes[_promoCode];
            require(promo.isActive && promo.expiration > block.timestamp, "Bad promo");
            if (promo.promoType == 0) newRate = promo.value;
            else newTokenAmount = tokenAmount * (10000 + promo.value) / 10000;
        }
        return (newTokenAmount, newRate);
    }
}