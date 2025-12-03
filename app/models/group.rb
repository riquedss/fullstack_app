class Group < ApplicationRecord
  belongs_to :creator, class_name: "User"
  has_many :group_memberships
  has_many :members, through: :group_memberships, source: :user # Adicionado para fácil acesso aos membros
  has_many :expenses
  has_many :payments

  validates :name, presence: true, uniqueness: true

  # Calcula o saldo líquido de cada usuário no grupo.
  # @return [Hash<User, BigDecimal>] Um hash mapeando usuários para seus saldos líquidos.
  def calculate_balances
    balances = Hash.new { |hash, key| hash[key] = BigDecimal("0.00") }

    # Calcular balanços a partir das despesas
    expenses.includes(expense_participants: :user).each do |expense|
      balances[expense.payer] += expense.total_amount
      expense.expense_participants.each do |participant|
        balances[participant.user] -= participant.amount_owed
      end
    end

    # Ajustar balanços para pagamentos (lógica Splitwise)
    # Pagamentos melhoram o saldo do pagador (reduzem dívida) e pioram o saldo do recebedor
    payments.each do |payment|
      balances[payment.payer] += payment.amount
      balances[payment.receiver] -= payment.amount
    end

    balances
  end

  # Helper para obter membros ativos do grupo
  def active_members
    members.where(group_memberships: { status: "active" })
  end
end
