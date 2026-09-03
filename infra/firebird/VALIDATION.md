# Evidência de validação dos clientes Firebird

**Data:** 3 de setembro de 2026  
**RAD Studio:** 13 Florence, compilador 37.0.57242.3601  
**Servidor:** Firebird 5.0.4.1812 Win32, TCP 3050

| Alvo Delphi | Kit oficial | SHA-256 do arquivo | PE de `fbclient.dll` | Conexão FireDAC |
|---|---|---|---|---|
| Win32 | `Firebird-5.0.4.1812-0-windows-x86.zip` | `E46747EE167FB0B305BF2A7CEC70964FA2499F58A7E5F89E64FF0EBAC8F4768A` | `0x014C` | Firebird 5.0.4 |
| Win64 | `Firebird-5.0.4.1812-0-windows-x64.zip` | `01E844FCE4D5F53272A76205DBC3A1BA4B782AB8E8EADCD808CDBCCD9CE13B72` | `0x8664` | Firebird 5.0.4 |

Hashes observados das bibliotecas cliente:

- Win32: `E9BA227123EC78C8599F27AC1AB6F4F39E90AD5ECF5B16F5A1EED3191B52FFFE`;
- Win64: `0B8B81B733820008A0287498912C0A308CFCC35370DE8CC4D496538DF7AA93A6`.

Os dois programas foram compilados separadamente, carregaram o cliente correspondente
e executaram por FireDAC uma consulta de versão contra o mesmo servidor. Senhas e
binários não foram gravados no repositório.
