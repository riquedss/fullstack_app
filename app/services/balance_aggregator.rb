# fullstack_app/app/services/balance_aggregator.rb
require "bigdecimal"

class BalanceAggregator
  # Inicializa o BalanceAggregator com os balanços líquidos e detalhados.
  # @param net_balances [Hash<User, BigDecimal>] Saldos líquidos de cada usuário (calculado pelo BalanceCalculator).
  # @param detailed_balances [Hash<User, Hash<User, BigDecimal>>] Dívidas diretas entre usuários (calculado pelo BalanceCalculator).
  # @param tolerance [BigDecimal] Tolerância para considerar pequenas discrepâncias de arredondamento como zero.
  def initialize(net_balances, detailed_balances, tolerance: BigDecimal("0.01"))
    @net_balances = net_balances.transform_values(&:round) # Garante arredondamento inicial
    @detailed_balances = detailed_balances.transform_values { |v| v.transform_values(&:round) } # Garante arredondamento inicial
    @tolerance = tolerance
  end

  # Consolida os balanços e prepara uma estrutura simplificada de dívidas e créditos.
  # @return [Hash<User, Hash<User, BigDecimal>>] Um grafo de dívidas simplificado (devedor -> credor -> montante).
  # @raise [RuntimeError] Se uma inconsistência grave for detectada.
  def aggregate_balances
    validate_overall_balance
    handle_rounding_discrepancies
    build_simplified_debt_graph
  end

  private

  # Valida se a soma total dos balanços líquidos do grupo é zero (ou dentro da tolerância).
  # @raise [RuntimeError] Se a inconsistência for maior que a tolerância.
  def validate_overall_balance
    total_net_sum = @net_balances.values.sum
    if total_net_sum.abs > @tolerance
      Rails.logger.error("Inconsistência grave no balanço agregado: Soma total é #{total_net_sum}. Esperado 0.")
      raise "Inconsistência grave no balanço: a soma total dos saldos líquidos do grupo não é zero. (Diferença: #{total_net_sum})"
    elsif total_net_sum != BigDecimal("0.00") # Se estiver dentro da tolerância, mas não for exatamente zero
      # Ajustar a pequena diferença para um usuário arbitrário
      Rails.logger.warn("Pequena inconsistência de balanço (arredondamento): Soma total é #{total_net_sum}. Ajustando.")
      adjust_small_discrepancy(total_net_sum)
    end
  end

  # Ajusta pequenas discrepâncias de arredondamento distribuindo-as para um usuário.
  # @param discrepancy [BigDecimal] O valor da discrepância a ser ajustado.
  def adjust_small_discrepancy(discrepancy)
    # Encontra o usuário que mais pagou ou deve, para atribuir a diferença
    # Ou simplesmente atribui ao primeiro usuário na lista de balanços
    if @net_balances.empty?
      Rails.logger.warn("Não há usuários para ajustar a discrepância de balanço de #{discrepancy}.")
      return
    end

    # Prioriza ajustar para o criador do grupo, se disponível, ou o primeiro membro
    user_to_adjust = @net_balances.keys.first # Pode ser refinado para o criador do grupo, ou o maior devedor/credor

    @net_balances[user_to_adjust] -= discrepancy
    Rails.logger.info("Discrepância de #{discrepancy} ajustada para o usuário #{user_to_adjust.id}.")
  end

  # Não faz uma correção de arredondamento agressiva aqui, pois o BalanceCalculator já fez um ajuste.
  # Este método é mais um placeholder para futuras regras de tratamento de valores residuais,
  # como consolidar múltiplas moedas.
  def handle_rounding_discrepancies
    # Lógica para tratar valores residuais ou arredondamentos específicos, se necessário.
    # Por enquanto, assumimos que ensure_total_balance_is_zero já lidou com isso no net_balances.
    # No entanto, detailed_balances podem ter pequenos resíduos que precisam ser limpos.
    @detailed_balances.each do |debtor, creditors|
      creditors.each do |creditor, amount|
        if amount.abs < @tolerance
          @detailed_balances[debtor].delete(creditor) # Remove dívidas muito pequenas
        end
      end
      @detailed_balances.delete(debtor) if @detailed_balances[debtor].empty?
    end
  end

  # Converte os balanços líquidos e detalhados em um grafo simplificado de dívidas para o otimizador.
  # A ideia é ter um mapeamento claro de quem deve a quem, ignorando ciclos intermediários.
  # @return [Hash<User, Hash<User, BigDecimal>>] Grafo de dívidas simplificado.
  def build_simplified_debt_graph
    # Começa com as dívidas diretas e as ajusta com base nos saldos líquidos.
    simplified_graph = Hash.new { |h1, k1| h1[k1] = Hash.new { |h2, k2| h2[k2] = BigDecimal("0.00") } }

    # Popula o grafo com os saldos líquidos: quem tem saldo negativo deve, quem tem saldo positivo recebe.
    # Isso transforma os saldos líquidos em um grafo de dívidas/créditos mais abstrato.
    debtors = @net_balances.select { |_user, amount| amount < BigDecimal("0.00") }
                           .sort_by { |_user, amount| amount } # Maiores devedores primeiro
                           .to_h
    creditors = @net_balances.select { |_user, amount| amount > BigDecimal("0.00") }
                             .sort_by { |_user, amount| -amount } # Maiores credores primeiro
                             .to_h

    # Lógica para criar um grafo de dívidas simples "devedor para credor"
    # Este é um passo crucial para o SettlementOptimizer
    debtors_copy = debtors.dup
    creditors_copy = creditors.dup

    debtors_copy.each do |debtor, debt_amount_raw|
      debt_amount = debt_amount_raw.abs # Valor absoluto da dívida

      creditors_copy.each do |creditor, credit_amount_raw|
        credit_amount = credit_amount_raw # Valor absoluto do crédito

        next if debt_amount <= @tolerance || credit_amount <= @tolerance || debtor == creditor

        payment_amount = [ debt_amount, credit_amount ].min

        simplified_graph[debtor][creditor] += payment_amount

        debt_amount -= payment_amount
        creditors_copy[creditor] -= payment_amount

        break if debt_amount <= @tolerance # Se o devedor já quitou sua parte
      end
    end

    # Limpa as entradas zero
    cleaned_graph = {}
    simplified_graph.each do |debtor, creditors_hash|
      cleaned_creditors = creditors_hash.select { |_creditor, amount| amount > @tolerance }
      cleaned_graph[debtor] = cleaned_creditors if cleaned_creditors.any?
    end

    cleaned_graph
  end
end
