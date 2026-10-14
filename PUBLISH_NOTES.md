# PUBLISH_NOTES: setup-run-1/2/3.html (phases 74-81)

## Web bundle (pages/web-bundle)

The web app files at the repo root (js, css, index.html, sw.js) were refreshed from My-tools `web/` by a script that never touches `config.js`, `setup-*.html`, `audit-a.html` or this file. `index.html` loads each script and style with `?v=<build id>` and `sw.js` has a matching VERSION, so phones never mix old and new files. Details, database phase table and rollback are in `DEPLOY_CHECKLIST.md`.

Source repo: https://github.com/mistybari99/My-tools , branch `integration/p72-p79`, commit used: `fd9590a47969010f0d678f532ccaa8126735f1c6` (integration had not moved; HEAD is still this commit). Phase files 72-81 are unchanged vs the earlier builds (sha256 below). Phases 82+ are NOT included.

Owner already ran phases 72, 73 and the first half of phase 74 (`setup-sql-1.html`, kept as a record). Remaining SQL is three one-paste pages split at whole-phase boundaries (phase files are paste-twice safe, so Run 1 re-running the first half of phase 74 is harmless):

| Page | Phases | Payload bytes | Payload sha256 |
|---|---|---|---|
| setup-run-1.html | 74, 75 | 132954 | `2f12335a35f58e6bd4e9ddb2899dc25d9af831764c9f635a62534242b477966d` |
| setup-run-2.html | 76, 77, 78, 79 | 172470 | `b584c7b620a1338fd15e712934019245efbd1b35d6dd35da9f640fa41c1ec094` |
| setup-run-3.html | 80, 81 | 160332 | `e19f84f461bc2325abb3f9ccd798e4dc80b8dc68ea4c0cb866baa630e09f06ac` |

Payload = for each phase: the line `-- ===== phase NN =====` + newline, then the exact bytes of `supabase/phaseNN.sql`; nothing else added, statements unaltered. All three payloads are under 250 KB.
Run 3 also has a read-only CHECK (single SELECT, 4085 bytes, sha256 `475bc343e0a3b25c645f22580466f89fa17cdbd81ca7843c25b71dc0a8db685b`) as a second small Copy button.
Order lock (chain): Run 2 needs Run 1 done, Run 3 needs Run 2 done. Shared localStorage key `bos_setup_run_done_v1` (try/catch, in-memory fallback). Undoing a run clears the later ones.

## Source files (sha256 of each whole phase file)

| Phase | Last commit touching file | Bytes | sha256 |
|---|---|---|---|
| 72 | eb5f6a3 | 78993 | `8b9a5ca868d8a4c39e13b577d2910e09ba838257371072806c1d4eaac17652e8` |
| 73 | 36fe06d | 53075 | `b1b4f37682f62f8c73c37305f6492f1f7d90e3221613bc62b425c7a1de85f4d7` |
| 74 | c8c4f56 | 77437 | `4ef3837cf9260fffe0fdc8d4a365695dfa21ddf4182b5063ddd86b67bab9dc72` |
| 75 | 1669f37 | 55469 | `c450df969e4d6cde4ee723b47307a4f99070835d3c9f16b5ef34693584f2afba` |
| 76 | 8f9c6b1 | 67945 | `d7a8bfdcbcfb966d7e301d2751b4e689bf041471512d49a02f10bba3545bbaaf` |
| 77 | b75d9ec | 20754 | `5938a8a5cf343d605f864e737a5c9786a7432b4b71ec132efece0b13278a63ae` |
| 78 | f8d786c | 37377 | `5a8c2f306fdc3aa4f2c7c0879f5a03c3c34a9f99fa0dc716e5fcd60368e2fbb4` |
| 79 | dbecc25 | 46298 | `7a1a5d4dd3ac9f2491c248021b8dadb9af3d5551eb791df3d5d0318c05e65dd5` |
| 80 | c23e82d | 94090 | `c5143b460a0fb2e8d7171644b8963b2dcf8c8b04896838199128d159eeee90d3` |
| 81 | bb8913d | 66194 | `5985766b48667d68c565fe26ae5b8523257b5ad7fa141e044896bf0fdac6691d` |

---

# Runs 4-9 (phases 82-98)

