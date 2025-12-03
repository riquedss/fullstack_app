RSpec.describe 'Expense', type: :system, js: true do
  let!(:user) { create(:user) }
  let!(:user2) { create(:user) }
  let!(:group) { create(:group, name: 'Meu Grupo', creator: user) }
  let!(:membership) { create(:group_membership, group: group, user: user2) }

  def login(user)
    visit '/'
    fill_in 'Email', with: user.email
    fill_in 'Senha', with: 'password'
    click_button 'Entrar'
  end

  it 'permite que um usuário adicione uma despesa a um grupo' do
    login(user)

    find('.group-item span', text: group.name).click

    click_button 'Adicionar Despesa'

    fill_in 'Descrição', with: 'Compra de supermercado'
    fill_in 'Valor', with: '150.00'

    within('.participants-selection') do
      check user.name
      check user2.name
    end

    click_button 'Salvar Despesa'

    expect(page).to have_content('Despesas do Grupo')
    expect(page).to have_content('Compra de supermercado')
    expect(page).to have_content('Valor Total: 150 BRL')
    expect(page).to have_content(user.name)
    expect(page).to have_content(user2.name)
  end
end
