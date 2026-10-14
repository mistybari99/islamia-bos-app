# PUBLISH_NOTES: setup-run-1/2/3.html (phases 74-81)

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
