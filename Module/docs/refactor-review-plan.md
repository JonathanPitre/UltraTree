# UltraTree Refactor Review Plan

This document captures the current architecture review for UltraTree, with emphasis on scan throughput, duplicate detection correctness, fallback parity, duplicate-engine improvements, and the option to ship a precompiled C# assembly.

## Locked Product Decisions

These decisions are treated as fixed requirements for the refactor:

- Duplicate waste must be reported as reclaimable bytes.
- Hardlinks must be surfaced in a separate linked-files section instead of being counted as normal duplicate waste.
- The module must remain compatible with Windows PowerShell 5.1 because it is widely used through RMM tooling and under `SYSTEM`.

## Review Scope

The review focused on these areas:

- Scan-path performance in `Get-FolderSizes` and `MftScanner`
- Correctness of duplicate detection
- Performance and feature depth of the duplicate engine
- Consistency between NTFS and fallback scan modes
- PowerShell overhead after C# scanning completes
- Packaging and startup costs for the embedded `Add-Type` model

## Executive Summary

UltraTree already pushes the heavy scan loop into C#, but the implementation still leaves meaningful performance on the table.

The biggest near-term issues are:

1. A correctness bug in duplicate detection caused by desynchronized `ConcurrentBag` arrays.
2. Incomplete result metadata in fallback mode.
3. High contention in folder-size ancestor aggregation.
4. Continued path-based filesystem I/O inside the "MFT" path.
5. A duplicate pipeline that works, but can prune candidates much more aggressively before full-file hashing.

The biggest structural improvement is to move from runtime-compiled embedded C# to a precompiled DLL, but that primarily improves import time, packaging, and maintainability. The larger scan-speed wins will come from reducing per-file metadata I/O and contention in the scan loop.

For implementation sequencing, the DLL migration should be treated as the last stage. During active scanner and duplicate-engine refactoring, keeping the C# code in the current `Add-Type` flow is the simpler and lower-risk development path. Once the engine is stable and benchmarked, it can be moved into a compiled assembly.

## Current Status

Current stable baseline on branch `codex/dev-refactor`:

- Keep commit: `5b2bad3` (`Fix: restore compressed size scan semantics`)
- Development model: `Add-Type` remains in place
- Performance work status: paused for now

What has been completed and validated on Windows:

- Duplicate candidate collection was fixed by moving to a single candidate object.
- Fallback scans now return the same result shape and metadata categories as the NTFS path.
- Duplicate quick hashing was upgraded from a prefix-only hash to sampled hashing.
- Duplicate full-hash file opens now use broader sharing for better live-system coverage.
- Hardlinks are separated from duplicate waste and surfaced as `LinkedFiles`.
- HTML output now includes a separate linked-files section.
- Locale-sensitive byte formatting was normalized to invariant formatting.

What was tried and deliberately not kept as the main path:

- Replacing hot-path compressed-size reads with a handle-based all-files metadata probe.
- Switching scan size semantics to `AllocationSize`.

Why it was not kept:

- It increased scan failures significantly on live systems.
- It changed duplicate threshold behavior.
- It did not produce a meaningful performance win.

Practical conclusion:

- The current scanner is already fast enough for production use.
- Further hot-path performance changes are likely to have diminishing returns.
- The remaining likely ceiling is storage I/O and per-file metadata access, not PowerShell control flow.
- Future performance experiments should be isolated and benchmark-driven, not mixed into the stable path.

## Key Findings

### 1. Duplicate candidate arrays can desynchronize

Severity: High

Current behavior:

- Candidate paths are stored in one `ConcurrentBag<string>`.
- Candidate sizes are stored in one `ConcurrentBag<long>`.
- Both bags are converted to arrays and consumed by index.

Problem:

`ConcurrentBag` is unordered, and two independent bags do not preserve a shared order. That means `pathsArray[i]` may not belong to `sizesArray[i]`.

Impact:

- False positives
- False negatives
- Incorrect duplicate group size and wasted-space calculations

Recommended fix:

- Replace the two bags with a single candidate type, for example:
  - `struct DuplicateCandidate { string Path; long Size; }`
  - `List<DuplicateCandidate>` with locking or per-thread local buffers
  - `ConcurrentBag<DuplicateCandidate>`

Priority:

- Fix first, before any larger performance refactor.

### 2. Fallback scans return incomplete metadata

Severity: High

Current behavior:

When the drive is non-NTFS, the volume cannot be opened, or the USN journal is unavailable, the code falls back to directory walking but only sets `result.Items`.

