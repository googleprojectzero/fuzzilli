# Parallelized Corpus Import on Multi-Threaded Workers

## TL;DR

This feature parallelizes Fuzzilli's corpus import phase across local multi-threaded worker instances (`--jobs=N`). Instead of importing sequentially on the main thread while worker threads wait or fuzz on an empty corpus, all local worker threads will immediately start up and concurrently consume from a shared, in-memory, thread-safe import queue. Once the import queue is depleted, the workers send their local corpora and coverage to the parent node via `ThreadSync`, which merges them and broadcasts the unified state back, transitioning all instances into active fuzzing simultaneously.

*(Note: Network-distributed fuzzing via `NetworkSync` is explicitly out of scope; multi-machine cluster setups will continue to use standard sequential/delayed worker synchronization).*

---

## Production Safety & Guardrails (Meta-Goal)

A foundational architectural requirement for this feature is that **no changes should impact existing production configurations or execution paths by default**.

- **Preserve Default Behavior:** By default, Fuzzilli must continue to perform single-threaded sequential imports with delayed worker startup exactly as it does today.
- **Strict Scope (ThreadSync Only):** Parallel import is strictly scoped to local in-process worker threads sharing process memory via `ThreadSync`. Network-distributed fuzzing (`NetworkSync`) is explicitly out of scope and remains untouched.
- **Strict Feature-Flagging:** All parallelized import routines, barrier synchronization protocols, trace buffering, and coverage drop-out mechanisms must be strictly gated behind configuration flags (e.g., `--parallelImport`, `--randomEdgeReset`).
- **No-Impact Refactoring:** Any modifications to shared base classes, core engines, or serialization layers must be clean refactorings that introduce zero behavioral changes or performance degradation for non-parallel modes.
- **Off-Production Testing:** The new parallel mode and its settings will be thoroughly tested and validated on separate, isolated machines prior to any production rollouts.

---

## Non-Goals

- **Network Mode (`NetworkSync`):** Implementing parallel corpus import for network-distributed instances (`--networkMaster` / `--networkWorker`) is explicitly a **non-goal**. Network setups introduce socket transport latency, lack shared memory, and require distributed scheduling primitives. Multi-machine cluster setups will continue to operate under the existing sequential/delayed worker synchronization model.
- **Modifying Default Single-Threaded Behavior:** The default single-threaded sequential import must remain functionally and performance-wise identical.
- **Global In-Memory Trace Buffering:** We explicitly avoid uncapped trace buffering across all programs (Option 1) to prevent high peak memory usage during large corpus imports.

---

## Background: Existing Corpus Import

In Fuzzilli's current architecture, corpus import is a single-threaded operation executing solely on the main fuzzer instance. Because each program being imported must be executed and potentially minimized, importing large corpora (thousands of files) can take a significant amount of time (from minutes to hours).

While the main thread is importing:
1. **Underutilization:** Worker threads/processes either wait or start fuzzing with a delayed offset (configured via `--workerDelay`, ranging from 1 to 10 minutes by default).
2. **Redundancy:** If workers are started early, they start with a serialized snapshot of whatever the main thread has imported so far. Once running, any new coverage found by workers is sent to the parent, which in turn distributes it to other workers. This requires each thread to execute full coverage-convergence runs for every shared sample, adding significant overhead.

---

## Proposed Feature: Coordinated Parallel Import

We propose a fully parallelized import mode. All fuzzer instances (parent and workers) start up immediately without delay and concurrently import programs from a shared import queue. When the queue is empty, the threads synchronize, merge their state, and transition to fuzzing together.

### Sequence Diagram (PlantUML)

```
@startuml
scale 4
queue Programs as P
participant main as M
participant worker1 as W1
participant worker2 as W2

M -> P : initialize
M -> W1 : start import async
M -> W2 : start import async
M -> P : pull async
W1 -> P : pull async
W2 -> P : pull async
W1 -> M : serialized data
W2 -> M : serialized data
M -> W1 : serialized merged data
M -> W2 : serialized merged data
M -> W1 : start fuzzing async
M -> W2 : start fuzzing async
@enduml
```

### Process Lifecycle and Coordination

