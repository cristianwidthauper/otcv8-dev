# Samera Client — Guia de Build & Deploy (OTCv8)

Documentação completa de como **compilar, rodar e publicar** o client do Samera a partir
deste fonte. Escrito em 2026-06-19 depois de modernizar o código (de 2023) pro toolchain de 2026.

---

## ⚠️ LEIA ISTO ANTES DE BUILDAR (lições caras — 2026-07-14)

**Custo real de ignorar esta seção: 6 builds falhados e ~2h de trabalho jogado fora.**
Tudo abaixo já estava escrito neste doc — e foi ignorado. **Leia antes de tocar em Actions.**

### 1️⃣ REGRA DE OURO: existe só UM workflow que presta

| Workflow | Arquivo | Status |
|---|---|---|
| ✅ **Build Windows Samera** | `build-windows.yml` (id **298791151**) | **USE ESTE.** Histórico 100% sucesso |
| ❌ Build win (GL only) | `build-win.yml` | **NATIMORTO** — nunca passou. Não use, não conserte |
| ❌ Build on request / ci-cd / pr-test | outros | não são o caminho do Samera |

O `build-win.yml` aponta pro **vcpkg de 2022 (`3b3bd424`)**, que tem **asset rot**: baixa 7zip/msys2
de URLs que hoje são **404**, e o vcpkg velho **não enxerga o Visual Studio** do runner atual
(o `windows-2019` foi aposentado pelo GitHub). **Não tem conserto que valha a pena** — os artefatos
sumiram da internet (o `libwinpthread-git` não existe nem no web.archive). A modernização já foi
feita no `build-windows.yml` (vcpkg 2026-06 + overlay do LuaJIT). **Não reinvente.**

### 2️⃣ Se um build falhar, ANTES de debugar: olhe o histórico

Não presuma que "o build quebrou". Descubra **qual workflow já funcionou** e **quando**:

```bash
TOKEN=$(cat /root/.ghtoken); REPO=cristianwidthauper/otcv8-dev
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://api.github.com/repos/$REPO/actions/runs?per_page=100" \
 | python3 -c "
import sys,json
for r in json.load(sys.stdin)['workflow_runs']:
    if r.get('conclusion')=='success': print(r['created_at'][:16],'|',r['name'],'|',r['id'])"
```
Em 2026-07-14 isso teria respondido em 5 segundos: **"Build Windows Samera", último sucesso 22/jun**.
O build **não tinha quebrado** — ninguém tinha rodado desde então.

### 3️⃣ Race `git push` → `workflow_dispatch` (queimou 2 builds)

Disparar logo após o push pega a **ref VELHA** — você lê o log de um código que nem subiu, e sai
"consertando" o que já estava certo. **Espere propagar e valide o `head_sha`:**

```bash
WANT=$(git rev-parse origin/master)
# espera a API refletir o push
for i in $(seq 6); do
  API=$(curl -s -H "Authorization: Bearer $TOKEN" "https://api.github.com/repos/$REPO/commits/master" \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['sha'])")
  [ "$API" = "$WANT" ] && break; sleep 10
done
# ... dispatch ... e DEPOIS confirme:
#   head_sha do run == $WANT   -> senão, NÃO leia o log, é o commit velho
```

### 4️⃣ Deploy do `.exe` (o updater NÃO troca o exe)

O Windows não deixa o client sobrescrever a si mesmo rodando. Então:
1. Baixe o artifact **`Download-binaries`** → `otclient_gl.exe`
2. `cp` pra `aac/updater/otclient_gl.exe` (**backup antes**) — mantém o updater coerente
3. `cp` pra `aac/downloads/<nome-claro>.exe` → é **esse link** que o Felipe baixa na mão
4. `chown www-data:www-data` nos dois

⚠️ **Não crie nomes novos de exe sem avisar.** Em 2026-07-14 o Felipe ficou com `samera.exe` (antigo)
e `samera-escuridao.exe` (novo) na mesma pasta e testou o **errado** — o que invalidou o teste.
Ou reutilize o mesmo nome, ou diga explicitamente qual rodar.

