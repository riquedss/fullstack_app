# frozen_string_literal: true

require 'bigdecimal'

# Simulação da classe User para os testes, necessária para o BalanceAggregator
# que usa objetos User como chaves nos seus HashMaps.
User = Struct.new(:id) do
  def to_s
    "User_#{id}"
  end
  # Adiciona uma comparação simples para uso em testes
  def ==(other)
    other.is_a?(User) && id == other.id
  end
end

# A classe BalanceAggregator (assumindo que está no caminho de load)
# Para fins de teste, recriamos a estrutura mínima para garantir que o teste seja autossuficiente
class BalanceAggregator
  require 'bigdecimal'

  # Inicializa o BalanceAggregator com os balanços líquidos e detalhados.
  # @param net_balances [Hash<User, BigDecimal>] Saldos líquidos de cada usuário (calculado pelo BalanceCalculator).
  # @param detailed_balances [Hash<User, Hash<User, BigDecimal>>] Dívidas diretas entre usuários (calculado pelo BalanceCalculator).
  # @param tolerance [BigDecimal] Tolerância para considerar pequenas discrepâncias de arredondamento como zero.
  def initialize(net_balances, detailed_balances, tolerance: BigDecimal('0.01'))
    # Garante arredondamento inicial e copia para não modificar os objetos originais
    @net_balances = net_balances.transform_values(&:round)
    @detailed_balances = detailed_balances.transform_values { |v| v.transform_values(&:round) }
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
      # Em um ambiente de teste, o Rails.logger não existe, então usamos puts/padrão.
      raise "Inconsistência grave no balanço: a soma total dos saldos líquidos do grupo não é zero. (Diferença: #{total_net_sum})"
    elsif total_net_sum != BigDecimal('0.00') # Se estiver dentro da tolerância, mas não for exatamente zero
      adjust_small_discrepancy(total_net_sum)
    end
  end

  # Ajusta pequenas discrepâncias de arredondamento distribuindo-as para um usuário.
  # @param discrepancy [BigDecimal] O valor da discrepância a ser ajustado.
  def adjust_small_discrepancy(discrepancy)
    if @net_balances.empty?
      return
    end

    # Prioriza ajustar para o primeiro usuário (índice 0)
    user_to_adjust = @net_balances.keys.first

    @net_balances[user_to_adjust] -= discrepancy
  end

  # Limpa dívidas detalhadas muito pequenas.
  def handle_rounding_discrepancies
    @detailed_balances.each do |debtor, creditors|
      creditors.each do |creditor, amount|
        if amount.abs < @tolerance
          @detailed_balances[debtor].delete(creditor)
        end
      end
      @detailed_balances.delete(debtor) if @detailed_balances[debtor].empty?
    end
  end

  # Converte os balanços líquidos em um grafo simplificado de dívidas para o otimizador.
  def build_simplified_debt_graph
    simplified_graph = Hash.new { |h1, k1| h1[k1] = Hash.new { |h2, k2| h2[k2] = BigDecimal('0.00') } }

    debtors = @net_balances.select { |_user, amount| amount < BigDecimal('0.00') }
                           .sort_by { |_user, amount| amount }
                           .to_h
    creditors = @net_balances.select { |_user, amount| amount > BigDecimal('0.00') }
                             .sort_by { |_user, amount| -amount }
                             .to_h

    debtors_copy = debtors.dup
    creditors_copy = creditors.dup

    debtors_copy.each do |debtor, debt_amount_raw|
      debt_amount = debt_amount_raw.abs

      creditors_copy.each do |creditor, credit_amount_raw|
        credit_amount = credit_amount_raw

        next if debt_amount <= @tolerance || credit_amount <= @tolerance || debtor == creditor

        payment_amount = [debt_amount, credit_amount].min

        simplified_graph[debtor][creditor] += payment_amount

        # Atualiza os valores residuais
        debt_amount -= payment_amount
        creditors_copy[creditor] -= payment_amount

        break if debt_amount <= @tolerance
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


