// fullstack_app/client/src/components/groups/GroupForm.tsx
import React, { useState, useEffect } from 'react';
import api from '../../services/api';

interface Group {
  id?: number;
  name: string;
  description: string;
  group_type: string;
  creator_id?: number;
}

interface GroupFormProps {
  existingGroup?: Group | null;
  onFormSubmit: () => void;
  onCancel: () => void;
}

const GroupForm: React.FC<GroupFormProps> = ({ existingGroup, onFormSubmit, onCancel }) => {
  const [name, setName] = useState(existingGroup?.name || '');
  const [description, setDescription] = useState(existingGroup?.description || '');
  const [groupType, setGroupType] = useState(existingGroup?.group_type || 'other'); // Valor padrão
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (existingGroup) {
      setName(existingGroup.name);
      setDescription(existingGroup.description);
      setGroupType(existingGroup.group_type);
    } else {
      setName('');
      setDescription('');
      setGroupType('other');
    }
  }, [existingGroup]);

  const handleSubmit = async (event: React.FormEvent) => {
    event.preventDefault();
    setLoading(true);
    setError(null);

    try {
      const groupData = {
        name,
        description,
        group_type: groupType,
      };

      let response;
      if (existingGroup) {
        response = await api.patch(`/groups/${existingGroup.id}`, { group: groupData });
      } else {
        response = await api.post('/groups', { group: groupData });
      }

      if (response.status === 200 || response.status === 201) {
        console.log('Grupo salvo com sucesso', response.data);
        onFormSubmit();
      } else {
        setError(response.data.errors ? response.data.errors.join(', ') : 'Erro desconhecido ao salvar grupo.');
      }
    } catch (err: any) {
      console.error('Erro ao salvar grupo', err);
      if (err.response && err.response.data && err.response.data.errors) {
        setError(err.response.data.errors.join(', '));
      } else if (err.response && err.response.data && err.response.data.message) {
        setError(err.response.data.message);
      } else {
        setError('Erro ao tentar salvar grupo. Por favor, tente novamente.');
      }
    }
    setLoading(false);
  };

  return (
    <form onSubmit={handleSubmit} className="group-form">
      <h2>{existingGroup ? 'Editar Grupo' : 'Criar Novo Grupo'}</h2>
      {error && <p className="error-message">{error}</p>}
      <div>
        <label htmlFor="name">Nome do Grupo:</label>
        <input
          type="text"
          id="name"
          name="Nome do Grupo"
          value={name}
          onChange={(e) => setName(e.target.value)}
          required
        />
      </div>
      <div>
        <label htmlFor="description">Descrição:</label>
        <textarea
          id="description"
          value={description}
          onChange={(e) => setDescription(e.target.value)}
        ></textarea>
      </div>
      <div>
        <label htmlFor="groupType">Tipo de Grupo:</label>
        <select
          id="groupType"
          value={groupType}
          onChange={(e) => setGroupType(e.target.value)}
        >
          <option value="other">Outro</option>
          <option value="home">Casa</option>
          <option value="travel">Viagem</option>
          <option value="couple">Casal</option>
        </select>
      </div>
      <button type="submit" disabled={loading}>
        {loading ? 'Salvando...' : 'Salvar Grupo'}
      </button>
      <button type="button" onClick={onCancel} disabled={loading}>
        Cancelar
      </button>
    </form>
  );
};

export default GroupForm;
