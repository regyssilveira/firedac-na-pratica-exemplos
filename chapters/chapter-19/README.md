# Capítulo 19 — Execução assíncrona, threads e pooling

O laboratório cobre abertura assíncrona e propagação de erro, `AbortJob`, doze
`TTask`s com componentes próprios, pool concorrente e saturação/recuperação.
O modo `generation` força a resposta antiga a chegar depois da atual e comprova
descarte por geração com transferência única de ownership.

```powershell
.\scripts\validate-chapter-19.ps1 -AdminPassword '<senha>' -AppPassword '<senha>'
```

BM-08 mede dez leases novos e dez leases após aquecimento do pool. BM-09 separa
tempo de retorno da chamada assíncrona e tempo total para cem mil registros.
