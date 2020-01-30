pragma solidity ^0.5.13;

import "./TrustToken.sol";

import "openzeppelin-solidity/contracts/token/ERC721/IERC721.sol";
import "openzeppelin-solidity/contracts/token/ERC721/IERC721Receiver.sol";
import "openzeppelin-solidity/contracts/utils/Address.sol";

contract Vesting /*is IERC721*/ {
    using Address for address;

    address public owner;
    address public pendingOwner;
    mapping (address => uint256) public balanceOf;
    mapping (address => mapping (address => bool)) public isApprovedForAll;
    mapping (uint256 => address) public getApproved;

    struct MintOperation {
        address recipient;
        uint256 amount;
        uint256 activation;
    }
    MintOperation[] public mintOperations;

    constructor() public {
        owner = msg.sender;
    }

    function totalSupply() public view returns (uint256) {
        return mintOperations.length;
    }
    function ownerOf(uint256 nonce) public view returns (address) {
        return mintOperations[nonce].recipient;
    }

    function token() internal view returns (TrustToken);
    bytes4 private constant ERC721_RECEIVED = 0x150b7a02;

    // Claimable
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    // ERC721
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    // Vesting
    event MintScheduled(uint256 indexed nonce, address indexed recipient, uint256 indexed amount, uint256 activation);
    event MintCancelled(uint256 indexed nonce);
    event MintClaimed(uint256 indexed nonce, address indexed beneficiary);

    modifier onlyPendingOwner() {
        require(msg.sender == pendingOwner, "only pending owner");
        _;
    }
    modifier onlyOwner() {
        require(msg.sender == owner, "only owner");
        _;
    }

    function claimTokenOwnership() public onlyOwner {
        token().claimOwnership();
    }

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

    function scheduleMint(address recipient, uint256 amount, uint256 activationTime) external onlyOwner returns (uint256) {
        uint256 id = mintOperations.length;
        emit MintScheduled(id, recipient, amount, activationTime);
        emit Transfer(address(0), recipient, id);
        balanceOf[recipient]++;
        mintOperations.push(MintOperation(
            recipient, amount, activationTime
        ));
        return id;
    }

    function cancelMint(uint256 id) external onlyOwner {
        address prior = mintOperations[id].recipient;
        require(prior != address(0));
        emit MintCancelled(id);
        emit Transfer(prior, address(0), id);
        balanceOf[prior]--;
        mintOperations[id].recipient = address(0);
    }

    function claim(uint256 id) external {
        deliver(id, msg.sender);
    }

    function deliver(uint256 id, address beneficiary) public {
        address holder = mintOperations[id].recipient;
        require(msg.sender == holder);
        require(mintOperations[id].activation <= now);
        emit MintClaimed(id, beneficiary);
        emit Transfer(holder, address(0), id);
        balanceOf[holder]--;
        token().mint(beneficiary, mintOperations[id].amount);
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

    function transferFrom(address from, address to, uint256 tokenId) public {
        require(from != address(0));
        require(to != address(0));
        address prior = mintOperations[tokenId].recipient;
        require(prior == from);
        require(prior == msg.sender || isApprovedForAll[prior][msg.sender] || getApproved[tokenId] == msg.sender);


        getApproved[tokenId] = address(0);
        balanceOf[from]--;
        balanceOf[to]++;
        mintOperations[tokenId].recipient = to;
        emit Transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public {
        safeTransferFrom(from, to, tokenId, "");
    }
}
