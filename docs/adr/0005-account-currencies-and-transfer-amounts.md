---
status: accepted
---

# Accounts own currencies; transfers retain both amounts

The owner keeps money in EUR and INR and sends euros to an Indian account, so each account has exactly one currency and each expense or income uses that currency. A transfer stores the amount sent in its source account's currency and the amount received in its destination account's currency; both are required for new cross-currency transfers, while same-currency transfers store equal amounts from one input. Centtrail never converts currencies or adds them into a combined total: an effective transfer rate is derived only from the two recorded amounts, keeping account history exact without exchange-rate feeds.

Existing ledgers migrate in place: accounts become EUR without changing amounts, and historical transfers retain their sent amount with no received amount or review flag. A one-time migration allowance lets the owner mark the India account INR; otherwise an account holding entries cannot change currency. Currency fields and budget records sync with the rest of the ledger, and Home and budgets keep spending separate by currency.
