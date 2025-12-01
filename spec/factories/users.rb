FactoryBot.define do
  factory :user do
    # O erro 'undefined method email=' sugere que o FactoryBot está tentando definir
    # um email, mas o atributo pode ter sido removido ou o factory está malformado.
    # Certifique-se de que o atributo 'email' está presente e que você está usando
    # `sequence` ou `Faker` corretamente para garantir que ele seja único e exista.
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "password" }
    password_confirmation { "password" }
    name { "Test User" }
  end
end