FactoryBot.define do
  factory :payment do
    amount { Faker::Number.decimal(l_digits: 2, r_digits: 2) }
    payment_date { Date.today }
    currency { 'BRL' }
    group { association :group }
    payer { association :user }
    receiver { association :user }
  end
end
