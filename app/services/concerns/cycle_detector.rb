# frozen_string_literal: true

# fullstack_app/app/services/concerns/cycle_detector.rb
module CycleDetector
  private

  def mark_node_as_visited(u, visited, recursion_stack, path)
    visited[u] = true
    recursion_stack[u] = true
    path << u
  end

  def process_neighbors(u, visited, recursion_stack, path)
    return unless @debt_graph[u]

    @debt_graph[u].keys.each do |v|
      next unless significant_debt?(u, v)

      handle_neighbor(u, v, visited, recursion_stack, path)
    end
  end

  def significant_debt?(u, v)
    @debt_graph[u][v] > @tolerance
  end

  def handle_neighbor(u, v, visited, recursion_stack, path)
    if !visited[v]
      dfs_detect_and_remove_cycle(v, visited, recursion_stack, path)
    elsif recursion_stack[v]
      process_cycle(u, v, path)
    end
  end

  def cleanup_recursion_state(u, recursion_stack, path)
    recursion_stack.delete(u)
    path.pop
  end
end
