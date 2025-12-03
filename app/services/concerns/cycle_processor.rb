# frozen_string_literal: true

# fullstack_app/app/services/concerns/cycle_processor.rb
module CycleProcessor
  private

  def extract_cycle_from_path(cycle_end_node, current_path)
    start_index = current_path.index(cycle_end_node)
    return unless start_index

    current_path[start_index..-1]
  end

  def find_minimum_debt_in_cycle(cycle)
    min_debt = BigDecimal("Infinity")

    cycle.each_cons(2) do |from_node, to_node|
      min_debt = [ min_debt, @debt_graph[from_node][to_node] ].min
    end

    # Include the closing edge of the cycle
    closing_debt = @debt_graph[cycle.last][cycle.first]
    [ min_debt, closing_debt ].min
  end

  def apply_debt_reduction(cycle, reduction_amount)
    cycle.each_cons(2) do |from_node, to_node|
      @debt_graph[from_node][to_node] -= reduction_amount
    end

    # Apply to closing edge
    @debt_graph[cycle.last][cycle.first] -= reduction_amount
  end

  def log_cycle_removal(cycle, reduction_amount)
    cycle_path = cycle.map(&:id).join(" -> ")
    closing_node = cycle.first.id

    Rails.logger.info(
      "Ciclo removido: #{cycle_path} -> #{closing_node}. Valor ajustado: #{reduction_amount}"
    )
  end
end
