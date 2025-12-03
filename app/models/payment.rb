class Payment < ApplicationRecord
  belongs_to :payer, class_name: "User"
  belongs_to :receiver, class_name: "User"
  belongs_to :group

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :payer, presence: true
  validates :receiver, presence: true
  validates :group, presence: true
  validates :payment_date, presence: true
  validates :currency, presence: true

  validate :payment_date_cannot_be_in_the_future
  validate :payer_cannot_be_receiver
  validate :payer_must_be_group_member
  validate :receiver_must_be_group_member

  def payment_date_cannot_be_in_the_future
    if payment_date.present? && payment_date > Date.current
      errors.add(:payment_date, "não pode ser no futuro")
    end
  end

  def payer_cannot_be_receiver
    if payer_id == receiver_id
      errors.add(:receiver, "não pode ser o mesmo que o pagador")
    end
  end

  def payer_must_be_group_member
    if payer.present? && group.present? && !group.active_members.include?(payer)
      errors.add(:payer, "deve ser um membro ativo do grupo")
    end
  end

  def receiver_must_be_group_member
    if receiver.present? && group.present? && !group.active_members.include?(receiver)
      errors.add(:receiver, "deve ser um membro ativo do grupo")
    end
  end
end
