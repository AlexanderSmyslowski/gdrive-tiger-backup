# Version publication history

Git preserves every source commit, while a GitHub Release is a separate
publication record. This project continued version development after v1.5.0
without merging the development branch or creating later tags and releases.
The source history is retained without squashing, and the missing publication
records are restored transparently as historical source milestones.

| Version | Build | Source commit | Publication record |
| --- | ---: | --- | --- |
| v1.0.0 | 1 | `567f353` | Original tag; bundle metadata used `1.0`; release page added retrospectively |
| v1.1.0 | 2 | `826e5d0` | Published 2026-05-24 |
| v1.1.1 | 3 | `944b74a` | Published 2026-05-24 |
| v1.2.0 | 4 | `6067ba6` | Published 2026-05-24 |
| v1.2.1 | 5 | `9c00998` | Published 2026-05-24 |
| v1.2.2 | 6 | `c8a5c58` | Published 2026-05-24 |
| v1.3.0 | 7 | `4dcef3f` | Published 2026-05-24 |
| v1.3.1 | 8 | `7cf3c1a` | Published 2026-05-24 |
| v1.4.0 | 9 | `9cd5373` | Published 2026-05-24 |
| v1.5.0 | 10 | `beb1e5b` | Published 2026-05-24 |
| v1.6.0 | 11 | — | Internal milestone only; no matching app metadata or honest tag exists |
| v1.6.1 | 12 | `e71e16f` | Historical source milestone published retrospectively |
| v1.7.0 | 13 | `39f9e03` | Historical source milestone published retrospectively |
| v1.8.0 | 14 | `bdff900` | Historical source milestone published retrospectively |
| v1.9.0 | 15 | `32544f2` | Historical source milestone published retrospectively |
| v2.0.0 | 16 | `4a9faa4` | Historical source milestone published retrospectively |
| v2.1.0 | 17 | `89f3477` | Historical source milestone published retrospectively |
| v2.2.0 | 18 | `8b7d620` | Historical source milestone published retrospectively |
| v2.2.1 | 19 | `3eaa217` | Historical source milestone published retrospectively |
| v2.2.2 | 20 | `d14c1b0` | Historical source milestone published retrospectively |
| v2.3.0 | 21 | `0714564` | Historical source milestone published retrospectively |
| v2.3.1 | 22 | `c3c94b2` | Historical source milestone published retrospectively |
| v2.3.2 | 23 | `7ecda45` | Historical source milestone published retrospectively |
| v2.4.0 | 24 | tag `v2.4.0` | Published tested release |
| v2.4.1 | 25 | tag `v2.4.1` | Superseded; its protected entitlement caused macOS to reject the unsigned app at launch |
| v2.4.2 | 26 | tag `v2.4.2` | Superseded tested release |
| v2.4.3 | 27 | tag `v2.4.3` | Superseded tested release |
| v2.4.4 | 28 | tag `v2.4.4` | Current tested release |

No historical binary installer is reconstructed and presented as an original
artifact. Retrospective release pages expose GitHub's source archives and state
their later publication date. The current release alone receives the installer
built and verified from its exact tag.

Future version tags trigger the release workflow. It refuses a tag that does
not match the app version, positive build number, README, and dated changelog
section; it also refuses to publish while entries remain under **Unreleased**.
Only a tagged commit already contained in `main` can become a release. The
workflow reruns the full suite, builds and verifies the installer, publishes a
SHA-256 digest, and then creates the GitHub Release.
