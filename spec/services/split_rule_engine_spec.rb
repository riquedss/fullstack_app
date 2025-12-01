require 'rails_helper'
require 'bigdecimal'

RSpec.describe SplitRuleEngine, type: :service do

  let!(:user_a) { create(:user, id: 10, email: 'a@example.com') }
  let!(:user_b) { create(:user, id: 20, email: 'b@example.com') }
  let!(:user_c) { create(:user, id: 30, email: 'c@example.com') }
  let!(:group) { create(:group) }

  let(:expense) {
    instance_double(
      'Expense',
      total_amount: BigDecimal('10.00'),
      group: instance_double('Group', active_members: [user_a, user_b, user_c])
    )
  }
  subject { SplitRuleEngine.new(expense) }



  context '#apply_split' do
  
    it 'levanta um ArgumentError se não houver participantes ativos no grupo' do
      empty_expense = instance_double('Expense', total_amount: BigDecimal('10.00'), group: instance_double('Group', active_members: []))
      engine = SplitRuleEngine.new(empty_expense)
      expect {
        engine.apply_split(:equally)
      }.to raise_error(ArgumentError, /Não há participantes ativos no grupo/)
    end

    it 'levanta um ArgumentError para um método de divisão desconhecido' do
      expect {
        subject.apply_split(:unknown_method)
      }.to raise_error(ArgumentError, /Método de divisão desconhecido/)
    end
  end
  

  describe '#validate_total_match' do

    let(:engine) { SplitRuleEngine.new(expense) }
    

    it 'levanta um RuntimeError se a soma calculada for diferente do total' do

      invalid_amounts = { user_a => BigDecimal('5.00'), user_b => BigDecimal('4.99') }
      
      expect {

        engine.send(:validate_total_match, invalid_amounts)
      }.to raise_error(/Erro de validação interna: A soma das parcelas calculadas \(9\.99\) não corresponde ao montante total da despesa \(10\.0\)/)
    end
  end


  describe 'Divisão por :equally' do

    it 'calcula o valor base e distribui o restante (remainder) para o primeiro participante' do
      expense_unrounded = instance_double('Expense', total_amount: BigDecimal('10.01'), group: instance_double('Group', active_members: [user_a, user_b, user_c]))
      engine = SplitRuleEngine.new(expense_unrounded)
      amounts = engine.apply_split(:equally)
      
      expect(amounts[user_a]).to eq(BigDecimal('3.33')) 
      expect(amounts[user_b]).to eq(BigDecimal('3.34'))
      expect(amounts[user_c]).to eq(BigDecimal('3.34'))
      expect(amounts.values.sum).to eq(BigDecimal('10.01'))
    end
  end


  describe 'Divisão por :by_percentages' do

    it 'levanta um ArgumentError se a soma das porcentagens não for 100%' do
      invalid_percentages = { user_a.id => 50, user_b.id => 30, user_c.id => 10 } # Soma 90
      expect {
        subject.apply_split(:by_percentages, percentages: invalid_percentages)
      }.to raise_error(ArgumentError, /A soma das porcentagens deve ser 100%/)
    end
    

    it 'levanta um ArgumentError se as porcentagens não forem numéricas ou não forem um Hash' do
      expect {
        subject.apply_split(:by_percentages, percentages: { user_a.id => '50%' })
      }.to raise_error(ArgumentError, /devem ser um hash com user_id como chave e valores numéricos/)
    end


    it 'levanta um ArgumentError se o user_id não pertencer a um participante ativo' do
      invalid_percentages = { 999 => 100 } 
      expect {
        subject.apply_split(:by_percentages, percentages: invalid_percentages)
      }.to raise_error(ArgumentError, /não é um participante ativo do grupo/)
    end

    it 'garante que a soma total seja exata, ajustando a diferença para um participante' do
      expense_diff = instance_double(
        'Expense',
        total_amount: BigDecimal('1.00'),
        group: instance_double('Group', active_members: [user_a, user_b])
      )

      percentages_imprecise = { user_a.id => BigDecimal('99.99'), user_b.id => BigDecimal('0.01') } 
      
      engine = SplitRuleEngine.new(expense_diff)
      amounts = engine.apply_split(:by_percentages, percentages: percentages_imprecise)
      
    
      expect(amounts.values.sum).to eq(BigDecimal('1.00')) 
      expect(amounts[user_a]).to be >= BigDecimal('0.99') 
    end
  end



  describe 'Divisão por :by_weights' do

    it 'levanta um ArgumentError se a soma dos pesos for zero' do
      invalid_weights = { user_a.id => 0, user_b.id => 0 }
      expect {
        subject.apply_split(:by_weights, weights: invalid_weights)
      }.to raise_error(ArgumentError, /Os pesos devem ser um hash com user_id como chave e valores numéricos positivos./)
    end
  end



  describe 'Divisão por :by_fixed_amounts' do

    it 'levanta um ArgumentError se a soma dos montantes fixos for diferente do total' do
      invalid_amounts = { user_a.id => 5.00, user_b.id => 3.00, user_c.id => 1.00 } # Soma 9.00 != 10.00
      expect {
        subject.apply_split(:by_fixed_amounts, amounts: invalid_amounts)
      }.to raise_error(ArgumentError, /A soma dos valores fixos \(9\.0\) não corresponde ao total da despesa \(10\.0\)/)
    end


    it 'levanta um ArgumentError se um usuário especificado não for participante ativo' do
      invalid_amounts = { 999 => 10.00 } 
      expect {
        subject.apply_split(:by_fixed_amounts, amounts: invalid_amounts)
      }.to raise_error(ArgumentError, /não é um participante ativo do grupo/)
    end
  end
end