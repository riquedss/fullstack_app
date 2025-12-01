require 'rails_helper'

RSpec.describe User, type: :model do
  describe 'validations' do
    it { should validate_presence_of(:email) }
    it { should validate_uniqueness_of(:email).case_insensitive }
    it { should validate_presence_of(:name) }
    it { should have_secure_password }
  end

  describe 'associations' do
    it { should have_many(:created_groups).class_name('Group').with_foreign_key('creator_id') }
    it { should have_many(:group_memberships) }
    it { should have_many(:groups).through(:group_memberships) }
    it { should have_many(:paid_expenses).class_name('Expense').with_foreign_key('payer_id') }
    it { should have_many(:expense_participants) }
    it { should have_many(:sent_payments).class_name('Payment').with_foreign_key('payer_id') }
    it { should have_many(:received_payments).class_name('Payment').with_foreign_key('receiver_id') }
  end

  describe 'factory' do
    it 'creates a valid user' do
      user = build(:user)
      expect(user).to be_valid
    end
  end
end