Problem:

The returned `ScanResult` omits:

- `TotalFiles`
- `TotalFolders`
- `FileTypes`
- `CleanupSuggestions`
- Duplicate-analysis metadata

Impact:

- HTML output shows misleading totals
- Behavior changes depending on admin rights and filesystem type
- Public API contract is inconsistent

Recommended fix:

- Make fallback produce the same `ScanResult` shape as the NTFS path.
- Share a common aggregation pipeline so both scan modes feed the same result builder.

Priority:

- Fix alongside or immediately after the duplicate bug.

### 3. Ancestor aggregation is a high-contention hot path

Severity: Medium-High

Current behavior:

For every file, the scanner walks parent folders and calls `ConcurrentDictionary.AddOrUpdate` for each ancestor.

Problem:

- Heavy contention under large trees
- Repeated delegate invocation in the hottest path
- Poor scaling as core count and file count increase

Impact:

- CPU overhead dominates in large scans
- Parallel execution does not scale as cleanly as it should

Recommended fix options:

1. Per-thread local dictionaries merged at the end
2. Partitioned dictionaries per worker
3. Compact integer folder indexing and array-based accumulation

Best long-term option:

- Convert folder references into compact integer indexes and aggregate sizes into arrays or unmanaged buffers, then merge once.

Priority:

- High-value performance change after correctness fixes.

### 4. The MFT path still pays for per-file filesystem I/O

Severity: Medium-High

Current behavior:

After MFT/USN enumeration, the scanner still:

- Builds a full path for each file
- Calls `GetCompressedFileSize(path, ...)`
- Calls `File.GetLastWriteTime(path)` for large files
- Calls `Directory.GetLastWriteTime(path)` for folders

Problem:

This preserves a large amount of path-based metadata I/O even after native enumeration.

Impact:

- Prevents the scanner from approaching the real native ceiling
- Adds syscall overhead for very large trees
- Makes path resolution more expensive than necessary

Recommended fix:

- Reuse `entry.TimeStamp` from the USN record for last-modified values.
- Delay path materialization until an item actually needs to be emitted.
- Investigate richer NTFS/native metadata retrieval so file size does not require one path-based call per file.

Priority:

- Main throughput improvement after correctness fixes.

### 5. PowerShell reshapes too much data after C# scanning

Severity: Medium

Current behavior:

`Get-FolderSizes` converts each result item into a `PSCustomObject`, formats byte sizes into strings, and then filters/sorts again in PowerShell.

Problem:

- Extra allocations
- Extra formatting work
- Extra sort/filter pass after C# already did most of the expensive work

Impact:

- Avoidable CPU and GC overhead on large scans
- More pressure on the PowerShell pipeline than necessary

Recommended fix:

- Keep results typed until the final presentation layer.
- Return already-filtered top-N data from C# where possible.
- Only format human-readable sizes in HTML generation or display-specific wrappers.

Priority:

- Good secondary optimization.

### 6. Runtime C# compilation adds import-time overhead

Severity: Medium

Current behavior:

- The module loads C# via `Add-Type -TypeDefinition`
- The manifest does not use `RequiredAssemblies`
- Build output still produces a script module rather than a binary-backed module

Impact:

- Slower fresh import
- More moving pieces in packaging
- Harder to version and test the native portion cleanly

Recommended fix:

- Ship a compiled `UltraTree.Native.dll`
- Load it via `RequiredAssemblies` or module root bootstrap logic
- Leave PowerShell responsible only for command surface and HTML/report formatting

Priority:

- Recommended, but not the first scan-speed fix.

### 7. The duplicate pipeline can eliminate more work before full hashing

Severity: Medium

Current behavior:

The duplicate engine currently uses:

1. Group by file size
2. Quick hash of the first 8 KB
3. Full-file xxHash64

Problem:

The first-8-KB quick hash is cheap but weak for many real-world file types:

- Installers with common headers
- Media files with shared container structure
- Office files with similar prefixes
- Build artifacts with identical headers and differing payloads

Impact:

- Too many candidates survive into the full-hash stage
- More disk I/O than necessary
- Dedup throughput falls off as the corpus gets larger

Recommended fix:

- Replace the single-prefix quick hash with a stronger sampled fingerprint:
  - head + middle + tail samples
  - fixed stripes across large files
  - include file size in the candidate fingerprint key
- Keep full-file hashing as the final verifier, but feed it fewer candidates.

Priority:

- High-value dedup optimization after the correctness fixes.

### 8. Duplicate hashing can be more resilient for open and special files

