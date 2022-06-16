require 'json'
require 'stripe'
require 'dotenv/load'
require 'date'
require 'csv'
require 'active_support/core_ext/time'
require 'MailchimpMarketing'

Stripe.api_key = ENV['STRIPE_SECRET_KEY']
subscriptions = Stripe::Subscription.list({ status: 'all' })

mailchimp = MailchimpMarketing::Client.new
mailchimp.set_config({
  api_key: ENV['MAILCHIMP_API_KEY'],
  server: ENV['MAILCHIMP_SERVER_PREFIX']
})

members = []

subscriptions.auto_paging_each do |s|
  puts "Processing Subscription #{s.id}"

  subscription_start = Time.at(s.start_date).in_time_zone('America/Chicago')
  customer = Stripe::Customer.retrieve(s.customer)

  city = if customer.address[:city].present?
    customer.address[:city]
  elsif customer.shipping[:address].present? && customer.shipping[:address][:city].present?
    customer.shipping[:address][:city]
  else
    ''
  end

  state = if customer.address[:state].present?
    customer.address[:state]
  elsif customer.shipping[:address].present? && customer.shipping[:address][:state].present?
    customer.shipping[:address][:state]
  else
    ''
  end

  additional_donations = Stripe::InvoiceItem.list({customer: customer}).data.select { |invoice_item| invoice_item.description == 'One-Time Donation' }.sum(&:amount) / 100.0

  # Mailing List
  mailing_list_status = nil
  email_hash = Digest::MD5.hexdigest(customer.email.downcase)

  # Check if user exists in Mailchimp
  begin
    response = mailchimp.lists.get_list_member(ENV['MAILCHIMP_LIST_ID'], email_hash)
    mailing_list_status = response['status']
  rescue MailchimpMarketing::ApiError => e
    if e.status == 404
      mailing_list_status = 'need_to_add'
    else
      raise e
    end
  end

  if mailing_list_status == 'need_to_add'
    puts "Adding #{customer.email} to list"

    response = mailchimp.lists.add_list_member(ENV['MAILCHIMP_LIST_ID'], {
      email_address: customer.email.downcase,
      status: 'subscribed',
      merge_fields: {
        FNAME: customer.name.split(' ', 2)[0],
        LNAME: customer.name.split(' ', 2)[1]
      }
    })

    mailing_list_status = 'subscribed'
  end

  # If member is subscribed but missing the Member tag
  if mailing_list_status == 'subscribed' && s.status == 'active' && response['tags'].select { |t| t['name'] == 'Member' }.empty?
    puts "Adding Member Tag for #{customer.email}"

    mailchimp.lists.update_list_member_tags(ENV['MAILCHIMP_LIST_ID'], email_hash, {
      tags: [
        {
          name: 'Member',
          status: 'active'
        }
      ]
    })
  end

  # TODO: remove expired members from mailing list

  members.push({
    name: customer.name,
    email: customer.email,
    city: city,
    state: state,
    subscription_status: s.status,
    subscription_start: Time.at(s.start_date).in_time_zone('America/Chicago'),
    additional_donations: additional_donations.positive? ? "$#{additional_donations}" : '',
    mailing_list_status: mailing_list_status,
    subscription_id: s.id
  })
end

member_count = 0

CSV.open('output/members.csv', 'wb') do |csv|
  csv << ['#','Name', 'Email', 'City', 'State', 'Member Status', 'Member Since', 'Donations', 'Mailing List', 'Stripe ID']

  members.sort_by { |m| m[:subscription_start] }.each do |member|
    member_count += 1 if member[:subscription_status] == 'active'
    csv << [
      member[:subscription_status] == 'active' ? member_count : '',
      member[:name],
      member[:email],
      member[:city],
      member[:state],
      member[:subscription_status],
      member[:subscription_start].strftime('%Y-%m-%d'),
      member[:additional_donations],
      member[:mailing_list_status],
      member[:subscription_id]
    ]
  end
end
