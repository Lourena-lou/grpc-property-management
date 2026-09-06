import ballerina/http;
import ballerina/log;

# Builds a 404 response.
#
# + message - Explanation of what was not found
# + return - A `NotFoundError` carrying the message
isolated function notFound(string message) returns NotFoundError =>
    {body: {errmsg: message}};

# Builds a 400 response.
#
# + message - Explanation of why the request was rejected
# + return - A `BadRequestError` carrying the message
isolated function badRequest(string message) returns BadRequestError =>
    {body: {errmsg: message}};

service /library on new http:Listener(9090) {

    # Runs once when the listener starts. Loads the sample data so the client
    # has something to display on a fresh run.
    function init() {
        seedData();
        log:printInfo("Library service started on port 9090 with seed data loaded");
    }

    # Lists assets, optionally filtered. All three filters are independent and
    # combinable; omitting them all returns every asset (the "global view").
    #
    #   GET /library/assets
    #   GET /library/assets?institution=University%20of%20Namibia
    #   GET /library/assets?institution=...&site=Main%20Campus%20-%20Library
    #   GET /library/assets?status=AVAILABLE
    #
    # + institution - Institution name to filter by, or omitted for all
    # + site - Site or campus to filter by, or omitted for all
    # + status - Asset status to filter by, or omitted for all
    # + return - Matching assets, or 400 if `status` is not a valid state
    isolated resource function get assets(string? institution, string? site, string? status)
            returns Asset[]|BadRequestError {

        if status is string {
            if status !is AssetStatus {
                return badRequest(string `Invalid status '${status}'. ` +
                    "Expected one of: AVAILABLE, LOANED_OUT, OCCUPIED, " +
                    "UNDER_MAINTENANCE, DISPOSED");
            }
            Asset[] byStatus = findAssetsByStatus(status);
            return from Asset a in byStatus
                where institution is () || a.institution == institution
                where site is () || a.site == site
                select a;
        }

        return findAssets(institution, site);
    }

    # Lists assets with at least one schedule whose due date has passed.
    #
    # + return - Assets with one or more overdue schedules
    isolated resource function get assets/overdue() returns Asset[] => findOverdueAssets();

    # Fetches one asset by tag.
    #
    # + assetTag - Tag from the URL path
    # + return - The asset, or 404 if unknown
    isolated resource function get assets/[string assetTag]() returns Asset|NotFoundError {
        Asset? asset = getAsset(assetTag);
        if asset is () {
            return notFound(string `Asset '${assetTag}' not found`);
        }
        return asset;
    }
}