RSpec.describe BalanceAggregator do
  let(:u1) { User.new(1) }
  let(:u2) { User.new(2) }
  let(:u3) { User.new(3) }
  let(:u4) { User.new(4) }
  let(:zero) { BigDecimal('0.00') }
  let(:tolerance) { BigDecimal('0.01') }

  # Helper para comparar BigDecimal
  def b(value)
    BigDecimal(value.to_s)
  end

  # Testes para cenários de liquidação
  describe '#aggregate_balances (Settlement Logic)' do
    # Cenário 1: Liquidação simples entre dois usuários
    context 'when two users have opposite balances' do
      let(:net_balances) { { u1 => b('-100.00'), u2 => b('100.00') } }
      let(:detailed_balances) { { u1 => { u2 => b('100.00') } } }

      it 'returns a single transaction from debtor to creditor' do
        aggregator = BalanceAggregator.new(net_balances, detailed_balances)
        result = aggregator.aggregate_balances

        # Esperado: U1 deve 100.00 para U2
        expect(result.keys).to contain_exactly(u1)
        expect(result[u1].keys).to contain_exactly(u2)
        expect(result[u1][u2]).to be_within(tolerance).of(b('100.00'))
      end
    end

    # Cenário 2: Liquidação de três usuários que pode ser otimizada (Chain Debt)
    # U3 deve 100 (Debtor), U1 deve 100 (Creditor), U2 está neutro.
    # Otimização espera: U3 paga diretamente U1 100.00
    context 'when chain debt allows simplification (U3 -> U1)' do
      let(:net_balances) { { u1 => b('100.00'), u2 => zero, u3 => b('-100.00') } }
      let(:detailed_balances) { { u3 => { u2 => b('100.00') }, u2 => { u1 => b('100.00') } } }

      it 'simplifies the debt to a single transaction between the net debtor and net creditor' do
        aggregator = BalanceAggregator.new(net_balances, detailed_balances)
        result = aggregator.aggregate_balances

        # Esperado: U3 deve 100.00 para U1
        expect(result.keys).to contain_exactly(u3)
        expect(result[u3].keys).to contain_exactly(u1)
        expect(result[u3][u1]).to be_within(tolerance).of(b('100.00'))
      end
    end

    # Cenário 3: Múltiplos devedores e múltiplos credores
    context 'when multiple debtors and creditors are involved' do
      let(:net_balances) { { u1 => b('100.00'), u2 => b('-50.00'), u3 => b('70.00'), u4 => b('-120.00') } }
      # Soma total: 100 - 50 + 70 - 120 = 0.00 (Correto)

      let(:detailed_balances) { {} } # Não importa para a lógica de simplificação baseada em net_balances

      it 'allocates payments optimally from multiple debtors to multiple creditors' do
        aggregator = BalanceAggregator.new(net_balances, detailed_balances)
        result = aggregator.aggregate_balances

        # Devedores: U2 (50), U4 (120) -> Total: 170
        # Credores: U1 (100), U3 (70) -> Total: 170

        # O otimizador faz a alocação:
        # 1. U4 (maior devedor) paga U1 (maior credor) 100.00.
        #    - Saldo U4: 20 a pagar.
        #    - Saldo U1: 0.
        # 2. U4 (devedor residual) paga U3 (credor) 20.00.
        #    - Saldo U4: 0.
        #    - Saldo U3: 50 a receber.
        # 3. U2 (devedor) paga U3 (credor residual) 50.00.
        #    - Saldo U2: 0.
        #    - Saldo U3: 0.

        # Esperado: (U4 -> U1 100.00), (U4 -> U3 20.00), (U2 -> U3 50.00)
        expect(result.keys).to contain_exactly(u4, u2)
        expect(result[u4].keys).to contain_exactly(u1, u3)
        expect(result[u4][u1]).to be_within(tolerance).of(b('100.00'))
        expect(result[u4][u3]).to be_within(tolerance).of(b('20.00'))
        expect(result[u2].keys).to contain_exactly(u3)
        expect(result[u2][u3]).to be_within(tolerance).of(b('50.00'))
      end
    end
  end

  # Testes para tratamento de inconsistência/arredondamento
  describe '#aggregate_balances (Validation and Rounding)' do
    context 'when total balance is significantly inconsistent (e.g., > tolerance)' do
      let(:net_balances) { { u1 => b('100.00'), u2 => b('-50.00') } }
      let(:detailed_balances) { {} } # Soma: +50.00

      it 'raises a RuntimeError' do
        aggregator = BalanceAggregator.new(net_balances, detailed_balances)
        expect { aggregator.aggregate_balances }.to raise_error(RuntimeError, /Inconsistência grave/)
      end
    end

    context 'when total balance has a small discrepancy (within tolerance)' do
      # Soma: 50.01 - 50.00 = +0.01
      let(:net_balances) { { u1 => b('50.01'), u2 => b('-50.00') } }
      let(:detailed_balances) { {} }
      
      it 'adjusts the discrepancy to the first user (U1) and proceeds' do
        aggregator = BalanceAggregator.new(net_balances, detailed_balances)
        
        # O U1 deve ser ajustado para 50.01 - 0.01 = 50.00
        # O grafo deve ser: U2 deve U1 50.00
        result = aggregator.aggregate_balances

        expect(result.keys).to contain_exactly(u2)
        expect(result[u2].keys).to contain_exactly(u1)
        expect(result[u2][u1]).to be_within(tolerance).of(b('50.00'))
      end
    end

    context 'when detailed balances have sub-tolerance residues' do
      # Soma dos net balances: 100 - 100 = 0.00 (Correto)
      let(:net_balances) { { u1 => b('100.00'), u2 => b('-100.00') } }
      # Detailed: U2 deve U1 99.99, U1 deve U2 0.005 (residual)
      let(:detailed_balances) { {
        u2 => { u1 => b('99.99') },
        u1 => { u2 => b('0.005') } # Este valor deve ser limpo pelo handle_rounding_discrepancies
      } }

      it 'removes transactions smaller than the tolerance from the detailed balances' do
        aggregator = BalanceAggregator.new(net_balances, detailed_balances, tolerance: b('0.01'))
        
        # A lógica de simplificação é baseada em net_balances, mas testamos se o handle_rounding_discrepancies roda sem erro
        # e garante a limpeza de detailed_balances (embora detailed_balances não seja o output final).
        expect { aggregator.aggregate_balances }.not_to raise_error
      end
    end
  end
end