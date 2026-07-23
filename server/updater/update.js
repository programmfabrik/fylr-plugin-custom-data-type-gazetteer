// Custom data type updater of custom-data-type-gazetteer.
//
// fylr calls this program for the actions "start_update", "update" and
// "end_update". The request is read from stdin, the response is written to
// stdout. The updater looks up the current data of every entry in the
// iDAI.gazetteer and returns the entries that have changed.

const gazetteer = require("../lib/gazetteer")

const PLUGIN = "custom-data-type-gazetteer"

// Returns true when the stored data differs from the current gazetteer data.
function hasChanges(objectData, saveData) {
    const keys = ["displayName", "gazId", "otherNames", "types", "position", "iconName", "_fulltext", "_standard"]
    return keys.some((key) => !gazetteer.isEqual(objectData[key], saveData[key]))
}

// Reads the configured gazetteer URL from info.json, null for the default.
function apiUrl(info) {
    try {
        const settings = info.config.plugin[PLUGIN].config.gazetteer_api_settings
        if (settings.api_url) {
            return settings.api_url
        }
    } catch (e) {}
    return null
}

// ------------------------------------------------------------------ updating

async function update(payload, info, log) {
    // It is possible to have the same gazetteer ID in more than one entry, so
    // the entries are grouped by ID.
    const objectsById = {}
    const searchIds = []

    for (const object of payload.objects) {
        if (!object.identifier || !object.data) {
            continue
        }
        const gazId = object.data.gazId
        if (gazId === undefined || gazId === null || gazId === "") {
            continue
        }
        if (!objectsById[gazId]) {
            objectsById[gazId] = []
            searchIds.push(gazId)
        }
        objectsById[gazId].push(object)
    }

    if (searchIds.length === 0) {
        return { payload: [] }
    }

    // One search request finds all entries of the batch.
    const result = await gazetteer.searchByIds(searchIds, { apiUrl: apiUrl(info) })

    const updated = []
    for (const gazObject of result) {
        const objects = objectsById[gazObject.gazId]
        if (!objects) {
            continue
        }
        const saveData = gazetteer.toSaveData(gazetteer.toObjectData(gazObject))
        for (const object of objects) {
            if (!hasChanges(object.data, saveData)) {
                continue
            }
            object.data = saveData
            updated.push(object)
        }
    }

    log.push(`${updated.length} of ${payload.objects.length} entries updated`)
    return { payload: updated }
}

// --------------------------------------------------------------------- entry

function respond(body) {
    process.stdout.write(JSON.stringify({ status_code: 200, body: body }))
}

function respondError(error) {
    process.stdout.write(
        JSON.stringify({
            status_code: 400,
            body: { error: error.toString() },
        })
    )
}

async function main(payload, info) {
    switch (payload.action) {
        case "start_update":
            respond({ state: {}, log: [`${PLUGIN} update started`] })
            return
        case "update": {
            if (!Array.isArray(payload.objects)) {
                throw new Error("objects are missing in the payload")
            }
            const log = []
            respond(Object.assign(await update(payload, info, log), { state: payload.state || {}, log: log }))
            return
        }
        case "end_update":
            respond({ state: {}, log: [`${PLUGIN} update done`] })
            return
        default:
            throw new Error(`unsupported action ${payload.action}`)
    }
}

;(() => {
    // info contains the plugin config with the optional gazetteer URL
    let info = {}
    try {
        info = JSON.parse(process.argv[2])
    } catch (e) {}

    let data = ""
    process.stdin.setEncoding("utf8")
    process.stdin.on("data", (chunk) => (data += chunk))
    process.stdin.on("end", async () => {
        try {
            await main(JSON.parse(data), info)
        } catch (e) {
            console.error(e)
            respondError(e)
        }
    })
})()
