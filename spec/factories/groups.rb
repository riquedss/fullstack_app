FactoryBot.define do
  factory :group do
    name { Faker::Company.unique.name }
    description { Faker::Lorem.sentence }
    creator { association :user }

    after(:create) do |group|
      # Adiciona o criador como membro ativo
      group.group_memberships.create!(
        user: group.creator,
        status: 'active',
        joined_at: Time.current
      )
    end
  end
end
