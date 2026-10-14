Proposal: Metadata Caching and Selector Pushdown — Umbrella KEP Draft for Discussion

Short description:
This is a draft umbrella proposal intended to be pasted into a GitHub issue or discussion thread for community review. It is not a final KEP submission and will likely become multiple formal KEPs later. Feedback is requested on scope split, architecture, and rollout (please do not focus on template compliance at this stage).

Suggested labels/tags: SIG API Machinery, SIG Apps, proposal, umbrella

KEP: Metadata Caching and Selector Pushdown - Planning Document

Author: @mhmxs
Status: Draft
Date: 2026-10-13

---

Summary

This document proposes a KEP-style plan to make the current metadata-caching and selector-pushdown proof-of-concept (POC) presentable for upstream review and community discussion (SIG API Machinery / SIG Apps). The proposal separates configuration and controller-facing filtering concerns from any backend-specific selector-pushdown implementation, introduces a typed contract for converted field selectors, and recommends a phased, reviewable roadmap with clear milestones and testing strategies.

This KEP cites HariKube (https://github.com/HariKube/harikube) as a concrete reference implementation that has experimented with selector pushdown and metadata-only informer payloads: HariKube's README claims that pushing filtering into the database allows the watch cache to be disabled and reduces runtime memory to O(1), and includes benchmark comparisons against vanilla Kubernetes while explicitly noting that patched Kubernetes images are required. We treat HariKube as useful evidence that selector pushdown can yield real scale/stability/latency benefits, but we do not treat its patched, backend-specific approach as the upstream design - upstream work must define a generic, typed contract and adapter-based rollout that can be reviewed and implemented safely across multiple storage backends.

Beyond immediate technical improvements to apiserver memory and request throughput, this KEP is explicitly motivated by two co-equal goals: (1) to make more services and their state first-class cloud-native citizens by enabling representation via Kubernetes-native APIs and CRDs, and (2) to enable Kubernetes to reliably serve much larger clusters and higher object counts without forcing operators into fragmented, out-of-tree solutions. Concretely, better selector pushdown and metadata filtering reduce barriers to modeling services as Kubernetes APIs and CRDs by allowing controllers and operators to request metadata-only or filtered views of large resources, lowering the operational and performance costs of hosting application state in-tree rather than in bespoke external datastores. At the same time, the same architectural work - a typed, versioned selector contract plus storage capability/adapters and controller-configurable informer behavior - is necessary for apiservers and storage backends to scale to much larger clusters and object volumes. The KEP therefore frames the work not merely as a performance optimization, but as an umbrella infrastructure effort that equally advances cloud-native extensibility (more services as Kubernetes-native APIs/CRDs) and large-cluster scalability, while preserving upstream safety, reviewability, and phased validation.

Motivation / Problem Statement

This work has two co-equal motivations that must be treated explicitly and in parallel: (A) cloud-native enablement - reducing barriers so more services and their mutable state can be represented as first-class Kubernetes APIs and CRDs through robust, versioned metadata filtering and selector pushdown; and (B) large-scale cluster support - providing the architectural primitives required for apiservers and storage to serve much larger clusters and higher object counts without pushing operators into forks or external caches.

- Controllers and clients benefit from cached metadata and the ability to push label/field selectors into storage to reduce network and CPU consumption.
- Beyond localized cost savings, the ability to push selectors and receive metadata-only payloads is foundational to supporting much larger clusters and application workloads: without a reviewable, generic design for metadata filtering and selector pushdown, teams running large-scale systems must continue to rely on out-of-tree forks, bespoke backends, or external caches - creating operational fragmentation and raising barriers for services to become native Kubernetes citizens.
- Current work in-tree looks like a POC: it mixes concerns across request/transport, watch cache and storage layers; it relies on ad hoc context-encoded keys (e.g., CONVERTED_FIELD_SELECTOR) and vendor/proto churn; and it patches shared backend behavior (etcd3) without a driver/capability abstraction.
- There is no clear, generic configuration surface to control which processes (e.g., kube-controller-manager) should receive filtered metadata informers vs full objects; the present code uses a hard-coded flag (!skip-controller-manager-metadata-caching) that is not acceptable for upstream generality.
- The lack of a typed, versioned selector contract and adapter path prevents the apiserver from safely delegating selection semantics to capable backends; without that architectural separation, operators and platform teams cannot confidently move more application state into Kubernetes-native APIs at scale.

Goals

- Produce a community-friendly, reviewable design that separates controller/consumer configuration from storage backends and provides a clear migration plan.
- Define an explicit, typed request/storage contract for converted/translated field selectors instead of raw context plumbing.
- Provide an adapter/capability abstraction for selector pushdown so backends can opt in safely without invasive, backend-specific patches to shared code.
- Recommend a phased rollout and PR split for incremental review and testing.

Non-Goals

- This is not an implementation patch; it will not modify public export signatures or change running behavior by itself.
- This document does not prescribe a single storage implementation; it focuses on API, design, and integration boundaries.

Background / Current POC Assessment

Why the current state reads like a POC:

- Mixed concerns: The prototype mixes controller informers, request translation, storage-level selector handling, and local watch-cache behavior in the same change set.
- Vendor / proto churn: The POC contains transient protobuf or vendor-specific code that will likely change and therefore should not be directly upstreamed as-is.
- Ad hoc context usage: The implementation carries selector state via a raw context key (e.g., CONVERTED_FIELD_SELECTOR) and expects downstream components to interpret a string-laden contract.
- watch-cache-off local testing: Local tests disable the watch cache in ways that mask real interaction patterns with the cache and storage.
- Unclear upstream story: There is no clear narrative presented to SIGs on why a backend must be changed vs why a higher-level adapter is preferred.
- Practical reference: the HariKube fork implements a working selector-pushdown path and therefore provides concrete implementation evidence (see README and code references below), but it also exposes why upstream caution is warranted: HariKube's approach requires patched Kubernetes images and includes backend- and project-specific special-casing that we should avoid upstream by defining a typed, versioned contract and capability/adapter isolation.

Proposal (high-level)

1) Expose a generic, configurable informer-filtering surface for controller processes (kube-controller-manager, controllers) that allows operators to opt into metadata-only informer payloads and specify filtering rules: do not hard-code a behavior keyed on !skip-controller-manager-metadata-caching.

