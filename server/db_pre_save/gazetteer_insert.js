// db_pre_save callback of custom-data-type-gazetteer.
//
// Port of the easydb5 server plugin gazetteer_insert.py. Instead of writing
// to the database directly, missing objects are created over api/v1/db.
//
// When a record of the configured hierarchical objecttype is saved, the
// callback reads the gazetteer ID from the source field (or from the target
// field). It looks up the place and its parents in the iDAI.gazetteer. The
// parent tree of the gazetteer is mirrored: missing parent records are
// created over api/v1/db, the saved record is attached to its direct parent.
// The target field of the saved record is filled with the current gazetteer
// data.
//
// fylr sends {objects, info} on stdin. The response on stdout contains only
// the objects that were changed by the callback, or an error.

const gazetteer = require("../lib/gazetteer")

const PLUGIN = "custom-data-type-gazetteer"

// Comment set on records created by this callback, for the object history.
const INSERT_COMMENT = `<inserted by ${PLUGIN}>`

// The api/v1/db inserts of this callback trigger db_pre_save again. The
// internal requests are marked with this query parameter and the callback
// skips them, which guards against recursion. A query parameter is used
// instead of the comment: the comment is persisted with the record and
// round-trips through GET and POST, a query parameter cannot.
const INSERT_QUERY_PARAM = "gazetteer_insert"

// -------------------------------------------------------------------- output

function respond(body) {
    process.stdout.write(JSON.stringify(body))
}

function respondError(code, description) {
    console.error(`${PLUGIN} gazetteer_insert: ${description}`)
    respond({
        error: {
            code: `${PLUGIN}.gazetteer_insert.${code}`,
            statuscode: 400,
            description: description,
            error: description,
        },
    })
    process.exit(0)
}

// ------------------------------------------------------------------ fylr API

class FylrApi {
    constructor(info) {
        if (!info.api_url) {
            respondError("config_error", "api_url is missing in the callback info")
        }
        if (!info.api_user_access_token) {
            respondError("config_error", "api_user_access_token is missing in the callback info")
        }
        this.url = info.api_url.replace(/\/+$/, "")
        this.token = info.api_user_access_token
    }

    request(method, path, body) {
        return gazetteer.request({
            method: method,
            url: this.url + path,
            body: body,
            headers: {
                Authorization: "Bearer " + this.token,
            },
        })
    }

    // Returns the _id of the record that holds the gazetteer ID in the target
    // field, or null when there is none.
    async findByGazId(objecttype, fieldTo, gazId) {
        const response = await this.request("POST", "/api/v1/search", {
            format: "short",
            limit: 1,
            objecttypes: [objecttype],
            search: [
                {
                    type: "in",
                    bool: "must",
                    fields: [`${objecttype}.${fieldTo}.gazId`],
                    in: [`${gazId}`],
                },
            ],
        })
        if (!response.objects || response.objects.length === 0) {
            return null
        }
        return response.objects[0][objecttype]._id
    }

    // Creates a record and returns its _id.
    async createObject(objecttype, fields) {
        const inner = Object.assign({ _version: 1 }, fields)
        const response = await this.request("POST", `/api/v1/db/${objecttype}?${INSERT_QUERY_PARAM}=1`, [
            {
                _objecttype: objecttype,
                _mask: "_all_fields",
                _comment: INSERT_COMMENT,
                [objecttype]: inner,
            },
        ])
        if (!Array.isArray(response) || !response[0] || !response[0][objecttype]) {
            throw new Error(`unexpected response of api/v1/db/${objecttype}: ${JSON.stringify(response)}`)
        }
        return response[0][objecttype]._id
    }
}

// ------------------------------------------------------------------- helpers

// Strips the objecttype prefix from a field fullname of the base config.
function stripObjecttype(fieldName, objecttype) {
    if (fieldName && fieldName.startsWith(objecttype + ".")) {
        return fieldName.substring(objecttype.length + 1)
    }
    return fieldName
}

function isEmpty(value) {
    return value === undefined || value === null || `${value}`.trim() === ""
}

// --------------------------------------------------------------------- main

