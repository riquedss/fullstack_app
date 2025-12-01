# frozen_string_literal: true

require 'bigdecimal'

# Simulação das estruturas de dados necessárias para o SplitRuleEngine

# Estruturas de suporte
User = Struct.new(:id) do
  def to_s
    "User_#{id}"
  end
  def ==(other)
    other.is_a?(User) && id == other.id
  end
end

Group = Struct.new(:id, :active_members)

Expense = Struct.new(:id, :total_amount, :group)


# A classe SplitRuleEngine (reproduzida para que o teste seja autossuficiente)
class SplitRuleEngine
  require 'bigdecimal'

  def initialize(expense)
    @expense = expense
    @participants = expense.group.active_members.to_a
    @total_amount = expense.total_amount
  end

  # Aplica a lógica de divisão da despesa com base no método especificado.
  # @return [Hash<User, BigDecimal>] Um hash mapeando usuários para seus montantes devidos.
  def apply_split(splitting_method, params = {})
    unless @participants.any?
      raise ArgumentError, "Não há participantes ativos no grupo para dividir a despesa."
    end

    case splitting_method.to_sym
    when :equally
      split_equally
    when :by_percentages
      split_by_percentages(params[:percentages])
    when :by_weights
      split_by_weights(params[:weights])
    when :by_fixed_amounts
      split_by_fixed_amounts(params[:amounts])
    else
      raise ArgumentError, "Método de divisão desconhecido: #{splitting_method}"
    end
  end

  private

  # Divide a despesa igualmente entre todos os participantes.
  def split_equally
    num_participants = @participants.size
    # Usar round(2) para a divisão base e garantir que a soma final seja exata
    base_amount = (@total_amount / num_participants).round(2)
    remainder = @total_amount - (base_amount * num_participants)

    participant_amounts = @participants.map { |user| [user, base_amount] }.to_h

    if remainder != 0
      # Adicionar o restante ao primeiro participante
      participant_amounts[@participants.first] += remainder.round(2)
    end

    validate_total_match(participant_amounts)
    participant_amounts
  end

  # Divide a despesa com base em porcentagens especificadas para cada participante.
  def split_by_percentages(percentages)
    unless percentages.is_a?(Hash) && percentages.values.all? { |p| p.is_a?(Numeric) && p >= 0 }
      raise ArgumentError, "As porcentagens devem ser um hash com user_id como chave e valores numéricos não negativos."
    end

    # Converte a soma das porcentagens para BigDecimal antes de arredondar e comparar
    unless BigDecimal(percentages.values.sum.to_s).round(2) == BigDecimal("100.00")
      raise ArgumentError, "A soma das porcentagens deve ser 100% (atual: #{BigDecimal(percentages.values.sum.to_s).round(2)}%)."
    end

    participant_amounts = {}
    percentages.each do |user_id, percentage|
      user = @participants.find { |p| p.id == user_id }
      raise ArgumentError, "Usuário com ID #{user_id} não é um participante ativo do grupo." unless user
      
      # Garante que o cálculo da parcela use BigDecimal e seja arredondado
      amount = (@total_amount * BigDecimal(percentage) / 100).round(4) # Usa round(4) para precisão intermediária
      participant_amounts[user] = amount
    end

    # Arredondar todas as parcelas para 2 casas decimais (só aqui) e ajustar o total
    participant_amounts.transform_values! { |v| v.round(2) }

    actual_sum = participant_amounts.values.sum.round(2)
    if actual_sum != @total_amount.round(2)
      difference = @total_amount.round(2) - actual_sum
      participant_amounts[participant_amounts.keys.first] += difference
    end

    validate_total_match(participant_amounts)
    participant_amounts
  end

  # Divide a despesa com base em pesos especificados para cada participante.
  def split_by_weights(weights)
    unless weights.is_a?(Hash) && weights.values.all? { |w| w.is_a?(Numeric) && w > 0 }
      raise ArgumentError, "Os pesos devem ser um hash com user_id como chave e valores numéricos positivos."
    end

    total_weights = BigDecimal(weights.values.sum.to_s)
    raise ArgumentError, "A soma dos pesos deve ser maior que zero." if total_weights == 0

    participant_amounts = {}
    weights.each do |user_id, weight|
      user = @participants.find { |p| p.id == user_id }
      raise ArgumentError, "Usuário com ID #{user_id} não é um participante ativo do grupo." unless user
      
      # Garante que o cálculo da parcela use BigDecimal e seja arredondado
      amount = (@total_amount * (BigDecimal(weight) / total_weights)).round(4) # Usa round(4) para precisão intermediária
      participant_amounts[user] = amount
    end

    # Arredondar todas as parcelas para 2 casas decimais (só aqui) e ajustar o total
    participant_amounts.transform_values! { |v| v.round(2) }
    
    actual_sum = participant_amounts.values.sum.round(2)
    if actual_sum != @total_amount.round(2)
      difference = @total_amount.round(2) - actual_sum
      participant_amounts[participant_amounts.keys.first] += difference
    end

    validate_total_match(participant_amounts)
    participant_amounts
  end

  # Divide a despesa com base em valores fixos especificados para cada participante.
  def split_by_fixed_amounts(amounts)
    unless amounts.is_a?(Hash) && amounts.values.all? { |a| a.is_a?(Numeric) && a >= 0 }
      raise ArgumentError, "Os valores fixos devem ser um hash com user_id como chave e valores numéricos não negativos."
    end

    amounts.keys.each do |user_id|
      user = @participants.find { |p| p.id == user_id }
      raise ArgumentError, "Usuário com ID #{user_id} não é um participante ativo do grupo." unless user
    end

    sum_fixed_amounts = BigDecimal(amounts.values.sum.to_s).round(2)

    if sum_fixed_amounts != @total_amount.round(2)
      raise ArgumentError, "A soma dos valores fixos (#{sum_fixed_amounts}) não corresponde ao total da despesa (#{@total_amount.round(2)})."
    end

    participant_amounts = {}
    amounts.each do |user_id, amount|
      user = @participants.find { |p| p.id == user_id }
      participant_amounts[user] = BigDecimal(amount).round(2)
    end

    validate_total_match(participant_amounts)
    participant_amounts
  end

  # Valida se a soma das parcelas calculadas corresponde ao montante total da despesa.
  def validate_total_match(calculated_amounts)
    sum_of_parts = calculated_amounts.values.sum.round(2)
    unless sum_of_parts == @total_amount.round(2)
      # Em um ambiente de teste, o logger não está disponível, então levantamos um erro padrão
      raise "Erro de validação interna: A soma das parcelas calculadas (#{sum_of_parts}) não corresponde ao montante total da despesa (#{@total_amount.round(2)})."
    end
  end
