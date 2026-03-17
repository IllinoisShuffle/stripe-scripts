# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

See [README.md](README.md) for project overview, setup instructions, and architecture documentation.

## Language Migration Status

The codebase has migrated from Ruby to Python:
- **Python** (`member_csv.py`): Current production version - make changes here
- **Ruby** (`member_csv.rb`): Deprecated, kept for reference only
- **Ruby** (`generate_payment_links.rb`): Still active (no Python equivalent yet)

When making changes, modify Python scripts unless specifically working on Ruby code.

## Hardcoded Values

Update these values when modifying scripts:

**Subscription Ignore List** (`member_csv.py:30-36`):
```python
ignore_subscriptions = {
    "sub_1LBOHNG9vhwQIFDDfUpz7HSM",
    "sub_1LBOOAG9vhwQIFDDy9msWx4R",
    "sub_1KbZHMG9vhwQIFDD9sXK0tIi",
    "sub_1KcC9OG9vhwQIFDDHkGiH3S7",
    "sub_1LcZIUG9vhwQIFDDkmzqx39N"
}
```

**Google Spreadsheet ID** (`member_csv.py:185`):
```python
spreadsheet_id = "1xmZL8_d8yAv8qjSJjdQri6Z74Sn8PQkr9hSNcmRdMNg"
```

**Stripe Price IDs** (`generate_payment_links.rb:8-22`): Production price objects (test IDs commented out on lines 24-38)

## Implementation Notes

- **Timezone**: All dates use `America/Chicago` - use `pytz` for conversions
- **Mailchimp Member ID**: MD5 hash of lowercase email (`hashlib.md5(email.lower().encode()).hexdigest()`)
- **One-Time Donations**: Only InvoiceItems with description exactly matching "One-Time Donation" are counted
- **No Cleanup**: Script does NOT remove expired members or "Member" tags from Mailchimp
- **Duplicate Handling**: Multiple subscriptions per customer results in duplicate API calls; only latest status persists
