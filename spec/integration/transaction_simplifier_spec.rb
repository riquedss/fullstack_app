# frozen_string_literal: true

require 'bigdecimal'

# Simulação das estruturas de dados necessárias para o TransactionSimplifier

# Estrutura de suporte
User = Struct.new(:id) do
  def to_s
    "User_#{id}"
  end
  def ==(other)
    other.is_a?(User) && id == other.id
  end
  def hash
    id.hash
  end
end

# A classe TransactionSimplifier (reproduzida para que o teste seja autossuficiente)
class TransactionSimplifier
  require 'bigdecimal'

  # Inicializa o TransactionSimplifier com um grafo de dívidas detalhado ou simplificado.
  def initialize(debt_graph, tolerance: BigDecimal('0.01'))
    @debt_graph = deep_copy_hash(debt_graph) # Trabalha com uma cópia para não alterar o original
    @tolerance = tolerance
  end

  # Simplifica o grafo de dívidas identificando e removendo ciclos e combinando transações diretas.
  def simplify_transactions
    remove_direct_opposing_debts
    find_and_remove_cycles
    clean_zero_debts
    @debt_graph
  end

  private

  # Realiza uma cópia profunda do hash para evitar efeitos colaterais.
  def deep_copy_hash(hash)
    Marshal.load(Marshal.dump(hash))
  end

  # Remove dívidas diretas opostas (A deve a B, B deve a A) simplificando-as para uma única transação líquida.
  def remove_direct_opposing_debts
    # Copia as chaves para evitar problemas de iteração enquanto altera o hash
    @debt_graph.keys.dup.each do |user1|
      # Usar .keys.dup para iterar sobre as chaves internas
      if @debt_graph[user1]
        @debt_graph[user1].keys.dup.each do |user2|
          next if user1 == user2

          # Verifica se existe uma dívida na direção oposta (user2 deve user1)
          if @debt_graph[user2] && @debt_graph[user2][user1] &&
             @debt_graph[user1][user2] > @tolerance && @debt_graph[user2][user1] > @tolerance
            
            debt1_to_2 = @debt_graph[user1][user2]
            debt2_to_1 = @debt_graph[user2][user1]

            if debt1_to_2 > debt2_to_1
              # user1 deve a user2 o saldo líquido
              @debt_graph[user1][user2] = debt1_to_2 - debt2_to_1
              @debt_graph[user2].delete(user1)
            else
              # user2 deve a user1 o saldo líquido
              @debt_graph[user2][user1] = debt2_to_1 - debt1_to_2
              @debt_graph[user1].delete(user2)
            end
          end
        end
      end
    end
  end

  # Algoritmo principal para encontrar e remover ciclos de dívidas.
  def find_and_remove_cycles
    users = @debt_graph.keys.uniq
    visited = {}
    recursion_stack = {}
    path = []

    users.each do |start_node|
      # Se o nó não foi totalmente processado, começa o DFS
      if !visited[start_node]
        dfs_detect_and_remove_cycle(start_node, visited, recursion_stack, path)
      end
    end
  end

  # Função auxiliar de DFS para detectar e remover ciclos.
  def dfs_detect_and_remove_cycle(u, visited, recursion_stack, path)
    visited[u] = true
    recursion_stack[u] = true
    path << u

    # Itera sobre os vizinhos do nó atual (aqueles a quem ele deve)
    # Copia as chaves para permitir modificação no grafo dentro do process_cycle
    if @debt_graph[u]
      @debt_graph[u].keys.dup.each do |v|
        next unless @debt_graph[u][v] && @debt_graph[u][v] > @tolerance

        if !visited[v]
          # Se o vizinho não foi visitado, continua o DFS
          dfs_detect_and_remove_cycle(v, visited, recursion_stack, path)
        elsif recursion_stack[v]
          # CICLO DETECTADO! (u -> v, e v já está na pilha de recursão)
          process_cycle(v, u, path) # v é o nó que começa o ciclo no caminho
        end
      end
    end

    # Remove o nó da pilha de recursão ao sair do DFS para ele
    recursion_stack.delete(u)
    path.pop
  end

  # Processa um ciclo de dívidas.
  def process_cycle(cycle_start_node, cycle_end_node, current_path)
    # Encontra os nós que formam o ciclo completo (do cycle_start_node até cycle_end_node, incluindo a aresta cycle_end_node -> cycle_start_node)
    start_index = current_path.index(cycle_start_node)
    return unless start_index

    # O ciclo é: cycle_start_node -> ... -> cycle_end_node -> cycle_start_node
    cycle = current_path[start_index..-1]
    
    # 1. Encontra o menor valor de dívida em todas as arestas do ciclo (incluindo a de fechamento: cycle_end_node -> cycle_start_node)
    min_debt_in_cycle = BigDecimal('Infinity')

    # Arestas internas do ciclo
    cycle.each_cons(2) do |from_node, to_node|
      min_debt_in_cycle = [min_debt_in_cycle, @debt_graph[from_node][to_node]].min
    end
    # Aresta que fecha o ciclo (cycle_end_node -> cycle_start_node)
    min_debt_in_cycle = [min_debt_in_cycle, @debt_graph[cycle.last][cycle.first]].min
    
    # 2. Reduz todas as dívidas no ciclo pelo min_debt_in_cycle
    cycle.each_cons(2) do |from_node, to_node|
      @debt_graph[from_node][to_node] -= min_debt_in_cycle
    end
    @debt_graph[cycle.last][cycle.first] -= min_debt_in_cycle # Aresta de fechamento

    # Neste ambiente, apenas comentamos o logger
    # Rails.logger.info("Ciclo removido: #{cycle.map(&:id).join(' -> ')} -> #{cycle.first.id}. Valor ajustado: #{min_debt_in_cycle}")
  end

  # Limpa todas as dívidas que se tornaram zero ou insignificantes.
  def clean_zero_debts
    # Copia as chaves externas e internas para iteração segura
    @debt_graph.keys.dup.each do |debtor|
      if @debt_graph[debtor]
        @debt_graph[debtor].keys.dup.each do |creditor|
          if @debt_graph[debtor][creditor] <= @tolerance
            @debt_graph[debtor].delete(creditor)
          end
        end
        @debt_graph.delete(debtor) if @debt_graph[debtor].empty?
      end
    end
  end
