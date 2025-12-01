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
      }.to raise_error(/Erro de validação interna: A soma das parcelas calculadas \(9.99\) não corresponde ao montante total da despesa \(10.0\)/)
    end
  end


  describe 'Divisão por :equally' do

    it 'calcula o valor base e distribui o restante (remainder) para o primeiro participante' do
      # 10.01 / 3 = 3.3366... -> 3.34, 3.33, 3.34
      # Base: 3.33. Remainder: 10.01 - (3 * 3.33) = 0.02.
      # Correção: O Ruby fará 3.33 + 3.33 + 3.33 = 9.99, faltando 0.02
      # O código divide 10.01 / 3 = 3.33 e o restante de 0.02 vai para o primeiro.
      expense_unrounded = instance_double('Expense', total_amount: BigDecimal('10.01'), group: instance_double('Group', active_members: [user_a, user_b, user_c]))
      engine = SplitRuleEngine.new(expense_unrounded)
      amounts = engine.apply_split(:equally)
      
      # O primeiro participante recebe o base (3.33) + remainder (0.02)
      expect(amounts[user_a]).to eq(BigDecimal('3.35')) 
      expect(amounts[user_b]).to eq(BigDecimal('3.33'))
      expect(amounts[user_c]).to eq(BigDecimal('3.33'))
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
      # Total: 1.00
      # A: 99.99% de 1.00 = 0.9999 -> 1.00 (round(2))
      # B: 0.01% de 1.00 = 0.0001 -> 0.00 (round(2))
      # Soma calculada: 1.00. Não houve erro de arredondamento neste caso.
      
      # Novo cenário para forçar o ajuste:
      # Total: 0.08
      # A: 50% = 0.04
      # B: 50% = 0.04
      expense_diff = instance_double(
        'Expense',
        total_amount: BigDecimal('0.07'), # Total que causará desvio se dividido em 3
        group: instance_double('Group', active_members: [user_a, user_b, user_c])
      )

      # 33.33% * 0.07 = 0.0233 -> 0.02
      # Soma calculada: 3 * 0.02 = 0.06. Diferença: 0.01.
      percentages_imprecise = { user_a.id => BigDecimal('33.33'), user_b.id => BigDecimal('33.33'), user_c.id => BigDecimal('33.34') } 
      
      engine = SplitRuleEngine.new(expense_diff)
      amounts = engine.apply_split(:by_percentages, percentages: percentages_imprecise)
      
      # Deve ajustar 0.01 para o user_a (o primeiro na lista de chaves)
      expect(amounts.values.sum).to eq(BigDecimal('0.07')) 
      expect(amounts[user_a]).to eq(BigDecimal('0.03')) # 0.02 + 0.01 (ajuste)
      expect(amounts[user_b]).to eq(BigDecimal('0.02'))
      expect(amounts[user_c]).to eq(BigDecimal('0.02')) 
    end
  end



  describe 'Divisão por :by_weights' do
    
    it 'levanta um ArgumentError se os pesos não forem numéricos ou não forem um Hash' do
      invalid_weights = { user_a.id => 1, user_b.id => 'peso' }
      expect {
        subject.apply_split(:by_weights, weights: invalid_weights)
      }.to raise_error(ArgumentError, /Os pesos devem ser um hash com user_id como chave e valores numéricos positivos./)
    end
    
    it 'levanta um ArgumentError se a soma dos pesos for zero' do
      invalid_weights = { user_a.id => 0, user_b.id => 0 }
      expect {
        subject.apply_split(:by_weights, weights: invalid_weights)
      }.to raise_error(ArgumentError, /A soma dos pesos deve ser maior que zero./)
    end
    
    it 'garante que a soma total seja exata, ajustando a diferença para um participante (cobre arredondamento)' do
      # Total: 10.00
      # Pesos: A=1, B=1, C=1. Total=3.
      # A: 10.00 * (1/3) = 3.333... -> 3.33
      # B: 10.00 * (1/3) = 3.333... -> 3.33
      # C: 10.00 * (1/3) = 3.333... -> 3.33
      # Soma calculada: 9.99. Diferença (ajuste): 0.01.
      
      weights_imprecise = { user_a.id => 1, user_b.id => 1, user_c.id => 1 }
      
      amounts = subject.apply_split(:by_weights, weights: weights_imprecise)
      
      # O ajuste de 0.01 deve ir para o user_a (o primeiro na lista de chaves)
      expect(amounts.values.sum).to eq(BigDecimal('10.00')) 
      expect(amounts[user_a]).to eq(BigDecimal('3.34')) # 3.33 + 0.01 (ajuste)
      expect(amounts[user_b]).to eq(BigDecimal('3.33'))
      expect(amounts[user_c]).to eq(BigDecimal('3.33'))
    end

    it 'levanta um ArgumentError se o user_id em pesos não pertencer a um participante ativo' do
      invalid_weights = { 999 => 1, user_a.id => 1 } 
      expect {
        subject.apply_split(:by_weights, weights: invalid_weights)
      }.to raise_error(ArgumentError, /não é um participante ativo do grupo/)
    end
  end



  describe 'Divisão por :by_fixed_amounts' do

    it 'levanta um ArgumentError se a soma dos montantes fixos for diferente do total' do
      invalid_amounts = { user_a.id => 5.00, user_b.id => 3.00, user_c.id => 1.00 } # Soma 9.00 != 10.00
      expect {
        subject.apply_split(:by_fixed_amounts, amounts: invalid_amounts)
      }.to raise_error(ArgumentError, /A soma dos valores fixos \(9.0\) não corresponde ao total da despesa \(10.0\)/)
    end


    it 'levanta um ArgumentError se um usuário especificado não for participante ativo' do
      invalid_amounts = { 999 => 10.00 } 
      expect {
        subject.apply_split(:by_fixed_amounts, amounts: invalid_amounts)
      }.to raise_error(ArgumentError, /não é um participante ativo do grupo/)
    end
    
    it 'calcula corretamente os montantes quando a soma é exata' do
      valid_amounts = { user_a.id => 5.00, user_b.id => 3.00, user_c.id => 2.00 } # Soma 10.00
      amounts = subject.apply_split(:by_fixed_amounts, amounts: valid_amounts)
      
      expect(amounts[user_a]).to eq(BigDecimal('5.00'))
      expect(amounts[user_b]).to eq(BigDecimal('3.00'))
      expect(amounts[user_c]).to eq(BigDecimal('2.00'))
      expect(amounts.values.sum).to eq(BigDecimal('10.00'))
    end
  end
end