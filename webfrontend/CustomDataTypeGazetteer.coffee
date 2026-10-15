class CustomDataTypeGazetteer extends CustomDataType

	getCustomDataTypeName: ->
		"custom:base.custom-data-type-gazetteer.gazetteer"

	getCustomDataTypeNameLocalized: ->
		$$("custom.data.type.gazetteer.name")

	getCustomDataOptionsInDatamodelInfo: (custom_settings) ->
		return []

	supportsStandard: ->
		true

	renderSearchInput: (data, opts={}) ->
		return new SearchToken(
			column: @
			data: data
			fields: opts.fields
		).getInput().DOM

	getFieldNamesForSearch: ->
		@__getFieldNames()

	getFieldNamesForSuggest: ->
		@__getFieldNames()

	renderEditorInput: (data) ->
		initData = @__initData(data)

		content = CUI.dom.div()
		waitBlock = new CUI.WaitBlock(element: content)

		setContent = =>
			[searchInput, displayOutput] = @__initForm(initData)
			searchInput.start()
			displayOutput.start()

			CUI.dom.append(content, searchInput)
			CUI.dom.append(content, displayOutput)
			waitBlock.destroy()

		waitBlock.show()
		@__fillMissingData(initData).done(setContent)

		return content

	renderTableOutput: (data, _, opts) ->
		initData = @__initData(data)

		content = @__renderOutput(
			data: initData
			onlyText: true
		)
		return content

	renderDetailOutput: (data, _, opts) ->
		initData = @__initData(data)

		content = CUI.dom.div()
		waitBlock = new CUI.WaitBlock(element: content)
		mapPlugin = (opts.detail?.getPlugins() ? []).find((plugin) => @isPluginSupported(plugin))

		setContent = =>
			outputFieldElement = @__renderOutput(data: initData)
			CUI.dom.replace(content, outputFieldElement)
			waitBlock.destroy()

			if mapPlugin and CUI.Map.isValidPosition(initData.position)
				mapPlugin.addMarker(position: initData.position, iconName: initData.iconName, iconColor: "#6786ad")

		waitBlock.show()
		@__fillMissingData(initData).done(setContent)

		if mapPlugin
			CUI.Events.listen
				type: "map-detail-click-location"
				node: content
				call: (_, info) =>
					if info.data?.position == initData.position
						CUI.dom.scrollIntoView(content)

		return content

	renderFieldAsGroup: ->
		return false

	getTemplateData: (data) ->
		return data?._template?[@name()]

	getSaveData: (data, save_data) ->
		fieldData = data[@name()]

		if CUI.util.isEmpty(fieldData) or CUI.util.isEmpty(fieldData.gazId)
			templateData = @getTemplateData(data)
			if not CUI.util.isEmpty(templateData)
				return save_data[@name()] = templateData
			return save_data[@name()] = null

		if fieldData.notFound
			return throw new InvalidSaveDataException()

		return save_data[@name()] = ez5.GazetteerUtil.getSaveDataObject(fieldData)

	getQueryFieldBadge: (data) =>
		if data["#{@name()}:unset"]
			value = $$("text.column.badge.without")
		else
			value = data[@name()]

		name: @nameLocalized()
		value: value

	getSearchFilter: (data, key=@name()) ->
		if data[key+":unset"]
			filter =
				type: "in"
				fields: [ @fullName()+".displayName" ]
				in: [ null ]
			filter._unnest = true
			filter._unset_filter = true
			return filter

		filter = super(data, key)
		if filter
			return filter

		if CUI.util.isEmpty(data[key])
			return

		val = data[key]
		[str, phrase] = Search.getPhrase(val)

		switch data[key+":type"]
			when "token", "fulltext", undefined
				filter =
					type: "match"
					mode: data[key+":mode"]
					fields: @getFieldNamesForSearch()
					string: str
					phrase: phrase

			when "field"
				filter =
					type: "in"
					fields: @getFieldNamesForSearch()
					in: [ str ]
		filter

	__getFieldNames: ->
		return [
			@fullName()+".gazId"
			@fullName()+".displayName"
		]

	__initForm: (formData) ->
		searchData = q: ""
		resultsContainer = "results"
		loadingContainer = "loading"
		noResultsContainer = "no_results"
		loadingLabel = new LocaLabel(loca_key: "autocompletion.loading", padded: true)
		noResultsLabel = new LocaLabel(loca_key: "custom.data.type.gazetteer.search.no-results", padded: true)

		searchField = new CUI.Input
			name: "q"
			hidden: true
			placeholder: $$("custom.data.type.gazetteer.search.placeholder")
			maximize_horizontal: true
			data: searchData
			onDataChanged: =>
				CUI.scheduleCallback
					ms: 200
					call: search

		autocompletionPopup = new AutocompletionPopup
			element: searchField
			onHide: =>
				autocompletionPopup.hide()
		autocompletionPopup.addContainer(resultsContainer)
		autocompletionPopup.addContainer(loadingContainer)
		autocompletionPopup.addContainer(noResultsContainer)

		outputDiv = CUI.dom.div()
		outputField = new CUI.DataFieldProxy
			name: "displayName"
			hidden: true
			element: outputDiv

		onDelete = =>
			searchField.show()
			outputField.hide()
			cleanData()
			searchField.reload()

			CUI.Events.trigger
				node: searchField
				type: "editor-changed"


		showOutputField = =>
			card = @__renderOutput(
					data: formData
					editor: true
					onDelete: onDelete
					onModify: =>
						id = formData.gazId
						onDelete()
						searchData.q = id
						searchField.reload()
						search()
			)
			CUI.dom.replace(outputDiv, card)
			outputField.show()

		cleanData = =>
			delete formData.displayName
			delete formData.gazId
			delete formData.otherNames
			delete formData.types
			delete formData.position
			delete formData.iconName

		setData = (object) =>
			searchData.q = ""
			ez5.GazetteerUtil.setObjectData(formData, object)

		searchXHR = null
		search = =>
			searchXHR?.abort()
			autocompletionPopup.emptyContainer(resultsContainer)
			autocompletionPopup.emptyContainer(loadingContainer)
			autocompletionPopup.emptyContainer(noResultsContainer)
			if searchData.q.length == 0 # Trigger search when it is not empty.
				return

			autocompletionPopup.getContainer(loadingContainer).replace(loadingLabel)
			autocompletionPopup.show()

			searchXHR = new CUI.XHR
				method: "GET"
				url: ez5.GazetteerUtil.SEARCH_API_URL + CUI.encodeUrlData(searchData)

			searchXHR.start().done((data) =>
				autocompletionPopup.emptyContainer(loadingContainer)
				if data.result?.length == 0
					autocompletionPopup.getContainer(noResultsContainer).replace(noResultsLabel)
					return

				for object in data.result
					do(object) =>
						item = autocompletionPopup.appendItem(resultsContainer,
							@__renderAutocompleteCard(object)
						)
						CUI.Events.listen
							type: "click"
							node: item
							call: (ev) =>
								ev.stopPropagation()

								if object
									setData(object)
								else
									cleanData()

								searchField.hide()
								showOutputField()

								autocompletionPopup.hide()
								CUI.Events.trigger
									node: searchField
									type: "editor-changed"

								return

				CUI.Events.trigger
					type: "content-resize"
					node: autocompletionPopup
			)

		if CUI.util.isEmpty(formData) or formData.notFound or not formData.gazId
			searchField.show()
		else
			showOutputField()

		[searchField, outputField]

	__initData: (data) ->
		if not data[@name()]
			initData = {}
			data[@name()] = initData
		else
			initData = data[@name()]
		initData

	__renderOutput: (opts) ->
		formData = opts.data
		if formData.notFound
			return new CUI.EmptyLabel(text: $$("custom.data.type.gazetteer.preview.id-not-found"), class: "ez-label-invalid")
		if formData.gazId
			return @__renderCard(opts)
		else
			return new CUI.EmptyLabel(text: $$("custom.data.type.gazetteer.preview.empty-label"))

	__renderAutocompleteCard: (data) ->
		object = {}
		ez5.GazetteerUtil.setObjectData(object, data)
		@__renderCard(
			data: object
			small: true
		)

	__renderCard: (_opts) ->
		opts = CUI.Element.readOpts(_opts, "CustomDataTypeGazetteer.__renderCard",
			data:
				check: "PlainObject"
				mandatory: true
			editor:
				check: Boolean
				default: false
			small:
				check: Boolean
				default: false
			onlyText:
				check: Boolean
				default: false
			onDelete:
				check: Function
			onModify:
				check: Function
		)

		{data, editor, small, onDelete, onModify, onlyText} = opts

		content = [
			new CUI.Label(text: data.displayName, appearance: "title", multiline: true)
		]

		if onlyText
			return content[0]

		link = ez5.GazetteerUtil.PLACE_URL + data.gazId

		menuItems = [
			new LocaButtonHref
				loca_key: "custom.data.type.gazetteer.link.button"
				href: link
				target: "_blank"
		]

		if not small
			if CUI.Map.isValidPosition(data.position)
				menuItems.push(
					new LocaButton
						loca_key: "custom.data.type.gazetteer.preview.button"
						onClick: =>
							previewPopover = new CUI.Popover
								element: menuButton
								placement: "sw"
								pane: @__buildPreviewMap(data.position, data.iconName)
								onHide: =>
									previewPopover.destroy()
							previewPopover.show()
				)

			if editor
				menuItems.push(
					new LocaButton
						loca_key: "custom.data.type.gazetteer.delete.button"
						onClick: =>
							onDelete?()
				)

				menuItems.push(
					new LocaButton
						loca_key: "custom.data.type.gazetteer.modify.button"
						onClick: =>
							onModify?()
				)

			menuButton = new LocaButton
				loca_key: "custom.data.type.gazetteer.menu.button"
				icon: "ellipsis_v"
				icon_right: false
				appearance: "flat"
				menu:
					items: menuItems

		if data.types
			types = []
			for type in data.types
				types.push $$("custom.data.type.gazetteer.types.#{type}.text")
			content.push new CUI.Label(text: types.join(", "), appearance: "secondary")

		if not CUI.util.isEmpty(data.otherNames) and ez5.session.getBaseConfig("plugin", "custom-data-type-gazetteer").gazetteer_plugin_settings?.show_alternative_names
			otherNameLabels = []
			showingMore = false
			showMoreLessButton = new CUI.Button
				text: ""
				appearance: "link"
				size: "mini"
				onClick: =>
					if showingMore
						showLess()
					else
						showMore()
					showingMore = not showingMore
			CUI.dom.hideElement(showMoreLessButton)

			showLess = () ->
				for label in otherNameLabels
					CUI.dom.hideElement(label)

				for level in [0..3] by 1
					if not otherNameLabels[level]
						continue
					CUI.dom.showElement(otherNameLabels[level])

				if otherNameLabels.length > 4
					showMoreLessButton.setText($$("custom.data.type.gazetteer.types.card.show-more-button"))
					CUI.dom.showElement(showMoreLessButton)
				return

			showMore = () ->
				for label in otherNameLabels
					CUI.dom.showElement(label)
				showMoreLessButton.setText($$("custom.data.type.gazetteer.types.card.show-less-button"))
				return

			otherNames = data.otherNames.map((otherName) -> otherName.title)
			for otherName in otherNames
				otherNameLabels.push(new CUI.Label(text: otherName, appearance: "secondary"))

			showLess()

			verticalListContent = if small then otherNameLabels else otherNameLabels.concat([showMoreLessButton])
			verticalList = new CUI.VerticalList(content: verticalListContent)
			content.push(verticalList)

		if not CUI.util.isEmpty(data.position) and ez5.session.getBaseConfig("plugin", "custom-data-type-gazetteer").gazetteer_plugin_settings?.show_lat_lng
			content.push(new CUI.Label(text: $$("custom.data.type.gazetteer.types.latitude_longitude.text", data.position), appearance: "secondary"))

		list = new CUI.VerticalList(content: content)

		if small
			return list
		else
			plugin = ez5.pluginManager.getPlugin("custom-data-type-gazetteer")
			previewImage = new Image(36, 36)
			previewImage.src = plugin.getBaseURL() + plugin.getWebfrontend().logo

			return new CUI.HorizontalLayout(
				class: "ez5-field-object ez5-custom-data-type-gazetteer-card"
				left:
					content: previewImage
				center:
					content: list
				right:
					content: menuButton
			)

	__buildPreviewMap: (position, iconName) ->
		return new CUI.MapInput.defaults.mapClass(
			selectedMarkerPosition: position
			selectedMarkerOptions:
				iconName: iconName
				iconColor: "#6786ad"
			centerPosition: position
			clickable: false
			zoom: 10
		)

	# This is the case that the ID is in the data but it was not found before.
	__fillMissingData: (data) ->
		if data.gazId and (not data.displayName or not data.types)
			deferred = new CUI.Deferred()
			ez5.GazetteerUtil.searchById(data.gazId).done((dataFound) =>
				ez5.GazetteerUtil.setObjectData(data, dataFound)
			).fail( =>
				data.notFound = true
			).always(deferred.resolve)
			return deferred.promise()
		else
			return CUI.resolvedPromise()

	# MapDetailPlugin comes from the detail-map plugin, which may not be installed.
	isPluginSupported: (plugin) ->
		return typeof MapDetailPlugin != 'undefined' and plugin instanceof MapDetailPlugin

CustomDataType.register(CustomDataTypeGazetteer)
