// ============================================================================
// service_test.bal — Tests for the library service.
//
// `bal test` starts the service automatically, runs these against it, then
// stops it. See https://ballerina.io/learn/test-ballerina-code/write-tests/
//
// Note the tests share the SAME in-memory store, so order matters where one
// test mutates state another reads. Keep each test's mutations self-contained.
// ============================================================================
import ballerina/http;
import ballerina/test;

final http:Client testClient = check new ("http://localhost:9090/library");

// ----------------------------------------------------------------------------
// READ OPERATIONS
// ----------------------------------------------------------------------------

@test:Config {}
function testGetAllAssets() returns error? {
    Asset[] assets = check testClient->/assets;
    // Three assets are seeded at startup.
    test:assertTrue(assets.length() >= 3, "Expected at least the 3 seeded assets");
}

@test:Config {}
function testGetSingleAsset() returns error? {
    Asset asset = check testClient->/assets/["NUST-LIB-3DP-001"];
    test:assertEquals(asset.name, "Pro-Series 3D Printer");
    test:assertEquals(asset.components.length(), 1);
}

@test:Config {}
function testGetUnknownAssetReturns404() returns error? {
    http:Response response = check testClient->/assets/["NO-SUCH-TAG"];
    test:assertEquals(response.statusCode, 404);
}

@test:Config {}
function testFilterByInstitution() returns error? {
    Asset[] assets = check testClient->/assets(institution = "University of Namibia");
    test:assertEquals(assets.length(), 1);
    test:assertEquals(assets[0].assetTag, "UNAM-RM-MTG-002");
}

@test:Config {}
function testInvalidStatusFilterReturns400() returns error? {
    http:Response response = check testClient->/assets(status = "NOT_A_STATUS");
    test:assertEquals(response.statusCode, 400);
}

@test:Config {}
function testOverdueAssets() returns error? {
    // The 3D printer is seeded with a schedule due 2026-06-01, in the past.
    Asset[] overdue = check testClient->/assets/overdue;
    test:assertTrue(overdue.length() >= 1, "Expected at least one overdue asset");
}

// ----------------------------------------------------------------------------
// WRITE OPERATIONS
// ----------------------------------------------------------------------------

@test:Config {}
function testCreateAsset() returns error? {
    Asset newAsset = {
        assetTag: "TEST-CREATE-001",
        name: "Test Projector",
        description: "Created by the test suite.",
        institution: "Namibia University of Science and Technology",
        site: "Main Campus - Library",
        dateAcquired: "2026-01-01"
    };
    Asset created = check testClient->/assets.post(newAsset);
    test:assertEquals(created.assetTag, "TEST-CREATE-001");
    // Defaults should have been applied.
    test:assertEquals(created.status, AVAILABLE);
    test:assertEquals(created.components.length(), 0);
}

@test:Config {dependsOn: [testCreateAsset]}
function testDuplicateAssetReturns409() returns error? {
    Asset duplicate = {
        assetTag: "TEST-CREATE-001",
        name: "Duplicate",
        description: "Should be rejected.",
        institution: "Namibia University of Science and Technology",
        site: "Main Campus - Library",
        dateAcquired: "2026-01-01"
    };
    http:Response response = check testClient->/assets.post(duplicate);
    test:assertEquals(response.statusCode, 409);
}

// ----------------------------------------------------------------------------
// LOANING — the state machine
// ----------------------------------------------------------------------------

@test:Config {}
function testLoanAndReturnCycle() returns error? {
    string tag = "NUST-LIB-LAP-014";

    Asset loaned = check testClient->/assets/[tag]/loan.post(());
    test:assertEquals(loaned.status, LOANED_OUT);

    // Loaning it again must fail — it is no longer AVAILABLE.
    http:Response conflictResponse = check testClient->/assets/[tag]/loan.post(());
    test:assertEquals(conflictResponse.statusCode, 409);

    Asset returned = check testClient->/assets/[tag]/'return.post(());
    test:assertEquals(returned.status, AVAILABLE);
}

// ----------------------------------------------------------------------------
// SUB-RESOURCES
// ----------------------------------------------------------------------------

@test:Config {}
function testAddAndRemoveSchedule() returns error? {
    string tag = "UNAM-RM-MTG-002";
    Schedule schedule = {
        scheduleId: "TEST-SCH-001",
        'type: SERVICING,
        dueDate: "2027-01-01",
        description: "Added by the test suite."
    };

    Schedule added = check testClient->/assets/[tag]/schedules.post(schedule);
    test:assertEquals(added.scheduleId, "TEST-SCH-001");

    Schedule removed = check testClient->/assets/[tag]/schedules/["TEST-SCH-001"].delete();
    test:assertEquals(removed.scheduleId, "TEST-SCH-001");
}

// ----------------------------------------------------------------------------
// INSTITUTIONS
// ----------------------------------------------------------------------------

@test:Config {}
function testCannotRemoveInstitutionWithAssets() returns error? {
    // NUST still owns seeded assets, so removal must be refused.
    http:Response response = check testClient->/institutions/["NUST"].delete();
    test:assertEquals(response.statusCode, 409);
}
