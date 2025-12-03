# frozen_string_literal: true

# fullstack_app/app/services/concerns/debt_opposition_handler.rb
module DebtOppositionHandler
  private

  def skip_self_debt?(user1, user2)
    user1 == user2
  end

  def has_opposing_debts?(user1, user2)
    @debt_graph[user2] &&
      @debt_graph[user2][user1] &&
      @debt_graph[user1][user2] > @tolerance &&
      @debt_graph[user2][user1] > @tolerance
  end

  def simplify_opposing_debt(user1, user2)
    debt1_to_2 = @debt_graph[user1][user2]
    debt2_to_1 = @debt_graph[user2][user1]

    if debt1_to_2 > debt2_to_1
      settle_debt_in_favor(user1, user2, debt1_to_2 - debt2_to_1)
    else
      settle_debt_in_favor(user2, user1, debt2_to_1 - debt1_to_2)
    end
  end

  def settle_debt_in_favor(creditor, debtor, amount)
    @debt_graph[creditor][debtor] = amount
    @debt_graph[debtor].delete(creditor)
  end
end
