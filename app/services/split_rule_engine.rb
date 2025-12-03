# fullstack_app/app/services/split_rule_engine.rb
require "bigdecimal"

class SplitRuleEngine
  def initialize(expense)
    @expense = expense
    @participants = expense.group.active_members.to_a # Assumindo que todos os membros ativos são potenciais participantes
    @total_amount = expense.total_amount
  end

  # Aplica a lógica de divisão da despesa com base no método especificado.
  # @param splitting_method [Symbol] O método de divisão (:equally, :by_percentages, :by_weights, :by_fixed_amounts).
  # @param params [Hash] Parâmetros adicionais necessários para o método de divisão.
  # @return [Hash<User, BigDecimal>] Um hash mapeando usuários para seus montantes devidos.
  # @raise [ArgumentError] Se não houver participantes ativos ou o método de divisão for desconhecido.
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
  # Trata o restante devido a arredondamento.
  # @return [Hash<User, BigDecimal>] Hash de montantes por participante.
  def split_equally
    num_participants = @participants.size
    base_amount = (@total_amount / num_participants).round(2)
    remainder = @total_amount - (base_amount * num_participants)

    participant_amounts = @participants.map { |user| [ user, base_amount ] }.to_h

    # Distribui o restante (devido a arredondamento) para um participante arbitrário, aqui o primeiro
    if remainder != 0
      participant_amounts[@participants.first] += remainder.round(2)
    end

    validate_total_match(participant_amounts)
    participant_amounts
  end

  # Divide a despesa com base em porcentagens especificadas para cada participante.
  # @param percentages [Hash<Integer, Numeric>] Hash mapeando user_id para a porcentagem.
  # @return [Hash<User, BigDecimal>] Hash de montantes por participante.
  # @raise [ArgumentError] Se as porcentagens forem inválidas ou não somarem 100%.
  def split_by_percentages(percentages)
    unless percentages.is_a?(Hash) && percentages.values.all? { |p| p.is_a?(Numeric) && p >= 0 }
      raise ArgumentError, "As porcentagens devem ser um hash com user_id como chave e valores numéricos não negativos."
    end

    unless percentages.values.sum.round(2) == BigDecimal("100.00")
      raise ArgumentError, "A soma das porcentagens deve ser 100% (atual: #{percentages.values.sum.round(2)}%)."
    end

    participant_amounts = {}
    percentages.each do |user_id, percentage|
      user = @participants.find { |p| p.id == user_id }
      raise ArgumentError, "Usuário com ID #{user_id} não é um participante ativo do grupo." unless user
      participant_amounts[user] = (@total_amount * BigDecimal(percentage) / 100).round(2)
    end

    # Ajustar o total para garantir que a soma seja exata, devido a arredondamento
    actual_sum = participant_amounts.values.sum.round(2)
    if actual_sum != @total_amount.round(2)
      difference = @total_amount.round(2) - actual_sum
      # Distribui a diferença para um participante arbitrário (o primeiro)
      participant_amounts[participant_amounts.keys.first] += difference.round(2)
    end

    validate_total_match(participant_amounts)
    participant_amounts
  end

  # Divide a despesa com base em pesos especificados para cada participante.
  # @param weights [Hash<Integer, Numeric>] Hash mapeando user_id para o peso.
  # @return [Hash<User, BigDecimal>] Hash de montantes por participante.
  # @raise [ArgumentError] Se os pesos forem inválidos ou sua soma for zero.
  def split_by_weights(weights)
    unless weights.is_a?(Hash) && weights.values.all? { |w| w.is_a?(Numeric) && w > 0 }
      raise ArgumentError, "Os pesos devem ser um hash com user_id como chave e valores numéricos positivos."
    end

    total_weights = weights.values.sum.to_f
    raise ArgumentError, "A soma dos pesos deve ser maior que zero." if total_weights == 0

    participant_amounts = {}
    weights.each do |user_id, weight|
      user = @participants.find { |p| p.id == user_id }
      raise ArgumentError, "Usuário com ID #{user_id} não é um participante ativo do grupo." unless user
      participant_amounts[user] = (@total_amount * (BigDecimal(weight) / BigDecimal(total_weights))).round(2)
    end

    # Ajustar o total para garantir que a soma seja exata, devido a arredondamento
    actual_sum = participant_amounts.values.sum.round(2)
    if actual_sum != @total_amount.round(2)
      difference = @total_amount.round(2) - actual_sum
      # Distribui a diferença para um participante arbitrário (o primeiro)
      participant_amounts[participant_amounts.keys.first] += difference.round(2)
    end

    validate_total_match(participant_amounts)
    participant_amounts
  end

  # Divide a despesa com base em valores fixos especificados para cada participante.
  # @param amounts [Hash<Integer, Numeric>] Hash mapeando user_id para o valor fixo.
  # @return [Hash<User, BigDecimal>] Hash de montantes por participante.
  # @raise [ArgumentError] Se os valores fixos forem inválidos ou não somarem o total da despesa.
  def split_by_fixed_amounts(amounts)
    unless amounts.is_a?(Hash) && amounts.values.all? { |a| a.is_a?(Numeric) && a >= 0 }
      raise ArgumentError, "Os valores fixos devem ser um hash com user_id como chave e valores numéricos não negativos."
    end

    # Valida se todos os usuários fornecidos em amounts são participantes ativos do grupo
    amounts.keys.each do |user_id|
      user = @participants.find { |p| p.id == user_id }
      raise ArgumentError, "Usuário com ID #{user_id} não é um participante ativo do grupo." unless user
    end

    sum_fixed_amounts = amounts.values.sum.round(2)

    if sum_fixed_amounts != @total_amount.round(2)
      raise ArgumentError, "A soma dos valores fixos (#{sum_fixed_amounts}) não corresponde ao total da despesa (#{@total_amount.round(2)})."
    end

    participant_amounts = {}
    amounts.each do |user_id, amount|
      user = @participants.find { |p| p.id == user_id } # Já validado acima, mas para consistência
      participant_amounts[user] = BigDecimal(amount).round(2)
    end

    validate_total_match(participant_amounts)
    participant_amounts
  end

  # Valida se a soma das parcelas calculadas corresponde ao montante total da despesa.
  # @param calculated_amounts [Hash<User, BigDecimal>] Hash de montantes por participante.
  # @raise [RuntimeError] Se a soma das parcelas não corresponder ao montante total.
  def validate_total_match(calculated_amounts)
    sum_of_parts = calculated_amounts.values.sum.round(2)
    unless sum_of_parts == @total_amount.round(2)
      raise "Erro de validação interna: A soma das parcelas calculadas (#{sum_of_parts}) não corresponde ao montante total da despesa (#{@total_amount.round(2)})."
    end
  end
end
