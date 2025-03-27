// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {PrivateERC20} from "@coti-io/coti-contracts/contracts/token/PrivateERC20/PrivateERC20.sol";
import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

contract PrivateAuction {
    uint public endTime;

    address public beneficiary;

    // Current highest bid.
    ctUint64 internal highestBid;

    // Mapping from bidder to their bid value.
    mapping(address => ctUint64) internal bids;

    // Number of bid
    uint public bidCounter;

    // The token contract used for encrypted bids.
    PrivateERC20 public tokenContract;

    // Whether the auction object has been claimed.
    ctBool internal objectClaimed;

    // If the token has been transferred to the beneficiary
    bool public tokenTransferred;

    bool public stoppable;

    bool public manuallyStopped = false;

    // The owner of the contract.
    address public contractOwner;

    // The function has been called too early.
    // Try again at `time`.
    error TooEarly(uint time);
    // The function has been called too late.
    // It cannot be called after `time`.
    error TooLate(uint time);

    event Winner(address who);

    event HighestBid(ctBool isHighestBid);

    constructor(
        address _beneficiary,
        PrivateERC20 _tokenContract,
        uint biddingTime,
        bool isStoppable
    ) {
        beneficiary = _beneficiary;
        tokenContract = _tokenContract;
        endTime = block.timestamp + biddingTime;
        objectClaimed = MpcCore.offBoard(MpcCore.setPublic(false));
        tokenTransferred = false;
        bidCounter = 0;
        stoppable = isStoppable;
        contractOwner = msg.sender;
    }

    function bid(
        itUint64 calldata itBid
    ) public onlyBeforeEnd {
        ctUint64 existingBid = bids[msg.sender];

        gtUint64 gtBid = MpcCore.validateCiphertext(itBid);

        if (ctUint64.unwrap(existingBid) == 0) {
            bidCounter++;
            bids[msg.sender] = MpcCore.offBoard(gtBid);
            tokenContract.transferFrom(
                msg.sender,
                address(this),
                gtBid
            );
        } else if (
            MpcCore.decrypt(
                MpcCore.ge(
                    MpcCore.onBoard(existingBid),
                    MpcCore.onBoard(highestBid)
                )
            )
        ) {
            bids[msg.sender] = MpcCore.offBoard(gtBid);
            gtUint64 toTransfer = MpcCore.sub(
                gtBid,
                MpcCore.onBoard(existingBid)
            );
            tokenContract.transferFrom(
                msg.sender,
                address(this),
                toTransfer
            );
        }
        ctUint64 currentBid = bids[msg.sender];
        if (
            ctUint64.unwrap(highestBid) == 0 ||
            MpcCore.decrypt(
                MpcCore.ge(
                    MpcCore.onBoard(existingBid),
                    MpcCore.onBoard(highestBid)
                )
            )
        ) {
            highestBid = currentBid;
        }
    }

    function getBid() public returns (ctUint64) {
        gtUint64 bidGt = MpcCore.onBoard(bids[msg.sender]);
        return MpcCore.offBoardToUser(bidGt, msg.sender);
    }

    function stop() public onlyContractOwner {
        require(stoppable);
        manuallyStopped = true;
    }

    function doIHaveHighestBid() public {
        gtBool isHighest = MpcCore.setPublic(false);
        if (
            ctUint64.unwrap(highestBid) != 0 &&
            ctUint64.unwrap(bids[msg.sender]) != 0
        ) {
            isHighest = MpcCore.ge(
                MpcCore.onBoard(bids[msg.sender]),
                MpcCore.onBoard(highestBid)
            );
        }
        
        emit HighestBid(MpcCore.offBoardToUser(isHighest, msg.sender));
    }

    function claim() public onlyAfterEnd {
        gtBool isHighest = MpcCore.ge(
            MpcCore.onBoard(bids[msg.sender]),
            MpcCore.onBoard(highestBid)
        );
        gtBool canClaim = MpcCore.and(
            MpcCore.not(MpcCore.onBoard(objectClaimed)),
            isHighest
        );
        if (MpcCore.decrypt(canClaim)) {
            objectClaimed = MpcCore.offBoard(MpcCore.setPublic(true));
            bids[msg.sender] = MpcCore.offBoardToUser(
                MpcCore.setPublic64(0),
                msg.sender
            );
            emit Winner(msg.sender);
        }
    }

    function auctionEnd() public onlyAfterEnd {
        require(!tokenTransferred);

        tokenTransferred = true;
        tokenContract.transfer(
            beneficiary,
            MpcCore.onBoard(highestBid)
        );
    }

    // Withdraw a bid from the auction to the caller once the auction has stopped.
    function withdraw() public onlyAfterEnd {
        gtUint64 bidValue = MpcCore.onBoard(bids[msg.sender]);
        gtBool isHighestBid = MpcCore.ge(bidValue, MpcCore.onBoard(highestBid));
        gtBool canWithdraw = MpcCore.not(
            MpcCore.and(
                isHighestBid,
                MpcCore.not(MpcCore.onBoard(objectClaimed))
            )
        );
        if (MpcCore.decrypt(canWithdraw)) {
            bids[msg.sender] = MpcCore.offBoardToUser(
                MpcCore.setPublic64(0),
                msg.sender
            );
            tokenContract.transfer(msg.sender, bidValue);
        }
    }

    modifier onlyBeforeEnd() {
        if (block.timestamp >= endTime || manuallyStopped == true)
            revert TooLate(endTime);
        _;
    }

    modifier onlyAfterEnd() {
        if (block.timestamp <= endTime && manuallyStopped == false)
            revert TooEarly(endTime);
        _;
    }

    modifier onlyContractOwner() {
        require(msg.sender == contractOwner);
        _;
    }
}