1. **Initialization:**
   - The main thread populates a thread-safe, synchronized queue (`SynchronizedQueue<Program>`) with the shuffled corpus.
   - Worker threads/instances are launched immediately without delay.

2. **Parallel Import Phase:**
   - Both the main thread and all worker threads transition to a new `.parallelImport` state.
   - All threads concurrently pull from the shared queue and run `importProgramWithFixup()`.

3. **Coordination Barrier (Depletion):**
   - When the shared queue is fully depleted, each thread finishes its current program and serializes its local corpus and coverage evaluator state.
   - Worker threads transmit their serialized states back to the main thread via the existing distributed fuzzing channel (`ThreadSync`).

4. **Merging & Sync Phase:**
   - The main thread collects all serialized states from the worker threads.
   - Once all states are collected, the main thread performs a fast union merge of all corpora and coverage evaluation states (creating a union of discovered edges and seeds).
   - The main thread distributes the merged unified state to all worker threads.

5. **Transition to Fuzzing:**
   - All worker threads apply the received unified state, updating their local corpus and coverage evaluators.
   - All instances simultaneously transition to the `.fuzzing` state.

---

## Detailed Design & Architecture

### 1. Thread-Safe Import Queue

Since Fuzzilli uses GCD and sequential `DispatchQueue`s per fuzzer instance, we will introduce a shared, thread-safe queue class to synchronize the programs:

```swift
public class ThreadSafeImportQueue {
    private let queue = DispatchQueue(label: "fuzzilli.import-queue")
    private var programs: [Program]
    public let initialCount: Int

    public init(_ programs: [Program]) {
        self.programs = programs
        self.initialCount = programs.count
    }

    public func next() -> Program? {
        return queue.sync {
            guard !programs.isEmpty else { return nil }
            return programs.removeLast()
        }
    }

    public var count: Int {
        return queue.sync { programs.count }
    }
}
```

### 2. Merging a Rarity Corpus

While merging standard corpora is simple (taking a set union of programs), merging rarity corpora requires special care to ensure that the rare-edge counts, seed IDs, relative seed order, and energy heaps are combined correctly.

#### The Startup Bottleneck (Sparse Edge Seen Counts)
During normal sequential import, as samples are imported, the fuzzer's `edgeSeenCount` accumulates. When `addInternal` is called for a seed, its `rareEdges` is computed and capped based on this accumulated count.

However, in a parallel import mode:
- Each worker thread imports a subset of programs independently.
- At the beginning of the import phase, each worker's `edgeSeenCount` is completely empty or sparse.
- If a seed's rare edges are filtered and capped to `maxTrackedEdgesPerSeed` (128) immediately, common static edges (e.g., initialization paths hit by all programs) will initially look "rare" to that worker. They will populate the seed's rare edges, causing the genuinely rare edges to be sorted out or discarded during the initial capping.
- After all programs are imported and the unified `edgeSeenCount_U` is computed, these static edges will be filtered out, leaving those early-imported seeds with zero or very few tracked rare edges, severely impacting fuzzer performance.

#### Evaluated Solutions

The core challenge is that we need the unified, global `edgeSeenCount_U` to correctly determine which edges are genuinely rare before capping each program's tracked rare edges to `maxTrackedEdgesPerSeed` (128). We evaluate three main strategies:

##### Option 1: In-Memory Trace Buffering (No Re-execution, Precise, Worker-Side Capping)
In this approach, workers calculate each program's deterministic coverage exactly once. Instead of immediate capping, they keep the full trace of all seen `deterministicEdges` in-memory.
1. **Import Pass:** Workers execute programs, accumulate local `edgeSeenCount`, and store the full raw `deterministicEdges: [UInt32]` array in a temporary in-memory trace buffer.
2. **IPC Seen-Count Sync:** Workers send their local `edgeSeenCount` arrays (a flat byte array of size equal to the coverage bitmap, e.g., 2.3MB for 2.3M overall edges) to the parent.
3. **Merge Seen-Counts:** The parent merges them to create the unified `edgeSeenCount_U` array and broadcasts it back to all workers.
4. **Local Capping:** Workers perform a fast, entirely in-memory filtering, sorting, and capping of their trace buffers down to the top-128 rare edges using the unified counts.
5. **Partial Corpus Sync:** Workers instantiate their final `Seed` structures and serialize their correctly-capped partial corpora back to the parent for the final interleaving union.

