# frozen_string_literal: true

require 'rails_helper'
require 'benchmark'
require 'memory_profiler'

RSpec.describe 'Requisitos de Performance', type: :system, js: true do
  let!(:user) { create(:user, email: 'test@example.com', name: 'Test User') }
  let!(:group) { create(:group, name: 'Grupo Performance Test', creator: user) }
  let!(:members) { create_list(:user, 10) }
  
  before do
    members.each { |member| create(:group_membership, group: group, user: member, status: 'active') }

    10.times do
      expense = create(:expense, group: group, payer: members.sample, total_amount: rand(50..500))
      members.sample(3).each do |member|
        ExpenseParticipant.create!(
          expense: expense,
          user: member,
          amount_owed: rand(10..100)
        )
      end
    end

    10.times do
      payer = members.sample
      receiver = (members - [payer]).sample
      create(:payment, group: group, payer: payer, receiver: receiver, amount: rand(20..200))
    end
  end

  def login(user)
    visit '/'
    fill_in 'Email', with: user.email
    fill_in 'Senha', with: 'password'
    click_button 'Entrar'
  end

  describe 'Performance de Carregamento de Página' do
    it 'carrega lista de grupos dentro do tempo aceitável', :performance do
      
      load_time = Benchmark.measure do
        login(user)
        expect(page).to have_content('Meus Grupos')
      end
      
      expect(load_time.real).to be < 3.0
    end

    it 'realiza operações de banco de dados eficientemente', :performance do
      login(user)

      find('.group-item', text: group.name).click
      
      click_button 'Adicionar Despesa'

      fill_in 'Descrição', with: 'Despesa Performance Test'
      fill_in 'Valor', with: '150.00'
      
      check members.first.name
      check members.second.name
      
      load_time = Benchmark.measure do
        click_button 'Salvar Despesa'
        
        expect(page).to have_content('Despesa Performance Test')
      end
      
      expect(load_time.real).to be < 2.0
    end
  end

  after do
    Capybara.reset_sessions!
  end
end
