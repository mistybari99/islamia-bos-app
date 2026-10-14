# PUBLISH_NOTES: setup-run-1.html / setup-run-2.html (phases 74-81)

Source repo: https://github.com/mistybari99/My-tools , branch `integration/p72-p79`, commit used: `fd9590a47969010f0d678f532ccaa8126735f1c6`. Phase files 72-81 are unchanged vs the earlier setup-sql-1..4 build (sha256 identical, listed below). Phases 82+ are NOT included.

Owner already ran phases 72, 73 and phase 74 part 1 (`setup-sql-1.html`, kept as a record). Remaining SQL is two one-paste pages (phase files are paste-twice safe, so Run 1 re-runs the first half of phase 74 harmlessly):

| Page | Phases | Payload bytes | Payload sha256 |
|---|---|---|---|
| setup-run-1.html | 74, 75, 76 | 200923 | `56b1c76792918c5b211cd277cd4e420e13c7019b9b3b1d244298f0f22a939495` |
| setup-run-2.html | 77, 78, 79, 80, 81 | 264833 | `b6d1febd0103e7521fd1a2ae67981360f9470ad95edbe5d18fdef02e4ac4b618` |

Payload = for each phase: the line `-- ===== phase NN =====` + newline, then the exact bytes of `supabase/phaseNN.sql`; nothing else added, statements unaltered.
Run 2 lists a read-only CHECK (single SELECT, 4085 bytes, sha256 `475bc343e0a3b25c645f22580466f89fa17cdbd81ca7843c25b71dc0a8db685b`) as a second small Copy button.
Order lock: Run 2 is locked until Run 1 is marked done (localStorage key `bos_setup_run_done_v1`, try/catch with in-memory fallback). Undoing Run 1 clears Run 2.

WARNING: Run 2 payload is 264833 bytes (> 250 KB): possible Supabase editor / phone clipboard risk. A prepared, NOT linked alternative (Run 2 split by phase boundaries into 3 pages) is in `alt/`: setup-run-2a.html (phases 77-79, 104501 B), setup-run-2b.html (phase 80, 94114 B), setup-run-2c.html (phase 81 + CHECK, 66218 B), with `alt/setup-run-1.html` chaining to them. To use it, link `alt/setup-run-1.html`.

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

## Alternative pages (alt/, not linked)

| Page | Phases | Payload bytes | Payload sha256 |
|---|---|---|---|
| alt/setup-run-2a.html | 77, 78, 79 | 104501 | `2696e73ba87eddf8dad2b2272749f29f3d1dd5f868b0e01fe73b13f5fade7045` |
| alt/setup-run-2b.html | 80 | 94114 | `d26be09d032b51a2ba9277c5681f8f5391391a0db383c57d298b82630c50f04e` |
| alt/setup-run-2c.html | 81 | 66218 | `c9f11cf032b443811d42c6ca07ea68c222e51658cf2e6807e67d38b8a375113d` |
