require 'rails_helper'

RSpec.describe Group, type: :model do
  subject { create(:group) }

  describe 'validations' do
    it { should validate_presence_of(:name) }
    it { should validate_uniqueness_of(:name).case_insensitive }
  end

  describe 'associations' do
    it { should belong_to(:creator).class_name('User') }
    it { should have_many(:group_memberships) }
    it { should have_many(:members).through(:group_memberships).source(:user) }
    it { should have_many(:expenses) }
    it { should have_many(:payments) }
  end

  describe 'factory' do
    it 'creates a valid group' do
      group = build(:group)
      expect(group).to be_valid
    end

    it 'creates group with creator as active member' do
      group = create(:group)
      expect(group.active_members).to include(group.creator)
    end
  end
end

