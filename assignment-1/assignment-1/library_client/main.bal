import ballerina/http;
import ballerina/io;

// The service's base URL. `check` here means a bad URL fails at startup
// rather than on first use.
final http:Client libraryClient = check new ("http://localhost:9090/library");

// A plain divider, built once rather than rebuilt on every call.
const string DIVIDER = "============================================================";

// ----------------------------------------------------------------------------
// PRESENTATION HELPERS
// ----------------------------------------------------------------------------

# Prints a section heading.
#
# + title - Heading text
function header(string title) {
    io:println("\n" + DIVIDER);
    io:println("  " + title);
    io:println(DIVIDER);
}

# Prints one asset as a short summary block.
#
# + asset - The asset to display
function printAssetLine(Asset asset) {
    io:println(string `  ${asset.assetTag}`);
    io:println(string `    ${asset.name}  [${asset.status}]`);
    io:println(string `    ${asset.institution} - ${asset.site}`);
}

# Prints a list of assets, or a placeholder when empty.
#
# + assets - Assets to display
function printAssets(Asset[] assets) {
    if assets.length() == 0 {
        io:println("  (none)");
        return;
    }
    foreach Asset a in assets {
        printAssetLine(a);
        io:println("");
    }
    io:println(string `  ${assets.length()} asset(s).`);
}

# Reports a failed request in a readable way.
#
# When a resource returns 4xx, the Ballerina client surfaces it as an error
# rather than a value, so every call site has to handle it explicitly.
#
# + e - The error returned by the client call
function reportError(error e) {
    io:println("  Request failed: " + e.message());
}

// ----------------------------------------------------------------------------
// VIEW 2 — GLOBAL VIEW
// ----------------------------------------------------------------------------

# Lists every asset across the ministry.
function globalView() {
    header("GLOBAL VIEW - All assets across the ministry");
    Asset[]|error assets = libraryClient->/assets;
    if assets is error {
        reportError(assets);
        return;
    }
    printAssets(assets);
}

// ----------------------------------------------------------------------------
// MENU LOOP
// ----------------------------------------------------------------------------

public function main() {
    io:println("\n  Ministry of Higher Education - Library & Resource Management");
    io:println("  Connected to http://localhost:9090/library");

    while true {
        io:println("\n  ------------------------------");
        io:println("  2. Global View");
        io:println("  0. Exit");
        string choice = io:readln("  Select: ").trim();

        match choice {
            "2" => {
                globalView();
            }
            "0" => {
                io:println("  Goodbye.");
                return;
            }
            _ => {
                io:println("  Unknown option.");
            }
        }
    }
}