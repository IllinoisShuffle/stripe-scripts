import os
import csv
import hashlib
from datetime import datetime
import pytz
from dotenv import load_dotenv
import stripe
import mailchimp_marketing as MailchimpMarketing
from mailchimp_marketing.api_client import ApiClientError
import gspread

load_dotenv()

stripe.api_key = os.environ['STRIPE_SECRET_KEY']

output_csv = "output/members.csv"

start_time = datetime.now()

# Initialize Mailchimp client
mailchimp = MailchimpMarketing.Client()
mailchimp.set_config({
    "api_key": os.environ['MAILCHIMP_API_KEY'],
    "server": os.environ['MAILCHIMP_SERVER_PREFIX']
})

members = []

# list of subscription IDs to ignore
ignore_subscriptions = {
    "sub_1LBOHNG9vhwQIFDDfUpz7HSM",
    "sub_1LBOOAG9vhwQIFDDy9msWx4R",
    "sub_1KbZHMG9vhwQIFDD9sXK0tIi",
    "sub_1KcC9OG9vhwQIFDDHkGiH3S7",
    "sub_1LcZIUG9vhwQIFDDkmzqx39N"
}

timezone = pytz.timezone("America/Chicago")

latest_status = {}

# Retrieve all subscriptions
for s in stripe.Subscription.list(status='all', limit=100).auto_paging_iter():
    print(f"Processing Subscription {s.id}")

    if s.id in ignore_subscriptions:
        print(f"Ignoring Subscription {s.id}")
        continue

    # Parse subscription start date to timezone-aware datetime
    collection_method = s.collection_method
    sub_start = datetime.fromtimestamp(s.start_date, tz=timezone)
    if s.ended_at is not None:
        sub_end = datetime.fromtimestamp(s.ended_at, tz=timezone)
    else:
        for i in list(s.items()):
            if i[0] == "items":
                current_period_end = i[1]['data'][0]['current_period_end']
        sub_end = datetime.fromtimestamp(current_period_end, tz=timezone)

    # Load customer object
    customer = stripe.Customer.retrieve(s.customer)

    # Determine city and state
    city = ""
    state = ""
    addr = customer.get('address') or {}
    ship = customer.get('shipping', {}) or {}
    ship_addr = ship.get('address') or {}

    city = addr.get('city') or ship_addr.get('city') or ""
    state = addr.get('state') or ship_addr.get('state') or ""

    # Sum up one-time donation invoice items
    invoice_items = stripe.InvoiceItem.list(customer=customer.id).auto_paging_iter()
    additional_donations_cents = sum(
        ii.amount for ii in invoice_items
        if ii.description == "One-Time Donation"
    )
    additional_donations = additional_donations_cents / 100.0

    # Mailchimp: look up by email MD5 hash
    email = customer.email.strip().lower()
    email_hash = hashlib.md5(email.encode('utf-8')).hexdigest()
    mailing_list_status = None
    mc_response = None


    # check if the user is already in mailchimp, if not they need to be added
    try:
        mc_response = mailchimp.lists.get_list_member(os.environ['MAILCHIMP_LIST_ID'], email_hash)
        mailing_list_status = mc_response.get('status')
    except ApiClientError as e:
        if e.status_code == 404:
            mailing_list_status = 'need_to_add'
        else:
            raise

    # if they need to be added, push them to mailchimp
    if mailing_list_status == 'need_to_add':
        print(f"Adding {email} to list")
        fname, _, lname = (customer.name or "").partition(" ")
        mc_response = mailchimp.lists.add_list_member(os.environ['MAILCHIMP_LIST_ID'], {
            "email_address": email,
            "status": "subscribed",
            "merge_fields": {"FNAME": fname, "LNAME": lname, "SUB_STATUS": s.status}
        })
        mailing_list_status = mc_response.get('status')    
    if email not in latest_status.keys():
        # for everyone else, just update custom merge tags
        # set up new tags here: https://us10.admin.mailchimp.com/audience/merge-fields/?id=337185
        mc_response = mailchimp.lists.update_list_member(os.environ['MAILCHIMP_LIST_ID'],email_hash, {
            "email_address": email,
            "merge_fields": {"SUB_STATUS": s.status}
        })
        latest_status[email] = s.status

    # Add the "Member" tag if needed
    if mailing_list_status == "subscribed" and s.status == "active":
        tags = mc_response.get('tags', [])
        has_member = any(tag.get('name') == 'Member' for tag in tags)
        if not has_member:
            print(f"Adding Member Tag for {email}")
            mailchimp.lists.update_list_member_tags(
                os.environ['MAILCHIMP_LIST_ID'],
                email_hash,
                {"tags": [{"name": "Member", "status": "active"}]}
            )

    members.append({
        "name": customer.name,
        "email": email,
        "city": city,
        "state": state,
        "subscription_status": s.status,
        "subscription_start": sub_start,
        "subscription_end": sub_end,
        "additional_donations": f"${additional_donations:.2f}" if additional_donations > 0 else "",
        "mailing_list_status": mailing_list_status,
        "collection_method": collection_method,
        "subscription_id": s.id
    })