Severity: Medium

Current behavior:

The quick-hash and full-hash stages open files with `FileShare.Read`.

Problem:

Actively used files may be skipped even though they are safe to read in a scanner context.

Impact:

- Reduced duplicate coverage on live systems
- More false negatives in practical MSP/admin scenarios

Recommended fix:

- Use broader sharing where safe for scanning, such as:
  - `FileShare.ReadWrite | FileShare.Delete`
- Track and surface hash-skip reasons separately from generic errors.

Priority:

- Good operational improvement for duplicate coverage.

### 9. Duplicate analysis should understand NTFS identity, not only path identity

Severity: Medium

Current behavior:

Duplicate grouping is path-based.

Problem:

Hardlinks can appear as multiple paths to the same underlying file record. Those are not true wasted duplicate bytes.

Impact:

- Over-reported duplicate waste
- Misleading cleanup recommendations

Recommended fix:

- Add file identity awareness using NTFS file reference metadata where available.
- Treat hardlinks as a separate reported category or exclude them from wasted-space totals.

Priority:

- Important for correctness if duplicate cleanup is used operationally.

### 10. Duplicate results can be more actionable

Severity: Medium

Current behavior:

Duplicate groups currently expose hash, file size, file list, and wasted space.

Problem:

The data is enough to display duplicates, but not enough to drive clean review or cleanup decisions.

Recommended improvements:

- Add a canonical file recommendation per group
- Add oldest/newest timestamps
- Add top parent folder or drive impact
- Add flags such as:
  - `IsHardlinkGroup`
  - `HasOpenFileFailures`
  - `VerificationLevel`

Priority:

- Secondary feature improvement after engine correctness and throughput work.

## Recommended Refactor Strategy

### Phase 1: Correctness and contract stability

Goal:

- Fix incorrect output before chasing micro-optimizations.

Work:

1. Replace separate duplicate candidate bags with a single candidate type.
2. Make fallback mode return the same result contract as NTFS mode.
3. Add tests for:
   - Duplicate candidate ordering
   - Fallback totals and metadata
   - Duplicate wasted-space calculations
4. Add tests for:
   - duplicate grouping stability
   - duplicate group hash/value consistency
   - non-NTFS fallback parity for duplicate-enabled scans

Expected result:

- Stable behavior across environments
- Safer baseline for later optimization

### Phase 2: Remove obvious hot-path waste

Goal:

- Reduce scan-loop contention and avoidable metadata calls.

Work:

1. Replace shared ancestor aggregation with per-thread local aggregation and merge.
2. Reuse the USN/MFT timestamp already captured.
3. Stop calling `Directory.GetLastWriteTime` and `File.GetLastWriteTime` in the hot loop unless required for emitted items.
4. Delay path construction until needed.
5. Broaden duplicate file sharing mode where safe so open files are less likely to be skipped.

Status:

- Partially completed

Notes:

- Per-worker local aggregation was implemented and kept because it improved structure and reduced shared hot-path updates.
- On real Windows scans, it did not produce a material end-to-end speedup by itself.
- Replacing hot-path size retrieval semantics was tested and rolled back.

Expected result:

- Cleaner scan internals
- Better baseline for future isolated experiments
- No current expectation of a major scan-time reduction from more work in this phase

### Phase 3: Strengthen the duplicate engine

Goal:

- Reduce the amount of disk I/O required to find trustworthy duplicate groups.

Work:

1. Group duplicate candidates by size during the main scan instead of collecting flat arrays and regrouping later.
2. Replace the first-8-KB quick hash with a sampled fingerprint:
   - head
   - middle
   - tail
   - optional stripe sampling for very large files
3. Keep full-file xxHash64 as the final verification stage.
4. Rework `ComputeFullHash` to reduce temporary allocations during streaming.
5. Separate hash errors from access errors in reporting.
6. Add tests and benchmarks for:
   - sampled-hash candidate reduction
   - full-hash throughput
   - duplicate coverage with open files

Status:

- Substantially completed for the current release goal

Completed:

- Sampled quick hashing
- Broader file sharing in hash stages
- Reduced full-hash allocation churn
- Hardlink-aware duplicate classification

Notes:

- These changes improved correctness and operational coverage more than raw speed.
- The duplicate engine is currently in a good enough place for stabilization.

Expected result:

- Stable duplicate reporting
- Better live-system duplicate coverage
- Safer duplicate totals due to hardlink separation

### Phase 4: Reshape the result pipeline

Goal:

- Keep data native and typed for longer.

Work:

