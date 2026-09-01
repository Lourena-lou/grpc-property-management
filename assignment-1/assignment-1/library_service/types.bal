// ----------------------------------------------------------------------------
// ENUMS
// The brief names exactly four asset states. Using an `enum` instead of a bare
// `string` means an invalid status is a COMPILE error, not a runtime surprise.
// An enum in Ballerina is shorthand for a union of string constants, so these
// still serialise to plain JSON strings like "AVAILABLE".
// ----------------------------------------------------------------------------

# Lifecycle state of a library resource.
public enum AssetStatus {
    AVAILABLE,
    LOANED_OUT,
    OCCUPIED,
    UNDER_MAINTENANCE,
    DISPOSED
}

# Category of a planned event against an asset.
public enum ScheduleType {
    MAINTENANCE,
    SERVICING,
    BOOKING
}

# Lifecycle state of a repair job.
public enum WorkOrderStatus {
    OPEN,
    IN_PROGRESS,
    CLOSED
}