- **Pros:** 100% mathematically precise, zero double-execution overhead, and highly optimized IPC payloads since only the capped (128-edge) seeds are serialized over process boundaries.
- **Cons:** Significant memory overhead if we store the full, uncapped deterministic edge arrays for large corpora (see calculations below).

##### Option 2: Configurable Buffer Cap (Optimization of Option 1)
Option 2 is structurally identical to Option 1, but addresses the memory concern by introducing a configurable cap $K$ on the trace buffer (e.g., `maxCandidateEdges = 1024` or `2048`) during the initial import pass.
- **Mechanism:** During the import pass, workers filter and sort deterministic edges by their *local* `edgeSeenCount` ascending, keeping at most $K$ candidates in the trace buffer. After receiving the unified `edgeSeenCount_U`, the workers perform the final capping from $K$ candidates down to 128 elements.
- **Why it works perfectly:** Simple static/initialization edges are hit by almost every program. Thus, their local seen counts will grow very rapidly during the import pass and far exceed `rareEdgeLimit` (typically 8). These common edges automatically get pushed to the back of the sorted candidate list and are discarded by the $K$ cap. The genuinely rare edges (seen 1 or 2 times) are guaranteed to be in the front of the candidate array and will easily fit within $K = 1024$ or $2048$ candidates.
- **Pros:** 100% of the accuracy of Option 1, zero double-execution overhead, and extremely low memory usage (megabytes instead of gigabytes).

##### Option 3: Two-Pass Execution (Time-Consuming but Low-Memory)
- **Mechanism:** Workers perform two separate passes of execution on their assigned programs. Pass 1 executes all programs purely to collect and synchronize the unified `edgeSeenCount_U` array. Pass 2 re-executes all successful programs to perform precise filtering and capping of `deterministicEdges` using the final unified counts.
- **Pros:** Minimal memory usage.
- **Cons:** Program execution is Fuzzilli's primary bottleneck. Running every program twice practically doubles the parallel import time, negating its speed advantages.

---

#### Memory Consumption Analysis (Production Scale)

To evaluate the feasibility of **Option 1 (Uncapped)** vs **Option 2 (Capped)**, we calculate the worst-case memory usage using actual production metrics:
* **Resume Corpus Size ($N$):** 40,000 programs
* **Overall Coverage Space:** 2.3M edges
* **Session Coverage:** ~25% (~575,000 edges)
* **Single Program Max Coverage:** up to 5% of overall edges (~115,000 edges)
* **Data Type:** `UInt32` for edge indexes (4 bytes per edge)

#### Worst-Case Memory for Option 1 (Uncapped Trace Buffering)
Under the absolute theoretical worst case, where every single one of the 40,000 programs hits the maximum program coverage of 115,000 edges:
$$\text{Memory per trace} = 115,000 \times 4\text{ bytes} \approx 460\text{ KB}$$
$$\text{Total Memory} = 40,000 \times 460\text{ KB} \approx 18.4\text{ GB}$$

If distributed across $P$ workers (e.g., $P = 10$):
$$\text{Memory per worker process} \approx 1.84\text{ GB}$$

While 1.84 GB per worker is affordable on high-end fuzzing servers, in memory-constrained containers or multi-tenant environments, a transient peak of **18.4 GB** across the machine is substantial and risky.

#### Worst-Case Memory for Option 2 (Configurable Buffer Cap, $K = 1024$)
By applying a local pre-cap of $K = 1024$ candidates during the initial import pass:
$$\text{Memory per trace} = 1024 \times 4\text{ bytes} \approx 4\text{ KB}$$
$$\text{Total Memory} = 40,000 \times 4\text{ KB} \approx 160\text{ MB}$$

If distributed across $P = 10$ workers:
$$\text{Memory per worker process} \approx 16\text{ MB}$$

Even if we increase the candidate cap to a highly conservative $K = 2048$ (8 KB per trace), the total memory across all worker processes combined is only **320 MB** (32 MB per worker).

