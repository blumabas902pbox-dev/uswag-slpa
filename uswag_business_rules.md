# USWAG Business Rules

1. A **Seller** (local SLP member) owns many Products, Sales, Expenses and exactly one Capital record.
2. An **Account** has exactly one role: Buyer, Seller or SLP Admin. A Seller row links to at most one Account.
3. A **Product** belongs to one Seller and one Category; its name is unique per seller.
4. **Stock never changes by hand.** It changes only through verified Inventory_Transactions (Harvest/Restock, Sale, Spoilage, Adjustment); sellers record, the SLP Admin verifies.
5. A **Sale** is a header with one or more Sale_Details; line_total is computed (quantity x price at sale). An empty sale cannot be marked Paid.
6. A sale is **Pending** until paid; **Paid** sales credit the seller's capital and generate exactly one receipt (80 mm ATM-style JSON).
7. **Offline sales** carry a client UUID; syncing is idempotent (no duplicates) and flips Offline -> Online.
8. **Expenses** debit capital; every capital movement is written to the append-only **Capital_Ledger**. Balance cannot be edited directly (FIX-1).
9. Verified inventory entries and Paid receipts cannot be deleted; corrections are posted as Adjustments.
10. Contact messages are reviewed by an SLP Admin (Review / Received / Rejected).
