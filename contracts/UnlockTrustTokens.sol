pragma solidity ^0.5.13;

import "./TrustToken.sol";

import "openzeppelin-solidity/contracts/token/ERC721/IERC721.sol";
import "openzeppelin-solidity/contracts/token/ERC721/IERC721Receiver.sol";
import "openzeppelin-solidity/contracts/utils/Address.sol";

/**
 * TrustToken Unlocking
 * 1. Vault contract is deployed
 * 2. TrustTokens are minted and transferred to vault
 * 3. Unlock contract is deployed
 * 4. Token unlocks are scheduled
 * 
 * Unlock transfers can only be called by the owner
 */

contract Ownable {
    address public owner;
    address public pendingOwner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function transferOwnership(address newOwner) public onlyOwner {
        pendingOwner = newOwner;
    }

    function claimOwnership() public onlyPendingOwner {
        emit OwnershipTransferred(owner, pendingOwner);
        owner = pendingOwner;
        pendingOwner = address(0);
    }

    function renounceOwnership() public onlyOwner {
        emit OwnershipTransferred(owner, address(0));
        owner = address(0);
        pendingOwner = address(0);
    }

    modifier onlyPendingOwner() {
        require(msg.sender == pendingOwner, "only pending owner");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "only owner");
        _;
    }
}

/**
 * @title TrustTokenVault
 * @dev Holds TrustTokens for unlocking contract.
 * TrustTokens are deposited into the vault and withdrawn directly to recipients.
 * This allows the cancellation of scheduled unlocks.
 */
contract TrustTokenVault is Ownable {
    uint256 balance;
    bool minted;
    uint256 constant MINT_AMOUNT = 100000000000000; // 1 million trusttokens

    // Vault Events
    event TrustTokensMinted(uint256 amount);

    constructor() public {
        owner = msg.sender;
        minted = false;
        token().approve(address(this), MINT_AMOUNT);
    }

    function token() internal view returns (TrustToken);

    function vaultBalance() public view returns (uint256) {
        return balance;
    }

    function symbol() public view returns (string memory) {
        return token().symbol();
    }

    function transfer(address _to, uint256 _amount) external onlyOwner {
        token().transfer(_to, _amount);
        balance -= _amount;
    }

    /**
     * @dev Mint MINT_AMOUNT of trusttokens and flag as minted
     * Can only mint TrustTokens once.
     */
    function mintTrustTokens() external onlyOwner {
        require(minted == false, "trusttokens already minted");
        token().mint(address(this), MINT_AMOUNT);
        balance = MINT_AMOUNT;
        minted = true;
        emit TrustTokensMinted(MINT_AMOUNT);
    }

    function claimTokenOwnership() external onlyOwner {
        token().claimOwnership();
    }
}

/**
 * @title UnlockTrustTokens
 * @dev This Unlock contract allows a token issuer to issue tokens in the future.
 * If a mistake is made in the process, the issuer can cancel the unlock and reissue.
 * The issuer is expectedd to renounce their ownership after checking all of the pending unlocks in order to protect the token pool
 * A pending unlock is an ERC721 token
 * Once claimed, unlock token is "burned" by setting recipient to address(0)
 * IERC721 is not implemented because of the current solidity behavior that public members conflict with public functions of the same name
 */
