# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'SplitRuleEngine Integration', type: :integration do
  let!(:group) { create(:group) }
  let!(:user_a) { group.creator } # Use the group creator as user_a (already has active membership)
  let!(:user_b) { create(:user) }
  let!(:user_c) { create(:user) }

  let!(:membership_b) { create(:group_membership, group: group, user: user_b, status: 'active') }
  let!(:membership_c) { create(:group_membership, group: group, user: user_c, status: 'active') }

  let(:expense) { build(:expense, group: group, payer: user_a, total_amount: BigDecimal('100.00')) }

  before do
    # Mock expense participants for the engine
    allow(expense).to receive(:group).and_return(group)
    allow(expense).to receive(:total_amount).and_return(BigDecimal('100.00'))
  end

  describe '#apply_split' do
    it 'splits equally among active members' do
      engine = SplitRuleEngine.new(expense)
      result = engine.apply_split(:equally)

      expect(result.keys).to contain_exactly(user_a, user_b, user_c)
      expect(result[user_a]).to eq(BigDecimal('33.34'))
      expect(result[user_b]).to eq(BigDecimal('33.33'))
      expect(result[user_c]).to eq(BigDecimal('33.33'))
      expect(result.values.sum).to eq(BigDecimal('100.00'))
    end

    it 'splits by percentages' do
      percentages = {
        user_a.id => 50,
        user_b.id => 30,
        user_c.id => 20
      }

      engine = SplitRuleEngine.new(expense)
      result = engine.apply_split(:by_percentages, percentages: percentages)

      expect(result[user_a]).to eq(BigDecimal('50.00'))
      expect(result[user_b]).to eq(BigDecimal('30.00'))
      expect(result[user_c]).to eq(BigDecimal('20.00'))
      expect(result.values.sum).to eq(BigDecimal('100.00'))
    end

    it 'divide por peso' do
      weights = {
        user_a.id => 2,
        user_b.id => 3,
        user_c.id => 5
      }

      engine = SplitRuleEngine.new(expense)
      result = engine.apply_split(:by_weights, weights: weights)

      expect(result[user_a]).to eq(BigDecimal('20.00'))
      expect(result[user_b]).to eq(BigDecimal('30.00'))
      expect(result[user_c]).to eq(BigDecimal('50.00'))
      expect(result.values.sum).to eq(BigDecimal('100.00'))
    end

    it 'divide por quantidades fixas' do
      amounts = {
        user_a.id => 60.00,
        user_b.id => 25.00,
        user_c.id => 15.00
      }

      engine = SplitRuleEngine.new(expense)
      result = engine.apply_split(:by_fixed_amounts, amounts: amounts)

      expect(result[user_a]).to eq(BigDecimal('60.00'))
      expect(result[user_b]).to eq(BigDecimal('25.00'))
      expect(result[user_c]).to eq(BigDecimal('15.00'))
      expect(result.values.sum).to eq(BigDecimal('100.00'))
    end

    it 'dispara erro quando recebe método desconhecido' do
      engine = SplitRuleEngine.new(expense)
      expect {
        engine.apply_split(:unknown_method)
      }.to raise_error(ArgumentError, /Método de divisão desconhecido/)
    end

    it 'dispara erro quando não há participantes ativos' do
      empty_group = create(:group)
      empty_group.group_memberships.first.update!(status: 'inactive')
      empty_expense = build(:expense, group: empty_group, total_amount: BigDecimal('100.00'))

      engine = SplitRuleEngine.new(empty_expense)
      expect {
        engine.apply_split(:equally)
      }.to raise_error(ArgumentError, /Não há participantes ativos/)
    end
  end
end