1. Move more filtering, sorting, and top-N selection into C#.
2. Return typed DTOs for:
   - Items
   - File types
   - Cleanup suggestions
   - Duplicate groups
3. Minimize `PSCustomObject` conversion in `Get-FolderSizes`.
4. Only format strings such as `Size` and `LastModified` at the display layer.

Status:

- Deferred

Reason:

- The remaining PowerShell-side overhead does not currently justify another risky refactor.
- This remains a good cleanup target later, especially before DLL packaging.

Expected result:

- Less PowerShell overhead
- Cleaner separation between scan engine and output formatting

### Phase 5: Improve duplicate feature depth

Goal:

- Make duplicate output safer and more useful for remediation work.

Work:

1. Add NTFS identity awareness so hardlinks are not counted as wasted duplicate bytes.
2. Extend duplicate-group DTOs with richer metadata:
   - canonical file suggestion
   - oldest/newest
   - skipped-file count
   - verification level
3. Add configuration for dedup behavior:
   - exclude paths
   - include extensions
   - report hardlinks separately
   - sampled hash aggressiveness
4. Update HTML/report rendering to display the richer duplicate metadata and add a separate linked-files section.

Status:

- Mostly completed for the current feature set

Completed:

- Hardlink detection
- Linked-files reporting in result objects
- Linked-files rendering in HTML output

Remaining optional improvements:

- Canonical file suggestion
- Verification metadata
- More explicit cleanup guidance for duplicate groups

Expected result:

- More trustworthy duplicate reporting
- Better cleanup decisions
- Safer future expansion toward remediation features

### Phase 6: Ship a precompiled assembly

Goal:

- Improve startup, packaging, and long-term maintainability.

Work:

1. Freeze the scanner and duplicate-engine interfaces after benchmark validation.
2. Move scanner code into a dedicated C# project, for example:
   - `Module/src/UltraTree.Native/UltraTree.Native.csproj`
3. Build a Windows PowerShell 5.1-compatible DLL.
4. Build the DLL during the module build process.
5. Package the DLL into the module artifact.
6. Update the manifest to load the assembly explicitly.
7. Keep PowerShell functions as thin wrappers.
8. Document signing as an optional release-hardening step rather than a development prerequisite.

Expected result:

- Faster import
- Cleaner code organization
- Easier unit testing of scanner internals
- Better foundation for future native optimizations

## Precompiled DLL Recommendation

Recommendation: Yes, but not as a substitute for scan-loop refactoring.

Why it is worth doing:

- Removes runtime compilation from module import
- Simplifies versioning and packaging
- Makes the native scanner easier to test and benchmark
- Reduces PowerShell-side complexity

Why it is not enough by itself:

- The largest remaining scan cost is still path-based metadata I/O
- The ancestor aggregation hot path still contends heavily
- The duplicate engine still needs better candidate pruning and richer file identity handling
- PowerShell still reshapes a large amount of data after scanning

Conclusion:

- A DLL is the right architecture.
- It should follow the correctness fixes and be paired with scan-loop refactoring.
- It should be introduced after the refactor is stable, not at the beginning of the development effort.

## DLL vs Add-Type During Development

Recommendation:

- Keep using `Add-Type` while the scanner and duplicate engine are being actively refactored.
- Move to a precompiled DLL only after behavior, interfaces, and benchmarks have stabilized.

Why this sequence is better:

- It keeps iteration fast while core logic is still changing.
- It avoids mixing packaging changes with hot-path logic changes.
- It lets performance work focus on scanner behavior first and startup/package improvements second.
- It preserves the current module development model until the engine is proven.

Why the DLL still matters later:

- It removes runtime compilation overhead.
- It simplifies production packaging.
- It gives a cleaner unit-test and benchmark boundary.
- It is a stronger long-term fit for a Windows PowerShell 5.1 production module used at scale.

Signing note:

- A precompiled DLL does not by itself force a PowerShell signing requirement.
- Script-signing concerns still primarily apply to the module script files such as `.psm1` and `.psd1`.
- Release signing may still be desirable for enterprise trust and reputation, but it is not a reason to avoid the DLL path.

## Proposed Target Architecture

### PowerShell responsibilities

- Public command surface
- Parameter validation
- Config loading
- HTML rendering
- User-friendly wrappers

### C# responsibilities

- NTFS/USN/MFT scanning
- Fallback scanning
- Duplicate detection
- Aggregation
- Top-N selection
- Typed result models
- File identity and duplicate classification

### Suggested assembly split

