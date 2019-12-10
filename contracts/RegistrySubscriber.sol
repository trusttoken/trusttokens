import "./ClaimableContract.sol";

contract RegistrySubscriber is ClaimableContract {
    // Registry Attributes
    bytes32 constant PASSED_KYCAML = "hasPassedKYC/AML";
    bytes32 constant IS_DEPOSIT_ADDRESS = "isDepositAddress";
    bytes32 constant BLACKLISTED = 0x6973426c61636b6c697374656400000000000000000000000000000000000000;
    bytes32 constant REGISTERED_CONTRACT = 0x697352656769737465726564436f6e7472616374000000000000000000000000;

    // attributes Bitmasks
    bytes32 constant ACCOUNT_BLACKLISTED = 0xff00000000000000000000000000000000000000000000000000000000000000;
    bytes32 constant ACCOUNT_KYC         = 0x00ff000000000000000000000000000000000000000000000000000000000000;
    bytes32 constant ACCOUNT_ADDRESS     = 0x000000000000000000000000ffffffffffffffffffffffffffffffffffffffff;
    bytes32 constant ACCOUNT_HOOK        = 0x0000ff0000000000000000000000000000000000000000000000000000000000;

    function registry() internal view returns (Registry);

    modifier onlyRegistry {
        require(msg.sender == address(registry()));
        _;
    }

    /**
        Attributes are set per autosweep account
        The layout of attributes is detailed here
        lower bytes -> upper bytes
        [0,20) recipient address
        [30, 31) PASSED_KYCAML
        [31, 32) BLACKLISTED
    */
    function syncAttributeValue(address _who, bytes32 _attribute, uint256 _value) public onlyRegistry {
        uint144 who = uint144(uint160(_who) >> 20);
        if (_attribute == IS_DEPOSIT_ADDRESS) {
            attributes[who] = (attributes[who] & address(0)) | uint256(address(_value));
        } else if (_attribute == BLACKLISTED) {
            if (_value) {
                attributes[who] |= ACCOUNT_BLACKLISTED;
            } else  {
                attributes[who] &= 0x00ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
            }
        } else if (_attribute == PASSED_KYCAML) {
            if (_value) {
                attributes[who] |= ACCOUNT_KYC;
            } else {
                attributes[who] &= 0xff00ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
            }
        } else if (_attribute == REGISTERED_CONTRACT) {
            if (_value) {
                attributes[who] |= ACCOUNT_HOOK;
            } else {
                attributes[who] &= 0xffff00ffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
            }
        }
    }
}
