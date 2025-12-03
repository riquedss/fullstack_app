# frozen_string_literal: true

# fullstack_app/app/services/transaction_simplifier.rb
require "bigdecimal"
require_relative "concerns/debt_opposition_handler"
require_relative "concerns/cycle_detector"
require_relative "concerns/cycle_processor"

class TransactionSimplifier
  include DebtOppositionHandler
  include CycleDetector
  include CycleProcessor
  # Inicializa o TransactionSimplifier com um grafo de dívidas detalhado ou simplificado.
  # O grafo deve ser no formato { devedor => { credor => montante } }.
  # @param debt_graph [Hash<User, Hash<User, BigDecimal>>] O grafo de dívidas a ser simplificado.
  # @param tolerance [BigDecimal] Tolerância para considerar um montante como zero.
  def initialize(debt_graph, tolerance: BigDecimal("0.01"))
    @debt_graph = deep_copy_hash(debt_graph) # Trabalha com uma cópia para não alterar o original
    @tolerance = tolerance
  end

  # Simplifica o grafo de dívidas identificando e removendo ciclos e combinando transações diretas.
  # @return [Hash<User, Hash<User, BigDecimal>>] O grafo de dívidas simplificado.
  def simplify_transactions
    remove_direct_opposing_debts # Simplifica dívidas diretas (A deve a B, B deve a A)
    find_and_remove_cycles # Lógica principal para alta complexidade ciclomática
    # Podemos adicionar mais lógica de simplificação aqui, como consolidar múltiplos devedores/credores para um único.
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
    @debt_graph.keys.each do |user1|
      @debt_graph[user1].keys.each do |user2|
        next if skip_self_debt?(user1, user2)
        next unless has_opposing_debts?(user1, user2)

        simplify_opposing_debt(user1, user2)
      end
    end
  end

  # Algoritmo principal para encontrar e remover ciclos de dívidas (complexidade ciclomática alta).
  # Utiliza uma abordagem de DFS para detecção de ciclos e remoção.
  def find_and_remove_cycles
    # Garante que os usuários estejam em uma ordem consistente para o DFS
    users = @debt_graph.keys.uniq
    visited = {} # Mantém o controle de nós visitados no DFS
    recursion_stack = {} # Mantém o controle de nós na pilha de recursão para detectar ciclos
    path = [] # Armazena o caminho atual no DFS

    # Itera sobre todos os usuários para garantir que todos os componentes conectados sejam visitados
    users.each do |start_node|
      # Aumenta a complexidade: a busca por ciclos envolve múltiplas chamadas recursivas
      # e manipulação de estado em cada chamada.
      dfs_detect_and_remove_cycle(start_node, visited, recursion_stack, path)
    end
  end

  # Função auxiliar de DFS para detectar e remover ciclos.
  # @param u [User] O nó atual no DFS.
  # @param visited [Hash] Hash de nós já visitados no DFS global.
  # @param recursion_stack [Hash] Hash de nós atualmente na pilha de recursão (para detecção de ciclo).
  # @param path [Array<User>] O caminho atual percorrido no DFS.
  def dfs_detect_and_remove_cycle(u, visited, recursion_stack, path)
    mark_node_as_visited(u, visited, recursion_stack, path)

    process_neighbors(u, visited, recursion_stack, path)

    cleanup_recursion_state(u, recursion_stack, path)
  end

  # Processa um ciclo de dívidas, removendo o menor valor de todas as arestas no ciclo.
  # @param cycle_start_node [User] O nó onde o ciclo foi detectado.
  # @param cycle_end_node [User] O nó que fechou o ciclo.
  # @param current_path [Array<User>] O caminho completo que levou à detecção do ciclo.
  def process_cycle(cycle_start_node, cycle_end_node, current_path)
    cycle = extract_cycle_from_path(cycle_end_node, current_path)
    return unless cycle

    min_debt = find_minimum_debt_in_cycle(cycle)
    apply_debt_reduction(cycle, min_debt)

    log_cycle_removal(cycle, min_debt)
  end

  # Limpa todas as dívidas que se tornaram zero ou insignificantes após a simplificação.
  def clean_zero_debts
    @debt_graph.keys.each do |debtor|
      @debt_graph[debtor].keys.each do |creditor|
        if @debt_graph[debtor][creditor] <= @tolerance
          @debt_graph[debtor].delete(creditor)
        end
      end
      @debt_graph.delete(debtor) if @debt_graph[debtor].empty?
    end
  end
end
