import ballerina/http;
import ballerina/log;

# Builds a 404 response.
#
# + message - Explanation of what was not found
# + return - A `NotFoundError` carrying the message
isolated function notFound(string message) returns NotFoundError =>
    {body: {errmsg: message}};

# Builds a 409 response.
#
# + message - Explanation of the conflict
# + return - A `ConflictError` carrying the message
isolated function conflictError(string message) returns ConflictError =>
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

    // ------------------------------------------------------------------
    // ASSETS — collection level (read + filters, create)
    // ------------------------------------------------------------------

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

    # Creates a new asset.
    #
    # A `post` resource returns 201 Created by default — no need to say so.
    # The `asset` parameter is bound from the JSON request body automatically;
    # a malformed body is rejected by the framework before this code runs.
    #
    # + asset - The asset to create, from the request body
    # + return - The created asset, or 409 if the tag is already in use
    isolated resource function post assets(Asset asset) returns Asset|ConflictError {
        Asset|error result = addAsset(asset);
        if result is error {
            return conflictError(result.message());
        }
        return result;
    }

    # Lists assets with at least one schedule whose due date has passed.
    #
    # + return - Assets with one or more overdue schedules
    isolated resource function get assets/overdue() returns Asset[] => findOverdueAssets();

    // ------------------------------------------------------------------
    // ASSETS — single item (read, update, delete)
    // ------------------------------------------------------------------

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

    # Replaces the mutable fields of an asset. The tag itself cannot change —
    # `AssetUpdate` has no `assetTag` field, so the compiler enforces that.
    #
    # + assetTag - Tag from the URL path
    # + update - Replacement field values, from the request body
    # + return - The updated asset, or 404 if unknown
    isolated resource function put assets/[string assetTag](AssetUpdate update)
            returns Asset|NotFoundError {
        Asset|error result = updateAsset(assetTag, update);
        if result is error {
            return notFound(result.message());
        }
        return result;
    }

    # Deletes an asset.
    #
    # + assetTag - Tag from the URL path
    # + return - The deleted asset, or 404 if unknown
    isolated resource function delete assets/[string assetTag]() returns Asset|NotFoundError {
        Asset|error result = deleteAsset(assetTag);
        if result is error {
            return notFound(result.message());
        }
        return result;
    }

    // ------------------------------------------------------------------
    // INSTITUTIONS
    // ------------------------------------------------------------------

    # Lists every registered institution.
    #
    # + return - All institutions
    isolated resource function get institutions() returns Institution[] => getAllInstitutions();

    # Registers a new institution.
    #
    # + institution - The institution to add, from the request body
    # + return - The created institution, or 409 if the id is already in use
    isolated resource function post institutions(Institution institution)
            returns Institution|ConflictError {
        Institution|error result = addInstitution(institution);
        if result is error {
            return conflictError(result.message());
        }
        return result;
    }

    # Removes an institution. Fails if assets are still assigned to it.
    #
    # + institutionId - Institution code from the URL path
    # + return - The removed institution, 404 if unknown, or 409 if still in use
    isolated resource function delete institutions/[string institutionId]()
            returns Institution|NotFoundError|ConflictError {
        Institution|error result = removeInstitution(institutionId);
        if result is error {
            if !institutionExists(institutionId) {
                return notFound(result.message());
            }
            return conflictError(result.message());
        }
        return result;
    }

    // ------------------------------------------------------------------
    // LOANING AND BOOKING
    // ------------------------------------------------------------------

    # Loans an asset or books a space.
    #
    # Two distinct failure modes share one store error, so we disambiguate by
    # asking whether the asset exists: absent means 404, present means the
    # request conflicts with the asset's current state, so 409.
    #
    # + assetTag - Tag from the URL path
    # + isSpace - `true` to book a room or lab (becomes OCCUPIED rather than LOANED_OUT)
    # + return - The updated asset, 404 if unknown, or 409 if not available
    isolated resource function post assets/[string assetTag]/loan(boolean isSpace = false)
            returns Asset|NotFoundError|ConflictError {
        Asset|error result = loanAsset(assetTag, isSpace);
        if result is error {
            if !assetExists(assetTag) {
                return notFound(result.message());
            }
            return conflictError(result.message());
        }
        return result;
    }

    # Returns a loaned asset or frees an occupied space.
    #
    # `return` is a reserved keyword, so the path segment is written `'return`.
    # The URL is still plain /library/assets/{tag}/return.
    #
    # + assetTag - Tag from the URL path
    # + return - The updated asset, 404 if unknown, or 409 if not currently out
    isolated resource function post assets/[string assetTag]/'return()
            returns Asset|NotFoundError|ConflictError {
        Asset|error result = returnAsset(assetTag);
        if result is error {
            if !assetExists(assetTag) {
                return notFound(result.message());
            }
            return conflictError(result.message());
        }
        return result;
    }

    // ------------------------------------------------------------------
    // COMPONENTS
    // ------------------------------------------------------------------

    # Adds a component to an asset.
    #
    # + assetTag - Tag from the URL path
    # + component - The component to add, from the request body
    # + return - The added component, 404 if the asset is unknown, 409 if the id is taken
    isolated resource function post assets/[string assetTag]/components(Component component)
            returns Component|NotFoundError|ConflictError {
        Component|error result = addComponent(assetTag, component);
        if result is error {
            if !assetExists(assetTag) {
                return notFound(result.message());
            }
            return conflictError(result.message());
        }
        return result;
    }

    # Removes a component from an asset.
    #
    # + assetTag - Tag from the URL path
    # + compId - Component identifier from the URL path
    # + return - The removed component, or 404 if either id is unknown
    isolated resource function delete assets/[string assetTag]/components/[string compId]()
            returns Component|NotFoundError {
        Component|error result = removeComponent(assetTag, compId);
        if result is error {
            return notFound(result.message());
        }
        return result;
    }

    // ------------------------------------------------------------------
    // SCHEDULES
    // ------------------------------------------------------------------

    # Adds a maintenance, servicing, or booking schedule to an asset.
    #
    # + assetTag - Tag from the URL path
    # + schedule - The schedule to add, from the request body
    # + return - The added schedule, 404 if the asset is unknown, 409 if the id is taken
    isolated resource function post assets/[string assetTag]/schedules(Schedule schedule)
            returns Schedule|NotFoundError|ConflictError {
        Schedule|error result = addSchedule(assetTag, schedule);
        if result is error {
            if !assetExists(assetTag) {
                return notFound(result.message());
            }
            return conflictError(result.message());
        }
        return result;
    }

    # Replaces an existing schedule.
    #
    # + assetTag - Tag from the URL path
    # + scheduleId - Schedule identifier from the URL path
    # + updated - Replacement schedule, from the request body
    # + return - The updated schedule, or 404 if either id is unknown
    isolated resource function put assets/[string assetTag]/schedules/[string scheduleId](
            Schedule updated) returns Schedule|NotFoundError {
        Schedule|error result = updateSchedule(assetTag, scheduleId, updated);
        if result is error {
            return notFound(result.message());
        }
        return result;
    }

    # Removes a schedule from an asset.
    #
    # + assetTag - Tag from the URL path
    # + scheduleId - Schedule identifier from the URL path
    # + return - The removed schedule, or 404 if either id is unknown
    isolated resource function delete assets/[string assetTag]/schedules/[string scheduleId]()
            returns Schedule|NotFoundError {
        Schedule|error result = removeSchedule(assetTag, scheduleId);
        if result is error {
            return notFound(result.message());
        }
        return result;
    }
}