2) Replace the raw CONVERTED_FIELD_SELECTOR context plumbing with a typed request/storage contract: a typed object (e.g., ConvertedFieldSelectorRequest/Response) that travels with request metadata or is recorded in storage transaction metadata. The contract must be explicit, versioned, and supported by server-side request validation and audit logs.

3) Abstract selector pushdown behind a storage capability/adapter interface rather than modifying the shared etcd3 store path directly. Storage backends indicate capability support and accept typed selector pushdown requests; adapters translate the typed contract into backend-specific operations.

4) Phase and split the work into reviewable PRs: (A) configuration & controller informer filtering, (B) typed selector contract and API changes, (C) storage capability interface and adapter for one backend (experimental), (D) selective backend opt-ins and performance validation.

Detailed Design

Configuration & Controller Informer Filtering

- Introduce a kube-controller-manager configuration field (config file and CLI flag) to describe metadata-informer behavior.
  - Example options: full-objects (default), metadata-only, metadata-with-labels, metadata-with-field-subset.
  - Permit a per-controller override as well as a global default.
- Controllers should register against an informer factory that negotiates whether to subscribe for full objects or metadata-only events. This should be a generic pluggable behavior in client-go/informers, not a hard-coded special case.

Typed Converted Field Selector Contract

- Define a k8s.io/apimachinery/types/convertedselector API schema (versioned) or a typed transport header that carries:
  - The original human-visible field selector (for audit/logging),
  - A machine-parsed intermediate representation (IR) that describes semantic selection operations (AND/OR, equality, ranges),
  - Source and conversion metadata (server API version, conversion path),
  - Strong typing and feature-gating of new semantics.
