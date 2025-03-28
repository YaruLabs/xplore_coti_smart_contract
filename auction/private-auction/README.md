1. Privacy in Auctions
   
In a traditional blockchain auction, all bids would be visible to everyone on the blockchain. This creates several problems:
Participants can see each other's bids
Front-running attacks become possible (seeing a bid and quickly placing a slightly higher one)
Sensitive information about how much users are willing to pay is publicly exposed


2. Privacy-Preserving Bid Comparison

When someone places a bid, the contract can:
  Compare bids using encrypted operations through MpcCore
  Determine if a bid is higher without revealing the actual bid amounts
  Track the highest bidder without exposing their bid value

For example, in the bid() function:

    MpcCore.ge(
        MpcCore.onBoard(existingBid),
        MpcCore.onBoard(highestBid)
    )