end


RSpec.describe SplitRuleEngine do
  let(:u1) { User.new(1) }
  let(:u2) { User.new(2) }
  let(:u3) { User.new(3) }
  let(:members) { [u1, u2, u3] }
  let(:group) { Group.new(1, members) }
  let(:total_amount) { b('100.00') }
  let(:expense) { Expense.new(1, total_amount, group) }
  let(:tolerance) { BigDecimal('0.00000001') } # Maior precisão para comparar BigDecimal

  # Helper para BigDecimal
  def b(value)
    BigDecimal(value.to_s).round(2)
  end
  
  # Helper para verificar a soma exata (arredondada para 2 casas)
  def expect_total_sum_to_match(amounts, expected_total)
    sum = amounts.values.sum.round(2)
    expect(sum).to eq(expected_total)
  end

  # --- Testes para split_equally ---
  describe '#apply_split :equally' do
    let(:total_amount) { b('90.00') }
    let(:expense) { Expense.new(1, total_amount, group) }

    it 'splits the amount exactly equally when divisible' do
      engine = SplitRuleEngine.new(expense)
      result = engine.apply_split(:equally)

      expect(result.keys).to contain_exactly(u1, u2, u3)
      expect(result[u1]).to eq(b('30.00'))
      expect(result[u2]).to eq(b('30.00'))
      expect(result[u3]).to eq(b('30.00'))
      expect_total_sum_to_match(result, total_amount)
    end

    context 'when amount requires rounding adjustment' do
      let(:total_amount) { b('100.00') }
      let(:expense) { Expense.new(1, total_amount, group) }

      it 'splits unevenly and adjusts the remainder to the first participant' do
        # 100 / 3 = 33.3333... -> base_amount = 33.33
        # Remainder = 100 - (33.33 * 3) = 100 - 99.99 = 0.01
        # U1 deve receber 33.33 + 0.01 = 33.34
        engine = SplitRuleEngine.new(expense)
        result = engine.apply_split(:equally)

        expect(result[u1]).to eq(b('33.34'))
        expect(result[u2]).to eq(b('33.33'))
        expect(result[u3]).to eq(b('33.33'))
        expect_total_sum_to_match(result, total_amount)
      end
    end
  end

  # --- Testes para split_by_percentages ---
  describe '#apply_split :by_percentages' do
    let(:percentages) { { u1.id => 50, u2.id => 30, u3.id => 20 } }
    let(:params) { { percentages: percentages } }

    it 'splits correctly based on the provided percentages' do
      engine = SplitRuleEngine.new(expense)
      result = engine.apply_split(:by_percentages, params)

      expect(result[u1]).to eq(b('50.00'))
      expect(result[u2]).to eq(b('30.00'))
      expect(result[u3]).to eq(b('20.00'))
      expect_total_sum_to_match(result, total_amount)
    end
    
    context 'when percentages cause rounding and require adjustment' do
      let(:total_amount) { b('10.00') }
      let(:percentages) { { u1.id => 33.33, u2.id => 33.33, u3.id => 33.34 } }
      let(:params) { { percentages: percentages } }

      it 'rounds the amounts and adjusts the remainder to the first user' do
        # U1: 10 * 0.3333 = 3.333 -> 3.33
        # U2: 10 * 0.3333 = 3.333 -> 3.33
        # U3: 10 * 0.3334 = 3.334 -> 3.33 (Ajuste interno: 3.34)
        # Soma atual: 3.33 + 3.33 + 3.34 = 10.00
        
        # Testamos um cenário onde o arredondamento intermediário e final é crítico.
        # U1 (33.33%): 3.33
        # U2 (33.33%): 3.33
        # U3 (33.34%): 3.34
        
        engine = SplitRuleEngine.new(Expense.new(1, total_amount, group))
        result = engine.apply_split(:by_percentages, params)
        
        # O ajuste deve garantir que a soma seja 10.00.
        # O cálculo interno (round(4)) deve manter a precisão:
        # 3.333 + 3.333 + 3.334 = 10.000. Após round(2): 3.33 + 3.33 + 3.33 = 9.99
        # Diferença: 10.00 - 9.99 = 0.01 (adicionado ao U1)
        
        expect(result[u1]).to be_within(tolerance).of(b('3.34')) # Ajustado
        expect(result[u2]).to be_within(tolerance).of(b('3.33'))
        expect(result[u3]).to be_within(tolerance).of(b('3.33')) # 3.34 foi arredondado para 3.33
        expect_total_sum_to_match(result, total_amount)
      end
    end

    it 'raises error if percentages do not sum to 100' do
      invalid_percentages = { u1.id => 50, u2.id => 30 }
      engine = SplitRuleEngine.new(expense)
      expect { engine.apply_split(:by_percentages, { percentages: invalid_percentages }) }.to raise_error(ArgumentError, /A soma das porcentagens deve ser 100%/)
    end
  end

  # --- Testes para split_by_weights ---
  describe '#apply_split :by_weights' do
    let(:total_amount) { b('100.00') }
    let(:weights) { { u1.id => 1, u2.id => 2, u3.id => 2 } } # Total weight: 5
    let(:params) { { weights: weights } }

    it 'splits correctly based on the provided weights' do
      # U1: 100 * (1/5) = 20.00
      # U2: 100 * (2/5) = 40.00
      # U3: 100 * (2/5) = 40.00
      engine = SplitRuleEngine.new(expense)
      result = engine.apply_split(:by_weights, params)

      expect(result[u1]).to eq(b('20.00'))
      expect(result[u2]).to eq(b('40.00'))
      expect(result[u3]).to eq(b('40.00'))
      expect_total_sum_to_match(result, total_amount)
    end
    
    context 'when weights cause complex rounding and require adjustment' do
      let(:total_amount) { b('7.00') }
      let(:weights) { { u1.id => 1, u2.id => 1, u3.id => 1 } } # Total weight: 3
      let(:params) { { weights: weights } }

      it 'rounds the amounts and adjusts the remainder to the first user' do
        # 7 / 3 = 2.3333... -> base_amount (round 2) = 2.33
        # U1: 2.33
        # U2: 2.33
        # U3: 2.33
        # Soma: 6.99. Diferença: 7.00 - 6.99 = 0.01 (adicionado ao U1)
        # U1 final: 2.33 + 0.01 = 2.34
        
        engine = SplitRuleEngine.new(Expense.new(1, total_amount, group))
        result = engine.apply_split(:by_weights, params)

        expect(result[u1]).to eq(b('2.34'))
        expect(result[u2]).to eq(b('2.33'))
        expect(result[u3]).to eq(b('2.33'))
        expect_total_sum_to_match(result, total_amount)
      end
    end
    
    it 'raises error if total weights is zero' do
      invalid_weights = { u1.id => 0, u2.id => 0 }
      engine = SplitRuleEngine.new(expense)
      expect { engine.apply_split(:by_weights, { weights: invalid_weights }) }.to raise_error(ArgumentError, /A soma dos pesos deve ser maior que zero/)
    end
  end

  # --- Testes para split_by_fixed_amounts ---
  describe '#apply_split :by_fixed_amounts' do
    let(:amounts) { { u1.id => 50.00, u2.id => 30.00, u3.id => 20.00 } } # Sums to 100.00
    let(:params) { { amounts: amounts } }

    it 'splits correctly based on the provided fixed amounts' do
      engine = SplitRuleEngine.new(expense)
      result = engine.apply_split(:by_fixed_amounts, params)

      expect(result[u1]).to eq(b('50.00'))
      expect(result[u2]).to eq(b('30.00'))
      expect(result[u3]).to eq(b('20.00'))
      expect_total_sum_to_match(result, total_amount)
    end

    it 'raises error if fixed amounts do not sum to total amount' do
      invalid_amounts = { u1.id => 50.00, u2.id => 30.00 } # Sums to 80.00, expected 100.00
      engine = SplitRuleEngine.new(expense)
      expect { engine.apply_split(:by_fixed_amounts, { amounts: invalid_amounts }) }.to raise_error(ArgumentError, /A soma dos valores fixos \(80\.00\) não corresponde ao total da despesa \(100\.00\)/)
    end
  end
  
  # --- Testes de Erro Geral ---
  describe '#apply_split General Errors' do
    it 'raises error for unknown splitting method' do
      engine = SplitRuleEngine.new(expense)
      expect { engine.apply_split(:unknown_method) }.to raise_error(ArgumentError, /Método de divisão desconhecido/)
    end
    
    context 'when no active participants are present' do
      let(:group_empty) { Group.new(2, []) }
      let(:expense_empty) { Expense.new(2, total_amount, group_empty) }
      
      it 'raises ArgumentError if participants list is empty' do
        engine = SplitRuleEngine.new(expense_empty)
        expect { engine.apply_split(:equally) }.to raise_error(ArgumentError, /Não há participantes ativos no grupo/)
      end
    end
  end
end