- Ensure conversion rules are documented and that conversions are performed in the API server request pipeline before persisting or handing to storage adapters.

Storage Capability / Adapter Abstraction

- Introduce a new StorageCapability interface (name tentative) exported from staging/pkg/storage or a similarly upstream-accessible package that defines:
  - CanPushdownSelectors() bool
  - PushdownSelectors(ctx, namespace, resource, selectorIR) -> (accepted bool, storeQueryOptions)
  - ValidatePushdown(...) -> error
- Backends that wish to opt in implement an adapter that translates the selector IR into backend-native query hints (e.g., index scans, predicate pushdown).
- When a backend does not support pushdown, the server falls back to server-side filtering via existing watch/cache workflows.

Handling Converted Field Selectors Without Raw Context String Keys

- Remove reliance on raw context string keys; use a typed request attribute bag attached to the apirequest.RequestContext or a decorator on the request internal struct.
- When selectors are converted by the API server, populate the typed ConvertedFieldSelectorRequest object and pass it explicitly to the storage layer and watch/cache read path.
- For forward compatibility, add a transitional adapter that reads the older context key and converts it to the typed contract during the migration window, but document and timebox this transitional support.

API / CLI / Config Changes

- kube-controller-manager config: new tuning block for informer metadata filtering plus CLI flags: --informer-default=metadata-only|full|metadata-with-labels
- API server request context: typed ConvertedFieldSelector object in the apirequest.Info or a versioned request param (internal-only) used to coordinate storage behavior.
- Storage capability registration: storage registry or builder API extension that accepts capability descriptors and adapter factory functions.

Storage Architecture Direction

- Do not patch the shared etcd3 storage path to special-case selector pushdown; instead, add an adapter path that co-exists with the current storage driver. HariKube's prototype demonstrates a fully patched fork that renders selector-specific WHERE clauses and special-cases controller-manager behavior, which is useful as a working example but also shows the risks of in-place backend patching.
- Allow for an opt-in storage driver extension that is called only when the ConvertedFieldSelector contract is present and the backend advertises the capability; HariKube's drivers/generic implementation renders SQL list methods that turn selector IR into backend WHERE clauses and contains project-specific handling around flags such as skip-controller-manager-metadata-caching, illustrating why upstream needs capability negotiation and adapter isolation rather than hard-coded shared-store changes.
- Encourage experiments in a distinct driver (or a feature-gated adapter) and collect performance benchmarks before making any broad upstream change. HariKube's README includes benchmark tables that compare its fork against vanilla Kubernetes - these are valuable data points, but they come from a patched fork and must be validated in upstream-like, generic adapter experiments before any production-facing commitment is made.

Detailed Rollout / Phased Plan

Phase 0 - Design and Community Review (this KEP)
- Share the KEP with SIG API Machinery and SIG Apps for commentary.
- Reach agreement on typed contract surface and adapter shape.

Phase 1 - Configuration & Controller Filtering
- Implement informer filtering configuration and controller manager flags (client-side behavior only). This is low-risk and backwards compatible.
- Provide a reference implementation in client-go/informers and controller-runtime.

Phase 2 - Typed Selector Contract
- Introduce the versioned ConvertedFieldSelector typed object and plumbing in the API server to populate it.
- Provide transitional compatibility adapter to accept the older raw context key for a limited time.

Phase 3 - Storage Adapter & Capability
- Implement the StorageCapability interface and a single backend adapter prototype (e.g., a local-in-memory simulation or an experimental etcd3 adapter behind a feature gate).
- Run performance tests and gather data.

Phase 4 - Opt-in & Metrics
- Allow backends and clusters to opt in and measure: request latencies, apiserver CPU, etcd pressure, watch cache churn.
- Based on metrics, consider broader rollout or further changes to the adapter API.

Testing Strategy

