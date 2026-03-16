# MftScanner C# Type Definitions
# Ultra-fast folder size calculation using USN Journal / MFT enumeration

# Only add the type if it doesn't already exist (prevents re-compilation errors)
if (-not ([System.Management.Automation.PSTypeName]'MftTreeSizeV8.MftScanner').Type) {
    Add-Type -TypeDefinition @"
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Runtime.InteropServices;
using System.ComponentModel;
using Microsoft.Win32.SafeHandles;
using System.Diagnostics;

namespace MftTreeSizeV8
{
    public class FolderResult
    {
        public string Path;
        public long Size;
        public bool IsDirectory;
        public DateTime LastModified;
    }

    public class FileTypeInfo
    {
        public string Extension;
        public long TotalSize;
        public int FileCount;
    }

    public class CleanupSuggestion
    {
        public string Path;
        public string Category;
        public long Size;
        public string Description;
    }

    public class DuplicateGroup
    {
        public string Hash;
        public long FileSize;
        public List<string> Files;
        public long WastedSpace;
        public bool IsLinkedGroup;
    }

    public class DuplicateCandidate
    {
        public string Path;
        public long Size;
        public string FileIdentity;
        public int LinkCount;
    }

    public class DuplicateResult
    {
        public List<DuplicateGroup> Groups;
        public List<DuplicateGroup> LinkedGroups;
        public long TotalWastedSpace;
        public int TotalDuplicateFiles;

        public DuplicateResult()
        {
            Groups = new List<DuplicateGroup>();
            LinkedGroups = new List<DuplicateGroup>();
            TotalWastedSpace = 0;
            TotalDuplicateFiles = 0;
        }
    }

    public class ScanResult
    {
        public List<FolderResult> Items;
        public List<FileTypeInfo> FileTypes;
        public List<CleanupSuggestion> CleanupSuggestions;
        public DuplicateResult Duplicates;
        public long TotalUsedSpace;
        public long TotalFreeSpace;
        public long TotalDriveSize;
        public long ErrorCount;
        public long TotalFiles;
        public long TotalFolders;
    }

    public class FallbackScanContext
    {
        public ConcurrentBag<FolderResult> Items;
        public ConcurrentDictionary<string, long> FileTypeSizes;
        public ConcurrentDictionary<string, int> FileTypeCounts;
        public ConcurrentBag<DuplicateCandidate> DuplicateCandidates;
        public ConcurrentDictionary<string, long> CategorySizes;
        public long TotalFiles;
        public long TotalFolders;
        public long ErrorCount;
    }

    // Memory manager for dynamic RAM-based file loading
    public static class MemoryManager
    {
        private const long MIN_FILE_LOAD = 50L * 1024 * 1024;      // 50MB minimum
        private const long MAX_FILE_LOAD = 1024L * 1024 * 1024;    // 1GB maximum
        private const long CLEANUP_THRESHOLD = 50L * 1024 * 1024;  // Cleanup after 50MB files

        public static long GetAvailableMemory()
        {
            try
            {
                // Use GC to estimate available memory
                long totalMemory = GC.GetTotalMemory(false);
                // Assume 80% of max memory is usable, minus current usage
                long maxMemory = Environment.Is64BitProcess ? 8L * 1024 * 1024 * 1024 : 1536L * 1024 * 1024;
                return Math.Max(maxMemory - totalMemory, MIN_FILE_LOAD);
            }
            catch
            {
                return MIN_FILE_LOAD;
            }
        }

        public static long GetMaxFileLoadSize()
        {
            long available = GetAvailableMemory();
            // Use 25% of available, capped between min and max
            long maxLoad = available / 4;
            return Math.Max(Math.Min(maxLoad, MAX_FILE_LOAD), MIN_FILE_LOAD);
        }

        public static bool ShouldCleanup(long fileSize)
        {
            return fileSize > CLEANUP_THRESHOLD;
        }

        public static void Cleanup()
        {
            GC.Collect(2, GCCollectionMode.Optimized, false);
        }

        public static void ForceCleanup()
        {
            GC.Collect(2, GCCollectionMode.Forced, true);
            GC.WaitForPendingFinalizers();
        }
    }

    // Simple buffer pool to reduce GC pressure during file operations
    public static class BufferPool
    {
        private const int SMALL_BUFFER = 16384;     // 16KB for sampled quick hash
        private const int LARGE_BUFFER = 262144;    // 256KB for streaming
        private const int MAX_POOLED = 64;          // Max buffers to keep per size

        private static readonly ConcurrentBag<byte[]> _smallBuffers = new ConcurrentBag<byte[]>();
        private static readonly ConcurrentBag<byte[]> _largeBuffers = new ConcurrentBag<byte[]>();

        public static byte[] RentSmall()
        {
            byte[] buffer;
            if (_smallBuffers.TryTake(out buffer))
                return buffer;
            return new byte[SMALL_BUFFER];
        }

        public static byte[] RentLarge()
        {
            byte[] buffer;
            if (_largeBuffers.TryTake(out buffer))
                return buffer;
            return new byte[LARGE_BUFFER];
        }

        public static void Return(byte[] buffer)
        {
            if (buffer == null) return;

            if (buffer.Length == SMALL_BUFFER && _smallBuffers.Count < MAX_POOLED)
                _smallBuffers.Add(buffer);
            else if (buffer.Length == LARGE_BUFFER && _largeBuffers.Count < MAX_POOLED)
                _largeBuffers.Add(buffer);
            // Otherwise let GC collect it
        }

        public static void Clear()
        {
            byte[] dummy;
            while (_smallBuffers.TryTake(out dummy)) { }
            while (_largeBuffers.TryTake(out dummy)) { }
        }
    }

    public static class DuplicateFinder
    {
        private const int QUICK_SAMPLE_SIZE = 4096;    // 4KB per sample
        private const int QUICK_SAMPLE_COUNT = 4;      // head, 1/3, 2/3, tail
        private const int QUICK_HASH_SIZE = QUICK_SAMPLE_SIZE * QUICK_SAMPLE_COUNT;

        // xxHash64 constants
        private const ulong PRIME64_1 = 11400714785074694791UL;
        private const ulong PRIME64_2 = 14029467366897019727UL;
        private const ulong PRIME64_3 = 1609587929392839161UL;
        private const ulong PRIME64_4 = 9650029242287828579UL;
        private const ulong PRIME64_5 = 2870177450012600261UL;

        public static DuplicateResult FindDuplicates(
            DuplicateCandidate[] candidates,
            long minFileSize,
            bool verbose)
        {
            var result = new DuplicateResult();
            var totalSw = Stopwatch.StartNew();

            // ============ STAGE 1: Group by size ============
            var sw = Stopwatch.StartNew();
            var sizeGroups = new Dictionary<long, List<DuplicateCandidate>>();
            var linkedGroups = new List<DuplicateGroup>();
            for (int i = 0; i < candidates.Length; i++)
            {
                DuplicateCandidate candidate = candidates[i];
                if (candidate.Size < minFileSize) continue;

                List<DuplicateCandidate> sizeBucket;
                if (!sizeGroups.TryGetValue(candidate.Size, out sizeBucket))
                {
                    sizeBucket = new List<DuplicateCandidate>();
                    sizeGroups[candidate.Size] = sizeBucket;
                }

                sizeBucket.Add(candidate);
            }

            var sizeCandidates = new List<KeyValuePair<long, List<DuplicateCandidate>>>();
            foreach (var sizeGroup in sizeGroups)
            {
                var representativeCandidates = CollapseLinkedCandidates(sizeGroup.Value, sizeGroup.Key, linkedGroups);
                if (representativeCandidates.Count >= 2)
                {
                    sizeCandidates.Add(new KeyValuePair<long, List<DuplicateCandidate>>(sizeGroup.Key, representativeCandidates));
                }
            }

            int stage1Files = sizeCandidates.Sum(g => g.Value.Count);
            int stage1Groups = sizeCandidates.Count;
            result.LinkedGroups = linkedGroups.OrderByDescending(g => g.FileSize).ThenByDescending(g => g.Files.Count).ToList();

            sw.Stop();
            if (verbose) Console.WriteLine("  Stage 1 (size filter): {0:N0} files in {1:N0} groups | {2:N2}s",
                stage1Files, stage1Groups, sw.Elapsed.TotalSeconds);

            if (sizeCandidates.Count == 0) return result;

            // ============ STAGE 2: Quick sampled hash ============
            sw.Restart();
            var hashCandidates = new ConcurrentBag<KeyValuePair<long, List<DuplicateCandidate>>>();
            long hashErrors = 0;

            Parallel.ForEach(sizeCandidates, new ParallelOptions { MaxDegreeOfParallelism = Environment.ProcessorCount }, group =>
            {
                var hashGroups = new Dictionary<ulong, List<DuplicateCandidate>>();
                long fileSize = group.Key;

                foreach (DuplicateCandidate candidate in group.Value)
                {
                    try
                    {
                        ulong hash = ComputeQuickHash(candidate.Path, fileSize);

                        List<DuplicateCandidate> hashBucket;
                        if (!hashGroups.TryGetValue(hash, out hashBucket))
                        {
                            hashBucket = new List<DuplicateCandidate>();
                            hashGroups[hash] = hashBucket;
                        }

                        hashBucket.Add(candidate);
                    }
                    catch
                    {
                        Interlocked.Increment(ref hashErrors);
                    }
                }

                // Only keep groups with 2+ files (potential duplicates)
                foreach (var hg in hashGroups.Where(h => h.Value.Count >= 2))
                {
                    hashCandidates.Add(new KeyValuePair<long, List<DuplicateCandidate>>(fileSize, hg.Value));
                }
            });

            int stage2Files = hashCandidates.Sum(g => g.Value.Count);
            int stage2Groups = hashCandidates.Count;

            sw.Stop();
            if (verbose) Console.WriteLine("  Stage 2 (quick hash): {0:N0} files in {1:N0} groups, {2:N0} errors | {3:N2}s",
                stage2Files, stage2Groups, hashErrors, sw.Elapsed.TotalSeconds);

            if (hashCandidates.Count == 0) return result;

            // ============ STAGE 3: Full file hash comparison ============
            sw.Restart();
            var allDuplicateSets = new ConcurrentBag<DuplicateGroup>();
            long totalComparisons = 0;

            Parallel.ForEach(hashCandidates, new ParallelOptions { MaxDegreeOfParallelism = Math.Max(1, Environment.ProcessorCount / 2) }, group =>
            {
                var files = group.Value;
                long fileSize = group.Key;

                var duplicateSets = FindDuplicatesInGroup(files, fileSize, ref totalComparisons);
                foreach (var dupSet in duplicateSets)
                    allDuplicateSets.Add(dupSet);

                // Cleanup after large files
                if (MemoryManager.ShouldCleanup(fileSize))
                    MemoryManager.Cleanup();
            });

            foreach (var dupGroup in allDuplicateSets)
            {
                result.Groups.Add(dupGroup);
                result.TotalWastedSpace += dupGroup.WastedSpace;
                result.TotalDuplicateFiles += dupGroup.Files.Count;
            }

            result.Groups = result.Groups.OrderByDescending(g => g.WastedSpace).ToList();

            sw.Stop();
            totalSw.Stop();
            if (verbose)
            {
                Console.WriteLine("  Stage 3 (full hash): {0:N0} groups, {1:N0} comparisons | {2:N2}s",
                    result.Groups.Count, totalComparisons, sw.Elapsed.TotalSeconds);
                Console.WriteLine("  Duplicate scan total: {0:N2}s", totalSw.Elapsed.TotalSeconds);
            }

            // Final cleanup - release pooled buffers and force GC
            BufferPool.Clear();
            MemoryManager.ForceCleanup();

            return result;
        }

        private static List<DuplicateCandidate> CollapseLinkedCandidates(
            List<DuplicateCandidate> candidates,
            long fileSize,
            List<DuplicateGroup> linkedGroups)
        {
            var representativeCandidates = new List<DuplicateCandidate>(candidates.Count);
            var identityGroups = new Dictionary<string, List<DuplicateCandidate>>(StringComparer.OrdinalIgnoreCase);

            for (int i = 0; i < candidates.Count; i++)
            {
                DuplicateCandidate candidate = candidates[i];
                if (string.IsNullOrEmpty(candidate.FileIdentity))
                {
                    representativeCandidates.Add(candidate);
                    continue;
                }

                List<DuplicateCandidate> identityBucket;
                if (!identityGroups.TryGetValue(candidate.FileIdentity, out identityBucket))
                {
                    identityBucket = new List<DuplicateCandidate>();
                    identityGroups[candidate.FileIdentity] = identityBucket;
                }

                identityBucket.Add(candidate);
            }

            foreach (var identityGroup in identityGroups.Values)
            {
                representativeCandidates.Add(identityGroup[0]);

                if (identityGroup.Count >= 2)
                {
                    linkedGroups.Add(new DuplicateGroup
                    {
                        Hash = identityGroup[0].FileIdentity,
                        FileSize = fileSize,
                        Files = identityGroup.Select(c => c.Path).ToList(),
                        WastedSpace = 0,
                        IsLinkedGroup = true
                    });
                }
            }

            return representativeCandidates;
        }

        private static ulong ComputeQuickHash(string filePath, long fileSize)
        {
            byte[] buffer = BufferPool.RentSmall();

            try
            {
                using (var fs = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete, QUICK_HASH_SIZE, FileOptions.SequentialScan))
                {
                    if (fileSize <= QUICK_HASH_SIZE)
                    {
                        int bytesToRead = (int)Math.Min(fileSize, buffer.Length);
                        int bytesRead = fs.Read(buffer, 0, bytesToRead);
                        return XXHash64(buffer, bytesRead);
                    }

                    int writeOffset = 0;
                    var sampleOffsets = GetQuickHashSampleOffsets(fileSize);

                    for (int i = 0; i < sampleOffsets.Count; i++)
                    {
                        fs.Position = sampleOffsets[i];
                        int bytesRead = fs.Read(buffer, writeOffset, QUICK_SAMPLE_SIZE);
                        if (bytesRead <= 0) continue;
                        writeOffset += bytesRead;
                    }

                    return XXHash64(buffer, writeOffset);
                }
            }
            finally
            {
                BufferPool.Return(buffer);
            }
        }

        private static List<long> GetQuickHashSampleOffsets(long fileSize)
        {
            long maxOffset = Math.Max(0, fileSize - QUICK_SAMPLE_SIZE);
            var offsets = new List<long>(QUICK_SAMPLE_COUNT);

            AddQuickHashOffset(offsets, 0, maxOffset);
            AddQuickHashOffset(offsets, Math.Max(0, (fileSize / 3) - (QUICK_SAMPLE_SIZE / 2)), maxOffset);
            AddQuickHashOffset(offsets, Math.Max(0, ((fileSize * 2) / 3) - (QUICK_SAMPLE_SIZE / 2)), maxOffset);
            AddQuickHashOffset(offsets, maxOffset, maxOffset);

            return offsets;
        }

        private static void AddQuickHashOffset(List<long> offsets, long requestedOffset, long maxOffset)
        {
            long clampedOffset = Math.Max(0, Math.Min(requestedOffset, maxOffset));
            if (!offsets.Contains(clampedOffset))
                offsets.Add(clampedOffset);
        }

        private static ulong XXHash64(byte[] data, int length)
        {
            unchecked
            {
                ulong h64;
                int index = 0;

                if (length >= 32)
                {
                    ulong v1 = PRIME64_1 + PRIME64_2;
                    ulong v2 = PRIME64_2;
                    ulong v3 = 0;
                    ulong v4 = (ulong)-(long)PRIME64_1;

                    int limit = length - 32;
                    do
                    {
                        v1 = Round(v1, BitConverter.ToUInt64(data, index)); index += 8;
                        v2 = Round(v2, BitConverter.ToUInt64(data, index)); index += 8;
                        v3 = Round(v3, BitConverter.ToUInt64(data, index)); index += 8;
                        v4 = Round(v4, BitConverter.ToUInt64(data, index)); index += 8;
                    } while (index <= limit);

                    h64 = RotateLeft(v1, 1) + RotateLeft(v2, 7) + RotateLeft(v3, 12) + RotateLeft(v4, 18);
                    h64 = MergeRound(h64, v1);
                    h64 = MergeRound(h64, v2);
                    h64 = MergeRound(h64, v3);
                    h64 = MergeRound(h64, v4);
                }
                else
                {
                    h64 = PRIME64_5;
                }

                h64 += (ulong)length;

                // Process remaining bytes
                int remaining = length - index;
                while (remaining >= 8)
                {
                    h64 ^= Round(0, BitConverter.ToUInt64(data, index));
                    h64 = RotateLeft(h64, 27) * PRIME64_1 + PRIME64_4;
                    index += 8;
                    remaining -= 8;
                }
                while (remaining >= 4)
                {
                    h64 ^= BitConverter.ToUInt32(data, index) * PRIME64_1;
                    h64 = RotateLeft(h64, 23) * PRIME64_2 + PRIME64_3;
                    index += 4;
                    remaining -= 4;
                }
                while (remaining > 0)
                {
                    h64 ^= data[index] * PRIME64_5;
                    h64 = RotateLeft(h64, 11) * PRIME64_1;
                    index++;
                    remaining--;
                }

                // Final avalanche
                h64 ^= h64 >> 33;
                h64 *= PRIME64_2;
                h64 ^= h64 >> 29;
                h64 *= PRIME64_3;
                h64 ^= h64 >> 32;

                return h64;
            }
        }

        private static ulong Round(ulong acc, ulong input)
        {
            unchecked
            {
                acc += input * PRIME64_2;
                acc = RotateLeft(acc, 31);
                acc *= PRIME64_1;
                return acc;
            }
        }

        private static ulong MergeRound(ulong acc, ulong val)
        {
            unchecked
            {
                val = Round(0, val);
                acc ^= val;
                acc = acc * PRIME64_1 + PRIME64_4;
                return acc;
            }
        }

        private static ulong RotateLeft(ulong value, int count)
        {
            return (value << count) | (value >> (64 - count));
        }

        private static void ProcessStripe(ref ulong v1, ref ulong v2, ref ulong v3, ref ulong v4, byte[] data, int offset)
        {
            v1 = Round(v1, BitConverter.ToUInt64(data, offset));
            v2 = Round(v2, BitConverter.ToUInt64(data, offset + 8));
            v3 = Round(v3, BitConverter.ToUInt64(data, offset + 16));
            v4 = Round(v4, BitConverter.ToUInt64(data, offset + 24));
        }

        // Compute full file xxHash64 using streaming (256KB chunks)
        private static ulong ComputeFullHash(string filePath)
        {
            byte[] buffer = BufferPool.RentLarge();
            try
            {
                using (var fs = new FileStream(filePath, FileMode.Open, FileAccess.Read,
                       FileShare.ReadWrite | FileShare.Delete, 262144, FileOptions.SequentialScan))
                {
                    long fileLength = fs.Length;

                    // For files that fit in buffer, use direct hash
                    if (fileLength <= 262144)
                    {
                        int bytesRead = fs.Read(buffer, 0, (int)fileLength);
                        return XXHash64(buffer, bytesRead);
                    }

                    // For larger files, use streaming hash
                    unchecked
                    {
                        ulong v1 = PRIME64_1 + PRIME64_2;
                        ulong v2 = PRIME64_2;
                        ulong v3 = 0;
                        ulong v4 = (ulong)-(long)PRIME64_1;

                        int bytesRead;
                        long totalProcessed = 0;
                        byte[] tail = new byte[32];
                        int tailLen = 0;

                        while ((bytesRead = fs.Read(buffer, 0, 262144)) > 0)
                        {
                            int offset = 0;

                            // Complete a partial stripe carried over from the previous chunk.
                            if (tailLen > 0)
                            {
                                int bytesNeeded = 32 - tailLen;
                                int bytesToCopy = Math.Min(bytesNeeded, bytesRead);
                                Buffer.BlockCopy(buffer, 0, tail, tailLen, bytesToCopy);
                                tailLen += bytesToCopy;
                                offset += bytesToCopy;

                                if (tailLen == 32)
                                {
                                    ProcessStripe(ref v1, ref v2, ref v3, ref v4, tail, 0);
                                    totalProcessed += 32;
                                    tailLen = 0;
                                }
                            }

                            // Process complete 32-byte blocks
                            while (offset + 32 <= bytesRead)
                            {
                                ProcessStripe(ref v1, ref v2, ref v3, ref v4, buffer, offset);
                                offset += 32;
                                totalProcessed += 32;
                            }

                            // Save remainder for next iteration
                            if (offset < bytesRead)
                            {
                                tailLen = bytesRead - offset;
                                Buffer.BlockCopy(buffer, offset, tail, 0, tailLen);
                            }
                        }

                        // Finalize
                        ulong h64;
                        if (totalProcessed >= 32)
                        {
                            h64 = RotateLeft(v1, 1) + RotateLeft(v2, 7) + RotateLeft(v3, 12) + RotateLeft(v4, 18);
                            h64 = MergeRound(h64, v1);
                            h64 = MergeRound(h64, v2);
                            h64 = MergeRound(h64, v3);
                            h64 = MergeRound(h64, v4);
                        }
                        else
                        {
                            h64 = PRIME64_5;
                        }

                        h64 += (ulong)fileLength;

                        // Process remaining bytes
                        if (tailLen > 0)
                        {
                            int idx = 0;
                            while (tailLen - idx >= 8)
                            {
                                h64 ^= Round(0, BitConverter.ToUInt64(tail, idx));
                                h64 = RotateLeft(h64, 27) * PRIME64_1 + PRIME64_4;
                                idx += 8;
                            }
                            while (tailLen - idx >= 4)
                            {
                                h64 ^= BitConverter.ToUInt32(tail, idx) * PRIME64_1;
                                h64 = RotateLeft(h64, 23) * PRIME64_2 + PRIME64_3;
                                idx += 4;
                            }
                            while (idx < tailLen)
                            {
                                h64 ^= tail[idx] * PRIME64_5;
                                h64 = RotateLeft(h64, 11) * PRIME64_1;
                                idx++;
                            }
                        }

                        // Final avalanche
                        h64 ^= h64 >> 33;
                        h64 *= PRIME64_2;
                        h64 ^= h64 >> 29;
                        h64 *= PRIME64_3;
                        h64 ^= h64 >> 32;

                        return h64;
                    }
                }
            }
            finally
            {
                BufferPool.Return(buffer);
            }
        }

        private static List<DuplicateGroup> FindDuplicatesInGroup(
            List<DuplicateCandidate> candidates,
            long fileSize,
            ref long totalComparisons)
        {
            var duplicateGroups = new List<DuplicateGroup>();
            var processed = new HashSet<int>();

            // Pre-compute hashes for all files in the group (more efficient)
            var fileHashes = new Dictionary<int, ulong>();
            for (int i = 0; i < candidates.Count; i++)
            {
                try
                {
                    fileHashes[i] = ComputeFullHash(candidates[i].Path);
                }
                catch
                {
                    // Skip files we can't read
                }
            }

            for (int i = 0; i < candidates.Count; i++)
            {
                if (processed.Contains(i)) continue;
                if (!fileHashes.ContainsKey(i)) continue;

                var currentSet = new List<string> { candidates[i].Path };

                for (int j = i + 1; j < candidates.Count; j++)
                {
                    if (processed.Contains(j)) continue;
                    if (!fileHashes.ContainsKey(j)) continue;

                    Interlocked.Increment(ref totalComparisons);

                    // Compare hashes (instant - no disk I/O)
                    if (fileHashes[i] == fileHashes[j])
                    {
                        currentSet.Add(candidates[j].Path);
                        processed.Add(j);
                    }
                }

                if (currentSet.Count > 1)
                {
                    duplicateGroups.Add(new DuplicateGroup
                    {
                        Hash = fileHashes[i].ToString("X16"),
                        FileSize = fileSize,
                        Files = currentSet,
                        WastedSpace = (currentSet.Count - 1) * fileSize
                    });
                }
                processed.Add(i);
            }

            return duplicateGroups;
        }
    }

    public class MftScanner
    {
        private const uint GENERIC_READ = 0x80000000;
        private const uint FILE_SHARE_READ = 0x00000001;
        private const uint FILE_SHARE_WRITE = 0x00000002;
        private const uint FILE_SHARE_DELETE = 0x00000004;
        private const uint OPEN_EXISTING = 3;
        private const uint FSCTL_ENUM_USN_DATA = 0x000900B3;
        private const uint FSCTL_QUERY_USN_JOURNAL = 0x000900F4;
        private const int ERROR_HANDLE_EOF = 38;
        private const int MFT_ROOT_REFERENCE = 5;
        private const int MAX_PATH_DEPTH = 100;
        private const int MFT_BUFFER_SIZE = 256 * 1024;

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        private static extern SafeFileHandle CreateFile(string lpFileName, uint dwDesiredAccess, uint dwShareMode, IntPtr lpSecurityAttributes, uint dwCreationDisposition, uint dwFlagsAndAttributes, IntPtr hTemplateFile);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool DeviceIoControl(SafeFileHandle hDevice, uint dwIoControlCode, IntPtr lpInBuffer, int nInBufferSize, IntPtr lpOutBuffer, int nOutBufferSize, out int lpBytesReturned, IntPtr lpOverlapped);

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        private static extern uint GetCompressedFileSize(string lpFileName, out uint lpFileSizeHigh);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetFileInformationByHandle(SafeFileHandle hFile, out BY_HANDLE_FILE_INFORMATION lpFileInformation);

        [StructLayout(LayoutKind.Sequential)]
        private struct USN_JOURNAL_DATA { public ulong UsnJournalID; public long FirstUsn; public long NextUsn; public long LowestValidUsn; public long MaxUsn; public ulong MaximumSize; public ulong AllocationDelta; }

        [StructLayout(LayoutKind.Sequential)]
        private struct MFT_ENUM_DATA_V0 { public ulong StartFileReferenceNumber; public long LowUsn; public long HighUsn; }

        [StructLayout(LayoutKind.Sequential)]
        private struct BY_HANDLE_FILE_INFORMATION
        {
            public uint FileAttributes;
            public System.Runtime.InteropServices.ComTypes.FILETIME CreationTime;
            public System.Runtime.InteropServices.ComTypes.FILETIME LastAccessTime;
            public System.Runtime.InteropServices.ComTypes.FILETIME LastWriteTime;
            public uint VolumeSerialNumber;
            public uint FileSizeHigh;
            public uint FileSizeLow;
            public uint NumberOfLinks;
            public uint FileIndexHigh;
            public uint FileIndexLow;
        }

        private struct MftEntry
        {
            public ulong FileRef;
            public ulong ParentRef;
            public string FileName;
            public bool IsDirectory;
            public long TimeStamp;
        }

        // Cleanup patterns - now passed from PowerShell via categories parameter
        public static ScanResult ScanWithAnalysis(
            string driveLetter,
            int maxDepth,
            int topN,
            bool includeFiles,
            bool verbose,
            bool findDuplicates,
            long minDuplicateSize,
            long largeFileThreshold,
            long cleanupMinSize,
            string[][] categoryPatterns,
            string[] categoryNames)
        {
            var result = new ScanResult
            {
                Items = new List<FolderResult>(),
                FileTypes = new List<FileTypeInfo>(),
                CleanupSuggestions = new List<CleanupSuggestion>(),
                Duplicates = new DuplicateResult()
            };

            driveLetter = driveLetter.TrimEnd(':');
            string volumePath = @"\\.\" + driveLetter + ":";
            string rootPath = driveLetter + ":\\";

            DriveInfo driveInfo = new DriveInfo(driveLetter);
            result.TotalDriveSize = driveInfo.TotalSize;
            result.TotalFreeSpace = driveInfo.TotalFreeSpace;
            result.TotalUsedSpace = driveInfo.TotalSize - driveInfo.TotalFreeSpace;

            var totalSw = Stopwatch.StartNew();

            if (!driveInfo.DriveFormat.Equals("NTFS", StringComparison.OrdinalIgnoreCase))
            {
                if (verbose) Console.WriteLine("Drive is not NTFS, using fallback");
                var fallbackResult = ScanFallback(driveLetter, maxDepth, topN, includeFiles, verbose, findDuplicates, minDuplicateSize, largeFileThreshold, cleanupMinSize, categoryPatterns, categoryNames);
                fallbackResult.TotalDriveSize = result.TotalDriveSize;
                fallbackResult.TotalFreeSpace = result.TotalFreeSpace;
                fallbackResult.TotalUsedSpace = result.TotalUsedSpace;
                return fallbackResult;
            }

            using (SafeFileHandle volumeHandle = CreateFile(volumePath, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero))
            {
                if (volumeHandle.IsInvalid)
                {
                    if (verbose) Console.WriteLine("Cannot open volume (need admin), using fallback");
                    var fallbackResult = ScanFallback(driveLetter, maxDepth, topN, includeFiles, verbose, findDuplicates, minDuplicateSize, largeFileThreshold, cleanupMinSize, categoryPatterns, categoryNames);
                    fallbackResult.TotalDriveSize = result.TotalDriveSize;
                    fallbackResult.TotalFreeSpace = result.TotalFreeSpace;
                    fallbackResult.TotalUsedSpace = result.TotalUsedSpace;
                    return fallbackResult;
                }

                IntPtr journalDataPtr = Marshal.AllocHGlobal(64);
                int bytesReturned;
                bool success = DeviceIoControl(volumeHandle, FSCTL_QUERY_USN_JOURNAL, IntPtr.Zero, 0, journalDataPtr, 64, out bytesReturned, IntPtr.Zero);

                if (!success)
                {
                    Marshal.FreeHGlobal(journalDataPtr);
                    if (verbose) Console.WriteLine("USN Journal not available, using fallback");
                    var fallbackResult = ScanFallback(driveLetter, maxDepth, topN, includeFiles, verbose, findDuplicates, minDuplicateSize, largeFileThreshold, cleanupMinSize, categoryPatterns, categoryNames);
                    fallbackResult.TotalDriveSize = result.TotalDriveSize;
                    fallbackResult.TotalFreeSpace = result.TotalFreeSpace;
                    fallbackResult.TotalUsedSpace = result.TotalUsedSpace;
                    return fallbackResult;
                }

                USN_JOURNAL_DATA journalData = (USN_JOURNAL_DATA)Marshal.PtrToStructure(journalDataPtr, typeof(USN_JOURNAL_DATA));
                Marshal.FreeHGlobal(journalDataPtr);

                // MFT Enumeration
                var sw = Stopwatch.StartNew();
                var fileMap = new Dictionary<ulong, MftEntry>(2000000);

                IntPtr buffer = Marshal.AllocHGlobal(MFT_BUFFER_SIZE);
                IntPtr enumDataPtr = Marshal.AllocHGlobal(24);

                try
                {
                    MFT_ENUM_DATA_V0 enumData = new MFT_ENUM_DATA_V0 { StartFileReferenceNumber = 0, LowUsn = 0, HighUsn = journalData.NextUsn };
                    Marshal.StructureToPtr(enumData, enumDataPtr, false);

                    while (true)
                    {
                        success = DeviceIoControl(volumeHandle, FSCTL_ENUM_USN_DATA, enumDataPtr, 24, buffer, MFT_BUFFER_SIZE, out bytesReturned, IntPtr.Zero);
                        if (!success) { if (Marshal.GetLastWin32Error() == ERROR_HANDLE_EOF) break; else break; }
                        if (bytesReturned <= 8) break;

                        ulong nextStartRef = (ulong)Marshal.ReadInt64(buffer);
                        int offset = 8;

                        while (offset < bytesReturned)
                        {
                            int recordLength = Marshal.ReadInt32(buffer, offset);
                            if (recordLength == 0) break;

                            ulong fileRef = (ulong)Marshal.ReadInt64(buffer, offset + 8) & 0x0000FFFFFFFFFFFF;
                            ulong parentRef = (ulong)Marshal.ReadInt64(buffer, offset + 16) & 0x0000FFFFFFFFFFFF;
                            long timeStamp = Marshal.ReadInt64(buffer, offset + 32);
                            uint fileAttributes = (uint)Marshal.ReadInt32(buffer, offset + 52);
                            short fileNameLength = Marshal.ReadInt16(buffer, offset + 56);
                            short fileNameOffset = Marshal.ReadInt16(buffer, offset + 58);
                            string fileName = Marshal.PtrToStringUni(IntPtr.Add(buffer, offset + fileNameOffset), fileNameLength / 2);

                            fileMap[fileRef] = new MftEntry { FileRef = fileRef, ParentRef = parentRef, FileName = fileName, IsDirectory = (fileAttributes & 0x10) != 0, TimeStamp = timeStamp };
                            offset += recordLength;
                        }

                        enumData.StartFileReferenceNumber = nextStartRef;
                        Marshal.StructureToPtr(enumData, enumDataPtr, false);
                    }
                }
                finally
                {
                    Marshal.FreeHGlobal(buffer);
                    Marshal.FreeHGlobal(enumDataPtr);
                }

                sw.Stop();
                if (verbose) Console.WriteLine("MFT enumeration: {0:N2}s ({1:N0} entries)", sw.Elapsed.TotalSeconds, fileMap.Count);

                // Build paths for directories
                sw.Restart();
                var pathCache = new Dictionary<ulong, string>(500000);
                pathCache[MFT_ROOT_REFERENCE] = rootPath;

                foreach (var entry in fileMap.Values)
                {
                    if (entry.IsDirectory)
                        GetFullPath(entry.FileRef, fileMap, pathCache, rootPath);
                }

                sw.Stop();
                if (verbose) Console.WriteLine("Directory paths: {0:N2}s ({1:N0} dirs)", sw.Elapsed.TotalSeconds, pathCache.Count);

                // Parallel size retrieval
                sw.Restart();
                var files = fileMap.Values.Where(e => !e.IsDirectory).ToArray();

                var folderSizesByRef = new ConcurrentDictionary<ulong, long>();
                var largeFiles = new ConcurrentBag<FolderResult>();
                var fileTypeSizes = new ConcurrentDictionary<string, long>();
                var fileTypeCounts = new ConcurrentDictionary<string, int>();

                var allDuplicateCandidates = findDuplicates ? new ConcurrentBag<DuplicateCandidate>() : null;

                // Dynamic cleanup tracking based on categories
                var categorySizes = new ConcurrentDictionary<string, long>();
                foreach (var name in categoryNames)
                    categorySizes[name] = 0;

                long errorCount = 0;

                Parallel.ForEach(files, new ParallelOptions { MaxDegreeOfParallelism = Environment.ProcessorCount }, entry =>
                {
                    string path = GetFullPathForFile(entry, fileMap, pathCache, rootPath);
                    if (path == null) return;

                    long size = 0;
                    try
                    {
                        uint high;
                        uint low = GetCompressedFileSize(path, out high);
                        if (low != 0xFFFFFFFF || Marshal.GetLastWin32Error() == 0)
                            size = ((long)high << 32) + low;
                        else
                        {
                            Interlocked.Increment(ref errorCount);
                            return;
                        }
                    }
                    catch
                    {
                        Interlocked.Increment(ref errorCount);
                        return;
                    }

                    if (findDuplicates && size >= minDuplicateSize)
                    {
                        var duplicateCandidate = new DuplicateCandidate { Path = path, Size = size };
                        PopulateFileIdentity(path, duplicateCandidate);
                        allDuplicateCandidates.Add(duplicateCandidate);
                    }

                    string ext = Path.GetExtension(entry.FileName);
                    if (!string.IsNullOrEmpty(ext))
                    {
                        ext = ext.ToLowerInvariant();
                        fileTypeSizes.AddOrUpdate(ext, size, (k, v) => v + size);
                        fileTypeCounts.AddOrUpdate(ext, 1, (k, v) => v + 1);
                    }

                    // Track cleanup categories
                    for (int c = 0; c < categoryPatterns.Length; c++)
                    {
                        if (ContainsAny(path, categoryPatterns[c]))
                        {
                            categorySizes.AddOrUpdate(categoryNames[c], size, (k, v) => v + size);
                            break;
                        }
                    }

                    if (includeFiles && size >= largeFileThreshold)
                    {
                        DateTime lastMod = DateTime.MinValue;
                        try { lastMod = File.GetLastWriteTime(path); } catch { }
                        largeFiles.Add(new FolderResult { Path = path, Size = size, IsDirectory = false, LastModified = lastMod });
                    }

                    ulong parentRef = entry.ParentRef;
                    int depth = 0;
                    while (parentRef >= MFT_ROOT_REFERENCE && depth < MAX_PATH_DEPTH)
                    {
                        folderSizesByRef.AddOrUpdate(parentRef, size, (k, v) => v + size);

                        MftEntry parentEntry;
                        if (!fileMap.TryGetValue(parentRef, out parentEntry)) break;
                        if (parentEntry.ParentRef == MFT_ROOT_REFERENCE && parentRef == MFT_ROOT_REFERENCE) break;
                        if (parentEntry.ParentRef == parentRef) break;

                        parentRef = parentEntry.ParentRef;
                        depth++;
                    }
                });

                sw.Stop();
                if (verbose) Console.WriteLine("Size + aggregation: {0:N2}s ({1:N0} files, {2:N0} errors)", sw.Elapsed.TotalSeconds, files.Length, errorCount);

                // Duplicate detection
                if (findDuplicates && allDuplicateCandidates != null && allDuplicateCandidates.Count > 0)
                {
                    sw.Restart();
                    if (verbose) Console.WriteLine("Duplicate detection: {0:N0} files >= {1} bytes", allDuplicateCandidates.Count, minDuplicateSize);

                    var candidatesArray = allDuplicateCandidates.ToArray();
                    result.Duplicates = DuplicateFinder.FindDuplicates(candidatesArray, minDuplicateSize, verbose);

                    sw.Stop();
                    if (verbose) Console.WriteLine("Duplicate scan complete: {0:N0} groups, {1} bytes wasted | {2:N2}s",
                        result.Duplicates.Groups.Count, result.Duplicates.TotalWastedSpace, sw.Elapsed.TotalSeconds);
                }

                // Build file type results
                result.FileTypes = fileTypeSizes
                    .Select(kvp => new FileTypeInfo { Extension = kvp.Key, TotalSize = kvp.Value, FileCount = fileTypeCounts.GetOrAdd(kvp.Key, 0) })
                    .OrderByDescending(f => f.TotalSize)
                    .Take(15)
                    .ToList();

                // Build cleanup suggestions from tracked categories
                foreach (var kvp in categorySizes)
                {
                    if (kvp.Value > cleanupMinSize)
                    {
                        result.CleanupSuggestions.Add(new CleanupSuggestion
                        {
                            Path = kvp.Key,
                            Category = kvp.Key,
                            Size = kvp.Value,
                            Description = ""
                        });
                    }
                }
                result.CleanupSuggestions = result.CleanupSuggestions.OrderByDescending(c => c.Size).ToList();

                // Convert folder refs to paths
                sw.Restart();
                var items = new List<FolderResult>();

                foreach (var kvp in folderSizesByRef)
                {
                    ulong folderRef = kvp.Key;
                    long size = kvp.Value;

                    string folderPath;
                    if (!pathCache.TryGetValue(folderRef, out folderPath))
                        folderPath = GetFullPath(folderRef, fileMap, pathCache, rootPath);

                    if (folderPath == null) continue;

                    int pathDepth = GetPathDepth(folderPath);
                    if (pathDepth <= maxDepth)
                    {
                        DateTime folderLastMod = DateTime.MinValue;
                        try { folderLastMod = Directory.GetLastWriteTime(folderPath); } catch { }
                        items.Add(new FolderResult { Path = NormalizePath(folderPath), Size = size, IsDirectory = true, LastModified = folderLastMod });
                    }
                }

                if (includeFiles)
                    items.AddRange(largeFiles);

                result.Items = items.OrderByDescending(r => r.Size).Take(topN).ToList();
                result.ErrorCount = errorCount;
                result.TotalFiles = files.Length;
                result.TotalFolders = pathCache.Count;

                sw.Stop();
                totalSw.Stop();
                if (verbose) Console.WriteLine("Results: {0:N2}s | TOTAL: {1:N2}s", sw.Elapsed.TotalSeconds, totalSw.Elapsed.TotalSeconds);
            }

            return result;
        }

        private static bool ContainsAny(string path, string[] patterns)
        {
            foreach (var pattern in patterns)
            {
                if (path.IndexOf(pattern, StringComparison.OrdinalIgnoreCase) >= 0)
                    return true;
            }
            return false;
        }

        private static string NormalizePath(string path)
        {
            if (string.IsNullOrEmpty(path)) return path;
            if (path.Length == 3 && path[1] == ':' && path[2] == '\\') return path;
            return path.TrimEnd('\\');
        }

        private static int GetPathDepth(string path)
        {
            if (string.IsNullOrEmpty(path)) return 0;
            int count = 0;
            for (int i = 0; i < path.Length; i++)
                if (path[i] == '\\') count++;
            return count;
        }

        private static string GetFullPathForFile(MftEntry entry, Dictionary<ulong, MftEntry> fileMap, Dictionary<ulong, string> pathCache, string rootPath)
        {
            string parentPath;
            if (!pathCache.TryGetValue(entry.ParentRef, out parentPath))
                parentPath = GetFullPath(entry.ParentRef, fileMap, pathCache, rootPath);
            if (parentPath == null) return null;
            return Path.Combine(parentPath, entry.FileName);
        }

        private static string GetFullPath(ulong fileRef, Dictionary<ulong, MftEntry> fileMap, Dictionary<ulong, string> pathCache, string rootPath)
        {
            string cached;
            if (pathCache.TryGetValue(fileRef, out cached)) return cached;

            MftEntry entry;
            if (!fileMap.TryGetValue(fileRef, out entry)) return null;

            if (entry.ParentRef == MFT_ROOT_REFERENCE || entry.FileRef == MFT_ROOT_REFERENCE)
            {
                string path = entry.FileRef == MFT_ROOT_REFERENCE ? rootPath : rootPath + entry.FileName;
                pathCache[fileRef] = path;
                return path;
            }
            if (entry.ParentRef < MFT_ROOT_REFERENCE) return null;

            string parentPath = GetFullPath(entry.ParentRef, fileMap, pathCache, rootPath);
            if (parentPath == null) return null;

            string fullPath = Path.Combine(parentPath, entry.FileName);
            pathCache[fileRef] = fullPath;
            return fullPath;
        }

        private static ScanResult ScanFallback(
            string driveLetter,
            int maxDepth,
            int topN,
            bool includeFiles,
            bool verbose,
            bool findDuplicates,
            long minDuplicateSize,
            long largeFileThreshold,
            long cleanupMinSize,
            string[][] categoryPatterns,
            string[] categoryNames)
        {
            var result = new ScanResult
            {
                Items = new List<FolderResult>(),
                FileTypes = new List<FileTypeInfo>(),
                CleanupSuggestions = new List<CleanupSuggestion>(),
                Duplicates = new DuplicateResult()
            };

            var context = new FallbackScanContext
            {
                Items = new ConcurrentBag<FolderResult>(),
                FileTypeSizes = new ConcurrentDictionary<string, long>(),
                FileTypeCounts = new ConcurrentDictionary<string, int>(),
                DuplicateCandidates = findDuplicates ? new ConcurrentBag<DuplicateCandidate>() : null,
                CategorySizes = new ConcurrentDictionary<string, long>()
            };

            foreach (var name in categoryNames)
                context.CategorySizes[name] = 0;

            var rootDir = new DirectoryInfo(driveLetter + ":\\");
            ScanDirectoryFallback(rootDir, 0, maxDepth, includeFiles, findDuplicates, minDuplicateSize, largeFileThreshold, context, categoryPatterns, categoryNames, verbose);

            if (findDuplicates && context.DuplicateCandidates != null && context.DuplicateCandidates.Count > 0)
            {
                if (verbose) Console.WriteLine("Fallback duplicate detection: {0:N0} files >= {1} bytes", context.DuplicateCandidates.Count, minDuplicateSize);
                result.Duplicates = DuplicateFinder.FindDuplicates(context.DuplicateCandidates.ToArray(), minDuplicateSize, verbose);
            }

            result.FileTypes = context.FileTypeSizes
                .Select(kvp => new FileTypeInfo { Extension = kvp.Key, TotalSize = kvp.Value, FileCount = context.FileTypeCounts.GetOrAdd(kvp.Key, 0) })
                .OrderByDescending(f => f.TotalSize)
                .Take(15)
                .ToList();

            foreach (var kvp in context.CategorySizes)
            {
                if (kvp.Value > cleanupMinSize)
                {
                    result.CleanupSuggestions.Add(new CleanupSuggestion
                    {
                        Path = kvp.Key,
                        Category = kvp.Key,
                        Size = kvp.Value,
                        Description = ""
                    });
                }
            }
            result.CleanupSuggestions = result.CleanupSuggestions.OrderByDescending(c => c.Size).ToList();

            result.Items = context.Items.OrderByDescending(r => r.Size).Take(topN).ToList();
            result.ErrorCount = context.ErrorCount;
            result.TotalFiles = context.TotalFiles;
            result.TotalFolders = context.TotalFolders;

            return result;
        }

        private static long ScanDirectoryFallback(
            DirectoryInfo dir,
            int depth,
            int maxDepth,
            bool includeFiles,
            bool findDuplicates,
            long minDuplicateSize,
            long largeFileThreshold,
            FallbackScanContext context,
            string[][] categoryPatterns,
            string[] categoryNames,
            bool verbose)
        {
            long totalSize = 0;
            try
            {
                Interlocked.Increment(ref context.TotalFolders);

                foreach (var file in dir.EnumerateFiles())
                {
                    try
                    {
                        uint high;
                        uint low = GetCompressedFileSize(file.FullName, out high);
                        long size = ((long)high << 32) + low;
                        totalSize += size;
                        Interlocked.Increment(ref context.TotalFiles);

                        if (findDuplicates && context.DuplicateCandidates != null && size >= minDuplicateSize)
                        {
                            var duplicateCandidate = new DuplicateCandidate { Path = file.FullName, Size = size };
                            PopulateFileIdentity(file.FullName, duplicateCandidate);
                            context.DuplicateCandidates.Add(duplicateCandidate);
                        }

                        string ext = Path.GetExtension(file.Name);
                        if (!string.IsNullOrEmpty(ext))
                        {
                            ext = ext.ToLowerInvariant();
                            context.FileTypeSizes.AddOrUpdate(ext, size, (k, v) => v + size);
                            context.FileTypeCounts.AddOrUpdate(ext, 1, (k, v) => v + 1);
                        }

                        for (int c = 0; c < categoryPatterns.Length; c++)
                        {
                            if (ContainsAny(file.FullName, categoryPatterns[c]))
                            {
                                context.CategorySizes.AddOrUpdate(categoryNames[c], size, (k, v) => v + size);
                                break;
                            }
                        }

                        if (includeFiles && size >= largeFileThreshold)
                        {
                            DateTime lastMod = DateTime.MinValue;
                            try { lastMod = file.LastWriteTime; } catch { }
                            context.Items.Add(new FolderResult { Path = file.FullName, Size = size, IsDirectory = false, LastModified = lastMod });
                        }
                    }
                    catch
                    {
                        Interlocked.Increment(ref context.ErrorCount);
                    }
                }

                var subDirs = dir.EnumerateDirectories().ToArray();
                var subSizes = new long[subDirs.Length];
                Parallel.For(0, subDirs.Length, i => {
                    try
                    {
                        subSizes[i] = ScanDirectoryFallback(subDirs[i], depth + 1, maxDepth, includeFiles, findDuplicates, minDuplicateSize, largeFileThreshold, context, categoryPatterns, categoryNames, verbose);
                    }
                    catch
                    {
                        Interlocked.Increment(ref context.ErrorCount);
                    }
                });
                totalSize += subSizes.Sum();

                if (depth <= maxDepth)
                {
                    DateTime lastMod = DateTime.MinValue;
                    try { lastMod = dir.LastWriteTime; } catch { }
                    context.Items.Add(new FolderResult { Path = NormalizePath(dir.FullName), Size = totalSize, IsDirectory = true, LastModified = lastMod });
                }
            }
            catch
            {
                Interlocked.Increment(ref context.ErrorCount);
            }
            return totalSize;
        }

        private static void PopulateFileIdentity(string path, DuplicateCandidate candidate)
        {
            try
            {
                using (SafeFileHandle fileHandle = CreateFile(path, 0, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero))
                {
                    if (fileHandle.IsInvalid) return;

                    BY_HANDLE_FILE_INFORMATION fileInfo;
                    if (!GetFileInformationByHandle(fileHandle, out fileInfo)) return;

                    candidate.LinkCount = (int)fileInfo.NumberOfLinks;
                    if (fileInfo.FileIndexHigh == 0 && fileInfo.FileIndexLow == 0) return;

                    candidate.FileIdentity = string.Format(
                        System.Globalization.CultureInfo.InvariantCulture,
                        "{0:X8}:{1:X8}{2:X8}",
                        fileInfo.VolumeSerialNumber,
                        fileInfo.FileIndexHigh,
                        fileInfo.FileIndexLow);
                }
            }
            catch
            {
                // Best-effort only; duplicate detection can continue without identity metadata.
            }
        }
    }
}
"@
}