### 5️⃣ Antes de culpar o `.exe` por um bug de comportamento

Cheque o `features.lua` (`aac/updater/modules/game_features/features.lua`). Muita coisa do C++ é
**gated por feature** — o código pode estar no exe e **dormindo**. Ex.: `GameFasterAnimations` está
**desligado** desde 2026-07-05 esperando "um build com creature.cpp que diferencia player/monstro"
(esse build **existe desde 2026-07-14** — dá pra religar quando quiser).

E lembre: **`git status` no repo** — pode haver fix local **nunca commitado** (logo, nunca buildado).
Foi o caso do `fastWalk` (2026-07-05 → só entrou no build de 2026-07-14).

---

## 0. TL;DR (o caminho feliz)

1. Faça seu patch no C++ (em `src/`) e dê push na branch `master` deste fork
   (`cristianwidthauper/otcv8-dev`).
2. Dispare o build: GitHub → Actions → **"Build Windows Samera"** → *Run workflow*
   (ou via API: `workflow_dispatch` em `build-windows.yml`).
3. Espere ~30-40min. Baixe o artifact **"Download-binaries"** → contém `otclient_gl.exe` (+ `.map`).
4. Pegue esse `otclient_gl.exe` e jogue **dentro da pasta do client Samera** (a que tem
   `data/`, `modules/`, `init.lua` com a config do Samera). É isso que aponta pro servidor.
5. Pra publicar pros players: ver seção **6. Deploy**.

> ⚠️ O `.exe` é só o **motor**. Ele NÃO contém config de servidor. Quem aponta pro Samera
> são os arquivos `init.lua` / `modules/` / `data/` da pasta do client (não o exe).

---

## 1. Arquitetura: fonte vs dist

| | Repo | Conteúdo |
|---|---|---|
| **Fonte C++** | `cristianwidthauper/otcv8-dev` (este) | `.cpp/.h`, `vc16/` (projeto VS), workflows |
| **Dist (o que roda)** | client deployado do Samera | `otclient_gl.exe` + `data/` + `modules/` + `init.lua` |

O build pega o fonte → gera `otclient_gl.exe`. Os `data/`/`modules/` do REPO são **vanilla**
(apontam pro `otclient.ovh`). Os do **Samera** têm a config do servidor + módulos custom +
version guard, e vivem na pasta do client deployado.

---

## 2. Build (GitHub Actions — nuvem, sem toolchain local)

Workflow: `.github/workflows/build-windows.yml`

- Runner **windows-2022**
- **vcpkg** pin `f3e10653...` (2026-06), triplet **x86-windows-static**
- Libs: boost-* (iostreams/asio/beast/system/variant/lockfree/process/program-options/uuid/filesystem),
  luajit, glew, physfs, openal-soft, libogg, libvorbis, zlib, libzip, bzip2, openssl
- **LuaJIT fixado em 2023-01-04** via `--overlay-ports` (ver seção 4 — CRÍTICO)
- MSBuild config **OpenGL**, PlatformToolset **v143**
- Artifact: `otclient_gl.exe` + `otclient_gl.map`
- Cache de deps: `VCPKG_BINARY_SOURCES=x-gha` (mas falha com frequência → builds lentos)

Primeira vez compila boost+luajit do zero (lento). Depois deveria cachear.

---

## 3. Correções feitas (código de 2023 → toolchain 2026)

### 3a. boost 1.88 (o asio mudou MUITA API) — toda no fonte, commitada
- `io_service` → `io_context` (pch.h, net, http, proxy, server)
- `resolver::iterator`/`query` → `results_type` + `async_resolve(host, service)`
- `buffer_cast` → `.data()` ; `expires_from_now` → `expires_after`
- `io_context::reset` → `restart` ; `address_v4::to_ulong` → `to_uint` ;
  `::from_string` → `make_address_v4` ; `timer.cancel(ec)` → `cancel()`