- `UltraTree.Native.dll`
  - Scanner engine
  - Duplicate engine
  - Result DTOs
  - File identity and hardlink handling
- `UltraTree.psm1`
  - Wrapper functions
  - HTML/report generation
  - Config and display helpers

## Testing Gaps

Current tests are strong on PowerShell command shape and help content, but light on scan-engine behavior.

Add tests for:

- Duplicate detection correctness under concurrent collection
- Duplicate candidate grouping by size
- Sampled fingerprint correctness
- Hardlink handling
- Open-file duplicate coverage
- Fallback-mode result parity
- Large-tree aggregation correctness
- Duplicate wasted-space totals
- Top-N sorting stability
- Import behavior when switching from `Add-Type` to a compiled assembly

If possible, also add benchmark-style tests for:

- Import time
- NTFS scan throughput
- Duplicate scan throughput
- Sampled-hash reduction rate
- Peak memory usage

## Suggested Implementation Order

Revised order after implementation and benchmarking:

1. Keep the current stable scan path based on compressed-size semantics
2. Treat additional scan-speed work as experimental only
3. Finish documentation and release hardening around duplicates and linked files
4. Expand behavioral test coverage where gaps remain
5. Clean up public/report semantics before packaging work
6. Stabilize engine interfaces
7. Introduce precompiled DLL packaging as the final structural phase

## Phase Task Breakdown

Use this section as the working checklist for implementation.

### Phase 1 Tasks

- [x] Create a single `DuplicateCandidate` type and replace the split path/size bags.
- [x] Refactor duplicate candidate collection to preserve size with the path at creation time.
- [x] Normalize fallback results so duplicate-enabled and non-duplicate scans return the same contract.
- [x] Add regression tests for duplicate wasted-space totals and fallback parity.

### Phase 2 Tasks

- [x] Replace shared folder aggregation with per-thread local aggregation and merge.
- [ ] Reuse MFT timestamps instead of path-based `GetLastWriteTime` calls.
- [ ] Defer file and folder path materialization until an item must be emitted.
- [x] Update duplicate file opens to use broader file sharing when safe.

Phase note:

- Further work here is paused unless future benchmarks justify it.

### Phase 3 Tasks

- [ ] Size-bucket duplicate candidates during the main scan.
- [x] Implement sampled duplicate fingerprints.
- [x] Benchmark head-only hashing versus sampled hashing.
- [x] Rework full-file hashing to reduce temporary allocations.
- [ ] Separate duplicate hash failures from general scan errors.

Phase note:

- Performance gains were modest, but correctness and live-system resilience improved.

### Phase 4 Tasks

- [ ] Move top-N selection and duplicate sorting into C#.
- [ ] Keep duplicate DTOs typed until the output layer.
- [ ] Minimize PowerShell object reshaping in `Get-FolderSizes`.
- [ ] Format duplicate display strings only in HTML/report code.

Phase note:

- Deferred for now.

### Phase 5 Tasks

- [x] Detect hardlinks and remove them from wasted-space totals.
- [ ] Extend duplicate DTOs with canonical-path and verification metadata.
- [ ] Add dedup configuration options for exclusion and behavior tuning.
- [x] Update duplicate HTML rendering to expose richer context.

### Phase 6 Tasks

- [ ] Freeze the native/public boundary after the refactor is stable.
- [ ] Split scanner and duplicate engine code into a dedicated C# project.
- [ ] Produce and package `UltraTree.Native.dll`.
- [ ] Target a Windows PowerShell 5.1-compatible framework/runtime.
- [ ] Update manifest/build logic to load the assembly explicitly.
- [ ] Add import-time benchmarks before and after the DLL migration.
- [x] Document signing as a release-hardening option rather than a development blocker.

## Recommended Next Focus

With performance work paused, the next practical work should be:

1. Stabilize documentation for duplicate and linked-file behavior.
2. Review remaining behavioral test gaps without changing the hot path.
3. Prepare the codebase for an eventual DLL move by clarifying boundaries, not by changing runtime behavior.

Do not resume scan-speed refactoring unless:

- a new benchmark identifies a clearly isolated hotspot, or
- a future native experiment is run behind an internal toggle and compared against the stable baseline.

## Notes for Future Benchmarking

When measuring improvements, track these separately:

- Module import time
- NTFS scan time without duplicates
- NTFS scan time with duplicates
- Fallback scan time
- Peak memory usage
- Total files scanned per second

Do not bundle all improvements into one measurement. The DLL change and the scan-loop changes improve different parts of the experience and should be measured independently.