end


RSpec.describe TransactionSimplifier do
  let(:u1) { User.new(1) }
  let(:u2) { User.new(2) }
  let(:u3) { User.new(3) }
  let(:u4) { User.new(4) }
  let(:tolerance) { BigDecimal('0.01') }
  let(:zero) { BigDecimal('0.00') }

  # Helper para BigDecimal
  def b(value)
    BigDecimal(value.to_s).round(2)
  end

  # Helper para normalizar o grafo de dívidas (remove zero, garante precisão)
  def normalize_graph(graph)
    cleaned = {}
    graph.each do |debtor, creditors|
      next unless debtor.is_a?(User)

      cleaned_creditors = creditors.select { |_c, amount| amount > tolerance }
                                    .transform_values { |v| v.round(2) }
      cleaned[debtor] = cleaned_creditors if cleaned_creditors.any?
    end
    cleaned
  end

  # --- Testes para remove_direct_opposing_debts (2-node cycles) ---
  describe '#simplify_transactions (Direct Opposing Debts)' do
    context 'when two users have opposing debts of different amounts' do
      # U1 deve U2: 100.00 | U2 deve U1: 50.00
      let(:debt_graph) {
        {
          u1 => { u2 => b('100.00') },
          u2 => { u1 => b('50.00'), u3 => b('10.00') } # U2 também deve U3
        }
      }

      it 'simplifies to a single net transaction (U1 owes U2 50.00)' do
        simplifier = TransactionSimplifier.new(debt_graph)
        result = simplifier.simplify_transactions
        
        expected_graph = {
          u1 => { u2 => b('50.00') }, # 100 - 50 = 50
          u2 => { u3 => b('10.00') }  # Não alterada
        }

        expect(normalize_graph(result)).to eq(normalize_graph(expected_graph))
      end
    end

    context 'when two users have equal opposing debts' do
      # U1 deve U2: 75.50 | U2 deve U1: 75.50
      let(:debt_graph) {
        {
          u1 => { u2 => b('75.50') },
          u2 => { u1 => b('75.50') }
        }
      }

      it 'removes both transactions resulting in an empty graph' do
        simplifier = TransactionSimplifier.new(debt_graph)
        result = simplifier.simplify_transactions
        
        expected_graph = {}
        expect(normalize_graph(result)).to eq(expected_graph)
      end
    end
  end

  # --- Testes para find_and_remove_cycles (3+ node cycles) ---
  describe '#simplify_transactions (Cycle Removal)' do
    
    context 'when a perfect 3-node cycle exists (U1->U2->U3->U1)' do
      # U1->U2: 10.00 | U2->U3: 10.00 | U3->U1: 10.00
      let(:debt_graph) {
        {
          u1 => { u2 => b('10.00') },
          u2 => { u3 => b('10.00') },
          u3 => { u1 => b('10.00') }
        }
      }

      it 'removes the entire cycle, resulting in an empty graph' do
        simplifier = TransactionSimplifier.new(debt_graph)
        result = simplifier.simplify_transactions
        
        expected_graph = {}
        expect(normalize_graph(result)).to eq(expected_graph)
      end
    end

    context 'when a partial 3-node cycle exists' do
      # U1->U2: 20.00 | U2->U3: 10.00 | U3->U1: 10.00 (min debt is 10.00)
      let(:debt_graph) {
        {
          u1 => { u2 => b('20.00') },
          u2 => { u3 => b('10.00') },
          u3 => { u1 => b('10.00') }
        }
      }

      it 'removes the minimum debt (10.00) from the cycle, leaving the net debt' do
        simplifier = TransactionSimplifier.new(debt_graph)
        result = simplifier.simplify_transactions
        
        # Esperado: U1 deve U2: 20.00 - 10.00 = 10.00
        expected_graph = {
          u1 => { u2 => b('10.00') }
        }
        
        expect(normalize_graph(result)).to eq(normalize_graph(expected_graph))
      end
    end
    
    context 'when a cycle is part of a longer path (U4->U1->U2->U3->U1)' do
      # U4->U1: 5.00 (fora do ciclo)
      # U1->U2: 15.00 | U2->U3: 10.00 | U3->U1: 10.00 (min debt is 10.00)
      let(:debt_graph) {
        {
          u4 => { u1 => b('5.00') },
          u1 => { u2 => b('15.00') },
          u2 => { u3 => b('10.00') },
          u3 => { u1 => b('10.00') }
        }
      }

      it 'removes the cycle first and preserves external paths' do
        simplifier = TransactionSimplifier.new(debt_graph)
        result = simplifier.simplify_transactions
        
        # Ciclo (U1->U2->U3->U1) ajustado em 10.00:
        # U1->U2: 15.00 - 10.00 = 5.00
        # U2->U3: 10.00 - 10.00 = 0.00 (removido)
        # U3->U1: 10.00 - 10.00 = 0.00 (removido)
        
        # U4->U1: 5.00 (preservado)
        
        expected_graph = {
          u4 => { u1 => b('5.00') },
          u1 => { u2 => b('5.00') }
        }
        
        expect(normalize_graph(result)).to eq(normalize_graph(expected_graph))
      end
    end
  end
end