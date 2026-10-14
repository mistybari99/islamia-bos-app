# PUBLISH_NOTES: setup-sql-1..4.html (phases 72-81)

Source repo: https://github.com/mistybari99/My-tools , branch `integration/p72-p79` (worktree /home/user/wt-int), HEAD commit used: `049dce47c75a850aaf07aa5798a384e463c8b176`.
Files copied byte-for-byte from `supabase/phaseNN.sql` (working tree clean at that commit). Phases 82+ are NOT included.

Four pages (English UI), 17 SQL parts in order, shared progress key `bos_setup72_81_done_v1` in localStorage so the order lock works across pages. A part is locked until every earlier part (also on earlier pages) is marked done; the lock text links to the page to open. A read-only CHECK (single SELECT) is on page 4 only. `setup-sql.html` has one added line linking to the four pages.
Parts are split only at top-level statement boundaries (never inside a $$ body, string or comment); max part 50,000 bytes. Concatenating a phase's parts equals the source file (sha256 below).

| Page | File | Parts | Bytes |
|---|---|---|---|
| 1 | setup-sql-1.html | 1-4 | 132068 (SQL) |
| 2 | setup-sql-2.html | 5-9 | 167718 (SQL) |
| 3 | setup-sql-3.html | 10-13 | 137562 (SQL) |
| 4 | setup-sql-4.html | 14-17 | 160284 (SQL) |

## Source files (sha256 of the whole phase file)

| Phase | Last commit touching file | Bytes | Parts | sha256 |
|---|---|---|---|---|
| 72 | eb5f6a3 | 78993 | 2 | `8b9a5ca868d8a4c39e13b577d2910e09ba838257371072806c1d4eaac17652e8` |
| 73 | 36fe06d | 53075 | 2 | `b1b4f37682f62f8c73c37305f6492f1f7d90e3221613bc62b425c7a1de85f4d7` |
| 74 | c8c4f56 | 77437 | 2 | `4ef3837cf9260fffe0fdc8d4a365695dfa21ddf4182b5063ddd86b67bab9dc72` |
| 75 | 1669f37 | 55469 | 2 | `c450df969e4d6cde4ee723b47307a4f99070835d3c9f16b5ef34693584f2afba` |
| 76 | 8f9c6b1 | 67945 | 2 | `d7a8bfdcbcfb966d7e301d2751b4e689bf041471512d49a02f10bba3545bbaaf` |
| 77 | b75d9ec | 20754 | 1 | `5938a8a5cf343d605f864e737a5c9786a7432b4b71ec132efece0b13278a63ae` |
| 78 | f8d786c | 37377 | 1 | `5a8c2f306fdc3aa4f2c7c0879f5a03c3c34a9f99fa0dc716e5fcd60368e2fbb4` |
| 79 | dbecc25 | 46298 | 1 | `7a1a5d4dd3ac9f2491c248021b8dadb9af3d5551eb791df3d5d0318c05e65dd5` |
| 80 | c23e82d | 94090 | 2 | `c5143b460a0fb2e8d7171644b8963b2dcf8c8b04896838199128d159eeee90d3` |
| 81 | bb8913d | 66194 | 2 | `5985766b48667d68c565fe26ae5b8523257b5ad7fa141e044896bf0fdac6691d` |

## Every part (sha256 of the exact text the Copy button writes)

| Part | Page | Phase | Bytes | sha256 |
|---|---|---|---|---|
| 1 | 1 | 72 (1/2) | 46721 | `f4659595c16e708ebcfcb440f611f6d5eb70627cd51af4be2aa6ad37851f5c83` |
| 2 | 1 | 72 (2/2) | 32272 | `e0fb5a8c018048347f8360a806305aaed62a151f77789240d306ebf69590a6db` |
| 3 | 1 | 73 (1/2) | 25620 | `ff44b00cf4fef76716a698659b24f3eaef9ce8212059d5366fa487f5f8e71754` |
| 4 | 1 | 73 (2/2) | 27455 | `cbfda0555e93cc1fd02670e69dbd12158a6818432c220ffda967974f006b2388` |
| 5 | 2 | 74 (1/2) | 42275 | `18f0fcd551b8c87461c3c5d039e366c827406c716e1fb16cfd85c8151a817da3` |
| 6 | 2 | 74 (2/2) | 35162 | `522be38235eeaae7203dbb4222adb48703ea8bd49ceeabe93b871d0478b1edec` |
| 7 | 2 | 75 (1/2) | 26643 | `9f5a9437c0b4ba9f511d6d1ef8a835d8fc7f56e0d468e1612b7c20d9b621e5e8` |
| 8 | 2 | 75 (2/2) | 28826 | `fc1f603c71a6c6422284621e18304ae35e27c465c995d6cde93e33e5c48149f1` |
| 9 | 2 | 76 (1/2) | 34812 | `c32b1f7cfd932e2006ffa665fca3fd951a71c7a092383f764bbb1ba6ea626e02` |
| 10 | 3 | 76 (2/2) | 33133 | `d0dc480d6beb9ca6ca4d43801a7747706aebdc0bf21c5998c770c44f5b65b265` |
| 11 | 3 | 77 | 20754 | `5938a8a5cf343d605f864e737a5c9786a7432b4b71ec132efece0b13278a63ae` |
| 12 | 3 | 78 | 37377 | `5a8c2f306fdc3aa4f2c7c0879f5a03c3c34a9f99fa0dc716e5fcd60368e2fbb4` |
| 13 | 3 | 79 | 46298 | `7a1a5d4dd3ac9f2491c248021b8dadb9af3d5551eb791df3d5d0318c05e65dd5` |
| 14 | 4 | 80 (1/2) | 47286 | `3eaad7916ffa45af203ef044ba7e2cae408aaece6f3843011776c0eaf967a5a7` |
| 15 | 4 | 80 (2/2) | 46804 | `7b6c4c26fbdca16219c9041c1b2dbe46987fe07c35badcd66455c3f2043c4a16` |
| 16 | 4 | 81 (1/2) | 23449 | `e513267ea06160637904d2e8e356e1d6e66233e9714d6af64c3f6f0fcb50bd4f` |
| 17 | 4 | 81 (2/2) | 42745 | `574615ff9ac90cc0658cbcc0bb9d0e0e17b8109c07837516979416d12e6b0b95` |
| CHECK | 4 | 72-81 (read-only SELECT) | 4085 | `475bc343e0a3b25c645f22580466f89fa17cdbd81ca7843c25b71dc0a8db685b` |
