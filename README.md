# Stripe Scripts

[![Sync ILSA Members](https://github.com/IllinoisShuffle/stripe-scripts/actions/workflows/sync-members.yml/badge.svg)](https://github.com/IllinoisShuffle/stripe-scripts/actions/workflows/sync-members.yml)

Automation scripts for the Illinois Shuffleboard Association (ILSA) to manage membership payments, subscriptions, and mailing lists through Stripe, Mailchimp, and Google Sheets.

## Scripts

| Script | Language | Purpose |
|--------|----------|---------|
| `member_csv.py` | Python | **Primary** - Syncs Stripe subscriptions to Mailchimp and Google Sheets |
| `generate_payment_links.rb` | Ruby | Generates Stripe payment links for membership + donation combinations |
| `member_csv.rb` | Ruby | Legacy version of member_csv.py (deprecated) |

## Setup

### Prerequisites

- Python 3.x (for `member_csv.py`)
- Ruby 3.1.2 (for Ruby scripts)

### Install Dependencies

```bash
# Python
pip install -r requirements.txt

# Ruby
bundle install
```

### Environment Variables

Create a `.env` file based on `.env.example`:

```
STRIPE_SECRET_KEY=          # Stripe API secret key
MAILCHIMP_API_KEY=          # Mailchimp API key
MAILCHIMP_SERVER_PREFIX=    # Mailchimp server prefix (e.g., "us10")
MAILCHIMP_LIST_ID=          # Mailchimp list/audience ID
```

### Google Service Account

For Google Sheets integration:

1. Create a service account following [gspread documentation](https://docs.gspread.org/en/latest/oauth2.html#for-bots-using-service-account)
2. Save credentials as `.google_credentials.json` (use `.google_credentials.json.example` as template)
3. Grant the service account email **Editor** access to the target Google Sheet

### GitHub Actions (Automated Sync)

Configure repository secrets at **Settings > Secrets and variables > Actions**:

| Secret Name | Description |
|-------------|-------------|
| `STRIPE_SECRET_KEY` | Stripe API secret key |
| `MAILCHIMP_API_KEY` | Mailchimp API key |
| `MAILCHIMP_SERVER_PREFIX` | Mailchimp server prefix (e.g., "us10") |
| `MAILCHIMP_LIST_ID` | Mailchimp list/audience ID |
| `GOOGLE_CREDENTIALS` | Entire contents of `.google_credentials.json` |

The workflow runs automatically daily at 8am Central, or can be triggered manually from the Actions tab.

## Usage

### Member CSV & Sync

**Automated (Recommended):** Runs automatically daily at 8am Central via GitHub Actions.

- **Manual trigger:** Go to [Actions](https://github.com/IllinoisShuffle/stripe-scripts/actions) > "Sync ILSA Members" > "Run workflow"
- **View results:** Check workflow run for logs; CSV artifact available for download (7-day retention)

**Local execution:**

```bash
python member_csv.py
```

This script:
1. Fetches all Stripe subscriptions (active and inactive)
2. Syncs members with Mailchimp (adds subscribers, updates tags)
3. Generates `output/members.csv`
4. Updates Google Sheets with backup rotation

### Generate Payment Links

```bash
ruby generate_payment_links.rb
```

Creates Stripe payment links combining:
- Base membership price
- Optional donation tiers ($5, $10, $25, $50, $100, $250, $500, $1000)
- Optional league fee

Outputs JSON with URLs for all combinations.

## Architecture

### Member CSV Workflow

```
Stripe API ──► member_csv.py ──┬──► Mailchimp (sync members/tags)
                               ├──► output/members.csv
                               └──► Google Sheets (current + backup)
```

**Stripe Data Extracted:**
- Subscriptions (all statuses)
- Customer info (name, email, address)
- One-time donations (InvoiceItems with description "One-Time Donation")

**Mailchimp Sync:**
- New members added with merge fields: `FNAME`, `LNAME`, `SUB_STATUS`
- Existing members: `SUB_STATUS` field updated
- Active subscriptions: "Member" tag applied
- Does NOT remove expired members or tags (manual cleanup required)

**Google Sheets:**
- Deletes "members - backup" sheet
- Renames "members - current" to "members - backup"
- Creates new "members - current" with latest data
- Applies formatting (frozen headers, auto-sized columns)

### CSV Output Format

| Column | Description |
|--------|-------------|
| # | Sequential counter (active members only) |
| Name | Customer full name |
| Email | Customer email |
| City, State | From address or shipping address |
| Member Status | Subscription status (active, canceled, etc.) |
| Member Since | Subscription start date |
| Subscription End | End date or current period end |
| Donations | Total one-time donations |
| Mailing List | Mailchimp subscription status |
| Collection Method | charge_automatically or send_invoice |
| Stripe ID | Subscription ID |

## Common Issues

1. **Google Sheets Permission Error**: Ensure service account email has Editor access *before* running
2. **Mailchimp Rate Limits**: Large member counts may hit API limits (sequential processing)
3. **Timezone**: All dates use America/Chicago timezone
4. **Duplicate Processing**: Multiple subscriptions per customer = multiple API calls (last status wins)
5. **One-Time Donations**: Only counted if InvoiceItem description exactly matches "One-Time Donation"

## Configuration

### Mailchimp Merge Fields

Custom merge fields configured at: https://us10.admin.mailchimp.com/audience/merge-fields/?id=337185

- `FNAME` - First name
- `LNAME` - Last name
- `SUB_STATUS` - Stripe subscription status
