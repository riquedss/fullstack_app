# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'TransactionSimplifier Integration', type: :integration do
  let!(:group) { create(:group) }
  let!(:user_a) { create(:user) }
  let!(:user_b) { create(:user) }
  let!(:user_c) { create(:user) }

  let!(:membership_a) { create(:group_membership, group: group, user: user_a, status: 'active') }
  let!(:membership_b) { create(:group_membership, group: group, user: user_b, status: 'active') }
  let!(:membership_c) { create(:group_membership, group: group, user: user_c, status: 'active') }

  describe '#simplify_transactions' do
    it 'remove dívidas conflitantes' do
      debt_graph = {
        user_a => { user_b => BigDecimal('50.00') },
        user_b => { user_a => BigDecimal('30.00') }
      }

      simplifier = TransactionSimplifier.new(debt_graph)
      simplified = simplifier.simplify_transactions

      expect(simplified).to have_key(user_a)
      expect(simplified[user_a]).to have_key(user_b)
      expect(simplified[user_a][user_b]).to eq(BigDecimal('20.00'))
      expect(simplified).not_to have_key(user_b)
    end

    it 'remove ciclo com 3 ou mais usuários' do
      debt_graph = {
        user_a => { user_b => BigDecimal('25.00') },
        user_b => { user_c => BigDecimal('25.00') },
        user_c => { user_a => BigDecimal('25.00') }
      }

      simplifier = TransactionSimplifier.new(debt_graph)
      simplified = simplifier.simplify_transactions

      expect(simplified).to be_empty
    end

    it 'lida com remoção parcial do ciclo' do
      debt_graph = {
        user_a => { user_b => BigDecimal('30.00') },
        user_b => { user_c => BigDecimal('20.00') },
        user_c => { user_a => BigDecimal('10.00') }
      }

      simplifier = TransactionSimplifier.new(debt_graph)
      simplified = simplifier.simplify_transactions

      expect(simplified[user_a][user_b]).to eq(BigDecimal('20.00'))
      expect(simplified[user_b][user_c]).to eq(BigDecimal('10.00'))
      expect(simplified.keys).not_to include(user_c)
    end

    it 'remove dívidas muito pequenas' do
      debt_graph = {
        user_a => { 
          user_b => BigDecimal('50.00'),
          user_c => BigDecimal('0.005')
        },
        user_b => { user_a => BigDecimal('0.008') }
      }

      simplifier = TransactionSimplifier.new(debt_graph)
      simplified = simplifier.simplify_transactions

      expect(simplified[user_a]).to have_key(user_b)
      expect(simplified[user_a]).not_to have_key(user_c)
      expect(simplified).not_to have_key(user_b)
    end

    it 'lidar com cenários com múltiplos usuários' do
      debt_graph = {
        user_a => { 
          user_b => BigDecimal('40.00'),
          user_c => BigDecimal('15.00')
        },
        user_b => { 
          user_a => BigDecimal('20.00'),
          user_c => BigDecimal('30.00')
        },
        user_c => { 
          user_a => BigDecimal('10.00')
        }
      }

      simplifier = TransactionSimplifier.new(debt_graph)
      simplified = simplifier.simplify_transactions

      expect(simplified[user_a][user_b]).to eq(BigDecimal('20.00'))
      expect(simplified[user_a][user_c]).to eq(BigDecimal('5.00'))
      expect(simplified[user_b]).not_to have_key(user_a)
      expect(simplified[user_b][user_c]).to eq(BigDecimal('30.00'))

      expect(simplified.keys).to include(user_a, user_b)
      expect(simplified.keys).not_to include(user_c)
    end

    it 'tem tolerância a valores válidos' do
      debt_graph = {
        user_a => { user_b => BigDecimal('0.05') }
      }

      simplifier_default = TransactionSimplifier.new(debt_graph)
      simplified_default = simplifier_default.simplify_transactions
      expect(simplified_default[user_a][user_b]).to eq(BigDecimal('0.05'))

      simplifier_high = TransactionSimplifier.new(debt_graph, tolerance: BigDecimal('0.10'))
      simplified_high = simplifier_high.simplify_transactions
      expect(simplified_high).to be_empty
    end

    it 'não modifica o gráfico original' do
      original_graph = {
        user_a => { user_b => BigDecimal('50.00') },
        user_b => { user_a => BigDecimal('30.00') }
      }

      simplifier = TransactionSimplifier.new(original_graph)
      simplified = simplifier.simplify_transactions

      expect(original_graph[user_a][user_b]).to eq(BigDecimal('50.00'))
      expect(original_graph[user_b][user_a]).to eq(BigDecimal('30.00'))

      expect(simplified[user_a][user_b]).to eq(BigDecimal('20.00'))
      expect(simplified).not_to have_key(user_b)
    end
  end

  describe 'integração com outros serviços' do
    it 'funciona com uma saída de BalanceCalculator' do
      # Create a realistic scenario
      expense = create(:expense, group: group, payer: user_a, total_amount: BigDecimal('90.00'))
      create(:expense_participant, expense: expense, user: user_b, amount_owed: BigDecimal('30.00'))
      create(:expense_participant, expense: expense, user: user_c, amount_owed: BigDecimal('30.00'))

      create(:payment, group: group, payer: user_b, receiver: user_a, amount: BigDecimal('20.00'))

      calculator = BalanceCalculator.new(group)
      detailed_balances = calculator.calculate_detailed_balances

      simplifier = TransactionSimplifier.new(detailed_balances)
      simplified = simplifier.simplify_transactions

      expect(simplified).to be_a(Hash)
      if simplified.any?
        simplified.each do |debtor, creditors|
          creditors.each do |creditor, amount|
            expect(amount).to be > BigDecimal('0')
          end
        end
      end
    end
  end
end
