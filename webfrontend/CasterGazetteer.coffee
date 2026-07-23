class ez5.CasterGazetteer extends ez5.CasterPlugin

	__initCasters: ->
		[
			name: $$("custom.data.type.gazetteer.name.caster.name")
			description: $$("custom.data.type.gazetteer.name.caster.description")
			canCast: (from, to) =>
				return from not instanceof LocaTextColumn and from instanceof TextColumn and to instanceof CustomDataTypeGazetteer
			doCast: (value) =>
				gazId = CUI.util.getInt(value)
				if CUI.util.isNull(gazId)
					return

				deferred = new CUI.Deferred()
				ez5.GazetteerUtil.searchById(gazId).done((dataFound) =>
					newData = {}
					ez5.GazetteerUtil.setObjectData(newData, dataFound)
					deferred.resolve(newData)
				).fail( =>
					deferred.resolve()
				)
				return deferred.promise()
		]

ez5.session_ready ->
	ez5.ScriptRunner.FieldsMigrator.casterPlugins?.registerPlugin(ez5.CasterGazetteer)