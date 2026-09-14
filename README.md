# Moonveil

A mobile AI agent app that fuses **on-device execution** (fork of [OpenMinis](https://github.com/OpenMinis/OpenMinis), GPLv3) with **remote agent workflows** speaking the Agents Anywhere protocol (MIT upstream). Two brains, one app: a local tab and a remote tab under a single native tab shell.

Closed development — private during this phase.

## Layout
- `src/ios/` — OpenMinis upstream (frozen zone; `git diff <openminis-tag> -- src/ios` must stay empty)
- `Packages/RemoteKit/` — isolated package (D4 门1): `Sources/AAV2` (verbatim AA V2 port) + `Sources/Glue` (our seam)
- `FusionUI/` — our presentation layer

## License
GPLv3 (app). Remote backend (moonveil-cloud) is MIT and operated separately.
