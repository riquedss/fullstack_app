RSpec.describe 'Group Members', type: :system, js: true do
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

  it 'permite que o criador veja e gerencie membros do grupo' do
    login(user)

    find('.group-item span', text: group.name).click

    click_button 'Gerenciar Membros'

    expect(page).to have_content('Gerenciar Membros do Grupo')
    expect(page).to have_content('Membros Atuais')
    expect(page).to have_content(user2.name)

    new_user = create(:user)

    fill_in 'Buscar usuário por nome ou email...', with: new_user.email[0, 5]
    expect(page).to have_content('Buscando...').or have_no_content('Buscando...')

    expect(page).to have_content(new_user.email)
    click_button 'Adicionar'

    expect(page).to have_content(new_user.name)
  end
end
