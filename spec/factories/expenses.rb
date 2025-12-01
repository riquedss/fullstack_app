# frozen_string_literal: true

# Factories relacionadas aos modelos Expense e Participant
FactoryBot.define do
  # Simula a classe ExpenseParticipant
  factory :participant do
    association :expense # Presume a existência da factory :expense (criada abaixo)
    association :user    # Presume a existência da factory :user
    
    # Valor padrão que pode ser sobrescrito nos testes
    amount_owed { BigDecimal('10.00') } 
  end

  # Simula a classe Expense
  factory :expense do
    # 'payer' é um User que pagou a despesa
    association :payer, factory: :user 
    association :group # A qual grupo pertence a despesa

    total_amount { BigDecimal('30.00') }
    description { Faker::Lorem.sentence } 
    split_type { 'equally' } # Default para SplitRuleEngine

    # Trait para criar participantes automaticamente para cobrir os testes
    trait :with_participants do
      transient do
        # Permite passar uma lista de users ou o número de participantes
        participants_users { [] }
        amounts_owed { [] }
        count { 3 } # Contagem padrão, usada se participants_users for vazio
      end

      after(:create) do |expense, evaluator|
        users = evaluator.participants_users.any? ? 
          evaluator.participants_users : 
          create_list(:user, evaluator.count)

        # Garante que o pagador esteja na lista de users para testes de detalhamento
        payer_is_participant = users.any? { |u| u.id == expense.payer_id }
        users << expense.payer unless payer_is_participant

        users.each_with_index do |user, index|
          # Se amounts_owed foi passado, usa o valor, senão calcula a divisão igual
          amount_owed = evaluator.amounts_owed[index] || (expense.total_amount / users.size).round(2)
          
          # Cria o Participant
          create(:participant, expense: expense, user: user, amount_owed: amount_owed)
        end
      end
    end
  end
end