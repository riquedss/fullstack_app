# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'BalanceCalculator Integration', type: :integration do
  let!(:group) { create(:group) }
  let!(:user_a) { create(:user) }
  let!(:user_b) { create(:user) }
  let!(:user_c) { create(:user) }

  let!(:membership_a) { create(:group_membership, group: group, user: user_a, status: 'active') }
  let!(:membership_b) { create(:group_membership, group: group, user: user_b, status: 'active') }
  let!(:membership_c) { create(:group_membership, group: group, user: user_c, status: 'active') }

  describe '#calculate_net_balances' do
    it 'calcula o saldo após despesas e pagamentos' do
      expense = create(:expense, group: group, payer: user_a, total_amount: BigDecimal('100.00'))
      create(:expense_participant, expense: expense, user: user_a, amount_owed: BigDecimal('33.34'))
      create(:expense_participant, expense: expense, user: user_b, amount_owed: BigDecimal('33.33'))
      create(:expense_participant, expense: expense, user: user_c, amount_owed: BigDecimal('33.33'))

      payment = create(:payment, group: group, payer: user_b, receiver: user_a, amount: BigDecimal('30.00'))

      calculator = BalanceCalculator.new(group)
      net_balances = calculator.calculate_net_balances

      expect(net_balances[user_a]).to be_within(BigDecimal('0.01')).of(BigDecimal('96.66'))
      expect(net_balances[user_b]).to be_within(BigDecimal('0.01')).of(BigDecimal('-63.33'))
      expect(net_balances[user_c]).to be_within(BigDecimal('0.01')).of(BigDecimal('-33.33'))
      expect(net_balances.values.sum).to be_within(BigDecimal('0.01')).of(BigDecimal('0.00'))
    end

    it 'lida com várias despesas corretamente' do
      expense1 = create(:expense, group: group, payer: user_a, total_amount: BigDecimal('60.00'))
      create(:expense_participant, expense: expense1, user: user_a, amount_owed: BigDecimal('20.00'))
      create(:expense_participant, expense: expense1, user: user_b, amount_owed: BigDecimal('20.00'))
      create(:expense_participant, expense: expense1, user: user_c, amount_owed: BigDecimal('20.00'))

      expense2 = create(:expense, group: group, payer: user_b, total_amount: BigDecimal('90.00'))
      create(:expense_participant, expense: expense2, user: user_a, amount_owed: BigDecimal('30.00'))
      create(:expense_participant, expense: expense2, user: user_b, amount_owed: BigDecimal('30.00'))
      create(:expense_participant, expense: expense2, user: user_c, amount_owed: BigDecimal('30.00'))

      calculator = BalanceCalculator.new(group)
      net_balances = calculator.calculate_net_balances

      expect(net_balances[user_a]).to be_within(BigDecimal('0.01')).of(BigDecimal('10.00'))
      expect(net_balances[user_b]).to be_within(BigDecimal('0.01')).of(BigDecimal('40.00'))
      expect(net_balances[user_c]).to be_within(BigDecimal('0.01')).of(BigDecimal('-50.00'))
      expect(net_balances.values.sum).to be_within(BigDecimal('0.01')).of(BigDecimal('0.00'))
    end
  end

  describe '#calculate_detailed_balances' do
    it 'cria relacionamento de dívida direta' do
      expense = create(:expense, group: group, payer: user_a, total_amount: BigDecimal('90.00'))
      create(:expense_participant, expense: expense, user: user_b, amount_owed: BigDecimal('30.00'))
      create(:expense_participant, expense: expense, user: user_c, amount_owed: BigDecimal('30.00'))

      calculator = BalanceCalculator.new(group)
      detailed_balances = calculator.calculate_detailed_balances

      expect(detailed_balances[user_b][user_a]).to eq(BigDecimal('30.00'))
      expect(detailed_balances[user_c][user_a]).to eq(BigDecimal('30.00'))
      expect(detailed_balances[user_a]).to be_nil # No debts from payer to self
    end

    it 'diminui dívida após pagamentos' do
      expense = create(:expense, group: group, payer: user_a, total_amount: BigDecimal('60.00'))
      create(:expense_participant, expense: expense, user: user_b, amount_owed: BigDecimal('20.00'))

      payment = create(:payment, group: group, payer: user_b, receiver: user_a, amount: BigDecimal('15.00'))

      calculator = BalanceCalculator.new(group)
      detailed_balances = calculator.calculate_detailed_balances

      expect(detailed_balances[user_b][user_a]).to eq(BigDecimal('5.00'))
    end

    it 'cria dívida reversa quando pagamento é maior que a dívida' do
      expense = create(:expense, group: group, payer: user_a, total_amount: BigDecimal('30.00'))
      create(:expense_participant, expense: expense, user: user_b, amount_owed: BigDecimal('20.00'))

      payment = create(:payment, group: group, payer: user_b, receiver: user_a, amount: BigDecimal('30.00'))

      calculator = BalanceCalculator.new(group)
      detailed_balances = calculator.calculate_detailed_balances

      expect(detailed_balances[user_a][user_b]).to eq(BigDecimal('10.00'))
      expect(detailed_balances[user_b]).to be_nil
    end
  end
end
