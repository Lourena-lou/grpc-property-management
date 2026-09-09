// ----------------------------------------------------------------------------
// VIEW 3 — CAMPUS VIEW
// ----------------------------------------------------------------------------

# Filters assets by institution and optionally by site.
function campusView() {
    header("CAMPUS VIEW - Filter by institution and site");

    Institution[]|error institutions = libraryClient->/institutions;
    if institutions is error {
        reportError(institutions);
        return;
    }
    io:println("  Registered institutions:");
    foreach Institution i in institutions {
        io:println(string `    ${i.institutionId} - ${i.name}`);
    }

    string institution = io:readln("\n  Institution name (blank for all): ").trim();
    string site = io:readln("  Site/campus (blank for all): ").trim();

    // Build the query only from the filters actually supplied. Sending an
    // empty string would filter for assets whose institution IS "".
    Asset[]|error assets;
    if institution == "" && site == "" {
        assets = libraryClient->/assets;
    } else if site == "" {
        assets = libraryClient->/assets(institution = institution);
    } else if institution == "" {
        assets = libraryClient->/assets(site = site);
    } else {
        assets = libraryClient->/assets(institution = institution, site = site);
    }

    if assets is error {
        reportError(assets);
        return;
    }
    io:println("");
    printAssets(assets);
}