#### Conclusion & Selection
**Option 2 with $K = 1024$** is selected as the primary design. It is mathematically identical to Option 1 in output quality (since static edges are discarded via local counts, and truly rare edges always fall within the top 1024), eliminates the execution bottleneck of Option 3, and reduces the worst-case RAM footprint by **99.1%** (from 18.4 GB down to 160 MB).

---

#### The Rarity Merge Algorithm (Selected: Option 2)
When performing the synchronization and merging under the chosen design, the process executes as follows:

1. **Edge Counter Union:**
   For every edge index in the coverage space:
   `edgeSeenCount_U[edge] = sum(edgeSeenCount_N[edge] for each node N)`
   Where `N` indexes all local worker corpora (including the parent's own local corpus).

2. **In-Memory Trace Capping (On Workers):**
   Using the unified `edgeSeenCount_U`, each worker filters and caps its buffered $K$-size deterministic edge traces down to the final `maxTrackedEdgesPerSeed` (128):
   `S.rareEdges = S.candidateEdges.filter { edgeSeenCount_U[Int($0)] < rareEdgeLimit }.sorted { edgeSeenCount_U[Int($0)] < edgeSeenCount_U[Int($1)] }.prefix(128)`

3. **Interleaving Seeds:**
   To prevent order-induced bias, the unified seed list `seeds_U` is constructed by interleaving seeds from all corpora:
   `seeds_U = [S_1^A, S_1^B, S_2^A, S_2^B, ...]`
   This retains the relative order of seeds from their respective original source corpora.

4. **Re-indexing:**
   Assign new, consecutive, unique IDs to all interleaved seeds.

5. **Heap Rebuild & Capping:**
   - Recompute energy and heap priority for all seeds based on the updated `edgeSeenCount_U` and seed ages.
   - Cap the seeds list to the maximum permitted size of the rarity corpus, evicting the lowest-energy seeds.

#### Preserving Seed Age Across Soft Resumes
To maintain historical context during rapid session resets (soft resumes):
- Seed age must be preserved and written into the protobuf serialization format on disk.
- Rarity and coverage are recalculated dynamically upon import, but the original seed age is retained.

#### Non-Qualifying Zero-Energy Seeds & Telemetry (Optional Extension)
During corpus import (especially on resumes of large, mature corpora), a seed's deterministic edges are evaluated against the global `edgeSeenCount_U`. If all edges covered by an imported seed have already reached `edgeSeenCount_U >= rareEdgeLimit` across the wider corpus:
- The seed's calculated rarity is `0.0`, resulting in an initial scheduling energy of `0.0`.
- As a consequence, the seed **does not qualify to enter the `energyHeap`** and will not be selected for mutation.

**Why this is Working As Intended (WAI):**
- In long-running fuzzing campaigns, older seeds naturally lose relative interest as newer seeds revisit and saturate their coverage paths. Eventually, their energy drops to zero and they are evicted from active scheduling.
- Resuming a session with an existing 40,000-program corpus simply reflects this exact terminal state: redundant seeds are filtered out of the mutation schedule, focusing CPU cycles on seeds with genuinely rare coverage.
- The seed still successfully seeded the fuzzer's global coverage bitmap (`virgin_bits`), preventing redundant discovery attempts for those paths.

**Optional Monitoring & Statistical Output:**
To give operators and developers visibility into corpus health and heap qualification:
- Track diagnostic counters during the rarity merge phase:
  - `totalImportedSeeds`: Total seeds parsed from disk.
  - `activeHeapSeeds`: Seeds with energy > 0 qualifying for the `energyHeap`.
  - `zeroEnergySeeds`: Seeds with energy = 0 whose tracked edges are saturated (`edgeSeenCount_U >= rareEdgeLimit`).
- Expose an optional CLI/diagnostic flag (e.g., `--logImportRarityStats`) or print a summary in `TerminalUI` upon import completion:
  `"Rarity corpus imported: 40,000 total seeds (14,200 active in heap, 25,800 zero-energy [WAI])"`

---

### 3. Optional Extension: Sample Diversity (Coverage & Seed Drop-out)

#### Motivation & Challenges
In standard fuzzing, diversity arises naturally because asynchronous workers discover coverage at different times. In parallel import, all workers start from an identical merged state, risking redundant exploration. To inject diversity, workers can reset a fraction of coverage edges locally using `cov_clear_edge_data()`. However, naive uniform edge drop-out creates two critical challenges:

1. **The Over-Minimization Trap:**
   Ubiquitous engine edges (e.g., startup and runtime boilerplate, ~25k edges) are hit by virtually any code. If a common edge is reset, any subsequent mutation will trigger it as "new" local coverage. During minimization, the `Minimizer` will strip away nearly all program features because the edge is satisfied by trivial stubs, polluting the corpus with degenerate 1-instruction programs and wasting CPU. **Guardrail:** Common edges must never be dropped.

2. **The Seed-Edge Decoupling Problem (Evaluating Program Dropping):**
   - *Dropping edges only:* If worker $W$ resets edge $E$ but retains seed $P$ (which hit $E$), mutating $P$ will immediately re-trigger $E$ and minimize back to a duplicate of $P$, gaining no diversity.
   - *Dropping both the seed and its unique edges:* Evicting $P$ alongside its unique edges forces $W$ to find alternative paths to $E$ from different seeds. This is safe in distributed fuzzing because peer workers retain $P$, ensuring the cluster never loses coverage.

---

#### Strategy Evaluations

##### Option A: Ephemeral Provenance Tracking & Early-Program Protection
- **Mechanism:** During import, workers track which edges were introduced by which program. Edges discovered in the first $K$ programs (or programs with large discovery deltas) are pinned as protected bootstrap edges. From remaining programs, workers drop a random fraction of seeds and their unique edges, discarding tracking data post-import.
- **Trade-off:** Directly pairs seed eviction with edge clearing and protects startup paths, but relies on heuristic thresholds ($K$) sensitive to corpus shuffle order.

##### Option B: Cross-Worker Bitmap Frequency Filtering
- **Mechanism:** At the sync barrier, the parent analyzes coverage bitmaps across all $M$ workers. Edges hit by multiple independent workers ($C(E) \ge 2$) are classified as common and protected; only edges unique to a single worker ($C(E) == 1$) are eligible for local drop-out.
- **Trade-off:** Zero runtime tracking overhead and corpus-agnostic (works for Basic/Markov/Rarity), but coarse resolution with very few workers and lacks direct program-to-edge binding.

##### Option C: Rarity Corpus Frequency & Seed Coupling
- **Mechanism:** When using `RarityCorpus`, the global `edgeSeenCount_U` and per-seed `rareEdges` are already computed. Edges with `edgeSeenCount_U \ge rareEdgeLimit` are strictly protected. Workers drop a random fraction of seeds containing unique rare edges (`edgeSeenCount_U == 1`), evicting them from the energy heap and resetting their rare edges.
- **Trade-off:** Mathematically eliminates over-minimization and natively couples seeds to edges, but requires `RarityCorpus`.

##### Option D: Late-Import Candidate Dropout (Delayed Inclusion)
- **Concept:** Exploits random import order. In the tail phase of import (e.g., the final 10% of the shared queue), baseline engine edges (~25k) are already fully saturated. Any new coverage discovered at this stage is inherently rare and feature-specific.
- **Mechanism:**
  1. *Candidate Isolation:* During the tail phase, workers flag programs discovering new coverage as *dropout candidates*. The worker rolls back their new edges using `cov_clear_edge_data()` (or masks them) so they remain out of the local base bitmap, buffering `(Program, [newEdges])` separately.
  2. *Sync Barrier:* Workers transmit their base corpora and base bitmaps ($U_{\text{base}, w}$), plus their candidate buffers, to the parent.
  3. *Parent-Side Coordination & Distribution:* The parent merges base bitmaps into $U_{\text{base}} = \bigcup U_{\text{base}, w}$ and aggregates the global candidate pool $\mathcal{C}$.
     - *Cluster Safety Minimum:* The parent guarantees that every candidate program is retained by **at least 1 worker** (so no seed or edge is ever permanently lost from the cluster).
     - *Configurable Dropout:* Candidates are distributed across workers according to a configurable drop probability (e.g., $p_{\text{drop}} = 0.5$, dropping a candidate on ~50% of workers on average while retaining it on the remaining 50%).
     - For each worker $w$, the parent transmits $U_{\text{base}}$ and $w$'s assigned subset of $\mathcal{C}$.
  4. *Safety Guardrail:* If a candidate's edge is present in $U_{\text{base}}$ (covered by any worker's non-candidate imports) or covered by another retained candidate assigned to that worker, it is not reset. Only edges unique to the dropped candidates remain virgin on that worker.