- beast `string_view.to_string()` → `std::string(...)`
- `boost::process` (v1, removido) → **`g_platform.spawnProcess`** (relaunch nativo)
- Includes faltando: `<climits>` em `luaengine/lbitlib.cpp` e `net/inputmessage.cpp` (INT_MAX no MSVC2022)

> ℹ️ O código usa a API NOVA do asio (existe desde boost ~1.66) → compila em boost novo OU antigo.

### 3b. Link (settings.props / vc16/otclient.vcxproj)
- **Tirar nomes de lib vcpkg explícitos** (zlib/ssl/physfs/lua/glew32) — o
  `vcpkg integrate install` auto-linka tudo via wildcard `installed\...\lib\*.lib`.
  Manter só libs de **sistema** (opengl32, kernel32, winmm, dbghelp, **avrt**, etc.).
- **Runtime full-estático `/MT`**: remover CRT dinâmico (msvcrt/ucrt/vcruntime) +
  remover `IgnoreSpecificDefaultLibraries=libcmt`. (Mistura estático+dinâmico quebrava a STL.)
- **PlatformToolset v142 → v143** (o runner tem 14.29 E 14.44; mismatch deixava 25 símbolos
  STL — charconv/Thrd — órfãos). v143 alinha headers+libs+linker.
- Adicionar **avrt.lib** (openal usa `AvSetMmThreadCharacteristics`).

### 3c. LuaJIT — ver seção 4 (foi o crash de runtime)

---

## 4. ⚠️ CRÍTICO: LuaJIT precisa ser o 2023-01-04 (não o do vcpkg novo)

**Sintoma:** compila e linka, mas CRASHA no startup —
`ACCESS_VIOLATION` em `LuaInterface::luaCppFunctionCallback` (`popUpvalueUserdata()`
retorna NULL → deref de null), na PRIMEIRA chamada de função C++ do Lua.

**Causa:** o vcpkg `f3e10653` instala **LuaJIT 2026-05-24 (bleeding edge)**, que tem
mudança de layout de userdata/closure + `__gc` em outra thread → **quebra o binding do OTCv8**.
(Conhecido na comunidade: thread "LuaJIT Breaking Change" no OTLand.)

**Fix (aplicado):** pin do LuaJIT pra **2023-01-04 (port-7)** via overlay-port, mantendo
o resto do vcpkg igual:
- pasta `vcpkg-overlay-ports/luajit/` (port copiado do git-tree `8d6aa0d` do vcpkg)
- `--overlay-ports=${{ github.workspace }}/vcpkg-overlay-ports` no `vcpkgArguments`

> O vcpkg manteve LuaJIT 2023-01-04 de 2023 até DEZ/2025; só pulou pro 2026 em jan/2026.
> Logo 2023-01-04 = a era do client que funciona.

**Fallback** (se 2023 algum dia falhar): **LuaJIT 2.0.5** (o que o ci-cd OFICIAL do OTCv8
pina). Port já pronto em `vcpkg-overlay-205/luajit/` — é só trocar o conteúdo de
`vcpkg-overlay-ports/luajit/` por ele.

---

## 5. Rodar / Testar

O `.exe` precisa das pastas `data/`, `modules/`, `init.lua` ao lado (não roda sozinho).

- **Testar o engine (vanilla):** `clientrafa-full.zip` (em `samera.online`) = exe + data/modules
  vanilla. Abre, mas o server list aponta pro otclient.ovh (não pro Samera).
- **Testar CONTRA o Samera:** jogue o `otclient_gl.exe` novo **dentro da pasta do client
  Samera real** (com a config/módulos do Samera) → aí conecta no Samera.

### Debugar crash de runtime (Wine ou Windows)
O reporter de erro do OTCv8 só trata `stdext::exception`; `std::exception`/segfault viram
"fatal error" cego. Método que funciona:
```bash
WINEDEBUG=+seh wine otclient_gl.exe 2>&1 | grep -iE "c0000005|exception|fault"
```
Pegue o `addr=` / `eip=` da linha `c0000005` → mapeie no `otclient_gl.map`
(o build gera com `GenerateMapFile=true` + `RandomizedBaseAddress=false` p/ o endereço bater):
acha o símbolo com endereço logo abaixo do `eip`.

