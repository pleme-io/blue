# SERVICE-ACCESS — one access declaration, enforced by every layer that builds a service

Status: DESIGN, 2026-10-27. One part is built: the engine posture (§4, A0).
Nothing else here is built unless the tier ledger (§9) says so. It extends
`SERVICE-ARCHITECTURE.md`: access is one more service concern, on by default,
tuned or refused alone.

## 1. Destination

A blue service states what it may touch in its `service(...)` declaration:
which host effects, which network peers, which paths it reads at boot, which
paths it writes, which ports it listens on, which programs it runs. The
default is narrow: network to the bindings the service declares, and no disk.
Every layer that builds or runs the service renders that one value into its own
mechanism, so access is scoped mechanically at each layer, not by convention:

- the blue engine binds every refused effect as a refusal;
- the systemd, launchd and home-manager units carry the matching sandbox;
- the Helm chart carries the matching pod security, volumes and NetworkPolicy;
- the image closure holds nothing a refused effect would need;
- a Rust host's config is refused when it names a path the access does not list.

Compiling the service (`nix run .#regen`, then `nix flake check`) regenerates
every rendering, in the service repo and in the GitOps repo, and the freshness
checks fail until the diff is committed. A change of access is one edit in the
Bluefile and a reviewed diff everywhere else.

## 2. Ground — what exists

| Piece | Where | State |
|---|---|---|
| Closed capability universe: `Process`, `FileSystem`, `Environment`, `Clock`, `Network`, `Entropy`, each with its fixed word list | `crates/blue-lang-waku/src/capability.rs:70-140`, `:348` | exists |
| Engine posture: `Load::posture(allowed)` binds every host effect not allowed as a refusal; `refused_by` derives the set | `crates/blue-lang-host/src/lib.rs` (`b21d99b`), `tests/host.rs` | built 2026-10-27; kensa loads with `posture(&[])` (`kensa@872cc76`) |
| Bluefile `posture(when:)`; `posture(reach:)` named as a plain to-do | `crates/blue-lang-pkg/src/bluefile.rs:7`, `:76-81` | `when` only |
| Service lowering: chart, config, DDL, app, image, checks `-fresh`, `-chart`, `-serves`, `-migrations`, `-trio`, `-distroless` | `nix/service.nix`, `nix/project.nix:53` | exists |
| Chart container: `readOnlyRootFilesystem: true`, non-root | `bidamas/haibi/haibi.b:192-194`, `crates/blue-lang-pkg/src/deploy/render.rs:553` | exists; no NetworkPolicy, no egress scope |
| Module trio for a service | `nix/service.nix:161-170` → substrate `lib/module-trio.nix` `mkModuleTrio` (`kind = "service"`) | exists for blue-built services; **a `host` service gets none** (`service.nix:8` filters `own`); no sandbox fields are rendered |
| systemd hardening fields in substrate | `substrate/lib/iroha/service-module.nix` (`ProtectSystem`, `NoNewPrivileges`, tests at `tests/service-module.nix:103`) | exists, not fed by blue |
| Hardened distroless image | substrate `mkHardenedImageSet` via `nix/image.nix` | exists; nothing ties its closure to the access |
| Workload objects for a Flux Kustomization | `crates/blue-lang-pkg/src/deploy/render.rs:1-11` | exists, rendered into the service repo |

## 3. The declaration

```ruby
service("kensa", {
  host: "kensa",
  access: {
    effects: [:network, :clock, :entropy],
    egress: [:database, :cache, "api.github.com:443"],
    reads: ["/var/run/secrets/kensa"],
    writes: [],
    listen: [8080, 8443],
    exec: []
  }
})
```

| Field | Meaning | Default when `access` is not written |
|---|---|---|
| `effects` | host effects the engine and the host may perform, from the closed `Capability` set | `[:network, :clock, :entropy, :environment]` |
| `egress` | peers: a binding the service declares (`:database` from `schema`, `:cache`, a declared queue) or `host:port` | the declared bindings, plus DNS |
| `reads` | read-only boot inputs: secret mounts, the declaration, config | the service's secret mounts and its config |
| `writes` | writable paths | none |
| `listen` | ports | the ports the service declares |
| `exec` | programs it may run | none |

Each field is judged alone; a bad field is refused with its reason and its
siblings stand.

| Refused alone when | Why |
|---|---|
| `writes` is not empty and `effects` lacks `:filesystem` | a writable path the engine could never use |
| `exec` is not empty and `effects` lacks `:process` | same |
| `egress` names a binding the service does not declare | a peer with no typed owner |
| `egress` is not empty and `effects` lacks `:network` | same |
| a path in `reads` or `writes` is relative or under `/nix/store` | not a mount point |
| `effects` names a pure capability (`:collections`) | pure capabilities are always granted; naming one is a misreading |

`effects` is the Bluefile `posture(reach:)` coordinate, closed by `Capability`,
so a misspelled effect is a parse failure, not a silent grant.

## 4. Renderers

One `Access` value, one renderer per layer. Each renderer has a row for every
host effect, by an exhaustive `match` with no wildcard, so a new `Capability`
does not compile until every layer says what it does with it.