- **Dropout Budgeting & Trade-offs:**
  - *Sample-Centric vs. Edge-Centric Budgeting:*
    - *Sample-Centric (`--candidateDropRate=0.5`):* Dropping a fixed percentage or count of candidate programs is natural for corpus scheduling and preserves balanced corpus sizes across workers. However, variance in edge density per program can result in uneven edge resets.
    - *Edge-Centric (`--maxDroppedEdges=N`):* Target a fixed number of edges to drop per worker, providing predictable coverage resets at the expense of uneven seed counts.
    - *Resolution via Delta-Cap:* By enforcing a candidate guardrail ($\Delta\text{Edges} \le 3$ or $5$), candidates have uniformly small edge footprints. This harmonizes sample-centric and edge-centric metrics, making both predictable.
  - *Why Pure Decentralization Fails:* A purely decentralized approach faces a fundamental contradiction: if workers drop candidates locally without sending them to the parent, those programs and unique edges are permanently lost from the cluster. If workers send candidates to the parent but receive a flat, merged bitmap, they lose provenance and cannot discern candidate-exclusive edges from cluster-wide common edges, risking the over-minimization trap. Hence, **parent-level candidate coordination is mandatory**.
  - *Revisit Trade-off:* If a subsequent non-candidate program on the same worker revisits a candidate edge, that hit is ignored. Because this is confined to the final tail phase, the revisit window is minimal and strictly limited to rare edges.

