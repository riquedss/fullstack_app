RSpec.describe 'Payment', type: :system, js: true do
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

  it 'permite que um usuário registre um pagamento no grupo' do
    login(user)

    find('.group-item span', text: group.name).click

    click_button 'Adicionar Pagamento'

    fill_in 'Valor', with: '200.00'
    select user2.name, from: 'Recebedor'
    fill_in 'Data do Pagamento', with: '2000-01-01'
    fill_in 'Moeda', with: 'BRL'

    click_button 'Salvar Pagamento'

    expect(page).to have_content('Pagamentos do Grupo')
    expect(page).to have_content("Pagamento de #{user.name} para #{user2.name}")
    expect(page).to have_content('Valor: 200 BRL')
  end
end
