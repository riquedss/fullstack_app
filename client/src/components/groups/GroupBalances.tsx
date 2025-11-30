// fullstack_app/client/src/components/groups/GroupBalances.tsx
import React from 'react';

interface UserData {
  id: number;
  name: string;
}

interface NetBalance {
  user: UserData;
  amount: string;
}

interface DetailedDebt {
  debtor: UserData;
  creditors: { user: UserData; amount: string; }[];
}

interface OptimizedPayment {
  payer: UserData;
  receiver: UserData;
  amount: string;
}

interface GroupBalancesProps {
  netBalances: NetBalance[];
  detailedBalances: DetailedDebt[];
  optimizedPayments: OptimizedPayment[];
  currency: string;
}

const GroupBalances: React.FC<GroupBalancesProps> = ({ netBalances, detailedBalances, optimizedPayments, currency }) => {
  return (
    <div className="group-balances">
      <h3>Balanços do Grupo</h3>

      <h4>Saldos Líquidos:</h4>
      {netBalances.length === 0 ? (
        <p>Nenhum saldo líquido para exibir.</p>
      ) : (
        <ul>
          {netBalances.map((balance, index) => {
            const amount = parseFloat(balance.amount);
            const isPositive = amount >= 0;
            const absAmount = Math.abs(amount);
            
            return (
              <li key={index}>
                <strong>{balance.user.name}:</strong>
                <span className={isPositive ? 'positive-balance' : 'negative-balance'}>
                  {isPositive 
                    ? `deve receber ${absAmount.toFixed(2)} ${currency}`
                    : `deve pagar ${absAmount.toFixed(2)} ${currency}`
                  }
                </span>
              </li>
            );
          })}
        </ul>
      )}

      <h4>Pagamentos Otimizados:</h4>
      {optimizedPayments.length === 0 ? (
        <p>Nenhum pagamento otimizado necessário. Contas estão equilibradas!</p>
      ) : (
        <ul>
          {optimizedPayments.map((payment, index) => (
            <li key={index}>
              {payment.payer.name} deve {payment.amount} {currency} para {payment.receiver.name}
            </li>
          ))}
        </ul>
      )}

      {/* Opcional: Visualização de detailedBalances para debug ou complexidade extra */}
      {/* <h4>Dívidas Detalhadas:</h4>
      {detailedBalances.length === 0 ? (
        <p>Nenhuma dívida detalhada para exibir.</p>
      ) : (
        <div>
          {detailedBalances.map((debt, index) => (
            <div key={index}>
              <p>{debt.debtor.name} deve:</p>
              <ul>
                {debt.creditors.map((creditorDebt, cIndex) => (
                  <li key={cIndex}>
                    {creditorDebt.amount} {currency} para {creditorDebt.user.name}
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>
      )} */}
    </div>
  );
};

export default GroupBalances;
