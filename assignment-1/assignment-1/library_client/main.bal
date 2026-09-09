// ----------------------------------------------------------------------------
// VIEW 4 — OVERDUE DASHBOARD
// ----------------------------------------------------------------------------

# Shows assets whose maintenance schedules have lapsed.
function overdueDashboard() {
    header("OVERDUE DASHBOARD - Items past their due date");
    Asset[]|error assets = libraryClient->/assets/overdue;
    if assets is error {
        reportError(assets);
        return;
    }
    if assets.length() == 0 {
        io:println("  Nothing overdue.");
        return;
    }
    foreach Asset a in assets {
        printAssetDetail(a);
        io:println("");
    }
    io:println(string `  ${assets.length()} asset(s) need attention.`);
}

// ----------------------------------------------------------------------------
// VIEW 5 — SCHEDULE MANAGER
// ----------------------------------------------------------------------------

# Adds, updates, or removes servicing schedules on an asset.
function scheduleManager() {
    header("SCHEDULE MANAGER");

    string tag = io:readln("  Asset tag: ").trim();
    Asset|error asset = libraryClient->/assets/[tag];
    if asset is error {
        reportError(asset);
        return;
    }

    io:println(string `${"\n"}  ${asset.name}`);
    if asset.schedules.length() == 0 {
        io:println("  No schedules yet.");
    } else {
        io:println("  Existing schedules:");
        foreach Schedule s in asset.schedules {
            io:println(string `    [${s.scheduleId}] ${s.'type} due ${s.dueDate} - ${s.description}`);
        }
    }

    io:println("\n  1) Add a schedule");
    io:println("  2) Update a schedule");
    io:println("  3) Remove a schedule");
    string choice = io:readln("  Choose: ").trim();

    if choice == "3" {
        string scheduleId = io:readln("  Schedule ID to remove: ").trim();
        Schedule|error removed = libraryClient->/assets/[tag]/schedules/[scheduleId].delete();
        if removed is error {
            reportError(removed);
            return;
        }
        io:println(string `  Removed '${removed.scheduleId}'.`);
        return;
    }

    if choice != "1" && choice != "2" {
        io:println("  Unknown choice.");
        return;
    }

    string scheduleId = io:readln("  Schedule ID: ").trim();
    string typeInput = io:readln("  Type (MAINTENANCE / SERVICING / BOOKING): ").trim();
    if typeInput !is ScheduleType {
        io:println("  Invalid type.");
        return;
    }
    string dueDate = io:readln("  Due date (YYYY-MM-DD): ").trim();
    string description = io:readln("  Description: ").trim();

    Schedule schedule = {
        scheduleId: scheduleId,
        'type: typeInput,
        dueDate: dueDate,
        description: description
    };

    Schedule|error result;
    if choice == "1" {
        result = libraryClient->/assets/[tag]/schedules.post(schedule);
    } else {
        result = libraryClient->/assets/[tag]/schedules/[scheduleId].put(schedule);
    }

    if result is error {
        reportError(result);
        return;
    }
    io:println(string `  Saved schedule '${result.scheduleId}'.`);
}