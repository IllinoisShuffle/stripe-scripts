require 'json'
require 'stripe'
require 'dotenv/load'
require 'date'
require 'csv'
require 'active_support/core_ext/time'

Stripe.api_key = ENV['STRIPE_SECRET_KEY']

subscriptions = Stripe::Subscription.list({status: 'all'})

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

  members.push({
    name: customer.name,
    email: customer.email,
    city: city,
    state: state,
    subscription_status: s.status,
    subscription_start: Time.at(s.start_date).in_time_zone('America/Chicago'),
    additional_donations: additional_donations.positive? ? "$#{additional_donations}" : '',
    subscription_id: s.id
  })
end

member_count = 0

CSV.open('output/members.csv', 'wb') do |csv|
  csv << ['#', 'Name', 'Email', 'City', 'State', 'Status', 'Member Since', 'Donations', 'Stripe ID']

  members.sort_by { |m| m[:subscription_start] }.each_with_index do |member, i|
    member_count += 1 if member[:subscription_status] == 'active'
    csv << [
      member[:subscription_status] == 'active' ? member_count : '',
      member[:name],
      member[:email],
      member[:city],
      member[:state],
      member[:subscription_status],
      member[:subscription_start],
      member[:additional_donations],
      member[:subscription_id]
    ]
  end
end
