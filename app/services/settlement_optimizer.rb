# fullstack_app/app/services/settlement_optimizer.rb
require "bigdecimal"

class SettlementOptimizer
  # Inicializa o SettlementOptimizer com o grafo de dívidas simplificado.
  # O grafo deve ser no formato { devedor => { credor => montante } }.
  # @param simplified_debt_graph [Hash<User, Hash<User, BigDecimal>>] Grafo de dívidas.
  # @param tolerance [BigDecimal] Tolerância para considerar um balanço como zero.
  def initialize(simplified_debt_graph, tolerance: BigDecimal("0.01"))
    @simplified_debt_graph = simplified_debt_graph
    @tolerance = tolerance
  end

  # Gera o conjunto mínimo de pagamentos necessários para liquidar todas as dívidas.
  # O algoritmo busca identificar os maiores devedores e maiores credores e criar pagamentos diretos.
  # @return [Array<Hash>] Uma lista de pagamentos sugeridos, cada um com :payer, :receiver, :amount.
  def generate_optimized_payments
    # Inicializa os saldos líquidos a partir do grafo de dívidas para identificar credores e devedores líquidos.
    balances = Hash.new { |h, k| h[k] = BigDecimal("0.00") }

    @simplified_debt_graph.each do |debtor, creditors_hash|
      creditors_hash.each do |creditor, amount|
        balances[debtor] -= amount
        balances[creditor] += amount
      end
    end

    # Separa credores e devedores com base nos saldos líquidos.
    # Filtra usuários com balanço zero ou muito próximo de zero (dentro da tolerância).
    creditors = balances.select { |_user, amount| amount > @tolerance }
                        .sort_by { |_user, amount| -amount } # Maiores credores primeiro
                        .to_h
    debtors = balances.select { |_user, amount| amount < -@tolerance }
                      .sort_by { |_user, amount| amount } # Maiores devedores (negativos) primeiro
                      .to_h

    optimized_payments = []

    # Algoritmo principal de otimização:
    # Enquanto houver devedores e credores
    while debtors.any? && creditors.any?
      debtor, debt_amount_raw = debtors.shift
      creditor, credit_amount_raw = creditors.shift

      debt_amount = debt_amount_raw.abs # Transforma dívida em valor absoluto
      credit_amount = credit_amount_raw

      # Determina o valor do pagamento, que é o mínimo entre a dívida e o crédito.
      payment_amount = [ debt_amount, credit_amount ].min

      if payment_amount > @tolerance # Apenas adiciona pagamentos significativos
        optimized_payments << {
          payer: debtor,
          receiver: creditor,
          amount: payment_amount.round(2)
        }

        # Atualiza os saldos restantes após o pagamento
        remaining_debt = debt_amount - payment_amount
        remaining_credit = credit_amount - payment_amount

        # Se o devedor ainda deve, o coloca de volta na lista de devedores.
        if remaining_debt > @tolerance
          # Reinsere mantendo a ordem (ou reordena, se necessário para a complexidade)
          insert_into_sorted_hash(debtors, debtor, -remaining_debt)
        end

        # Se o credor ainda tem crédito, o coloca de volta na lista de credores.
        if remaining_credit > @tolerance
          # Reinsere mantendo a ordem (ou reordena, se necessário para a complexidade)
          insert_into_sorted_hash(creditors, creditor, remaining_credit)
        end
      else
        # Se o pagamento for muito pequeno para ser significativo, reinserir quem sobrou
        insert_into_sorted_hash(debtors, debtor, debt_amount_raw) if debt_amount > @tolerance
        insert_into_sorted_hash(creditors, creditor, credit_amount_raw) if credit_amount > @tolerance
      end
    end
    optimized_payments
  end

  private

  # Helper para inserir um usuário em um hash ordenado (mantendo a ordem por valor).
  # @param hash [Hash] O hash de balanços (devedores ou credores).
  # @param user [User] O usuário a ser inserido.
  # @param amount [BigDecimal] O montante do balanço do usuário.
  def insert_into_sorted_hash(hash, user, amount)
    # Esta lógica de inserção ordenada aumenta a complexidade ciclomática e a lógica interna
    # para manter as listas de devedores/credores ordenadas dinamicamente.
    new_entry = { user => amount }

    if amount > BigDecimal("0.00") # Credor
      index = hash.keys.bsearch_index { |k| hash[k] <= amount } || hash.size
    else # Devedor
      index = hash.keys.bsearch_index { |k| hash[k] >= amount } || hash.size
    end

    # Converte o hash para um array de pares, insere e converte de volta para hash
    arr = hash.to_a
    arr.insert(index, new_entry.first)
    hash.replace(arr.to_h)
  end
end
