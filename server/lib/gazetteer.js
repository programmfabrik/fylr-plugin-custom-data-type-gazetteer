// Shared helpers of custom-data-type-gazetteer for talking to the
// iDAI.gazetteer and for building the custom data of an entry.

const http = require("http")
const https = require("https")

const DEFAULT_API_URL = "https://gazetteer.dainst.org"

// ----------------------------------------------------------------- transport

// Performs a request and returns the parsed JSON body.
function request(options) {
    const url = new URL(options.url)
    const client = url.protocol === "https:" ? https : http
    const body = options.body === undefined ? null : JSON.stringify(options.body)

    const headers = Object.assign({}, options.headers)
    if (body !== null) {
        headers["Content-Type"] = "application/json"
        headers["Content-Length"] = Buffer.byteLength(body)
    }

    return new Promise((resolve, reject) => {
        const req = client.request(url, { method: options.method || "GET", headers }, (res) => {
            let data = ""
            res.setEncoding("utf8")
            res.on("data", (chunk) => (data += chunk))
            res.on("end", () => {
                if (res.statusCode < 200 || res.statusCode >= 300) {
                    reject(new Error(`${options.method || "GET"} ${url.pathname} answered ${res.statusCode}: ${data}`))
                    return
                }
                if (data === "") {
                    resolve({})
                    return
                }
                try {
                    resolve(JSON.parse(data))
                } catch (e) {
                    reject(new Error(`could not parse the response of ${url.pathname}: ${e}`))
                }
            })
        })
        req.on("error", reject)
        if (body !== null) {
            req.write(body)
        }
        req.end()
    })
}

// Searches the given gazetteer IDs with one request and returns the result
// array. With addParents the parent chain of each place is included. The
// gazetteer URL can be overridden with apiUrl (base config of the plugin).
async function searchByIds(gazIds, options = {}) {
    const apiUrl = (options.apiUrl || DEFAULT_API_URL).replace(/\/+$/, "")
    const query = encodeURIComponent(gazIds.map((gazId) => `_id:${gazId}`).join(" OR "))
    let url = `${apiUrl}/search.json?q=${query}&limit=${gazIds.length}`
    if (options.addParents) {
        url += "&add=parents&noPolygons=1"
    }
    const data = await request({ url: url })
    return data.result || []
}

// ------------------------------------------------------------ gazetteer data

function isValidPosition(position) {
    return (
        !!position &&
        typeof position.lat === "number" &&
        typeof position.lng === "number" &&
        position.lat >= -90 &&
        position.lat <= 90 &&
        position.lng >= -180 &&
        position.lng <= 180
    )
}

// Builds the custom data of an entry from a gazetteer search result.
function toObjectData(gazObject) {
    const data = {
        displayName: gazObject.prefName ? gazObject.prefName.title : undefined,
        gazId: gazObject.gazId,
        otherNames: gazObject.names,
        types: gazObject.types || [],
    }

    if (gazObject.prefLocation && gazObject.prefLocation.coordinates) {
        const position = {
            lng: gazObject.prefLocation.coordinates[0],
            lat: gazObject.prefLocation.coordinates[1],
        }
        if (isValidPosition(position)) {
            data.position = position
            data.iconName = "fa-map"
        }
    }

    return data
}

// Builds the data that is saved back to fylr.
function toSaveData(data) {
    let fulltext = data.displayName
    if (Array.isArray(data.otherNames) && data.otherNames.length > 0) {
        fulltext = data.otherNames
            .map((otherName) => otherName.title)
            .concat(fulltext)
            .join(" ")
    }

    return {
        displayName: data.displayName,
        gazId: data.gazId,
        position: data.position,
        iconName: data.iconName,
        otherNames: data.otherNames,
        types: data.types,
        _fulltext: {
            text: fulltext,
            string: data.gazId,
        },
        _standard: {
            text: data.displayName,
        },
    }
}

function isEqual(a, b) {
    if (a === b) {
        return true
    }
    if (a === null || b === null || typeof a !== "object" || typeof b !== "object") {
        return false
    }
    if (Array.isArray(a) !== Array.isArray(b)) {
        return false
    }
    const keysA = Object.keys(a)
    const keysB = Object.keys(b)
    if (keysA.length !== keysB.length) {
        return false
    }
    return keysA.every((key) => isEqual(a[key], b[key]))
}

module.exports = {
    request,
    searchByIds,
    isValidPosition,
    toObjectData,
    toSaveData,
    isEqual,
}