- Unit tests: typed contract serialization, request pipeline plumbing, and informer negotiation logic.
- Integration tests: controller behavior with metadata-only informers vs full informers; ensure controller correctness.
- e2e/perf: benchmark scenarios with and without selector pushdown on representative clusters (small/medium/large) to measure API server and storage savings.
- Compatibility tests: transitional adapter acceptance of legacy context keys and a timeboxed deprecation plan.

Risks

- Behavioral regressions in controllers that assume full object payloads; mitigated by per-controller opt-outs and comprehensive integration tests.
- Complexity of typed selector IR and incorrect conversions causing misselection; mitigated by explicit conversion tests and versioned contracts.
- Backend fragmentation: different backends offering different pushdown semantics; mitigated by capability surface and adapter contract and a default server-side fallback.

Open Questions

- Authoritative location and lifetime for the typed contract (apiserver internal vs a staging API group).
- The exact shape of the selector IR (how to encode existence checks, not-equals, set membership) and whether a selector DSL is needed.
- How to safely timebox and remove the transitional raw-context adapter.
- Whether to surface some selector/metadata filtering options through Discovery or feature gates for third-party tools.

Alternatives Considered

- Keep the POC’s current approach (ad hoc context string keys + patching etcd3): rejected for maintainability and upstream acceptability.
- Implement selector pushdown via a centralized request router that rewrites queries before storage: considered but rejected because it centralizes more responsibility in the apiserver and tightly couples storage-layer concerns.
- Full-deprecation of field selector pushdown; still possible, but for large clusters selector pushdown offers measurable savings and should remain an option behind capability gating.

Recommended PR Split (reviewable, incremental)

1) PR: Configuration + controller informer filtering (client-go/informers changes + kube-controller-manager flags) - low risk, should land first.
2) PR: Typed selector contract and apiserver plumbing + unit tests + transitional adapter.
3) PR: Storage capability interface and registration mechanism (API + registry changes only) + unit tests.
4) PR: One experimental backend adapter implementation behind a feature gate (benchmarks + integration tests).
5) PR: Metrics, e2e/perf tests, and documentation for operators (how to opt in and test on their clusters).

Talking Points for SIGs

- The design prioritizes safe, reviewable changes: client-side configuration first so controllers can opt into metadata-only informers without storage changes.
- Typed contracts are both safer and more auditable than raw context-strings and must be versioned.
- Storage pushdown capability must be explicit and adapter-driven; we will not patch the shared etcd3 path by default.
- Phased rollout reduces blast radius and enables measurement-driven decisions.

Milestones

- Milestone A (1 month): Community feedback and consensus on KEP.
- Milestone B (2–3 months): Controller filtering PR landed and small-scale adoption by SIG-maintained controllers.
- Milestone C (4–6 months): Typed selector contract landed and transitional adapter in-tree.
- Milestone D (6–9 months): Backend adapter prototype completed and performance results collected.

Appendix: Implementation Notes & Example Data Structures (illustrative only)

- ConvertedFieldSelector{APIVersion string, IR Serialized []byte, Original string, ConverterMeta map[string]string}
- StorageCapability interface with PushdownSelectors method

Reference Implementation: HariKube

