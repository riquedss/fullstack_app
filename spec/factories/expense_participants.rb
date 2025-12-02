FactoryBot.define do
  factory :expense_participant do
    association :expense
    association :user
    amount_owed { Faker::Number.decimal(l_digits: 2, r_digits: 2) }
  end
end
