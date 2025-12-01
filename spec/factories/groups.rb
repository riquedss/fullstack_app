FactoryBot.define do
  factory :group do
    name { Faker::Company.name }
    association :creator, factory: :user # Deve estar aqui!
  end
end