HariKube (https://github.com/HariKube/harikube) is provided here as a targeted reference implementation that demonstrates feasibility and produces concrete, reviewable evidence for several of this KEP's claims. Concrete reference points in HariKube include:

- README.md: claims that pushing filtering to the database allows the watch cache to be disabled and reduces runtime memory to O(1); includes benchmark comparisons vs vanilla Kubernetes and explicitly states that patched Kubernetes images are required.
- pkg/util/selector.go: a selector-to-query translation layer that converts label and field selectors into a backend query representation.
- pkg/server/types.go: server-side backend interfaces that explicitly carry labelSelector and fieldSelector parameters rather than relying on opaque context plumbing.
- pkg/logstructured/sqllog/sql.go: list-path code that forwards selector information into backend list calls.
- pkg/drivers/generic/generic.go: SQL list methods that render selector-specific WHERE clauses and include project-specific handling around skip-controller-manager-metadata-caching.
- pkg/drivers/generic/tx.go: driver transaction code that contains project-specific metadata/owner-handling special cases tied to skip-controller-manager-metadata-caching.

What HariKube demonstrates (evidence):

- Selector pushdown can be implemented end-to-end and yield measurable runtime improvements in some benchmarked scenarios (see README benchmark tables).
- Moving selection work into the backend can materially reduce apiserver memory pressure in configurations where the watch cache is disabled; HariKube explicitly claims an O(1) runtime memory characteristic in that mode.
- A working fork surfaces the concrete plumbing required to translate selectors into backend queries (selector.go) and to carry selector information through server interfaces and logging paths.

Upstream caution points revealed by HariKube:

- HariKube requires patched Kubernetes images and a forked runtime to operate; upstream should avoid designs that require per-cluster or per-distribution binary patches.
- The implementation exposes backend-specific contracts and special-casing (e.g., skip-controller-manager-metadata-caching-related logic and tx-level owner/metadata handling) that would fragment behavior if adopted directly in-tree.
- A working fork does not equate to an upstream-acceptable API/storage design; upstream needs a generic, typed, versioned contract and clear capability/adaptor boundaries to enable reviewable, testable PRs.

How we use HariKube in this KEP:

- HariKube's README and code paths are cited as concrete evidence that selector pushdown can be beneficial and that a selector-to-query translation is possible; these concrete examples inform our choices around a typed ConvertedFieldSelector and adapter interface.
- The KEP intentionally does not recommend copying HariKube's exact patches; instead, it recommends deriving general principles from the fork (typed contract, capability/adapters, phased rollout, and rigorous benchmarks) and implementing those principles in a way that preserves upstream reviewability and cross-backend compatibility.

Feedback requested / Questions for reviewers

- Do you agree with splitting this umbrella proposal into multiple KEPs as proposed (configuration & informer filtering, typed selector contract, storage capability interface, adapter prototypes)?
- Is the proposed typed ConvertedFieldSelector contract the right abstraction surface, or should conversion live in a different API surface (internal apiserver-only vs staging API group)?
- Feedback on the selector IR shape: which operators (existence, not-equals, set membership, ranges) must be supported for useful pushdown semantics?
- Opinions on phased rollout and which SIGs or working groups should champion each phase; suggestions for low-risk experiments and candidate backends for prototypes.
- What key metrics and benchmarks would convince SIGs to expand opt-in beyond experimental adapters?

Conclusion

The recommended approach remains: (1) fix the configuration surface for controller metadata informers, (2) replace raw context selector plumbing with a typed request/storage contract, (3) hide backend-specific selector pushdown behind a capability/adapter interface, and (4) split the work into a sequence of reviewable phases with clear tests and metrics so SIGs can validate the design before broad rollout. These steps are deliberately chosen to serve the two co-equal motivations: enabling more services and application state to be modeled as Kubernetes-native APIs/CRDs (by lowering the cost of in-tree representation via metadata-only/filtering semantics) and equipping Kubernetes to handle much larger clusters and object volumes (by allowing efficient selector pushdown and backend adapters rather than forcing out-of-tree solutions). HariKube provides useful implementation evidence and benchmark claims that strengthen the case for careful experimentation, but its patched, backend-specific fork should not be treated as the downstream-approved upstream design; instead, upstream work must extract the generalizable lessons and implement them via typed contracts, adapter isolation, and phased, feature-gated rollout plans.

If accepted and executed carefully, this umbrella effort enables a strategic shift in two dimensions: it lowers the technical and operational barriers for platform teams and third-party services to expose richer APIs (CRDs and native resources) backed by Kubernetes, and it makes the core control plane and storage plumbing capable of scaling to substantially larger application-state footprints without fragmenting operator tooling across forks and bespoke stores. That vision depends on keeping the technical caution intact - experiments should be feature-gated, adapters must preserve cross-backend semantics, and any backend-specific patches (including HariKube-derived work) should be treated only as experimental evidence rather than prescriptive upstream changes.