contract UnlockTrustTokens is Ownable /*is IERC721*/ {
    using Address for address;

    uint256 burnCount;
    mapping (address => uint256) public balanceOf;
    mapping (address => mapping (address => bool)) public isApprovedForAll;
    mapping (uint256 => address) public getApproved;

    struct UnlockOperation {
        address recipient;
        uint256 amount;
        uint256 activation;
    }
    UnlockOperation[] public unlockOperations;

    constructor() public {
        owner = msg.sender;
    }

    function unlockOperationCount() public view returns (uint256) {
        return unlockOperations.length;
    }

    function totalSupply() public view returns (uint256) {
        // unlockOperations.length cannot be greater than burnCount
        return unlockOperations.length - burnCount;
    }
    function ownerOf(uint256 tokenId) public view returns (address) {
        return unlockOperations[tokenId].recipient;
    }

    function vault() internal view returns (TrustTokenVault);

    bytes4 private constant ERC721_RECEIVED = 0x150b7a02;
    
    // ERC721
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    
    // Unlock
    event UnlockScheduled(uint256 indexed tokenId, address indexed recipient, uint256 indexed amount, uint256 activation);
    event UnlockCancelled(uint256 indexed tokenId);
    event UnlockClaimed(uint256 indexed tokenId, address indexed beneficiary);


    function claimVaultOwnership() public onlyOwner {
        vault().claimTokenOwnership();
    }

    /**
     * @dev Schedule a token unlock at a specific time
     * @param recipient Recipient for unlock
     * @param amount Amount to unlock
     * @param activationTime Time which we want to activate claim
     */
    function scheduleUnlock(address recipient, uint256 amount, uint256 activationTime) external onlyOwner returns (uint256) {
        uint256 id = unlockOperations.length;
        emit UnlockScheduled(id, recipient, amount, activationTime);
        emit Transfer(address(0), recipient, id);
        balanceOf[recipient]++;
        unlockOperations.push(UnlockOperation(
            recipient, amount, activationTime
        ));
        return id;
    }

    /**
     * @dev Cancel token unlock for a specific ID
     * @param id Token id to cancel unlock for
     */
    function cancelUnlock(uint256 id) external onlyOwner {
        address prior = unlockOperations[id].recipient;
        require(prior != address(0));
        emit UnlockCancelled(id);
        emit Transfer(prior, address(0), id);
        balanceOf[prior]--;
        burnCount++;
        unlockOperations[id].recipient = address(0);
    }

    /**
     * @dev Allow owner of an unlock to claim tokens
     * @param id Token id for delivery
     */
    function claim(uint256 id) external {
        deliver(id, msg.sender);
    }

    /**
     * @dev Deliver tokens to a beneficiary for unlock id.
     * Token is "burned" here by setting recipient to address(0)
     * @param id Token id for delivery
     * @param beneficiary Reciever address for tokens
     */
    function deliver(uint256 id, address beneficiary) public {
        address holder = unlockOperations[id].recipient;
        require(msg.sender == holder);
        require(unlockOperations[id].activation <= now);
        emit UnlockClaimed(id, beneficiary);
        emit Transfer(holder, address(0), id);
        balanceOf[holder]--;
        burnCount++;
        unlockOperations[id].recipient = address(0);
        vault().transfer(beneficiary, unlockOperations[id].amount);
    }

    function approve(address to, uint256 tokenId) public {
        require(ownerOf(tokenId) == msg.sender);
        emit Approval(msg.sender, to, tokenId);
        getApproved[tokenId] = to;
    }

    function setApprovalForAll(address operator, bool approved) public {
        emit ApprovalForAll(msg.sender, operator, approved);
        isApprovedForAll[msg.sender][operator] = approved;
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory _data) public {
        transferFrom(from, to, tokenId);
        if (!to.isContract()) {
            return;
        }
        bytes4 retval = IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, _data);
        require (retval == ERC721_RECEIVED, "recipient cannot accept ERC721");
    }

    /**
     * @dev Transfer ownership for token id to new address
     * This needs
     */
    function transferFrom(address from, address to, uint256 tokenId) public {
        require(from != address(0));
        require(to != address(0));
        address prior = unlockOperations[tokenId].recipient;
        require(prior == from);
        require(prior == msg.sender || isApprovedForAll[prior][msg.sender] || getApproved[tokenId] == msg.sender);

        getApproved[tokenId] = address(0);
        balanceOf[from]--;
        balanceOf[to]++;
        unlockOperations[tokenId].recipient = to;
        emit Transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public {
        safeTransferFrom(from, to, tokenId, "");
    }

    function name() public view returns (string memory) {
        return string(abi.encodePacked("Unclaimed ", vault().symbol()));
    }

    function symbol() public view returns (string memory) {
        return string(abi.encodePacked("SOON:", vault().symbol()));
    }
}