# Sort members by subscription start date
members.sort(key=lambda m: m["subscription_start"])

# Write CSV
current_date = datetime.today().strftime("%Y-%m-%d")
header_row = ["#", "Name", "Email", "City", "State",
                    "Member Status", "Member Since","Subscription End",
                    "Donations", "Mailing List", "Collection Method",
                    "Stripe ID","Last Updated:",current_date]
member_count = 0
with open(output_csv, "w", newline="", encoding="utf‑8") as csvfile:
    writer = csv.writer(csvfile)
    writer.writerow(header_row)
    for m in members:
        if m["subscription_status"] == "active":
            member_count += 1
            count_field = member_count
        else:
            count_field = ""
        writer.writerow([
            count_field,
            m["name"],
            m["email"],
            m["city"],
            m["state"],
            m["subscription_status"],
            m["subscription_start"].strftime("%Y-%m-%d"),
            m["subscription_end"].strftime("%Y-%m-%d"),
            m["additional_donations"],
            m["mailing_list_status"],
            m['collection_method'],
            m["subscription_id"],
            "",
            ""
        ])

"""
Note: the email listed as client_email in the credentials must be added with editor privileges to the file you intend to update

This portion will move the latest member list to the "members backup" sheet and then upload the members.csv as the new "members" sheet
"""
spreadsheet_id = "1xmZL8_d8yAv8qjSJjdQri6Z74Sn8PQkr9hSNcmRdMNg"  # Please put your Spreadsheet ID.
current_list = "members - current" # this sheet will end up with the current list
previous_list = "members - backup" # the previous current list will be cycled to the backup list


client = gspread.service_account(filename='.google_credentials.json')
spreadsheet = client.open_by_key(spreadsheet_id)

# delete backup sheet
spreadsheet.del_worksheet(spreadsheet.worksheet(previous_list))

# rename existing sheet to backup
worksheet = spreadsheet.worksheet(current_list)
worksheet.update_title(previous_list)

# create new worksheet
worksheet = spreadsheet.add_worksheet(title=current_list, rows=1000, cols=20)

# upload data to new worksheet
f = open(output_csv, "r")
values = [r for r in csv.reader(f)]
worksheet.update(values)

# format the new sheet
formats = [
    {
        "range": "M1:N1",
        "format": {
            "textFormat": {
                "bold": True,
            },
        },
    }
]
worksheet.batch_format(formats)
worksheet.freeze(rows=1, cols=2)
worksheet.columns_auto_resize(start_column_index=0, end_column_index=len(header_row)+2)

# reorder the worksheets
correct_order = [
    spreadsheet.worksheet(current_list),
    spreadsheet.worksheet(previous_list)
]

spreadsheet.reorder_worksheets(correct_order)

end_time = datetime.now()
print("run complete in ",str(end_time - start_time))