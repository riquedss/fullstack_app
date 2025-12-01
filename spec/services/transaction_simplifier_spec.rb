require 'rails_helper'
require 'bigdecimal'

# Define factories dummy para usuários (simulando o create(:user) dos specs anteriores)
RSpec.describe TransactionSimplifier, type: :service do
  # Configuração de usuários (IDs fixos para garantir consistência no grafo de dívidas)
  let!(:user_a) { create(:user, id: 10, email: 'a@example.com') }
  let!(:user_b) { create(:user, id: 20, email: 'b@example.com') }
  let!(:user_c) { create(:user, id: 30, email: 'c@example.com') }
  let!(:user_d) { create(:user, id: 40, email: 'd@example.com') }
  let(:tolerance) { BigDecimal('0.01') }

  # Função auxiliar para garantir que o resultado corresponda exatamente ao esperado
  def expect_simplified_graph(result, expected_debts)
    # 1. Verifica se a chave do devedor (debtor) existe no resultado
    expected_debts.each do |debtor, creditors|
      expect(result).to have_key(debtor), "Esperado que #{debtor.email} fosse um devedor, mas não foi encontrado."
      
      # 2. Verifica se a chave do credor (creditor) existe e se o valor é exato
      creditors.each do |creditor, amount|
        expect(result[debtor]).to have_key(creditor), "Esperado que #{debtor.email} devesse a #{creditor.email}, mas não foi encontrado."
        expect(result[debtor][creditor]).to eq(amount), "Valor incorreto para #{debtor.email} -> #{creditor.email}. Esperado: #{amount}, Recebido: #{result[debtor][creditor]}."
      end
    end

    # 3. Verifica se o resultado não contém dívidas não esperadas (excessos)
    result.each do |debtor, creditors|
      creditors.each do |creditor, amount|
        next if expected_debts[debtor] && expected_debts[debtor][creditor]
        fail "Dívida inesperada encontrada: #{debtor.email} deve #{creditor.email} #{amount}."
      end
    end
    
    # 4. Verifica se o hash principal não tem devedores que deveriam ter sido limpos
    result.each do |debtor, creditors|
      expect(creditors).to_not be_empty, "Devedor #{debtor.email} não deveria estar no grafo se suas dívidas estão vazias."
    end
  end

  # --- Teste de Funcionalidade Principal (#simplify_transactions) ---
  describe '#simplify_transactions' do
    it 'não simplifica um grafo linear simples' do
      debt_graph = {
        user_a => { user_b => BigDecimal('15.00') }
      }
      simplifier = TransactionSimplifier.new(debt_graph)
      result = simplifier.simplify_transactions
      
      expected = { user_a => { user_b => BigDecimal('15.00') } }
      expect_simplified_graph(result, expected)
    end
    
    it 'limpa dívidas insignificantes (abaixo da tolerância)' do
      debt_graph = {
        user_a => { user_b => BigDecimal('10.00'), user_c => BigDecimal('0.005') }
      }
      simplifier = TransactionSimplifier.new(debt_graph)
      result = simplifier.simplify_transactions
      
      # A dívida de 0.005 deve ser limpa
      expected = { user_a => { user_b => BigDecimal('10.00') } }
      expect_simplified_graph(result, expected)
    end
  end

  # --- Teste de Simplificação Direta (#remove_direct_opposing_debts) ---
  describe '#remove_direct_opposing_debts' do
    it 'simplifica duas dívidas diretas em uma única transação líquida' do
      # A deve B: 10.00
      # B deve A: 3.50
      # Esperado: A deve B: 6.50 (e B deve A é removido)
      debt_graph = {
        user_a => { user_b => BigDecimal('10.00') },
        user_b => { user_a => BigDecimal('3.50') }
      }
      simplifier = TransactionSimplifier.new(debt_graph)
      simplifier.send(:remove_direct_opposing_debts) # Chama o método privado

      expected = {
        user_a => { user_b => BigDecimal('6.50') },
        user_b => {} # B deve ter sido limpo pelo método clean_zero_debts (chamado implicitamente pelo simplifier ou manualmente)
      }
      
      # Para este teste unitário, precisamos verificar o estado ANTES do clean_zero_debts
      # O método remove_direct_opposing_debts deve limpar a dívida B -> A
      expect(simplifier.instance_variable_get(:@debt_graph)[user_a][user_b]).to eq(BigDecimal('6.50'))
      expect(simplifier.instance_variable_get(:@debt_graph)[user_b]).to_not have_key(user_a)
    end

    it 'simplifica quando o credor tem o saldo líquido maior' do
      # A deve B: 5.00
      # B deve A: 12.00
      # Esperado: B deve A: 7.00 (e A deve B é removido)
      debt_graph = {
        user_a => { user_b => BigDecimal('5.00') },
        user_b => { user_a => BigDecimal('12.00') }
      }
      simplifier = TransactionSimplifier.new(debt_graph)
      simplifier.send(:remove_direct_opposing_debts)

      expect(simplifier.instance_variable_get(:@debt_graph)[user_b][user_a]).to eq(BigDecimal('7.00'))
      expect(simplifier.instance_variable_get(:@debt_graph)[user_a]).to_not have_key(user_b)
    end
    
    it 'lida corretamente com dívidas abaixo da tolerância em uma direção' do
      # A deve B: 10.00
      # B deve A: 0.005 (abaixo da tolerância, não deve acionar a lógica de simplificação mútua)
      debt_graph = {
        user_a => { user_b => BigDecimal('10.00') },
        user_b => { user_a => BigDecimal('0.005') } 
      }
      simplifier = TransactionSimplifier.new(debt_graph)
      simplifier.send(:remove_direct_opposing_debts)

      # A dívida deve permanecer como está, pois B -> A é insignificante
      expect(simplifier.instance_variable_get(:@debt_graph)[user_a][user_b]).to eq(BigDecimal('10.00'))
      expect(simplifier.instance_variable_get(:@debt_graph)[user_b][user_a]).to eq(BigDecimal('0.005'))
    end
  end

  # --- Teste de Ciclos de Dívidas (#find_and_remove_cycles) ---
  describe '#find_and_remove_cycles' do
    
    it 'remove um ciclo de três nós com o mesmo montante' do
      # A -> B (10.00), B -> C (10.00), C -> A (10.00)
      # Esperado: Todas as dívidas são zeradas
      debt_graph = {
        user_a => { user_b => BigDecimal('10.00') },
        user_b => { user_c => BigDecimal('10.00') },
        user_c => { user_a => BigDecimal('10.00') }
      }
      simplifier = TransactionSimplifier.new(debt_graph)
      simplifier.send(:find_and_remove_cycles)
      simplifier.send(:clean_zero_debts)
      
      expected = {} # O grafo deve estar vazio
      expect_simplified_graph(simplifier.instance_variable_get(:@debt_graph), expected)
    end
    
    it 'remove o ciclo e mantém o saldo restante' do
      # A -> B (10.00)
      # B -> C (5.00) <-- menor dívida no ciclo
      # C -> A (8.00)
      # Min debt: 5.00
      # Esperado: A -> B (5.00), C -> A (3.00), B -> C (removido)
      debt_graph = {
        user_a => { user_b => BigDecimal('10.00') },
        user_b => { user_c => BigDecimal('5.00') },
        user_c => { user_a => BigDecimal('8.00') }
      }
      simplifier = TransactionSimplifier.new(debt_graph)
      simplifier.send(:find_and_remove_cycles)
      simplifier.send(:clean_zero_debts)
      
      expected = {
        user_a => { user_b => BigDecimal('5.00') },
        user_c => { user_a => BigDecimal('3.00') }
      }
      expect_simplified_graph(simplifier.instance_variable_get(:@debt_graph), expected)
    end

    it 'lida com um ciclo de quatro nós' do
      # A -> B (10), B -> C (5), C -> D (5), D -> A (5)
      # Min debt: 5
      # Esperado: A -> B (5), B -> C (removido), C -> D (removido), D -> A (removido)
      debt_graph = {
        user_a => { user_b => BigDecimal('10.00') },
        user_b => { user_c => BigDecimal('5.00') },
        user_c => { user_d => BigDecimal('5.00') },
        user_d => { user_a => BigDecimal('5.00') }
      }
      simplifier = TransactionSimplifier.new(debt_graph)
      simplifier.send(:find_and_remove_cycles)
      simplifier.send(:clean_zero_debts)

      expected = {
        user_a => { user_b => BigDecimal('5.00') }
      }
      expect_simplified_graph(simplifier.instance_variable_get(:@debt_graph), expected)
    end

    it 'lida com grafo que contém um ciclo e uma transação externa (ciclo no meio)' do
      # D -> A (5.00) - Transação externa
      # A -> B (10.00)
      # B -> C (8.00)
      # C -> A (8.00)
      # Ciclo: A -> B -> C -> A. Min debt: 8.00
      # Esperado: D -> A (5.00), A -> B (2.00), B -> C (removido), C -> A (removido)
      debt_graph = {
        user_d => { user_a => BigDecimal('5.00') },
        user_a => { user_b => BigDecimal('10.00') },
        user_b => { user_c => BigDecimal('8.00') },
        user_c => { user_a => BigDecimal('8.00') }
      }
      simplifier = TransactionSimplifier.new(debt_graph)
      simplifier.send(:find_and_remove_cycles)
      simplifier.send(:clean_zero_debts)
      
      expected = {
        user_d => { user_a => BigDecimal('5.00') },
        user_a => { user_b => BigDecimal('2.00') }
      }
      expect_simplified_graph(simplifier.instance_variable_get(:@debt_graph), expected)
    end
  end

  # --- Teste de Cenários Combinados ---
  describe 'Cenário Complexo Integrado' do
    it 'combina dívidas opostas e remove um ciclo resultante' do
      # 1. Dívidas Iniciais (Ciclo e Opostas)
      # A deve B: 10.00
      # B deve A: 3.00 (Oposta)
      # B deve C: 8.00
      # C deve A: 5.00

      # 2. Após remove_direct_opposing_debts:
      # A deve B: 7.00
      # B deve C: 8.00
      # C deve A: 5.00
      # NOVO CICLO: A -> B -> C -> A. Min debt = 5.00.

      # 3. Após find_and_remove_cycles (removendo 5.00)
      # A deve B: 7.00 - 5.00 = 2.00
      # B deve C: 8.00 - 5.00 = 3.00
      # C deve A: 5.00 - 5.00 = 0.00 (limpo)
      
      debt_graph = {
        user_a => { user_b => BigDecimal('10.00') },
        user_b => { user_a => BigDecimal('3.00'), user_c => BigDecimal('8.00') },
        user_c => { user_a => BigDecimal('5.00') }
      }
      simplifier = TransactionSimplifier.new(debt_graph)
      result = simplifier.simplify_transactions
      
      expected = {
        user_a => { user_b => BigDecimal('2.00') },
        user_b => { user_c => BigDecimal('3.00') }
      }
      expect_simplified_graph(result, expected)
    end
  end
end