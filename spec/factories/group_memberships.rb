FactoryBot.define do
  factory :group_membership do
    group { association :group }
    user { association :user }
    status { 'active' }
    joined_at { Time.current }
  end
end
