// ----------------------------------------------------------------------------
// VIEW 1 — LOANING & BOOKING
// ----------------------------------------------------------------------------

# Loans an asset, books a space, or processes a return.
function loanAndBook() {
    header("LOANING & BOOKING");

    Asset[]|error available = libraryClient->/assets(status = "AVAILABLE");
    if available is error {
        reportError(available);
        return;
    }
    io:println("  Currently available:");
    printAssets(available);

    io:println("\n  1) Loan an asset");
    io:println("  2) Book a room or lab");
    io:println("  3) Return an asset");
    string choice = io:readln("  Choose: ").trim();

    if choice == "3" {
        string tag = io:readln("  Asset tag to return: ").trim();
        Asset|error returned = libraryClient->/assets/[tag]/'return.post(());
        if returned is error {
            reportError(returned);
            return;
        }
        io:println(string `  Returned. '${returned.name}' is now ${returned.status}.`);
        return;
    }

    if choice != "1" && choice != "2" {
        io:println("  Unknown choice.");
        return;
    }

    boolean isSpace = choice == "2";
    string tag = io:readln("  Asset tag: ").trim();
    Asset|error result = libraryClient->/assets/[tag]/loan.post((), isSpace = isSpace);
    if result is error {
        reportError(result);
        return;
    }
    io:println(string `  Done. '${result.name}' is now ${result.status}.`);
}