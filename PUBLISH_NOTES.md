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