---

#### Parent Corpus Role, Disk Persistence, and Re-discovery Dynamics

1. **The Parent as Canonical Archive:**
   - The parent instance always retains the complete, un-dropped unified corpus and full coverage bitmap.
   - *Rationale:* The parent's corpus is the sole state serialized to disk (via `Storage`) and persisted on session end for resumes. Dropping seeds on the parent would risk permanently losing coverage across fuzzing sessions.

2. **Re-discovery Dynamics (Working As Intended):**
   - When worker $W$ rediscovers a dropped edge $E$ with a new program $P_{\text{new}}$, $W$ considers it interesting and adds it to its local corpus.
   - When $W$ transmits $P_{\text{new}}$ to the parent via `ThreadSync`, the parent evaluates it against its complete bitmap. Because $E$ was already covered by the original candidate $P_{\text{orig}}$, the parent discards $P_{\text{new}}$ (unless $P_{\text{new}}$ also triggered globally novel edges).
   - **Why this is Working As Intended (WAI):**
     - *Local Genetic Launchpad:* The primary goal of dropout is to provide worker $W$ with an alternative ancestral seed ($P_{\text{new}}$ instead of $P_{\text{orig}}$) so that $W$'s mutations explore the vicinity of $P_{\text{new}}$ rather than $P_{\text{orig}}$.
     - *Global Cluster Payoff:* As soon as mutations of $P_{\text{new}}$ discover a truly novel edge $E_{\text{novel}}$, that descendant program *is* accepted by the parent and broadcast cluster-wide.
     - *Prevents Canonical Bloat:* Discarding $P_{\text{new}}$ on the parent prevents the canonical corpus from accumulating multiple redundant seeds for the same leaf edge.

3. **Potential Minor Refinements (Evaluated):**
   - *Diagnostic Metric:* The parent can optionally track recovery events (e.g. `recoveredCandidateEdges`) as a diagnostic metric to quantify worker exploration efficiency.
   - *Corpus Replacement (Future Work):* If $P_{\text{new}}$ is strictly smaller or faster than $P_{\text{orig}}$, the parent could theoretically replace $P_{\text{orig}}$ with $P_{\text{new}}$ in the canonical corpus. However, given the complexity of in-place seed replacement in `Corpus` and `RarityCorpus`, maintaining the standard WAI behavior is preferred.

---

