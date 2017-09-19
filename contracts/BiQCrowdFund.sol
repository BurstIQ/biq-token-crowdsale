pragma solidity ^0.4.15;

import './lib/safeMath.sol';
import './BiQToken.sol';

contract BiQCrowdFund {

    using SafeMath for uint256;

    BiQToken public token;                                 // Token contract reference

    //variables
    uint256 public crowdfundStartTime;                     // Starting time of CrowdFund
    uint256 public crowdfundEndTime;                       // End time of Crowdfund
    uint256 public totalWeiRaised = 0;                     // Counter to track the amount raised
    uint256 public exchangeRate = 2307;                    // Calculated using priceOfEtherInUSD/priceOfBiQToken so 276.84/0.12
    uint256 internal minAmount = 36.1219 * 10 ** 18;       // Calculated using 10k USD / 276.84 USD

    bool public isCrowdFundActive = false;                 // Flag to track the crowdfund active or not
    bool internal isTokenDeployed = false;                 // Flag to track the token deployment -- only can be set once
    bool internal hasCrowdFundStarted = false;             // Flag to track if the crowdfund started

    // addresses
    address public founderMultiSigAddress;                 // Founders multisig address
    address public remainingTokenHolder;                   // Address to hold the remaining tokens after crowdfund end
    address public authorizerAddress;                      // Address of Authorizer who will authorize the investor

    // mapping
    mapping (address => uint256) auth;                     // KYC authentication

    enum State { PreSale, CrowdFund }

    //events
    event TokenPurchase(address indexed beneficiary, uint256 value, uint256 amount);
    event CrowdFundClosed(uint256 _blockTimeStamp);
    event ChangeFoundersWalletAddress(uint256 _blockTimeStamp, address indexed _foundersWalletAddress);

    //Modifiers
    modifier tokenIsDeployed() {
        require(isTokenDeployed == true);
        _;
    }
     modifier nonZeroEth() {
        require(msg.value > 0);
        _;
    }

    modifier nonZeroAddress(address _to) {
        require(_to != 0x0);
        _;
    }

    modifier checkCrowdFundActive() {
        require(isCrowdFundActive == true);
        _;
    }

    modifier onlyFounders() {
        require(msg.sender == founderMultiSigAddress);
        _;
    }

    modifier onlyPublic() {
        require(msg.sender != founderMultiSigAddress);
        _;
    }

    modifier onlyAuthorizer() {
        require(msg.sender == authorizerAddress);
        _;
    }


    modifier inState(State state) {
        require(getState() == state);
        _;
    }

    // Constructor to initialize the local variables
    function BiQCrowdFund (address _founderWalletAddress, address _remainingTokenHolder, address _authorizerAddress) {
        founderMultiSigAddress = _founderWalletAddress;
        remainingTokenHolder = _remainingTokenHolder;
        authorizerAddress = _authorizerAddress;
    }

    // Function to change the founders multisig address
    function setFounderMultiSigAddress(address _newFounderAddress) onlyFounders nonZeroAddress(_newFounderAddress) {
        founderMultiSigAddress = _newFounderAddress;
        ChangeFoundersWalletAddress(now, founderMultiSigAddress);
    }

     function setAuthorizerAddress(address _newAuthorizerAddress) onlyFounders nonZeroAddress(_newAuthorizerAddress) {
        authorizerAddress = _newAuthorizerAddress;
    }

     function setRemainingTokenHolder(address _newRemainingTokenHolder) onlyFounders nonZeroAddress(_newRemainingTokenHolder) {
        remainingTokenHolder = _newRemainingTokenHolder;
    }

    // Attach the token contract, can only be done once
    function setTokenAddress(address _tokenAddress) onlyFounders nonZeroAddress(_tokenAddress) {
        require(isTokenDeployed == false);
        token = BiQToken(_tokenAddress);
        isTokenDeployed = true;
    }

    // change the state of crowdfund
    function changeCrowdfundState() tokenIsDeployed onlyFounders inState(State.CrowdFund) {
        isCrowdFundActive = !isCrowdFundActive;
    }

    // for KYC/AML
    function authorize(address _to, uint256 max_amount) onlyAuthorizer {
        auth[_to] = max_amount * 1 ether;
    }

    // Buy token function call only in duration of crowdfund active
    function buyTokens(address beneficiary) nonZeroEth tokenIsDeployed onlyPublic nonZeroAddress(beneficiary) payable returns(bool) {
        // Only allow a certain amount for every investor
        if (auth[beneficiary] < msg.value) {
            revert();
        }
        auth[beneficiary] = auth[beneficiary].sub(msg.value);

        if (getState() == State.PreSale) {
            if (buyPreSaleTokens(beneficiary)) {
                return true;
            }
            revert();
        } else {
            require(now < crowdfundEndTime && isCrowdFundActive);
            fundTransfer(msg.value);

            uint256 amount = getNoOfTokens(exchangeRate, msg.value);

            if (token.transfer(beneficiary, amount)) {
                token.changeTotalSupply(amount);
                totalWeiRaised = totalWeiRaised.add(msg.value);
                TokenPurchase(beneficiary, msg.value, amount);
                return true;
            }
            revert();
        }

    }

    // function to transfer the funds to founders account
    function fundTransfer(uint256 weiAmount) internal {
        founderMultiSigAddress.transfer(weiAmount);
    }

    ///////////////////////////////////// Constant Functions /////////////////////////////////////

    // function to get the current state of the crowdsale
   function getState() public constant returns(State) {
        if (!isCrowdFundActive && !hasCrowdFundStarted) {
            return State.PreSale;
        }
        return State.CrowdFund;
   }

    // To get the authorized amount corresponding to an address
   function getPreAuthorizedAmount(address _address) constant returns(uint256) {
        return auth[_address];
   }

   // get the amount of tokens a user would receive for a specific amount of ether
   function calculateTotalTokenPerContribution(uint256 _totalETHContribution) public constant returns(uint256) {
       if (getState() == State.PreSale) {
           return getTokensForPreSale(exchangeRate, _totalETHContribution * 1 ether).div(10 ** 18);
       }
       return getNoOfTokens(exchangeRate, _totalETHContribution);
   }

    // provides the bonus %
    function currentBonus(uint256 _ethContribution) public constant returns (uint8) {
        if (getState() == State.PreSale) {
            return getPreSaleBonusRate(_ethContribution * 1 ether);
        }
        return getCurrentBonusRate();
    }


///////////////////////////////////// Presale Functions /////////////////////////////////////
    // function to buy the tokens at presale with minimum investment = 10k USD
    function buyPreSaleTokens(address beneficiary) internal returns(bool) {
       // check the minimum investment should be 10k USD
        if (msg.value < minAmount) {
          revert();
        } else {
            fundTransfer(msg.value);
            uint256 amount = getTokensForPreSale(exchangeRate, msg.value);

            if (token.transfer(beneficiary, amount)) {
                token.changeTotalSupply(amount);
                totalWeiRaised = totalWeiRaised.add(msg.value);
                TokenPurchase(beneficiary, msg.value, amount);
                return true;
            }
            return false;
        }
    }

    // function calculate the total no of tokens with bonus multiplication in the duration of presale
    function getTokensForPreSale(uint256 _exchangeRate, uint256 _amount) internal returns (uint256) {
        uint256 noOfToken = _amount.mul(_exchangeRate);
        uint256 preSaleTokenQuantity = ((100 + getPreSaleBonusRate(_amount)) * noOfToken ).div(100);
        return preSaleTokenQuantity;
    }

    function getPreSaleBonusRate(uint256 _ethAmount) internal returns (uint8) {
        if ( _ethAmount >= minAmount.mul(5) && _ethAmount < minAmount.mul(10)) {
            return 30;
        }
        if (_ethAmount >= minAmount.mul(10)) {
            return 35;
        }
        if (_ethAmount >= minAmount) {
            return 25;
        }
    }
///////////////////////////////////// Crowdfund Functions /////////////////////////////////////

    // Starts the crowdfund, can only be called once
    function startCrowdfund(uint256 _exchangeRate) onlyFounders tokenIsDeployed inState(State.PreSale) {
        if (_exchangeRate > 0 && !hasCrowdFundStarted) {
            exchangeRate = _exchangeRate;
            crowdfundStartTime = now;
            crowdfundEndTime = crowdfundStartTime + 5 * 1 weeks; // end date is 5 weeks after the starting date
            isCrowdFundActive = !isCrowdFundActive;
            hasCrowdFundStarted = !hasCrowdFundStarted;
        } else {
            revert();
        }
    }

    // function call after crowdFundEndTime.
    // It transfers the remaining tokens to remainingTokenHolder address
    function endCrowdfund() onlyFounders returns (bool) {
        require(now > crowdfundEndTime);
        uint256 remainingToken = token.balanceOf(this);  // remaining tokens

        if (remainingToken != 0 && token.transfer(remainingTokenHolder, remainingToken)) {
          return true;
        } else {
            return false;
        }
        CrowdFundClosed(now);
    }

   // function to calculate the total no of tokens with bonus multiplication
    function getNoOfTokens(uint256 _exchangeRate, uint256 _amount) internal returns (uint256) {
         uint256 noOfToken = _amount.mul(_exchangeRate);
         uint256 noOfTokenWithBonus = ((100 + getCurrentBonusRate()) * noOfToken).div(100);
         return noOfTokenWithBonus;
    }

    // function provide the current bonus rate
    function getCurrentBonusRate() internal returns (uint8) {
        if (now > crowdfundStartTime + 4 weeks) {
            return 0;
        }
        if (now > crowdfundStartTime + 3 weeks) {
            return 5;
        }
        if (now > crowdfundStartTime + 2 weeks) {
            return 10;
        }
        if (now > crowdfundStartTime + 1 weeks) {
            return 15;
        }
        if (now > crowdfundStartTime) {
            return 20;
        }
    }

    // Crowdfund entry
    // send ether to the contract address
    // With at least 200 000 gas
    function() public payable {
        buyTokens(msg.sender);
    }
}
