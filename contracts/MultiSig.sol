// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.8.0;

import "./access/Ownable.sol";
import "./interfaces/IERC20.sol";
import "./libraries/SafeMath.sol";

contract MultiSig is Ownable {

  using SafeMath for uint256;

  uint constant ADD_SIG_REQ = 11;
  uint constant REM_SIG_REQ = 22;

  struct Token {
    uint256 id;    
    string name;
    string symbol;
    address creator;
    string tokenType;
    address[] signatories;
    address contractAddress;
    uint requiredApprovals;
    uint256 balance;
    uint256 activeSignatories;
    bool initialized;
  }

  struct Transaction {
    uint256 txId;
    uint256 tokenId;
    uint256 amount;
    address initiator;
    address payable recipient;
    mapping(address => bool) approvers;
    mapping(address => bool) rejecters;
    uint approvals;
    uint rejects;
    bytes32 txHash;
    bool approved;
    bool rejected;
    bool cancelled;
    uint256 timeCreated;
    uint256 timeApproved;
    uint256 timeRejected;
    uint256 timeCancelled;
  }

  struct GovernanceRequest {
    uint256 id;
    uint256 tokenId;
    uint requestType;
    address signatory;
    address initiator;
    mapping(address => bool) approvers;
    mapping(address => bool) rejecters;
    uint approvals;
    uint rejects;
    bool approved;
    bool rejected;
    bool cancelled;
    uint256 timeCreated;
    uint256 timeApproved;
    uint256 timeRejected;
    uint256 timeCancelled;
  }

  modifier isTokenCreator(uint256 _tokenId) {
    require(tokens[_tokenId].creator == msg.sender, "Only token creator.");
    _;
  }

  modifier isTxInitiator(uint256 _txId) {
    require(transactions[_txId].initiator == msg.sender, "Only transaction initiator.");
    _;
  }

  modifier tokenExists(uint256 _tokenId) {
    require(_tokenId > 0 && _tokenId <= tokenCount, "Token not found.");
    _;
  }

  modifier transactionExists(uint256 _txId) {
    require(_txId > 0 && _txId <= txCount, "Transaction missing.");
    _;
  }

  modifier requestExists(uint256 _requestId) {
    require(_requestId > 0 && _requestId <= requestCount, "Request not missing.");
    _;
  }

  modifier transactionIsPending(uint256 _txId) {
    Transaction storage _tx = transactions[_txId];
    Token storage t = tokens[_tx.tokenId];
    require(
      ! _tx.approved && ! _tx.rejected && ! _tx.cancelled && _tx.approvals < t.requiredApprovals && _tx.rejects < t.requiredApprovals,
      "Transaction not pending."
    );
    _;
  }

  modifier requestIsPending(uint256 _requestId) {
    GovernanceRequest storage gR = requests[_requestId];
    Token storage t = tokens[gR.tokenId];
    require(
      !gR.approved && !gR.rejected && !gR.cancelled && gR.approvals < t.requiredApprovals && gR.rejects < t.requiredApprovals,
      "Request not pending."
    );
    _;
  }

  modifier isTokenSignatory(uint256 _tokenId) {
    require(tokenTxApprovers[_tokenId][msg.sender], "Not valid signatory.");
    _;
  }

  modifier canApproveTransaction(uint256 _txId) {
    Transaction storage _tx = transactions[_txId];
    require(tokenTxApprovers[_tx.tokenId][msg.sender], "No transaction approval rights.");
    require(! _tx.approvers[msg.sender] && ! _tx.rejecters[msg.sender], " Multiple approvals not supported.");
    _;
  }

  modifier canApproveRequest(uint256 _requestId) {
    GovernanceRequest storage gR = requests[_requestId];
    require(tokenTxApprovers[gR.tokenId][msg.sender], "No request approval rights.");
    require(!gR.approvers[msg.sender] && !gR.rejecters[msg.sender], "Multiple request approvals not supported.");
    _;
  }
  
  event TransferApproved(uint256 indexed txId);
  event TransferRejected(uint256 indexed txId);
  event TransferCancelled(uint256 indexed txId);
  event TransferRequestRejected(uint256 indexed txId, uint256 indexed tokenId, address indexed signatory);
  event TransferRequestApproved(uint256 indexed txId, uint256 indexed tokenId, address indexed signatory);
  event TransferTokenRequest(uint256 txId, uint256 indexed tokenId, address indexed recipient, uint256 amount);

  event AddSignatoryApproved(uint256 indexed tokenId, address indexed account);
  event AddSignatoryRejected(uint256 indexed tokenId, address indexed signatory);
  event AddSignatoryCancelled(uint256 indexed tokenId, address indexed signatory);
  event AddSignatoryRequestRejected(uint256 indexed tokenId, address indexed signatory, address indexed actor);
  event AddSignatoryRequestApproved(uint256 indexed tokenId, address indexed signatory, address indexed actor);
  event AddTokenSignatoryRequest(uint256 indexed requestId, uint256 indexed tokenId, address indexed signatory);

  event RemoveSignatoryApproved(uint256 indexed tokenId, address indexed signatory);
  event RemoveSignatoryRejected(uint256 indexed tokenId, address indexed signatory);
  event RemoveSignatoryCancelled(uint256 indexed tokenId, address indexed signatory);
  event RemoveSignatoryRequestRejected(uint256 indexed tokenId, address indexed signatory, address indexed actor);
  event RemoveSignatoryRequestApproved(uint256 indexed tokenId, address indexed signatory, address indexed actor);
  event RemoveTokenSignatoryRequest(uint256 indexed requestId, uint256 indexed tokenId, address indexed signatory);

  event TokenAdded(uint256 indexed tokenId, string indexed tokenSymbol, uint256 amount, address creator);
  event TokenWalletInitialized(uint256 indexed tokenId, string name, string symbol);
  event TokenOwnershipTransferred(uint256 indexed tokenId, address indexed previousOwner, address indexed newOwner);

  uint256 txCount;
  mapping (uint256 => Transaction) transactions;
  mapping (address => uint[]) userTransactions;

  uint256 tokenCount;
  mapping (uint256 => Token) tokens;
  mapping(address => uint256[]) userTokens;
  mapping (uint256 => mapping(address => bool)) tokenTxApprovers;

  uint256 requestCount;
  mapping (uint256 => GovernanceRequest) requests;
  mapping (address => uint256[]) userAddSignatoryRequests;
  mapping (address => uint256[]) userRemoveSignatoryRequests;

  function transferToken(uint256 _tokenId, address payable _recipient, uint256 _amount) external tokenExists(_tokenId) isTokenSignatory(_tokenId) returns(bool) {
    
    Token storage t = tokens[_tokenId];
    
    require(_amount > 0, "Transaction: send at least one token unit.");
    require(t.balance >= _amount, "Transaction: not enough token balance.");
    require(_recipient != address(0x0), "Transaction: valid recipient address required.");

    t.balance                 -= _amount;
    uint256 txId              = ++txCount;
    Transaction storage tTx   = transactions[txId];
    
    tTx.amount      = _amount;
    tTx.tokenId     = _tokenId;
    tTx.initiator   = msg.sender;
    tTx.recipient   = _recipient;
    tTx.txHash      = blockhash(block.number);
    tTx.timeCreated = block.timestamp;

    for(uint256 i = 0; i < t.signatories.length; i++) {
      address _approver = t.signatories[i];
      if (tokenTxApprovers[_tokenId][_approver]) {
        userTransactions[_approver].push(txId);
      }
    }

    emit TransferTokenRequest(txId, _tokenId, _recipient, _amount);

    approveTransaction(txId, msg.sender);

    return true;
  }

  function approveTransaction(uint256 _txId) public transactionExists(_txId) transactionIsPending(_txId) canApproveTransaction(_txId) returns(bool) {
    return approveTransaction(_txId, msg.sender);
  }

  function approveTransaction(uint256 _txId, address _approver) private returns(bool) {
    Transaction storage tTx = transactions[_txId];
    Token storage  t = tokens[tTx.tokenId];

    tTx.approvals += 1;
    tTx.approvers[_approver] = true;

    emit TransferRequestApproved(_txId, tTx.tokenId, _approver);

    if(tTx.approvals == t.requiredApprovals ) {

      bytes32 tTypeHash = keccak256(abi.encodePacked(t.tokenType));

      if(tTypeHash == keccak256(abi.encodePacked("erc20"))) { //optimze
        transferERC20(tTx, t);
      }
      if(tTypeHash == keccak256(abi.encodePacked("ether"))) {
        transferEther(tTx);
      }

      emit TransferApproved(_txId);
    }
    return true;
  }

  function transferERC20(Transaction storage _tx, Token storage _t) private returns(bool) {
    
    IERC20 tokenContract = IERC20(_t.contractAddress);
    tokenContract.transfer(_tx.recipient, _tx.amount);

    _tx.approved = true;
    _tx.timeApproved = block.timestamp;

    return true;
  }

  function transferEther(Transaction storage _tx) private returns(bool) {
    _tx.recipient.transfer(_tx.amount);
    _tx.approved = true;
    _tx.timeApproved = block.timestamp;

    return true;
  }

  function rejectTransaction(uint256 _txId) public transactionExists(_txId) transactionIsPending(_txId) canApproveTransaction(_txId) returns(bool) {
    Transaction storage tTx = transactions[_txId];
    Token storage  t = tokens[tTx.tokenId];

    tTx.rejects += 1;
    tTx.rejecters[msg.sender] = true;

    emit TransferRequestRejected(_txId, t.id, msg.sender);

    if(tTx.rejects == t.requiredApprovals ) {
      tTx.rejected = true;
      tTx.timeRejected = block.timestamp;
      t.balance += tTx.amount;

      emit TransferRejected(_txId);
    }

    return true;
  }

  function cancelTransaction(uint256 _txId) public transactionExists(_txId) transactionIsPending(_txId) isTxInitiator(_txId) returns(bool) {
    
    Transaction storage tTx = transactions[_txId];
    Token storage  t = tokens[tTx.tokenId];

    tTx.cancelled = true;
    tTx.timeCancelled = block.timestamp;
    t.balance += tTx.amount;

    emit TransferCancelled(_txId);

    return true;
  }

  function addTokenSignatory(uint256 _tokenId, address _signatory) external tokenExists(_tokenId) isTokenSignatory(_tokenId) returns(bool) {
    
    Token storage t = tokens[_tokenId];
    require(_signatory != address(0), "Signatory: invalid signatory address.");
    require(! tokenTxApprovers[_tokenId][_signatory], "Signatory: already added as signatory.");

    if(!t.initialized) {
      require(msg.sender == t.creator, "Signatory: pre signatory approval reserved for creator.");
      return addSignatory(t, _signatory);
    }

    uint256 requestId = ++requestCount;
    GovernanceRequest storage gR = requests[requestId];

    gR.id           = requestId;
    gR.tokenId      = _tokenId;
    gR.signatory    = _signatory;
    gR.initiator    = msg.sender;
    gR.requestType  = ADD_SIG_REQ;
    gR.timeCreated  = block.timestamp;

    for(uint256 i = 0; i < t.signatories.length; i++) {
      address _approver = t.signatories[i];
      if (tokenTxApprovers[_tokenId][_approver]) {
        userAddSignatoryRequests[_approver].push(requestId);
      }
    }

    emit AddTokenSignatoryRequest(requestId, _tokenId, _signatory);

    approveSignatoryAddition(gR, t, msg.sender);

    return true;
  }

  function removeTokenSignatory(uint256 _tokenId, address _signatory) public tokenExists(_tokenId) isTokenSignatory(_tokenId) returns(bool) {
    
    Token storage t = tokens[_tokenId];
    require(tokenTxApprovers[_tokenId][_signatory], "Signatory: cannot remove unavailable signatory.");

    if(!t.initialized) {
      require(msg.sender == t.creator, "Signatory: pre signatory approval reserved for creator.");
      return removeSignatory(t, _signatory);
    }

    uint256 requestId = ++requestCount;
    GovernanceRequest storage gR = requests[requestId];

    gR.id           = requestId;
    gR.tokenId      = _tokenId;
    gR.signatory    = _signatory;
    gR.initiator    = msg.sender;
    gR.requestType  = REM_SIG_REQ;
    gR.timeCreated  = block.timestamp;

    for(uint256 i = 0; i < t.signatories.length; i++) {
      address _approver = t.signatories[i];
      if (tokenTxApprovers[_tokenId][_approver]) {
        userRemoveSignatoryRequests[_approver].push(requestId);
      }
    }

    emit RemoveTokenSignatoryRequest(requestId, _tokenId, _signatory);

    approveSignatoryRemoval(gR, t, msg.sender);

    return true;    
  }

  function addERC20Token(string memory _name, address _contractAddress, uint256 _amount) public returns(uint256 tokenId) { 
    
    require(
      keccak256(abi.encodePacked(_name)) != keccak256(abi.encodePacked("")),
      "Add ERC20: invalid wallet name."
    );
    require(isContract(_contractAddress), "Add ERC20: invalid contract address.");

    IERC20 token = IERC20(_contractAddress);
    require(token.allowance(msg.sender, address(this)) >= _amount, "Add ERC20: approve enough spending allowance to contract.");

    string memory _symbol = token.symbol();

    token.transferFrom(msg.sender, address(this), _amount);

    tokenId = addToken(msg.sender, _name, _symbol, "erc20", _contractAddress, _amount);
  }

  function addEther(string memory _name) public payable returns(uint256 tokenId) {
    uint256 _amount = msg.value;
    require(keccak256(abi.encodePacked(_name)) != keccak256(abi.encodePacked("")), "Add Ether: invalid wallet name");
    require(_amount > 0, "Add Ether: send at least 1 wei");
    tokenId = addToken(msg.sender, _name, "ETH", "ether", address(0), _amount);  
  }

  function addToken(address _from, string memory _name, string memory _symbol, string memory _tokenType, address _contractAddress, uint256 _value) private returns(uint256 tokenId) {
    
    tokenId = ++tokenCount;
    Token storage t = tokens[tokenId];

    t.id                = tokenId;
    t.name              = _name;
    t.symbol            = _symbol;
    t.creator             = _from;
    t.tokenType         = _tokenType;
    t.contractAddress   = _contractAddress;
    t.balance           = _value;
    addSignatory(t, _from);
    emit TokenAdded(tokenId, _symbol, _value, _from);
  }

  function initializeWallet(uint256 _tokenId) public tokenExists(_tokenId) isTokenCreator(_tokenId) returns(bool initialized) {
    Token storage t = tokens[_tokenId];
    t.initialized = true;
    initialized = t.initialized;
    emit TokenWalletInitialized(_tokenId, t.name, t.symbol);
  }

  function approveSignatoryAddition(uint256 _requestId) public requestExists(_requestId) requestIsPending(_requestId) canApproveRequest(_requestId) returns(bool){
    
    GovernanceRequest storage gR = requests[_requestId];
    Token storage t = tokens[gR.tokenId];

    require(gR.requestType == ADD_SIG_REQ, "Signatory: invalid approve request.");

    return approveSignatoryAddition(gR, t, msg.sender);    
  }

  function approveSignatoryAddition(GovernanceRequest storage gR, Token storage t, address approver) private returns(bool) {
    gR.approvals += 1;
    gR.approvers[approver] = true;

    emit AddSignatoryRequestApproved(t.id, gR.signatory, approver);

    if(gR.approvals == t.requiredApprovals) {
      gR.approved = true;
      gR.timeApproved = block.timestamp;
      addSignatory(t, gR.signatory);
    }

    return true;
  }

  function addSignatory(Token storage t, address _account) private returns(bool) {
    t.signatories.push(_account);
    tokenTxApprovers[t.id][_account] = true;
    t.activeSignatories += 1;

    userTokens[_account].push(t.id);

    setRequiredApprovals(t);
    emit AddSignatoryApproved(t.id, _account);
    return true;
  }

  function rejectSignatoryAddition(uint256 _requestId) public requestExists(_requestId) requestIsPending(_requestId) canApproveRequest(_requestId) returns(bool){

    GovernanceRequest storage gR = requests[_requestId];
    Token storage t = tokens[gR.tokenId];

    require(gR.requestType == ADD_SIG_REQ, "Signatory: invalid reject request.");

    gR.rejects += 1;
    gR.rejecters[msg.sender] = true;
    emit AddSignatoryRequestApproved(gR.tokenId, gR.signatory, msg.sender);

    if(gR.rejects == t.requiredApprovals) {
      gR.rejected = true;
      gR.timeRejected = block.timestamp;
      emit AddSignatoryRejected(gR.tokenId, gR.signatory);
    }

    return true;
  }

  function approveSignatoryRemoval(uint256 _requestId) public requestExists(_requestId) requestIsPending(_requestId) canApproveRequest(_requestId) returns(bool){
    GovernanceRequest storage gR = requests[_requestId];
    Token storage t = tokens[gR.tokenId];

    require(gR.requestType == REM_SIG_REQ, "Signatory: invalid remove request.");

    return approveSignatoryRemoval(gR, t, msg.sender);    
  }

  function approveSignatoryRemoval(GovernanceRequest storage gR, Token storage t, address rejecter) private returns(bool) {
    gR.approvals += 1;
    gR.approvers[rejecter] = true;

    emit RemoveSignatoryRequestApproved(gR.tokenId, gR.signatory, rejecter);

    if(gR.approvals == t.requiredApprovals) {
      gR.approved = true;
      gR.timeApproved = block.timestamp;
      removeSignatory(t, gR.signatory);
    }

    return true;
  }

  function removeSignatory(Token storage t, address _account) private returns(bool) {
    for(uint256 i = 0; i < t.signatories.length; i++) {
      if(t.signatories[i] == _account) {
        delete t.signatories[i];
      }
    }
    for(uint256 i = 0; i < userTokens[_account].length; i++) {
      if (userTokens[_account][i] == t.id ) {
        delete userTokens[_account][i];
      }
    }

    t.activeSignatories -= 1;
    tokenTxApprovers[t.id][_account] = false;

    setRequiredApprovals(t);
    emit RemoveSignatoryApproved(t.id, _account);
    return true;
  }

  function rejectSignatoryRemoval(uint256 _requestId) public requestExists(_requestId) requestIsPending(_requestId) canApproveRequest(_requestId) returns(bool){
    GovernanceRequest storage gR = requests[_requestId];
    Token storage t = tokens[gR.tokenId];

    require(gR.requestType == REM_SIG_REQ, "Signatory: invalid reject request.");

    gR.rejects += 1;
    gR.rejecters[msg.sender] = true;

    emit RemoveSignatoryRequestRejected(gR.tokenId, gR.signatory, msg.sender);

    if(gR.rejects == t.requiredApprovals) {
      gR.rejected = true;
      gR.timeRejected = block.timestamp;
      emit RemoveSignatoryRejected(gR.tokenId, gR.signatory);
    }

    return true;
  }

  function cancelRequest(uint256 _requestId) public requestExists(_requestId) requestIsPending(_requestId) returns(bool) {
    
    GovernanceRequest storage gR = requests[_requestId];
    require(gR.initiator == msg.sender, "Request: not request initiator.");

    gR.cancelled = true;
    gR.timeCancelled = block.timestamp;

    if(gR.requestType == ADD_SIG_REQ) {
      emit AddSignatoryCancelled(gR.tokenId, gR.signatory);
    }

    if(gR.requestType == REM_SIG_REQ) {
      emit RemoveSignatoryCancelled(gR.tokenId, gR.signatory);
    }

    return true;
  }

  function setRequiredApprovals(Token storage t) private returns(bool){
    uint256 _activeSign = t.activeSignatories;

    if(_activeSign > 3) {
      t.requiredApprovals = _activeSign;
      return true;
    }
    if(_activeSign.mod(2) > 0) {
      t.requiredApprovals = _activeSign.sub(1).div(2).add(1);
      return true;
    }
    t.requiredApprovals = _activeSign.div(2).add(1);
    return true;
  }

  function isContract(address account) private view returns(bool) {
    // codeHash for EOA
    bytes32 accountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
    bytes32 codeHash;    
    assembly { codeHash := extcodehash(account) }
    return (codeHash != accountHash && codeHash != 0x0);
  }
}