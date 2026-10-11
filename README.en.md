# FireDAC in Practice — shared examples

English reading guide to the examples by Régys Borges da Silveira. The repository
name, source paths, database objects, test identifiers, and runtime messages retain
their original spelling. FireStore is the sample application, not Google Cloud
Firestore. Do not translate identifiers when copying code or running a test.

## Start safely

Use Windows with RAD Studio 13 Florence (Delphi compiler 37.0). Build separate
Win32 and Win64 executables from the same source. Each process needs matching
native client libraries, regardless of the database server's architecture.
Firebird 5 is the main lab; SQLite, PostgreSQL 18, and MySQL 8.4 LTS support
complementary experiments.

Use a disposable laboratory environment, never a production database. Validation
scripts create databases, users, fixtures, and deliberate failures. Some recreate
named containers. Read the selected script and its prerequisites before running
it; do not use an existing customer environment as the test target. Credentials
belong in runtime configuration, not Git, screenshots, or shared logs.

From the repository root, validate the example catalog without running Delphi:

```powershell
.\scripts\validate-manifest.ps1
```

This checks metadata and evidence paths. It does not compile or execute the labs.
Open `manifest/examples.json`, find the book's `EX-NN-NN` identifier, and inspect
its evidence and limitations. States are PL (planned), IM (implemented), CP
(compiled), EX (executed), RV (reviewed), and EC (conditional evidence). EC is not
equivalent to RV. In particular, EX-21-04 still requires deployment validation on
a clean machine; success on a development workstation does not satisfy that gate.

## Run Chapter 1

First install/start your laboratory Firebird 5 server and identify its local
administrative password. Choose a disposable password for the FIRESTORE_APP lab
user. The scripts assume the standard RAD Studio installation path; inspect their
StudioVersion parameter and compiler path if your installation differs.

The client installer downloads pinned official Firebird kits and verifies their
hashes. It writes separate architecture folders; it does not install the server:

```powershell
.\scripts\install-firebird-clients.ps1 -Architecture Both
```

Keep the complete client dependency folders together. Do not mix Win32 and Win64
DLLs or replace a missing dependency with an arbitrary library from PATH.

The following example prompts for lab credentials rather than storing literal
passwords in a script. These existing validators accept strings, so the password
is still present in process memory; prompting does not make it a secure vault.

```powershell
$labAdminCredential = Get-Credential -UserName SYSDBA -Message 'Local Firebird lab administrator'
$labAppCredential = Get-Credential -UserName FIRESTORE_APP -Message 'Disposable application password'
.\scripts\validate-chapter-01.ps1 `
  -AdminPassword $labAdminCredential.GetNetworkCredential().Password `
  -AppPassword $labAppCredential.GetNetworkCredential().Password
```

This validator prepares FireStore M0, compiles both console and VCL projects for
both architectures, runs positive and negative cases, and checks the DFM. The
success line begins “Capítulo 1 aprovado”: Chapter 1 passed. A deliberate negative
case is successful only when the harness recognizes the expected failure; an
unhandled exception or nonzero exit is not a pass.

For manual exploration, open `chapters/chapter-01/src/Chapter01Vcl.dpr` in Delphi.
“Abrir catálogo” means “Open catalog.” Configuration comes from environment
variables, not saved passwords in the form. The validator sets up its own runtime
environment; a separately launched IDE does not automatically inherit it.

## Find subsequent labs

Chapter projects live in `chapters/chapter-NN/`. Chapter 4 is the exception: its
M0 application is in `firestore/`, with evidence under `manifest/evidence/M0/`.
The root-level validators are `scripts/validate-chapter-NN.ps1` for Chapters
1–3 and 5–21; use `scripts/validate-firestore-m0.ps1` for Chapter 4.
Do not assume every script accepts the same parameters. Inspect its initial
parameter block and chapter README before execution.

The additional Chapter 3 external lab is `scripts/validate-chapter-03-external.ps1`;
the Chapter 21 TLS lab is `scripts/validate-chapter-21-tls.ps1`. They use Docker
and PostgreSQL clients for both architectures. Override PostgreSQLClientWin32 and
PostgreSQLClientWin64 with your actual libpq.dll paths: the checked-in defaults
describe the original validation machine, not a portable installation location.
Review container names, exposed ports, and cleanup behavior before running them.
Do not run the whole script collection blindly.

## Interpret output

| Original wording | English meaning and action |
|---|---|
| aprovado / reprovado | passed / failed; check the harness's final result |
| Variável obrigatória ausente | required environment variable missing; set the named variable |
| Ambiente inválido | invalid environment profile; select a supported profile |
| Driver inesperado | unexpected driver; check the selected test configuration |
| O caminho do banco deve ser absoluto | database path must be absolute; supply a full path |
| Ordenação inválida | invalid sort order; choose an allowed option |
| Representação de active não homologada | unsupported active-field representation; inspect its type mapping |
| alteração(ões) pendente(s) | pending local changes, not confirmed database writes |
| alterações não foram aplicadas / erro(s) no apply | errors applying changes; inspect reconciliation details |
| erro(s) no grafo | errors applying the coordinated dataset graph |
| linhas afetadas | affected rows; compare the actual count with the command's contract |
| Quantidade inválida no chunk | invalid number of input rows in this chunk |
| Chunk esperava N linhas e informou M | expected N affected rows but reported M; investigate before retrying |
| evidência condicionada | conditional evidence; read the outstanding external gate |

Preserve names such as product, order_status, and parameter identifiers exactly.
Sample labels such as “Café especial” (specialty coffee) and “Mouse sem fio”
(wireless mouse) are data, not commands. Accent-bearing values deliberately help
test Unicode and comparison behavior. A translated explanation does not change
the original assertion, nor does this guide certify a new test run.

If execution differs from the book, record the example ID, architecture, Delphi
version, driver, loaded client path, server version, and first failing step.
Sanitize credentials and personal data before sharing diagnostics. The author's
code is Apache-2.0; third-party dependencies retain their respective licenses.
