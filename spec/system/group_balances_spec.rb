RSpec.describe 'Group Balances', type: :system, js: true do
  let!(:user)  { create(:user) }
  let!(:user2) { create(:user) }
  let!(:group) { create(:group, name: 'Meu Grupo', creator: user) }
  let!(:membership) { create(:group_membership, group: group, user: user2) }

  def login(user)
    visit '/'
    fill_in 'Email', with: user.email
    fill_in 'Senha', with: 'password'
    click_button 'Entrar'
  end

  it 'permite que um usuário visualize os balanços do grupo' do
    login(user)

    find('.group-item span', text: group.name).click

    click_button 'Ver Balanços e Otimizar Pagamentos'

    expect(page).to have_content('Balanços do Grupo')

    expect(page).to have_content('Saldos Líquidos:')
    expect(page).to have_content('Pagamentos Otimizados:')
  end
end
