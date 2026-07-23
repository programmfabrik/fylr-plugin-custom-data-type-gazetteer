# custom-data-type-gazetteer

Custom data type "Gazetteer" for fylr.

The plugin provides a custom data type for references to places in the [iDAI.gazetteer](https://gazetteer.dainst.org). The iDAI.gazetteer is the place repository of the German Archaeological Institute. In the record editor the field offers a search by place name or by Gazetteer ID. The plugin stores a reference to the place, including its coordinates and alternative names.

## Data structure

```json
{
    "displayName": "Buenos Aires",
    "iconName": "fa-map",
    "gazId": "2087760",
    "position": {
        "lat": -34.61315,
        "lng": -58.37723
    },
    "types": [
        "populated-place"
    ],
    "otherNames": [
        {
            "language": "spa",
            "title": "Ciudad Autónoma de Buenos Aires"
        },
        {
            "language": "rus",
            "title": "Буэнос-Айрес"
        }
    ],
    "_fulltext": {
        "text": [
            "Ciudad Autónoma de Buenos Aires",
            "Буэнос-Айрес",
            "Buenos Aires"
        ],
        "string": "2087760"
    },
    "_standard": {
        "text": "Buenos Aires"
    }
}
```

The keys `_fulltext` and `_standard` are used for searching.

## Automatic update

The plugin provides an updater, which fylr runs in the background. The updater collects the existing entries of this custom data type. It looks up each entry in the iDAI.gazetteer once per day. If the data in the iDAI.gazetteer has changed, the stored entry is updated.

## Automatic insertion of hierarchical records

The plugin can automatically build a hierarchy of records with Gazetteer fields. This feature is optional and must be enabled in the base configuration.

When a record of the configured object type is saved, the plugin reads the Gazetteer ID from the source field. If no source field is configured, the ID is taken from prefilled custom data in the target field. The plugin looks up the place and all its parents in the iDAI.gazetteer. The parent tree of the gazetteer is mirrored in the object hierarchy. Missing parent records are created over the fylr API endpoint `api/v1/db`. The saved record is attached to its direct parent and the target field is filled with the current gazetteer data.

If the Gazetteer ID already exists in another record of the object type, the save is rejected with an error.

### The query parameter `gazetteer_insert`

The plugin creates the missing parent records with the query parameter `gazetteer_insert=1` on `api/v1/db`. Every save triggers the plugin again, including the saves of these parent records. The parameter marks the internal requests of the plugin. Requests with this parameter are saved without any processing by the plugin. This prevents an endless recursion.

**Important**: never set `gazetteer_insert` on your own API requests. A save with this parameter bypasses the automatic insertion completely. The record is then saved without generated custom data, without a parent and without a duplicate check.

### Example

The object type `gazetteer_data` is configured with the source field `gazetteer_id` and the target field `custom_data`. The hierarchy already contains these records:

* World (ID [`2042600`](https://gazetteer.dainst.org/place/2042600))
    * Europe (ID [`2044223`](https://gazetteer.dainst.org/place/2044223))
        * Germany (ID [`2044274`](https://gazetteer.dainst.org/place/2044274))
            * Berlin (ID [`2048564`](https://gazetteer.dainst.org/place/2048564))

A new record with the Gazetteer ID [`2052755`](https://gazetteer.dainst.org/place/2052755) (Hamburg) is inserted. The parent Germany is already in the hierarchy. The new record is attached to it directly.

A new record with the Gazetteer ID [`2347833`](https://gazetteer.dainst.org/place/2347833) (Hanoi) is inserted. There is no parent for this place yet. The plugin finds the deepest existing parent, in this case World. The missing parents Asia and Vietnam are created and inserted into the tree:

* World
    * Europe
        * Germany
            * Berlin
            * Hamburg
    * Asia (ID [`2042932`](https://gazetteer.dainst.org/place/2042932))
        * Vietnam (ID [`2281934`](https://gazetteer.dainst.org/place/2281934))
            * Hanoi (ID [`2347833`](https://gazetteer.dainst.org/place/2347833))

## Configuration

The plugin is configured in the base configuration under the category "Gazetteer".

### API settings:

* "API URL": the URL of the gazetteer server, used by the server side of the plugin. The default value is `https://gazetteer.dainst.org` and **should not be changed**.

### Display settings:

* "Show alternative names": the field also displays the alternative place names.
* "Show latitude and longitude": the field also displays the coordinates of the place.

### Settings for the automatic insertion of hierarchical records:

* "Enabled": enables the automatic insertion for the selected object type.
* "Object type": a hierarchical object type from the dropdown menu. The list is prefiltered. The object type must be hierarchical to map the gazetteer structure. It must have at least one Gazetteer field outside of nested tables. Object types with required fields other than the target field are excluded, because the plugin cannot fill them.
* "Source field": the text field where the plugin reads the Gazetteer ID. If it is not selected, the plugin parses the ID from prefilled custom data in the target field.
* "Target field": the field of type Gazetteer where the plugin writes the generated custom data.
* "Update Gazetteer entries also when changing objects": by default only newly inserted records are handled. With this checkbox the plugin also handles every update of a record.

### Updater settings:

The updater needs no configuration.