Source repo My-tools, branch `integration/p72-p79`, canonical order from `docs/PASTE_ORDER.md` (INT3): 82,83,84,85,86,87,88,90,91,89,92,93,95,94,96,97,98 (phase 89 after 91, 94 after 95, 98 last). Requested tip `0f24cea`; the branch has since moved (HEAD `0aea30e`, a later template merge), but phase82..98 files are byte-identical at both commits (`git diff 0f24cea HEAD` empty for them) and every sha256 below equals the list in `docs/briefs_p2p3/step_INT3_REPORT.md`. Runs 1-3 (phases 72-81) are unchanged.

Pages (one Copy button each, chain lock Run N needs Run N-1 done, shared key `bos_setup_run_done_v1`, header "Run N of 9"). Payload = `-- ===== phase NN =====` line + exact source bytes, nothing else.

| Page | Phases (paste order) | Payload bytes | Payload sha256 |
|---|---|---|---|
| setup-run-4.html | 82, 83, 84 | 129958 | `3df870f2966ab820f999fa7d9b807401a4edac3dfecbea9c8011f6b749c6be72` |
| setup-run-5.html | 85, 86, 87 | 165543 | `ce58779ff2833cbed798da009dc6c6d271a737f35bca9bde9380b63c92d3b17d` |
| setup-run-6.html | 88, 90, 91 | 119492 | `32ad02df09128a8a350e3ab644c82c60058ac5180b7b398608935f4563bab545` |
| setup-run-7.html | 89, 92, 93 | 195107 | `3fd41eb71d0ebc5072da110980c6d116810d85a72350fc1e36921ab2c954a4d6` |
| setup-run-8.html | 95, 94, 96 | 169231 | `6e5069da1e27db49e748a19b382c583a9aa3e2905b5040e72bd1eccc06705ea9` |
| setup-run-9.html | 97, 98 | 198695 | `4e95dbd6b8467404f5369ea9fdbfa4fb15dcdeae418eeef515ad78a4e13a67cf` |

Run 9 also has a read-only CHECK (single SELECT, 4421 bytes, sha256 `e74340588601ba7a2186f4e35220812ebac0d9e1b9d484c6b7e6d41c0e732943`): tick/cross per phase 82..98 (functions, tables, triggers, rule keys, and function-body tags for 89 and 98).

| Phase | Bytes | sha256 |
|---|---|---|
| 82 | 49642 | `61439adc346e3328c89a0d17309443cfacfc08a6e63b29cffb636b5e6665495a` |
| 83 | 68300 | `848328e519c1f4d9d63d47609cbed49e677c60e049151deb46367e39ca68e514` |
| 84 | 11944 | `603f631fe38c2823bd3b8a954c4ff97584c8ddda377d0e516ca505a30c37c1d1` |
| 85 | 84301 | `7b7f39d1e3b53216f216d6a8df0b1cff5af3eb182d08008fbdab4eff1f6b7a5e` |
| 86 | 24535 | `ded9e918140ece5a1e187821982011bd5172b33485e77a0b9ad6c2a2fa73f993` |
| 87 | 56635 | `37c6cc8fdcd18b30d29294a7707bbd0d373c6e8a3173448a9126ff5423c95e1a` |
| 88 | 22291 | `1e675266dc2729f7f52a39f7cc1eff29b7d14be041f89ff0ffdb625db5922dad` |
| 89 | 177201 | `e32f027d9ed9222a969c7a1e37e9d9892518b69366cc89a192d931d2b8d2b1e0` |
| 90 | 53322 | `caf3bf9f2b21e1f7f88571ed252959b35a03897c1837903993cb24af84c9e6dc` |
| 91 | 43807 | `c11e2663bce92cee7df14819b17c84c0be5c88250df06111122e2647fe661a5a` |
| 92 | 12337 | `8289d6bed95d0cea79a37d5f95cdc24f0dc301975c9fa72d4ead0607dd146534` |
| 93 | 5497 | `0f43319cc7b54f85efcac24acac371fa036fe9e30e274d2718573f146ed4671e` |
| 94 | 51353 | `78a7be33c5bb83860532f19550d2fc1234654eaeca6709eb09ac8dcbf746b1bc` |
| 95 | 15952 | `6d5e099b27c49a569e898cd43088ded58b9cfcc83be35b5a974cd3171302f150` |
| 96 | 101854 | `944c8c1cc8484895754771d8b89dfa23f562bd1efc04665a744261d0c1dc217d` |
| 97 | 151589 | `e5966fb62ae9bdc02e504b4169c1b3141496b4475e7a9faeed9c0620882cca6a` |
| 98 | 47058 | `d18772a45739a45747b553afd5b53ca34be6249497f513ea6ba6b4f1c0ebc5ac` |

---

# Run 10 (phases 99-102)

