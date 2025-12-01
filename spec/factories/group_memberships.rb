# frozen_string_literal: true

FactoryBot.define do
  factory :group_member, class: 'GroupMembership' do
    # O erro 'undefined method active=' é a causa das 15 falhas.
    # Isso indica que o atributo 'active' foi removido da migration/modelo
    # ou não está sendo definido.
    # Adicione `active { true }` para cobrir o uso nos seus testes de balanço.
    # Se você removeu o campo 'active' do modelo, você deve revisar todos os testes
    # que o utilizam, mas o mais provável é que ele ainda seja necessário.
    group
    user
    active { true } # <-- Esta linha é a correção mais provável para o erro!
    is_admin { false }
  end
end