// Handles one saved record. Returns true when the record was changed.
async function handleObject(object, settings, fylr) {
    const objecttype = settings.objecttype
    const inner = object[objecttype]
    if (!inner) {
        return false
    }

    // Without on_update only newly inserted records are handled.
    if (!settings.on_update && inner._version !== 1) {
        return false
    }

    // The gazetteer ID comes from the source field. Without a source field it
    // is taken from prefilled custom data in the target field.
    let gazId = settings.field_from ? inner[settings.field_from] : null
    if (isEmpty(gazId)) {
        gazId = inner[settings.field_to] ? inner[settings.field_to].gazId : null
    }
    if (isEmpty(gazId)) {
        return false
    }

    // Look up the place and its parent chain in the gazetteer.
    const found = await gazetteer.searchByIds([gazId], { apiUrl: settings.api_url, addParents: true })
    const place = found.find((result) => `${result.gazId}` === `${gazId}`)
    if (!place || isEmpty(place.gazId)) {
        console.error(`${PLUGIN} gazetteer_insert: gazetteer ID ${gazId} was not found, record is saved unchanged`)
        return false
    }

    // The chain contains the place itself and its parents. The parents are
    // ordered from the direct parent up to the root.
    const chainIds = [`${place.gazId}`]
    for (const parent of place.parents || []) {
        if (!isEmpty(parent.gazId)) {
            chainIds.push(`${parent.gazId}`)
        }
    }

    // One search request fetches the full data of the whole chain.
    const saveDataById = {}
    for (const gazObject of await gazetteer.searchByIds(chainIds, { apiUrl: settings.api_url })) {
        saveDataById[`${gazObject.gazId}`] = gazetteer.toSaveData(gazetteer.toObjectData(gazObject))
    }
    if (!saveDataById[chainIds[0]]) {
        console.error(`${PLUGIN} gazetteer_insert: no data for gazetteer ID ${gazId}, record is saved unchanged`)
        return false
    }

    let parentId = null
    if (chainIds.length > 1) {
        // The place must not exist yet in the hierarchy.
        const existingId = await fylr.findByGazId(objecttype, settings.field_to, chainIds[0])
        if (existingId !== null) {
            respondError(
                "object.duplicate",
                `gazetteer ID ${chainIds[0]} already exists in record ${objecttype}:${existingId}`
            )
        }

        // Created parents get the pool of the saved record.
        let poolId = null
        if (inner._pool && inner._pool.pool) {
            poolId = inner._pool.pool._id
        }

        // Walk the chain from the root down to the direct parent. Missing
        // records are created, each one attached to the one before.
        for (let k = chainIds.length - 1; k >= 1; k--) {
            const chainGazId = chainIds[k]
            let objectId = await fylr.findByGazId(objecttype, settings.field_to, chainGazId)

            if (objectId === null) {
                if (!saveDataById[chainGazId]) {
                    console.error(`${PLUGIN} gazetteer_insert: no data for parent gazetteer ID ${chainGazId}, skipped`)
                    continue
                }
                const fields = {
                    _id_parent: parentId,
                    [settings.field_to]: saveDataById[chainGazId],
                }
                if (poolId !== null) {
                    fields._pool = { pool: { _id: poolId } }
                }
                objectId = await fylr.createObject(objecttype, fields)
            }

            parentId = objectId
        }
    }

    inner._id_parent = parentId
    inner[settings.field_to] = saveDataById[chainIds[0]]
    return true
}

async function main(data) {
    const info = data.info || {}

    // Skip the internal inserts of this callback (recursion guard).
    const query = info.request && info.request.query ? info.request.query : {}
    if (query[INSERT_QUERY_PARAM]) {
        respond({ objects: [] })
        return
    }

    let settings = null
    let apiSettings = null
    try {
        settings = info.config.plugin[PLUGIN].config.gazetteer_plugin_settings
        apiSettings = info.config.plugin[PLUGIN].config.gazetteer_api_settings
    } catch (e) {
        settings = null
    }

    if (!settings || !settings.enabled || isEmpty(settings.objecttype)) {
        respond({ objects: [] })
        return
    }

    if (isEmpty(settings.field_to)) {
        respondError("field_to.not_set", "no target field for generated gazetteer data selected in the base config")
    }

    settings = Object.assign({}, settings, {
        field_to: stripObjecttype(settings.field_to, settings.objecttype),
        field_from: isEmpty(settings.field_from) ? null : stripObjecttype(settings.field_from, settings.objecttype),
        api_url: apiSettings && !isEmpty(apiSettings.api_url) ? apiSettings.api_url : null,
    })

    const fylr = new FylrApi(info)

    const changed = []
    for (const object of data.objects || []) {
        if (object._objecttype !== settings.objecttype) {
            continue
        }
        if (await handleObject(object, settings, fylr)) {
            changed.push(object)
        }
    }

    respond({ objects: changed })
}

;(() => {
    let data = ""
    process.stdin.setEncoding("utf8")
    process.stdin.on("data", (chunk) => (data += chunk))
    process.stdin.on("end", async () => {
        try {
            await main(JSON.parse(data))
        } catch (e) {
            console.error(e)
            respondError("error", e.toString())
        }
    })
})()
