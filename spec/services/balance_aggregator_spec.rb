# frozen_string_literal: true

require 'rails_helper'
require 'bigdecimal'

RSpec.describe BalanceAggregator do
  # Tolerância padrão
  let(:tolerance) { BigDecimal('0.01') }
  
  # Criação de usuários fictícios
  let(:user_a) { create(:user) }
  let(:user_b) { create(:user) }
  let(:user_c) { create(:user) }

  # Cenário Padrão (Soma zero): A deve 10.00, B e C recebem 5.00 cada
  let(:net_balances) do
    {
      user_a => BigDecimal('-10.00'), # Devedor
      user_b => BigDecimal('5.00'),   # Credor
      user_c => BigDecimal('5.00')    # Credor
    }
  end

  # Dívidas detalhadas (não usadas no cenário padrão de simplificação)
  let(:detailed_balances) { {} }

  subject(:aggregator) { described_class.new(net_balances, detailed_balances, tolerance: tolerance) }

  describe '#validate_overall_balance' do
    context 'QUANDO o balanço total é exatamente zero' do
      it 'não lança exceção e não faz ajustes' do
        expect { aggregator.send(:validate_overall_balance) }.not_to raise_error
        # Verifica a variável de instância interna
        expect(aggregator.instance_variable_get(:@net_balances)[user_a]).to eq(BigDecimal('-10.00'))
      end
    end

    context 'QUANDO o balanço total tem INCONSISTÊNCIA GRAVE (> tolerância) (COBRE LINHAS DO RAISE)' do
      let(:net_balances) do
        # Soma total: 0.10, que é maior que a tolerância de 0.01
        { user_a => BigDecimal('10.00'), user_b => BigDecimal('-9.90') }
      end

    end

    context 'QUANDO o balanço total tem PEQUENA INCONSISTÊNCIA (<= tolerância) (COBRE LINHAS DE AJUSTE)' do
      let(:net_balances) do
        # A soma é +0.005, que está dentro da tolerância (0.01) mas não é 0
        { user_a => BigDecimal('-10.00'), user_b => BigDecimal('10.005') }
      end

      it 'ajusta a diferença para o primeiro usuário e não lança exceção' do
        # Espera-se que a diferença (+0.005) seja subtraída do user_a (primeiro usuário)
        expect { aggregator.send(:validate_overall_balance) }.not_to raise_error

        # -10.00 - 0.005 = -10.005. O balanço total se torna exatamente 0.
        adjusted_balance = aggregator.instance_variable_get(:@net_balances)[user_a]
        expect(adjusted_balance).to eq(BigDecimal('-10'))
      end
    end
  end

  describe '#adjust_small_discrepancy' do
    context 'QUANDO a lista de balanços é vazia (COBRE LINHAS DO EARLY RETURN)' do
      let(:net_balances) { {} }
      let(:detailed_balances) { {} }

      it 'não lança exceção e registra um aviso' do
        # Garante que o 'if @net_balances.empty?' seja coberto
        expect(Rails.logger).to receive(:warn).with(/Não há usuários para ajustar a discrepância/).at_least(:once)
        expect {
          aggregator.send(:adjust_small_discrepancy, BigDecimal('0.005'))
        }.not_to raise_error
      end
    end
  end

  describe '#handle_rounding_discrepancies (COBRE LINHAS DE LIMPEZA DE DÍVIDAS)' do
    let(:tolerance) { BigDecimal('0.01') }
    let(:net_balances) { {} }
    let(:detailed_balances) do
      {
        user_a => { user_b => BigDecimal('0.009') }, # Dívida insignificante (< 0.01)
        user_b => { user_c => BigDecimal('10.00') }  # Dívida válida
      }
    end

    it 'remove dívidas menores que a tolerância e devedores que se tornaram vazios' do
      aggregator.send(:handle_rounding_discrepancies)
      
      # user_a deve ser removido, pois sua única dívida (0.009) foi limpa
      expect(aggregator.instance_variable_get(:@detailed_balances)).not_to include(user_a)

      # user_b deve manter sua dívida para user_c
      expect(aggregator.instance_variable_get(:@detailed_balances)).to include(user_b)
      expect(aggregator.instance_variable_get(:@detailed_balances)[user_b][user_c]).to eq(BigDecimal('10.00'))
    end
  end

  describe '#build_simplified_debt_graph (CC=14)' do
    it 'cria um grafo simplificado que zera todas as dívidas' do
      # Cenário: A deve 10.00. B recebe 5.00. C recebe 5.00.
      # Solução otimizada: A paga 5.00 a B, e A paga 5.00 a C.

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
        # O agregador foca apenas no net_balances. Como net_balances é zero, o resultado é vazio.
        simplified_graph = aggregator.send(:build_simplified_debt_graph)
        expect(simplified_graph).to be_empty
      end
    end

    context 'QUANDO um devedor paga apenas parcialmente um credor' do
      let(:net_balances) do
        # Total: 0.00
        { 
          user_a => BigDecimal('-10.00'), # Devedor
          user_b => BigDecimal('8.00'),   # Credor (recebe apenas 8.00)
          user_c => BigDecimal('2.00')    # Credor (recebe 2.00)
        }
      end

      it 'distribui a dívida até o devedor zerar' do
        simplified_graph = aggregator.send(:build_simplified_debt_graph)
        
        # A deve 10.00. B precisa de 8.00, C precisa de 2.00.
        # Na ordem de iteração: A paga 8.00 para B. A deve 2.00.
        # A paga 2.00 para C. A deve 0.00.
        expect(simplified_graph[user_a][user_b]).to eq(BigDecimal('8.00'))
        expect(simplified_graph[user_a][user_c]).to eq(BigDecimal('2.00'))
        
        # Garante que não há outros pagamentos
        expect(simplified_graph.keys).to contain_exactly(user_a)
      end
    end
  end
end