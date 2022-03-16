require 'json'
require 'stripe'
require 'dotenv/load'
require 'date'
require 'csv'

Stripe.api_key = ENV['STRIPE_SECRET_KEY']

subscriptions = Stripe::Subscription.list({limit: 100}) # TODO: pagination once we're over 100 members

CSV.open('output/members.csv', 'wb') do |csv|
  csv << ['#', 'Member Since', 'Name', 'Email', 'Additional Donation', 'Spring Singles League']

  subscriptions.sort_by(&:start_date).each_with_index do |s, i|
    subscription_start = Time.at(s.start_date).to_datetime # TODO: specify timezone
    customer = Stripe::Customer.retrieve(s.customer)
    additional_donation = Stripe::InvoiceItem.list({customer: customer}).data.select { |invoice_item| invoice_item.description == 'One-Time Donation' }.sum(&:amount)
    singles_league = Stripe::InvoiceItem.list({customer: customer}).data.select { |invoice_item| invoice_item.description == 'Singles League - Spring 2022' }.any?

    csv << [
      i + 1,
      subscription_start.strftime('%Y-%m-%d'),
      customer.name,
      customer.email,
      '%.2f' % (additional_donation.to_f / 100),
      singles_league
    ]
  end
end
