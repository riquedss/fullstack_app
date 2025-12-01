RSpec.describe 'Group Management', type: :system, js: true do
  let!(:user) { create(:user) }

  def login(user)
    visit '/'
    fill_in 'Email', with: user.email
    fill_in 'Senha', with: 'password'
    click_button 'Entrar'
  end

  it 'permite que um usuário crie um grupo' do
    login(user)

    click_button 'Criar Novo Grupo'
    fill_in 'Nome do Grupo', with: 'Meu Grupo de Teste'
    click_button 'Salvar Grupo'

    expect(page).to have_content('Meu Grupo de Teste')
  end

  it 'permite que um usuário edite um grupo' do
    create(:group, name: 'Grupo Existente', creator: user)

    login(user)

    find('.group-item span', text: 'Grupo Existente').click

    click_button 'Editar Grupo'

    fill_in 'Nome do Grupo', with: 'Grupo Editado'
    click_button 'Salvar Grupo'

    expect(page).to have_content('Grupo Editado')
  end
end
