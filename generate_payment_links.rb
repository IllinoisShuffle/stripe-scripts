require 'json'
require 'stripe'
require 'dotenv/load'

# Add Stripe Key
Stripe.api_key = ENV['STRIPE_SECRET_KEY']

# Production Env Price Objects
membership = 'price_1KZA1nG9vhwQIFDD1nEKYXBz'
league = 'price_1KZA2kG9vhwQIFDDkOm9nECq'

donations = {
  0 => nil,
  5 => 'price_1KZA3nG9vhwQIFDDIvwEzhPd',
  10 => 'price_1KZA3nG9vhwQIFDD5p8ok6AG',
  25 => 'price_1KZA3nG9vhwQIFDDd6ViMXJw',
  50 => 'price_1KZA3nG9vhwQIFDDkiCDCTYa',
  100 => 'price_1KZA3nG9vhwQIFDD38RA5rKS',
  250 => 'price_1KZA3nG9vhwQIFDDNFiXOagH',
  500 => 'price_1KZA3nG9vhwQIFDDDDIBiJZr',
  1000 => 'price_1KZA3nG9vhwQIFDDmvjcWdZF'
}

# Test Env Price Objects
# membership = 'price_1KMJ5fG9vhwQIFDDuWlkXVlL'
# league = 'price_1KY1PsG9vhwQIFDDWyhmLBGE'

# donations = {
#   0 => nil,
#   5 => 'price_1KY3wiG9vhwQIFDDphs09C1H',
#   10 => 'price_1KY3wiG9vhwQIFDDMo0VxL5w',
#   25 => 'price_1KY3wiG9vhwQIFDDjVs1Etkx',
#   50 => 'price_1KY3wiG9vhwQIFDDFV1L5qQj',
#   100 => 'price_1KY3wiG9vhwQIFDDLxwNoo4B',
#   250 => 'price_1KY3wiG9vhwQIFDDflhuiFWn',
#   500 => 'price_1KY3wiG9vhwQIFDDm2PKBpJM',
#   1000 => 'price_1KY3wiG9vhwQIFDDU77e6HXD'
# }

output = {
  'no_league' => {},
  'league' => {}
}

donations.each do |amount, id|
  puts "Generating payment links for #{amount}..."

  # Start with membership
  line_items = [{ price: membership, quantity: 1 }]

  # Add donation
  line_items.push({ price: id, quantity: 1 }) if id

  # Create Link with no league
  puts '  No League'
  output['no_league'][amount.to_s] = Stripe::PaymentLink.create(
    line_items: line_items,
    shipping_address_collection: {allowed_countries: ['US']},
  ).url

  # Create Link with league
  puts '  League'
  output['league'][amount.to_s] = Stripe::PaymentLink.create(
    line_items: line_items + [{ price: league, quantity: 1 }],
    shipping_address_collection: {allowed_countries: ['US']},
  ).url
end

puts output.to_json
