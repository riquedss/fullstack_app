# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'BalanceAggregator Integration', type: :integration do
  let!(:group) { create(:group) }
  let!(:user_a) { create(:user) }
  let!(:user_b) { create(:user) }
  let!(:user_c) { create(:user) }

  let!(:membership_a) { create(:group_membership, group: group, user: user_a, status: 'active') }
  let!(:membership_b) { create(:group_membership, group: group, user: user_b, status: 'active') }
  let!(:membership_c) { create(:group_membership, group: group, user: user_c, status: 'active') }

  describe '#aggregate_balances' do
    it 'agrega saldos e cria gráfico simplificado' do
      expense = create(:expense, group: group, payer: user_a, total_amount: BigDecimal('99.00'))
      create(:expense_participant, expense: expense, user: user_a, amount_owed: BigDecimal('33.00'))
      create(:expense_participant, expense: expense, user: user_b, amount_owed: BigDecimal('33.00'))
      create(:expense_participant, expense: expense, user: user_c, amount_owed: BigDecimal('33.00'))

      calculator = BalanceCalculator.new(group)
      net_balances = calculator.calculate_net_balances
      detailed_balances = calculator.calculate_detailed_balances

      aggregator = BalanceAggregator.new(net_balances, detailed_balances)
      simplified_graph = aggregator.aggregate_balances

      expect(simplified_graph).to have_key(user_b)
      expect(simplified_graph).to have_key(user_c)
      expect(simplified_graph[user_b]).to have_key(user_a)
      expect(simplified_graph[user_c]).to have_key(user_a)

      expect(simplified_graph[user_b][user_a]).to be > BigDecimal('0')
      expect(simplified_graph[user_c][user_a]).to be > BigDecimal('0')
    end

    it 'lida com vários devedores e credores' do
      expense1 = create(:expense, group: group, payer: user_a, total_amount: BigDecimal('90.00'))
      create(:expense_participant, expense: expense1, user: user_b, amount_owed: BigDecimal('30.00'))
      create(:expense_participant, expense: expense1, user: user_c, amount_owed: BigDecimal('30.00'))

      expense2 = create(:expense, group: group, payer: user_b, total_amount: BigDecimal('60.00'))
      create(:expense_participant, expense: expense2, user: user_a, amount_owed: BigDecimal('20.00'))
      create(:expense_participant, expense: expense2, user: user_c, amount_owed: BigDecimal('20.00'))

      calculator = BalanceCalculator.new(group)
      net_balances = calculator.calculate_net_balances
      detailed_balances = calculator.calculate_detailed_balances

      aggregator = BalanceAggregator.new(net_balances, detailed_balances)
      simplified_graph = aggregator.aggregate_balances

      expect(simplified_graph.keys).to include(user_c)
      simplified_graph[user_c].keys.each do |creditor|
        expect([user_a, user_b]).to include(creditor)
      end
    end

    it 'valida saldo geral e faz pequenos ajustes' do
      expense = create(:expense, group: group, payer: user_a, total_amount: BigDecimal('99.01'))
      create(:expense_participant, expense: expense, user: user_a, amount_owed: BigDecimal('33.00'))
      create(:expense_participant, expense: expense, user: user_b, amount_owed: BigDecimal('33.00'))
      create(:expense_participant, expense: expense, user: user_c, amount_owed: BigDecimal('33.01'))

      calculator = BalanceCalculator.new(group)
      net_balances = calculator.calculate_net_balances
      detailed_balances = calculator.calculate_detailed_balances

      expect {
        aggregator = BalanceAggregator.new(net_balances, detailed_balances)
        aggregator.aggregate_balances
      }.not_to raise_error
    end

    it 'dispara erro para grandes descrepâncias no saldo' do
      net_balances = {
        user_a => BigDecimal('100.00'),
        user_b => BigDecimal('50.00'),
        user_c => BigDecimal('0.00')
      }
      detailed_balances = {}

      expect {
        aggregator = BalanceAggregator.new(net_balances, detailed_balances)
        aggregator.aggregate_balances
      }.to raise_error(RuntimeError, /Inconsistência grave no balanço/)
    end
  end
end
