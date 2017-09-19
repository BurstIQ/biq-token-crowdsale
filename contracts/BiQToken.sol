pragma solidity ^0.4.15;

import './helpers/BasicToken.sol';
import './lib/safeMath.sol';

contract BiQToken is BasicToken {

  using SafeMath for uint256;

  string public name = "BurstIQ Token";              //name of the token
  string public symbol = "BiQ";                      // symbol of the token
  uint8 public decimals = 18;                        // decimals
  uint256 public totalSupply = 1000000000 * 10**18;  // total supply of BiQ Tokens

  // variables
  uint256 public keyEmployeesAllocatedFund;           // fund allocated to key employees
  uint256 public advisorsAllocation;                  // fund allocated to advisors
  uint256 public marketIncentivesAllocation;          // fund allocated to Market
  uint256 public vestingFounderAllocation;            // funds allocated to founders that in under vesting period
  uint256 public totalAllocatedTokens;                // variable to keep track of funds allocated
  uint256 public tokensAllocatedToCrowdFund;          // funds allocated to crowdfund
  uint256 public saftInvestorAllocation;              // funds allocated to private presales and instituational investors

  bool public isPublicTokenReleased = false;          // flag to track the release the public token

  // addresses

  address public founderMultiSigAddress;              // multi sign address of founders which hold
  address public advisorAddress;                      //  advisor address which hold advisorsAllocation funds
  address public vestingFounderAddress;               // address of founder that hold vestingFounderAllocation
  address public crowdFundAddress;                    // address of crowdfund contract

  // vesting period

  uint256 public preAllocatedTokensVestingTime;       // crowdfund start time + 6 months

  //events

  event ChangeFoundersWalletAddress(uint256  _blockTimeStamp, address indexed _foundersWalletAddress);
  event TransferPreAllocatedFunds(uint256  _blockTimeStamp , address _to , uint256 _value);
  event PublicTokenReleased(uint256 _blockTimeStamp);

  //modifiers

  modifier onlyCrowdFundAddress() {
    require(msg.sender == crowdFundAddress);
    _;
  }

  modifier nonZeroAddress(address _to) {
    require(_to != 0x0);
    _;
  }

  modifier onlyFounders() {
    require(msg.sender == founderMultiSigAddress);
    _;
  }

  modifier onlyVestingFounderAddress() {
    require(msg.sender == vestingFounderAddress);
    _;
  }

  modifier onlyAdvisorAddress() {
    require(msg.sender == advisorAddress);
    _;
  }

  modifier isPublicTokenNotReleased() {
    require(isPublicTokenReleased == false);
    _;
  }


  // creation of the token contract
  function BiQToken (address _crowdFundAddress, address _founderMultiSigAddress, address _advisorAddress, address _vestingFounderAddress) {
    crowdFundAddress = _crowdFundAddress;
    founderMultiSigAddress = _founderMultiSigAddress;
    vestingFounderAddress = _vestingFounderAddress;
    advisorAddress = _advisorAddress;

    // Token Distribution
    vestingFounderAllocation = 18 * 10 ** 25 ;        // 18 % allocation of totalSupply
    keyEmployeesAllocatedFund = 2 * 10 ** 25 ;        // 2 % allocation of totalSupply
    advisorsAllocation = 5 * 10 ** 25 ;               // 5 % allocation of totalSupply
    tokensAllocatedToCrowdFund = 60 * 10 ** 25 ;      // 60 % allocation of totalSupply
    marketIncentivesAllocation = 5 * 10 ** 25 ;       // 5 % allocation of totalSupply
    saftInvestorAllocation = 10 * 10 ** 25 ;          // 10 % alloaction of totalSupply

    // Assigned balances to respective stakeholders
    balances[founderMultiSigAddress] = keyEmployeesAllocatedFund + saftInvestorAllocation;
    balances[crowdFundAddress] = tokensAllocatedToCrowdFund;

    totalAllocatedTokens = balances[founderMultiSigAddress];
    preAllocatedTokensVestingTime = now + 180 * 1 days;                // it should be 6 months period for vesting
  }

  // function to keep track of the total token allocation
  function changeTotalSupply(uint256 _amount) onlyCrowdFundAddress {
    totalAllocatedTokens = totalAllocatedTokens.add(_amount);
    tokensAllocatedToCrowdFund = tokensAllocatedToCrowdFund.sub(_amount);
  }

  // function to change founder multisig wallet address
  function changeFounderMultiSigAddress(address _newFounderMultiSigAddress) onlyFounders nonZeroAddress(_newFounderMultiSigAddress) {
    founderMultiSigAddress = _newFounderMultiSigAddress;
    ChangeFoundersWalletAddress(now, founderMultiSigAddress);
  }

  // function for releasing the public tokens called once by the founder only
  function releaseToken() onlyFounders isPublicTokenNotReleased {
    isPublicTokenReleased = !isPublicTokenReleased;
    PublicTokenReleased(now);
  }

  // function to transfer market Incentives fund
  function transferMarketIncentivesFund(address _to, uint _value) onlyFounders nonZeroAddress(_to)  returns (bool) {
    if (marketIncentivesAllocation >= _value) {
      marketIncentivesAllocation = marketIncentivesAllocation.sub(_value);
      balances[_to] = balances[_to].add(_value);
      totalAllocatedTokens = totalAllocatedTokens.add(_value);
      TransferPreAllocatedFunds(now, _to, _value);
      return true;
    }
    return false;
  }


  // fund transferred to vesting Founders address after 6 months
  function getVestedFounderTokens() onlyVestingFounderAddress returns (bool) {
    if (now >= preAllocatedTokensVestingTime && vestingFounderAllocation > 0) {
      balances[vestingFounderAddress] = balances[vestingFounderAddress].add(vestingFounderAllocation);
      totalAllocatedTokens = totalAllocatedTokens.add(vestingFounderAllocation);
      vestingFounderAllocation = 0;
      TransferPreAllocatedFunds(now, vestingFounderAddress, vestingFounderAllocation);
      return true;
    }
    return false;
  }

  // fund transferred to vesting advisor address after 6 months
  function getVestedAdvisorTokens() onlyAdvisorAddress returns (bool) {
    if (now >= preAllocatedTokensVestingTime && advisorsAllocation > 0) {
      balances[advisorAddress] = balances[advisorAddress].add(advisorsAllocation);
      totalAllocatedTokens = totalAllocatedTokens.add(advisorsAllocation);
      advisorsAllocation = 0;
      TransferPreAllocatedFunds(now, advisorAddress, advisorsAllocation);
      return true;
    } else {
      return false;
    }
  }

  // overloaded transfer function to restrict the investor to transfer the token before the ICO sale ends
  function transfer(address _to, uint256 _value) returns (bool) {
    if (msg.sender == crowdFundAddress) {
      return super.transfer(_to,_value);
    } else {
      if (isPublicTokenReleased) {
        return super.transfer(_to,_value);
      }
      return false;
    }
  }

  // overloaded transferFrom function to restrict the investor to transfer the token before the ICO sale ends
  function transferFrom(address _from, address _to, uint256 _value) returns (bool) {
    if (msg.sender == crowdFundAddress) {
      return super.transferFrom(_from, _to, _value);
    } else {
      if (isPublicTokenReleased) {
        return super.transferFrom(_from, _to, _value);
      }
      return false;
    }
  }

  // fallback function to restrict direct sending of ether
  function () {
    revert();
  }

}
