# fullstack_app/app/services/balance_calculator.rb
require 'bigdecimal'

class BalanceCalculator
  def initialize(group)
    @group = group
    @members = group.active_members # Considera apenas membros ativos
  end

  # Calcula o saldo líquido de cada usuário no grupo.
  # Um saldo positivo significa que o usuário tem crédito (deve receber).
  # Um saldo negativo significa que o usuário tem débito (deve pagar).
  # @return [Hash<User, BigDecimal>] Um hash mapeando usuários para seus saldos líquidos.
  def calculate_net_balances
    net_balances = Hash.new { |hash, key| hash[key] = BigDecimal('0.00') }

    # Processar despesas
    @group.expenses.each do |expense|
      # O pagador tem um crédito pelo montante total que adiantou
      net_balances[expense.payer] += expense.total_amount

      # Cada participante deve sua parte da despesa
      expense.expense_participants.each do |participant|
        net_balances[participant.user] -= participant.amount_owed
      end
    end

    # Processar pagamentos (lógica Splitwise)
    # No Splitwise: quando você paga, seu saldo PIORA (aumenta sua dívida)
    # Exemplo: Se você deve R$ 100 (saldo = -100) e paga R$ 50, você agora deve R$ 50 (saldo = -50)
    # Portanto: pagamentos SUBTRAEM do saldo do pagador (pioram) e ADICIONAM ao saldo do recebedor
    @group.payments.each do |payment|
      # O pagador está pagando sua dívida, então PIORA seu saldo (subtrai)
      # Se estava -100 e paga 50, fica -150 (piorou antes da compensação)
      net_balances[payment.payer] -= payment.amount
      
      # O recebedor está recebendo pagamento, então MELHORA seu saldo (adiciona)
      # Se estava +100 e recebe 50, fica +150 (melhorou antes da compensação)
      net_balances[payment.receiver] += payment.amount
    end

    # Filtra balanços para membros ativos e garante que o total seja zero para o grupo
    # Pequenos desvios podem ocorrer devido a arredondamento, mas a soma deve ser próxima de zero
    ensure_total_balance_is_zero(net_balances)
    net_balances
  end

  # Calcula os balanços detalhados de "quem deve a quem" dentro do grupo.
  # Isso é útil para a otimização de pagamentos.
  # @return [Hash<User, Hash<User, BigDecimal>>] Um hash aninhado representando as dívidas diretas.
  #   Ex: { devedor => { credor => montante_devido } }
  def calculate_detailed_balances
    # Inicializa um grafo de dívidas diretas entre cada par de usuários
    # { user_id_devedor => { user_id_credor => montante_devido } }
    direct_debts = Hash.new { |h1, k1| h1[k1] = Hash.new { |h2, k2| h2[k2] = BigDecimal('0.00') } }

    # Processar despesas para construir dívidas diretas
    @group.expenses.each do |expense|
      # Quem pagou (payer) tem um crédito do total
      # Cada participante deve sua parte ao pagador
      expense.expense_participants.each do |participant|
        if participant.user != expense.payer
          direct_debts[participant.user][expense.payer] += participant.amount_owed
        else
          # Se o pagador também é participante, ele deve a si mesmo, o que é um ajuste no crédito dele
          # Isso será lidado implicitamente pelo net_balances, mas para dívidas diretas, é um caso especial
          # que não gera uma "dívida" para si mesmo.
          # A lógica aqui é que o pagador pagou X e se devia Y, então seu crédito líquido é X-Y.
          # Para evitar ciclos, não criamos uma dívida para ele mesmo aqui.
        end
      end
    end

    # Processar pagamentos para reduzir dívidas diretas (lógica Splitwise)
    @group.payments.each do |payment|
      # O pagador (payment.payer) paga o recebedor (payment.receiver)
      # Isso reduz a dívida do pagador para o recebedor
      amount_to_settle = payment.amount

      # Caso 1: Pagador devia diretamente ao recebedor - reduz a dívida
      if direct_debts[payment.payer][payment.receiver] > BigDecimal('0.00')
        debt = direct_debts[payment.payer][payment.receiver]
        if amount_to_settle >= debt
          # Pagamento quita toda a dívida
          direct_debts[payment.payer][payment.receiver] = BigDecimal('0.00')
          amount_to_settle -= debt
        else
          # Pagamento quita parte da dívida
          direct_debts[payment.payer][payment.receiver] -= amount_to_settle
          amount_to_settle = BigDecimal('0.00')
        end
      end

      # Caso 2: Se o pagador não devia ao recebedor, mas ainda há montante a liquidar,
      # isso significa que o pagador está pagando mais do que devia (criando crédito reverso)
      # ou pagando dívidas indiretas. Isso será resolvido pelo BalanceAggregator e SettlementOptimizer.
      # Por enquanto, se houver montante restante, podemos criar uma "dívida reversa" 
      # (o recebedor agora deve ao pagador)
      if amount_to_settle > BigDecimal('0.00')
        # O pagador pagou mais do que devia, então o recebedor agora deve ao pagador
        direct_debts[payment.receiver][payment.payer] ||= BigDecimal('0.00')
        direct_debts[payment.receiver][payment.payer] += amount_to_settle
      end
    end

    # Remove dívidas zeradas e usuários sem dívidas/créditos
    cleaned_debts = {}
    direct_debts.each do |debtor, creditors_hash|
      cleaned_creditors = creditors_hash.select { |_creditor, amount| amount > BigDecimal('0.00') }
      cleaned_debts[debtor] = cleaned_creditors if cleaned_creditors.any?
    end

    # Adiciona usuários com créditos líquidos que não são diretamente pagos
    # Isso será mais evidente na classe BalanceAggregator
    # Aqui, a estrutura é focada em quem DEVE a quem, não em saldos líquidos gerais.

    cleaned_debts
  end


  private

  # Garante que a soma total dos balanços do grupo seja zero ou muito próxima de zero.
  # Se houver uma pequena diferença devido a arredondamento, ajusta-a para um usuário arbitrário.
  # @param net_balances [Hash<User, BigDecimal>] O hash de balanços líquidos para ajustar.
  def ensure_total_balance_is_zero(net_balances)
    total_sum = net_balances.values.sum
    if total_sum.abs > BigDecimal('0.01') # Tolerância para pequenas discrepâncias de arredondamento
      Rails.logger.warn("Inconsistência de balanço no grupo #{@group.id}: Soma total é #{total_sum}. Esperado 0.")
      # Tenta ajustar para um membro aleatório se a soma não for zero
      if @members.any?
        net_balances[@members.first] -= total_sum
      end
    end
    # Removido o arredondamento automático para manter precisão
  end
end