#### Recommended Strategy
- **Rarity Corpus (Default):** Use **Option C**. Only reset edges with `edgeSeenCount_U == 1` and evict their associated seeds, guaranteeing immunity for common edges and maximizing diversity.
- **Non-Rarity Corpora (Basic / Markov):** Use **Option D** (or a combination of **Option B** and **Option A**). Option D natively couples seed eviction with edge reset during the tail import phase without requiring ongoing edge frequency bookkeeping.

---

## Step-by-Step Implementation Plan (CL Roadmap)

To guarantee complete production safety and satisfy our meta-goals, all changes must either be zero-impact refactorings or logical changes gated behind configuration flags. **To ensure continuous verification, each CL must implement its own targeted unit tests side-by-side with its production code**, leaving only final, extensive end-to-end integration and off-machine verification for the last CL.

The feature is split into 6 incremental, easy-to-review Changelists (CLs):

### CL 1: Core Shared/Synchronized Import Queue
- **Files:** `Sources/Fuzzilli/Fuzzer.swift`, `Sources/Fuzzilli/Util/ThreadSafeImportQueue.swift` (New file), `Tests/FuzzilliTests/ThreadSafeImportQueueTests.swift` (New file)
- **Changes:**
  - Implement the thread-safe `ThreadSafeImportQueue` class.
  - **Production Safety (Refactoring Only):** Integrate the queue into `Fuzzer.swift` and `CorpusImportJob`.
  - **Flag Protection:** Ensure that if parallel import is disabled (default), the sequential import behaves exactly as it did before. The queue can either be bypassed completely or act as a single-threaded queue with identical sequencing and zero performance overhead.
  - **Side-by-Side Testing:** Add comprehensive unit tests in `ThreadSafeImportQueueTests.swift` to verify concurrent dequeueing safety, FIFO ordering, progress reporting correctness, empty queue handling, and integration with `CorpusImportJob` and `Fuzzer`.

### CL 2: Coordinated Parallel Import Flow & State Transitions
- **Files:** `Sources/Fuzzilli/Fuzzer.swift`, `Sources/Fuzzilli/Modules/Sync.swift`, `Sources/Fuzzilli/Modules/ThreadSync.swift`, `Sources/FuzzilliCli/main.swift`, `Sources/FuzzilliCli/TerminalUI.swift`, `Sources/Fuzzilli/Protobuf/fuzzilli.proto`, `Tests/FuzzilliTests/ParallelImportStateTests.swift` (New file)
- **Changes:**
  - Introduce new `.parallelImport` and `.parallelImportSync` fuzzer states if necessary, or adapt the existing state machine.
  - **UI Telemetry:** Update `TerminalUI.swift`'s exhaustive `switch fuzzer.state` (in `printStats`) to support `.parallelImport` and display live shared queue import progress.
  - **Flag Protection:** Update worker startup in `main.swift` so that if `--parallelImport` is disabled, the randomized/configured `--workerDelay` is applied exactly as before. If `--parallelImport` is enabled, launch workers immediately without delay.
  - **Sync Protocol & Protobuf:** Add new coordination opcodes to `MessageType` in `Sync.swift` (e.g., `.parallelImportSync`, `.parallelImportMergedState`) and define corresponding protobuf envelopes in `fuzzilli.proto`.
  - **Flag-gated Barrier:** Implement the completion barrier and sync message handling via `ThreadSync` (confirming `NetworkSync` remains unaffected). When the import queue is depleted, workers stop, serialize their local state, and send a coordination message. This coordination flow must be inactive/disabled under the default sequential mode.
  - **Flag-gated Merge & Resume:** The parent merges the states and broadcasts them back only when in parallel import mode.
  - **Side-by-Side Testing:** Write state-transition unit tests verifying the transition from `.parallelImport` to `.fuzzing` on depletion, and checking that the barrier correctly awaits all worker threads before proceeding.

