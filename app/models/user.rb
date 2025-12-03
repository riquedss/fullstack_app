class User < ApplicationRecord
  has_secure_password

  validates :name, presence: true
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  has_many :created_groups, class_name: "Group", foreign_key: "creator_id"
  has_many :group_memberships
  has_many :groups, through: :group_memberships # Adicionado para acessar os grupos dos quais o usuário é membro
  has_many :paid_expenses, class_name: "Expense", foreign_key: "payer_id"
  has_many :expense_participants
  has_many :sent_payments, class_name: "Payment", foreign_key: "payer_id"
  has_many :received_payments, class_name: "Payment", foreign_key: "receiver_id"
end