Source repo My-tools, branch `integration/p72-p79`, tip used: `994584b0749f5b2146add07500c88e9538c95cf0`. Order: 99, 100, 101, 102. Chain lock: Run 10 needs Run 9 done (key `bos_setup_run_done_v1`). Read-only CHECK (single SELECT, 2648 bytes, sha256 `c792d6ad85b545658aa4061d4f82b46ad3a179c9d02d4c13f0bf485e0114015e`) as a second small Copy button.

| Page | Phases | Payload bytes | Payload sha256 |
|---|---|---|---|
| setup-run-10.html | 99, 100, 101, 102 | 189204 | `516019cda3dc18ae4375b976e81e56629e7f312ed30654221486bd06cd5012e3` |

| Phase | Last commit touching file | Bytes | sha256 |
|---|---|---|---|
| 99 | 53396ec | 80341 | `da4f4b90fb57e243f67f7a30fb00b6d1c36fdedd5c4d0cebb7032f267d5a10c6` |
| 100 | 40b4c01 | 41429 | `1c30b9dd3ad986479468114e52cbc8136b21feb347857780031ebcdd812cec09` |
| 101 | 0a797e0 | 57272 | `6c4385bf422d2938874ddc9695f79ec04f9290cceaaf17f1bd8cd69bf9ac8c88` |
| 102 | 84c08a6 | 10063 | `14733ee7d3da5237ad39643eb7d807b089f81b7048a7e80f3dc518dcab5e3199` |

---

# Run 11 (phase 103)

Source repo My-tools, branch `integration/p72-p79`, tip used: `35f8f7dc1c7e9aa3d4cf5e515c262adedb64eb96`. Chain lock: Run 11 needs Run 10 done (key `bos_setup_run_done_v1`). Read-only CHECK (single SELECT, 1678 bytes, sha256 `30fab9597ebedbf130b70ffbad7a732a71f366fa63e86623dce024c83e946334`) as a second small Copy button.

| Page | Phase | Payload bytes | Payload sha256 |
|---|---|---|---|
| setup-run-11.html | 103 | 111658 | `e4354f8e77c853760ff8a1bbe32f538651789c4cbb9716651bfd8f6eb2bbe82c` |

| Phase | Last commit touching file | Bytes | sha256 |
|---|---|---|---|
| 103 | 0ecf984 | 111633 | `c99ca18eb9039ab30e57b01e1e1e1473484a544ac6d573ca7bb8d5c4bf0019ed` |

---

# Runs 12-13 (phases 104-109, 111)

Source repo My-tools, `origin/integration/p72-p79` tip used: `b7b2ffa2dd16a82ece6f10a150bbb116ad16ab04`. Every phase sha256 below equals the table in `docs/briefs_p2p3/step_INT4_REPORT.md`. Phase 110 is not included. Chain lock: Run 12 needs Run 11 done, Run 13 needs Run 12 done (key `bos_setup_run_done_v1`). Each page has a read-only CHECK (single SELECT) as a second small Copy button.

| Page | Phases | Payload bytes | Payload sha256 | CHECK bytes | CHECK sha256 |
|---|---|---|---|---|---|
| setup-run-12.html | 104, 105, 106, 107, 108 | 123805 | `a77676cda43745a4acb2bfd9dff4fbd45bf7fc547023281ffa7f9f43407fb889` | 3223 | `f20b0068d69a3b1a073d0a1a1787806cd653e7cc5ec7c321bed3d2cb2c8eb8a2` |
| setup-run-13.html | 109, 111 | 73703 | `35cb10d7b459e953ae0e82acd0f3c35011042b01608527e53bb47941a9f3c125` | 1888 | `ed84f2a0caa667eb64ebd0c6e544ecd1d265abc51b706ab2a1905b8759ff5953` |

| Phase | Last commit touching file | Bytes | sha256 |
|---|---|---|---|
| 104 | 3e7db42 | 7284 | `4832bf18b4cd0fc1428368794d23f0b84991f8fedb3e8e925d4c2ba040e3ebbe` |
| 105 | 09f4eae | 42703 | `f0151974a83824491c8adc4c9d60ff60c63aee17a209e01f93e3fdf2efeff0ec` |
| 106 | db7dc11 | 7404 | `4d241a03cf80b5b92fc946659a1e2a00bbfd577727a4f40ec29ee0acf4d4a471` |
| 107 | fe5feba | 27576 | `5285df741bacb3583edc13c9eeaf4c6b6fff018cba8c6edd9403fa3132bd537f` |
| 108 | 447edb2 | 38713 | `f2a6686ce7966815b0644f241edd1a9aad3e841524d0e7728ccb77be234cfd04` |
| 109 | 09f4eae | 63402 | `5123cd02eda8362e52da20aff4a2d7e48cbc21305e92412fce4318a87c52540b` |
| 111 | 09f4eae | 10251 | `d3e824359485c5f7b1e4e927de6c88d0cf002be77933bccb44494ab7eaa06a01` |