| Layer | Renders | Effect refused → | Built |
|---|---|---|---|
| Blue engine | `Load::posture(effects)` | the effect's words are bound as refusals; a call raises `this program's posture refuses <effect>` | ✅ A0 |
| systemd (NixOS trio, HM user unit) | `ProtectSystem=strict`, `ProtectHome=yes`, `PrivateTmp=yes`, `ReadOnlyPaths=` reads, `ReadWritePaths=` writes, `NoNewPrivileges=yes`, `CapabilityBoundingSet=`, `RestrictAddressFamilies=`, `IPAddressDeny=any` + `IPAddressAllow=` egress, `SystemCallFilter=@system-service` | filesystem: no `ReadWritePaths`; network: `PrivateNetwork=yes`; process: `~@process` minus what the runtime needs | ❌ A3 |
| launchd (darwin trio) | a sandbox profile (`sandbox-exec`) with `deny default`, file reads and writes and network from the access | the matching `deny` | ❌ A3; typed weaker: launchd has no mount namespace |
| Helm chart | `readOnlyRootFilesystem` (exists), an `emptyDir` or PVC only for each `writes` path, read-only volumes for `reads`, `NetworkPolicy` egress from `egress` (DNS + each peer), ingress from `listen`, `automountServiceAccountToken: false` unless egress names the API server, `seccompProfile: RuntimeDefault`, `capabilities.drop: [ALL]` | filesystem: no writable volume; network: egress `[]` | ❌ A2 |
| Image | closure gate: with `:process` refused, the closure holds no shell and no exec helper; with `writes` empty, no writable directory is created | the gate refuses the image | ❌ A4 |
| Rust host | the host's config is checked against the access at start: a store dir, a ledger file or a `local://` transport that names a path outside `writes` is refused alone | the entry is refused; siblings run | ❌ A6 |

## 5. Compile is render and diff

The service repo already holds its renderings under `deploy/<service>/`, gated
by `checks.service-<name>-fresh`. The GitOps side is not rendered yet. The
destination: a `placement` entry (fueki) names a cluster and a GitOps path,
and the compile renders the Flux `HelmRelease` (chart, version, values) and
its `Kustomization` there. Delivery is the pull the fleet already runs: the
GitOps repo pins the service as a flake input, and its own regen renders the
Flux objects from that pin, gated by its own `-fresh` check. A change of
access in the service repo becomes, after the pin moves, a generated diff in
the GitOps repo that a reviewer reads.

| Decision | Chosen | Rejected, and why |
|---|---|---|
| Where Flux objects are rendered | in the GitOps repo, from the pinned service flake | **The service repo pushes into the GitOps repo**: a credential per service repo, and two writers for one file |
| What a reviewer reads | the generated diff of chart values, NetworkPolicy and unit fields | **The Bluefile alone**: the rendering is what runs, so it is what gets reviewed |
| How staleness is caught | the `-fresh` check on both sides | **A CI bot that regenerates on push**: a green run that wrote nothing looks the same as one that did |

## 6. Decisions

| Question | Chosen | Rejected, and why |
|---|---|---|
| Where access is declared | the `service(...)` entry, field `access` | **A separate Bluefile word**: access is a property of one service; two services in one Bluefile differ |
| Default | network to declared bindings, clock, entropy, environment; no disk, no exec | **Everything allowed, opt in to scope**: the bad state is the default, and nobody opts in |
| Boot reads | allowed only for declared `reads`, read-only at every layer | **No reads at all**: the declaration and the secrets must arrive somehow; env vars for secrets leak into `/proc` and crash dumps |
| How the engine refuses | names bound as refusals; the call raises | **Names unresolvable (the frame)**: a bidama with one I/O word among pure ones (`shomei::random`) could not load at all, so a pure service could not use the library |
| Enforcement per layer, or trust the engine | every layer | **Engine only**: a Rust host or a compromised dependency is outside the engine |
| Host services | get the trio like blue-built services | **Leave `host` services to hand-written nix**: kensa is the counterexample; `service.nix:8` is the bug |
| darwin | render a sandbox profile and type it as weaker | **Skip darwin**: silence reads as enforcement |

## 7. Build order

Each step ends with blue's checks green and a red-then-green test.

| Step | Work | Gate |
|---|---|---|
| A0 | `Load::posture` | ✅ `blue-lang-host` `tests/host.rs`; kensa `event_tests` (one refused call per effect) |
| A1 | Bluefile: `access` field on `service`, judged alone; `posture(reach:)` reads the same `Capability` set | parse tests for every refusal in §3 |
| A2 | haibi renders §4's chart rows | rendered chart tests: no writable volume when `writes` is empty; NetworkPolicy egress equals the declared peers |
| A3 | the trio renders §4's unit rows; `trios` maps over every service, a `host` service's package comes from `spec.host` | `-trio` check reads the unit and finds each field; kensa gets `nixosModules.kensa` |
| A4 | image closure gate | an image with a shell under a no-`:process` access is refused |
| A5 | the blue runtime loads a service program with `Load::posture(access.effects)` | a service that writes a file under the default access raises |
| A6 | kensa adopts the default: ledger and stores to Postgres, `store` entry refused, runner profiles as `reads`, `local://` refused in the daemon | kensa's 45 disk call sites in 10 files (measured 2026-10-27) are each gone or behind a refused entry |
| A7 | GitOps rendering (§5) from a `placement` entry | the GitOps repo's `-fresh` check fails until the regenerated Flux objects are committed |

## 8. Open questions

| Question | Kind |
|---|---|
| Does a dependency bidama's own `posture(reach:)` compose with the service's access as a ceiling | ours: the service access is the ceiling; a dependency that needs more is refused at load |
| A `:filesystem` split into read and write | ours: `Capability` notes it as a later variant; `reads` and `writes` cover the platform side now |
| macOS sandbox profiles are deprecated by Apple | world-fact: they still run; the darwin row stays typed weaker |

## 9. Tier ledger

| Item | Tier |
|---|---|
| Engine posture (`Load::posture`, `refused_by`) | tested (`b21d99b`) |
| kensa engine under `posture(&[])` | tested (`kensa@872cc76`) |
| `access` declaration | design |
| Chart, unit, image, host renderers | design |
| Trio for `host` services | design |
| GitOps rendering | design |