---

## 6. Deploy (pros players) — checklist

1. **Re-ligar produção** no `vc16/settings.props` (estão OFF p/ debug):
   - `RandomizedBaseAddress` → `true` (re-ligar ASLR)
   - remover `GenerateMapFile` (ou deixar false)
2. Rebuild → baixar `otclient_gl.exe`.
3. **Ícone:** re-aplicar `samera.ico` no exe (o build sai com ícone padrão).
   Ver `/home/samera/client-rebuild/LEIA-ME.txt`.
4. **Repackage:** trocar o `otclient_gl.exe` antigo pelo novo na pasta do client Samera.
5. **Updater:** publicar via o auto-updater do OTCv8 (`aac/updater/`) — ver memória
   `samera-client-updater`. Casa com o version guard (`samera-client-version-guard`).

---

## 7. Gotchas / lições

- **run-vcpkg@v7 é modo CLÁSSICO** — ignora `vcpkg.json`/manifest. Por isso o pin do LuaJIT
  é via `--overlay-ports`, não manifest override.
- vcpkg MUITO antigo (~2021, ex commit 3b3bd424) tem **asset rot** (baixa 7zip/msys2 de URLs
  404). Por isso NÃO dá pra simplesmente voltar pro vcpkg antigo — daí o overlay.
  > **Autópsia (2026-07-14)** — tentei reviver esse vcpkg e mapeei a cascata inteira. Fica aqui
  > pra ninguém repetir. São 4 paredes, e a última **não tem saída**:
  > 1. **7zip 21.7.0** → `7-zip.org/a/7z2107-extra.7z` = **404**. *Contornável:* os bytes originais
  >    estão no web.archive (SHA512 confere) → pré-semear + `VCPKG_DOWNLOADS`.
  > 2. **pkg-config (MSYS2)** → o `bzip2` chama `vcpkg_fixup_pkgconfig`; os pacotes têm versão
  >    pinada e o MSYS2 **apagou de todos os 8 mirrors**. O `libwinpthread-git` **não existe nem no
  >    web.archive** → impossível pré-semear. *Contornável só* pelo escape hatch:
  >    `vcpkg_find_acquire_program.cmake:533` respeita a env **`PKG_CONFIG`** e dá `return()`.
  > 3. **Ambiente isolado** → o vcpkg builda ports num ambiente limpo (`docs/users/triplets.md`),
  >    então `PKG_CONFIG` não chega no portfile. Precisa de **`VCPKG_KEEP_ENV_VARS=PKG_CONFIG`**.
  > 4. **☠️ PAREDE FINAL** → `openal-soft` usa o generator do VS (os outros 89 usam Ninja). O vcpkg
  >    velho escolhe **v142 → "Visual Studio 16 2019"**, que **não existe** no runner (GitHub
  >    aposentou o `windows-2019`). Forçar **v143** via overlay-triplet resulta em
  >    `Unable to find a valid Visual Studio instance with toolset version v143` — o vcpkg-tool de
  >    2022 **não enxerga** o VS de 2026. Isso é **código dele**, não configuração. **Sem saída.**
  >
  > **Moral:** o caminho certo já está pronto no `build-windows.yml` (vcpkg 2026-06 + overlay do
  > LuaJIT). Cheguei a considerar "bumpar o vcpkg" como opção arriscada — **já estava feito lá**.
- Auto-link de libs: NÃO listar libs vcpkg explícitas no projeto (o wildcard cobre); só quebra.
- Editar o fonte rápido: este repo está clonado em `/root/otcv8-fix` (grep/sed >> API).
- Build local (VM Windows / Linux gdb) seria 10x mais rápido pra debugar runtime — fica de
  sugestão se a nuvem (30-40min/ciclo) incomodar.