---

# Run 14 (phase 110)

Source repo My-tools, `origin/integration/p72-p79` tip used: `dd9dd55666cd6975c5f967b69fd465fad57f17db`. phase110.sql: 27778 bytes, sha256 `2a116c98f4664bd41f1a892a6b714bb0acc6e817c1a31fd6593c325bc045b096` (equals the table in `docs/briefs_p2p3/step_INT4_REPORT.md`; last commit touching it `87165fb`). Page shows a top warning: paste at a quiet time (8 indexes briefly block writes). Chain lock: Run 14 needs Run 13 done.

| Page | Phase | Payload bytes | Payload sha256 | CHECK bytes | CHECK sha256 |
|---|---|---|---|---|---|
| setup-run-14.html | 110 | 27803 | `37b8d8caaf4c1f0eeeb9165d3625a3fbaa9d121ac7f10c8597eff8965d80194a` | 1651 | `15b5c7d4cf01892d2ea618a0c32211fc9908f1f66a315a3b51b37031ee5fede9` |

---

# Web bundle 4 (build 1a9e6c6b70) and Run 15 (phases 112-118, 121)

Source repo My-tools, branch `int/audit-fixes` (commit `44311c8`, includes merged impl/c1, impl/c2, impl/c5, impl/e1 and perf/webload). Web app built by `tools/build_web.sh --to` (core bundle + lazy screens, `?v=<hash>` per file, `sw.js` VERSION `bos-sw-1a9e6c6b70`). `config.js`, `setup-*.html` (except the new run-15 and the link line in `setup-sql.html`), `audit-a.html` and this file's earlier sections untouched. CSP meta kept as the perf branch built it. Phase 120 (perf review, c4) was not pushed yet and is NOT included.

Owner has phases 72..111 installed. setup-run-15.html: ONE Copy block with phases 112, 113, 114, 115, 116, 117, 118, 121 in that order (121 patches the bodies of 112..118, so it goes last). Payload = `-- ===== phase NN =====` line + exact source bytes. Every new rule is OFF by default: pasting changes nothing visible. Chain lock: Run 15 needs Run 14 done (key `bos_setup_run_done_v1`). Read-only CHECK (single SELECT, phases 112..121) as a second small Copy button; same text in My-tools `docs/CHECK_RUNS_15.sql`. Tested on a fresh build up to phase 111: page payload pasted once and twice with no error, CHECK shows all eight phases as done.

| Page | Phases | Payload bytes | Payload sha256 | CHECK bytes | CHECK sha256 |
|---|---|---|---|---|---|
| setup-run-15.html | 112, 113, 114, 115, 116, 117, 118, 121 | 355636 | `ee3a5864975a1768e8d4f4d5ad0616a6baac1a0003d823be31e06ae5fb68a84d` | 5673 | `b6fa805a78f1a2c0f527b7805c9485f399975160caf27511d85eae299086a985` |

| Phase | Bytes | sha256 |
|---|---|---|
| 112 | 34003 | `2359cbab51805f534c5350ff1085ab12ae6cc25d75e9fca823e5c2a6e17577c0` |
| 113 | 77340 | `ce09192bcc6bfdfbe939ebef82899a503363b730a179a0923fdbe13d63da93d4` |
| 114 | 34268 | `0e124e9a582101e9fe08c8c12b0a731852d9a8095db4fd53d54244101d79d0ce` |
| 115 | 26114 | `375ab165347c1d14f6b7ed145cb51dbe19a4f8eacff85f1334e26e981ae910ad` |
| 116 | 90349 | `c4a32d2a2cffa204519edf4831b75afbf594a0991063b994b3f902dcebc704bf` |
| 117 | 32233 | `0b770c9139e06fc791340b9ac11c146d3af21b6cdeed4ecd35345a8be3127381` |
| 118 | 51067 | `1bb51430c9bd72f8de774a1afae7ac13185f3fe44da7fd7fb6d72c5def38640d` |
| 121 | 10062 | `1a6399aecf183fe5638ec68250de31d3e371ae0277494c337e5b886c3f91276a` |
