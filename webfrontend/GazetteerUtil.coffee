class ez5.GazetteerUtil

	@SEARCH_API_URL = "https://gazetteer.dainst.org/search.json?limit=20&"
	@SEARCH_QUERY_API_URL = "https://gazetteer.dainst.org/search.json?q="
	@ID_API_URL = "https://gazetteer.dainst.org/doc/"
	@PLACE_URL = "https://gazetteer.dainst.org/place/"
	@JSON_EXTENSION = ".json"

	@searchById: (id) ->
		xhr = new CUI.XHR
			method: "GET"
			url: ez5.GazetteerUtil.ID_API_URL + id + ez5.GazetteerUtil.JSON_EXTENSION
		return xhr.start()

	@searchByQuery: (query, _options = {}) ->
		options =
			method: "GET"
			url: ez5.GazetteerUtil.SEARCH_QUERY_API_URL + query

		CUI.util.mergeMap(options, _options)

		xhr = new CUI.XHR(options)

		return xhr.start()

	# Set the necessary attributes from gazetteer *data* to *object*
	@setObjectData: (object, data) ->
		if CUI.util.isEmpty(data)
			return object
		delete object.notFound
		object.displayName = data.prefName?.title
		object.gazId = data.gazId
		object.otherNames = data.names
		object.types = data.types or []

		if data.prefLocation?.coordinates
			position =
				lng: data.prefLocation?.coordinates[0]
				lat: data.prefLocation?.coordinates[1]

			if CUI.Map.isValidPosition(position)
				object.position = position
				object.iconName = if data.prefLocation then "fa-map" else "fa-map-marker"
		return object

	@getSaveDataObject: (data) ->
		fulltext = data.displayName
		if data.otherNames?.length > 0
			fulltext = data.otherNames.map((otherName) -> otherName.title).concat(fulltext).join(' ')

		object =
			displayName: data.displayName
			gazId: data.gazId
			position: data.position
			iconName: data.iconName
			otherNames: data.otherNames
			types: data.types
			_fulltext:
				text: fulltext
				string: data.gazId
			_standard:
				text: data.displayName
		return object