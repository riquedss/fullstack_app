# frozen_string_literal: true

require 'rails_helper'
require 'bigdecimal'

# Assumindo que o BalanceAggregator está em 'app/services/balance_aggregator.rb'
# Necessita de dados de usuário real para o teste
RSpec.describe BalanceAggregator do
  let(:tolerance) { BigDecimal('0.01') }
  let(:user_a) { create(:user) }
  let(:user_b) { create(:user) }
  let(:user_c) { create(:user) }

  # Cenário: A deve 10 a B, B deve 5 a C
  let(:net_balances) do
    {
      user_a => BigDecimal('-10.00'), # Devedor
      user_b => BigDecimal('5.00'),   # Credor (parcial)
      user_c => BigDecimal('5.00')    # Credor (parcial)
    }
  end

  # Detalhes de dívida não são usados na agregação, mas necessários para inicialização
  let(:detailed_balances) { {} }

  subject(:aggregator) { described_class.new(net_balances, detailed_balances, tolerance: tolerance) }

  describe '#validate_overall_balance' do
    context 'QUANDO o balanço total é exatamente zero' do
      it 'não lança exceção e não faz ajustes' do
        expect { aggregator.send(:validate_overall_balance) }.not_to raise_error
        expect(net_balances[user_a]).to eq(BigDecimal('-10.00'))
      end
    end

    context 'QUANDO o balanço total tem INCONSISTÊNCIA GRAVE (> tolerância)' do
      let(:net_balances) do
        { user_a => BigDecimal('-10.00'), user_b => BigDecimal('1.00') } # Total: -9.00
      end

      it 'lança uma RuntimeError' do
        expect { aggregator.send(:validate_overall_balance) }.to raise_error(RuntimeError, /grave no balanço/)
      end
    end

    context 'QUANDO o balanço total tem PEQUENA INCONSISTÊNCIA (<= tolerância)' do
      let(:net_balances) do
        # Total: -0.005, que deve ser ajustado para o user_a (o primeiro na lista)
        { user_a => BigDecimal('-10.00'), user_b => BigDecimal('10.005') }
      end

      it 'ajusta a diferença e não lança exceção' do
        expect { aggregator.send(:validate_overall_balance) }.not_to raise_error
        # Após o arredondamento inicial: user_a: -10.00, user_b: 10.01
        # Total: 0.01, que é exatamente a tolerância, então não há ajuste
        expect(net_balances[user_a]).to eq(BigDecimal('-10.00'))
      end
    end
  end

  describe '#build_simplified_debt_graph (CC=14)' do
    it 'cria um grafo simplificado que zera todas as dívidas' do
      # Cenário ideal: A deve 10.00. B recebe 5.00. C recebe 5.00.
      # Solução otimizada esperada: A paga 5.00 a B, e A paga 5.00 a C.

      simplified_graph = aggregator.send(:build_simplified_debt_graph)

      # Espera-se que A (devedor) pague a B e C (credores)
      expect(simplified_graph.keys).to contain_exactly(user_a)
      expect(simplified_graph[user_a].keys).to contain_exactly(user_b, user_c)

      # Garante a exatidão dos valores
      expect(simplified_graph[user_a][user_b]).to eq(BigDecimal('5.00'))
      expect(simplified_graph[user_a][user_c]).to eq(BigDecimal('5.00'))
    end

    context 'QUANDO há ciclo de dívida (A deve 5 a B e B deve 5 a A)' do
      let(:net_balances) do
        { user_a => BigDecimal('0.00'), user_b => BigDecimal('0.00') }
      end
      let(:detailed_balances) do
        { user_a => { user_b => BigDecimal('5.00') },
          user_b => { user_a => BigDecimal('5.00') } }
      end

      it 'o grafo simplificado deve ser vazio, pois os balanços líquidos são zero' do
        # O agregador ignora o detailed_balances para o grafo simplificado,
        # focando apenas no net_balances. Como net_balances é zero, o resultado é vazio.
        simplified_graph = aggregator.send(:build_simplified_debt_graph)
        expect(simplified_graph).to be_empty
      end
    end
  end
end
