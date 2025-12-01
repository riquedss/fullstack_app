# frozen_string_literal: true

# Factories relacionadas ao modelo Payment
FactoryBot.define do
  # Simula a classe Payment (para quitação de dívidas)
  factory :payment do
    association :payer, factory: :user    # Quem pagou a dívida
    association :receiver, factory: :user # Quem recebeu o pagamento
    association :group                   # O grupo ao qual o pagamento pertence
    
    amount { BigDecimal('10.00') }
  end
end