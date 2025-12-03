class Expense < ApplicationRecord
  belongs_to :payer, class_name: "User"
  belongs_to :group
  has_many :expense_participants, dependent: :destroy

  validates :description, presence: true
  validates :total_amount, presence: true, numericality: { greater_than: 0 }
  validates :payer, presence: true
  validates :group, presence: true
  validates :expense_date, presence: true
  validates :currency, presence: true

  validate :expense_date_cannot_be_in_the_future
  validate :total_amount_matches_participant_amounts
  validate :payer_must_be_group_member
  validate :participants_must_be_group_members

  def expense_date_cannot_be_in_the_future
    if expense_date.present? && expense_date > Date.current
      errors.add(:expense_date, "não pode ser no futuro")
    end
  end

  def total_amount_matches_participant_amounts
    if expense_participants.present? && expense_participants.sum(&:amount_owed) != total_amount
      errors.add(:total_amount, "não corresponde à soma das parcelas dos participantes")
    end
  end

  def payer_must_be_group_member
    if payer.present? && group.present? && !group.active_members.include?(payer)
      errors.add(:payer, "deve ser um membro ativo do grupo")
    end
  end

  def participants_must_be_group_members
    if group.present? && expense_participants.present?
      expense_participants.each do |participant|
        unless group.active_members.include?(participant.user)
          errors.add(:expense_participants, "inclui um usuário que não é membro ativo do grupo")
          break
        end
      end
    end
  end
end