### CL 3: Rarity Corpus Merging Support & Age Serialization
- **Files:** `Sources/Fuzzilli/Corpus/RarityCorpus.swift`, `Sources/Fuzzilli/Protobuf/fuzzilli.proto`, `Tests/FuzzilliTests/RarityCorpusMergeTests.swift` (New file)
- **Changes:**
  - **Protobuf Backward Compatibility:** Add optional age serialization to `fuzzilli.proto`. Ensure deserialization degrades gracefully (with default age values) when reading older corpus files from disk where the age field is absent.
  - **Flag Protection:** In `RarityCorpus.swift`, the in-memory trace-buffering mechanism (Option 2 with $K = 1024$) and worker-side capping must only activate if `--parallelImport` is enabled.
  - If `--parallelImport` is disabled (the default production configuration), the rarity corpus must execute `addInternal` with immediate capping to 128 rare edges exactly as it does today.
  - Implement the `RarityCorpus` union/merge method on the parent following the defined Rarity Merge Algorithm.
  - **Side-by-Side Testing:** Write targeted unit tests in `RarityCorpusMergeTests.swift` testing the Rarity Merge Algorithm using mock worker corpora. Verify interleaving logic, re-indexing, rare edge filtering using `edgeSeenCount_U`, and correct heap priority rebuilding. Verify backwards compatibility when loading state without seed age data.

### CL 4 (Optional Extension): Sample Diversity via Safe Edge/Seed Drop-out
- **Files:** `Sources/Fuzzilli/Configuration.swift`, `Sources/Fuzzilli/Evaluation/ProgramCoverageEvaluator.swift`, `Sources/Fuzzilli/Corpus/RarityCorpus.swift`, `Sources/FuzzilliCli/main.swift`, `Tests/FuzzilliTests/CoverageDropoutTests.swift` (New file)
- **Changes:**
  - Add configuration parameters for diversity drop-out (e.g., `--randomSeedDropout=0.05` or `--randomEdgeReset=0.05`).
  - **Flag Protection:** Default the ratio to `0.0` (disabled) so that standard production coverage evaluation remains unchanged.
  - Implement safe dropout logic following the Hybrid Multi-Tier Drop-out design:
    - In `RarityCorpus.swift`, implement Option C (coupled seed eviction and rare-edge reset using `edgeSeenCount_U` and `cov_clear_edge_data()`).
    - For non-rarity corpora, implement Option D / Option B frequency filtering and Option A early program immunity to mask out common edges from reset.
  - **Side-by-Side Testing:** Add unit tests in `CoverageDropoutTests.swift` validating that common/bootstrap edges are strictly protected against drop-out (preventing the over-minimization trap), and that seed eviction cleanly rebuilds the energy heap in `RarityCorpus` without corrupting other evaluator state.

### CL 5 (Optional Extension): Rarity Import Qualification Telemetry & Statistics
- **Files:** `Sources/Fuzzilli/Corpus/RarityCorpus.swift`, `Sources/FuzzilliCli/TerminalUI.swift`, `Sources/FuzzilliCli/main.swift`, `Tests/FuzzilliTests/RarityCorpusMergeTests.swift`
- **Changes:**
  - Add optional telemetry tracking during the rarity merge phase: compute `totalImportedSeeds`, `activeHeapSeeds` (energy > 0), and `zeroEnergySeeds` (energy == 0).
  - Expose a diagnostic CLI flag (e.g., `--logImportRarityStats`) or print a summary string in `TerminalUI` upon import completion indicating heap qualification and corpus saturation.
  - **Flag Protection:** Ensure statistics computation and logging are purely observational and have zero impact on scheduling or active fuzzing.
  - **Side-by-Side Testing:** Add unit tests verifying accurate calculation and reporting of active vs. zero-energy seed counts under simulated saturated-edge scenarios.

### CL 6: End-to-End Tests, CLI Integration & Off-Machine Verification
- **Files:** `Tests/FuzzilliTests/ParallelImportTests.swift` (New file), `Sources/FuzzilliCli/main.swift`
- **Changes:**
  - Expose CLI arguments (e.g., `--parallelImport`, `--randomEdgeReset`).
  - **Flag Protection:** Keep all flags **off by default** so standard production runs remain 100% unaffected.
  - **Side-by-Side Testing:** Write extensive end-to-end integration tests spawning actual worker threads and performing the complete parallel import and merging flow on realistic program sets. Confirm that the default mode functions exactly as before with delayed workers.
  - **Optional Depletion Tracking Tests:** Optionally test explicit queue depletion hooks/callbacks or coordinator tracking if required beyond the standard `nil` dequeue termination check.
  - Perform verification runs on separate, isolated machines to check performance without impacting the live production environment.
