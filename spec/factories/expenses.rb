FactoryBot.define do
  factory :expense do
    description { Faker::Commerce.product_name }
    total_amount { Faker::Number.decimal(l_digits: 2, r_digits: 2) }
    expense_date { Date.today }
    currency { 'BRL' }
    group { association :group }
    payer { association :user }
  end
end
