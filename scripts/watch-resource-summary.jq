def nonnegative: type == "number" and . >= 0;
def logical_bytes: [.files[].logicalBytes] | add // 0;
def allocated_bytes:
    if all(.files[]; .allocatedBytes != null) then [.files[].allocatedBytes] | add // 0 else null end;

if type != "array" or length < 2 then error("At least two measured samples are required") else . end
| if all(.[];
    (.phase | type == "string" and length > 0)
    and (.systemUptimeSeconds | nonnegative) and (.processCPUSeconds | nonnegative)
    and (.voluntaryContextSwitches | nonnegative) and (.involuntaryContextSwitches | nonnegative)
    and (.pendingCount | nonnegative) and (.quarantineCount | nonnegative)
    and (.acknowledgementCount | nonnegative) and (.receiptCount | nonnegative)
    and (.outboxPayloadBytes | nonnegative)
    and (.files | type == "array" and length > 0)
    and all(.files[]; (.name | type == "string") and (.logicalBytes | nonnegative)
        and (.allocatedBytes == null or (.allocatedBytes | nonnegative)))
) then . else error("Incomplete or invalid measurement") end
| . as $samples
| if all(range(1; length); . as $i |
    $samples[$i].systemUptimeSeconds >= $samples[$i - 1].systemUptimeSeconds
    and $samples[$i].processCPUSeconds >= $samples[$i - 1].processCPUSeconds
    and $samples[$i].voluntaryContextSwitches >= $samples[$i - 1].voluntaryContextSwitches
    and $samples[$i].involuntaryContextSwitches >= $samples[$i - 1].involuntaryContextSwitches
) then . else error("Cumulative process counters decreased") end
| {
    test: $test, sampleCount: length,
    wallSecondsBetweenSamples: (.[-1].systemUptimeSeconds - .[0].systemUptimeSeconds),
    testHostCPUSecondsBetweenSamples: (.[-1].processCPUSeconds - .[0].processCPUSeconds),
    voluntaryContextSwitchesBetweenSamples: (.[-1].voluntaryContextSwitches - .[0].voluntaryContextSwitches),
    involuntaryContextSwitchesBetweenSamples: (.[-1].involuntaryContextSwitches - .[0].involuntaryContextSwitches),
    peakObservedLogicalStoreBytes: ([.[] | logical_bytes] | max),
    finalObservedLogicalStoreBytes: (.[-1] | logical_bytes),
    peakObservedAllocatedStoreBytes: (if all(.[]; allocated_bytes != null) then [.[] | allocated_bytes] | max else null end),
    finalObservedAllocatedStoreBytes: (.[-1] | allocated_bytes),
    peakOutboxCount: ([.[].pendingCount] | max), finalOutboxCount: .[-1].pendingCount,
    peakOutboxPayloadBytes: ([.[].outboxPayloadBytes] | max), finalOutboxPayloadBytes: .[-1].outboxPayloadBytes,
    finalAcknowledgementCount: .[-1].acknowledgementCount,
    finalQuarantineCount: .[-1].quarantineCount, finalReceiptCount: .[-1].receiptCount,
    samples: .
}
