class CustomBaseConfigGazetteer extends BaseConfigPlugin
	getFieldDefFromParm: (baseConfig, fieldName, def) ->
		getMask = (idTable) ->
			if CUI.util.isString(idTable) # Object types of connector instances.
				return false
			return Mask.getMaskByMaskName("_all_fields", idTable)

		getTopLevelRequiredFields = (objecttype) ->
			return objecttype.getFields().filter((field) ->
				return field.isTopLevelField() and field.isRequired()
			)

		switch def.plugin_type
			when "objecttype"
				field = new ez5.ObjecttypeSelector
					form: label: $$("custom.data.type.gazetteer.config.objecttype.label")
					name: fieldName
					show_name: true
					store_value: "fullname"
					filter: (objecttype) ->
						if not objecttype.isHierarchy()
							return false

						# The object type is only shown if at least one field is gazetteer.
						mask = getMask(objecttype.table.id())
						if not mask
							return false

						objecttype.addMask(mask)
						hasGazetteerField = objecttype.getFields().some((field) -> field instanceof CustomDataTypeGazetteer)
						if not hasGazetteerField
							return false

						requiredUniqueFields = getTopLevelRequiredFields(objecttype)
						if requiredUniqueFields.length == 0
							return true

						if requiredUniqueFields.length > 1
							return false

						# If there is just one required/unique field, it must be the custom data type gazetteer.
						return requiredUniqueFields[0] instanceof CustomDataTypeGazetteer

			when "field_from"
				field = new ez5.FieldSelector
					form: label: $$("custom.data.type.gazetteer.config.field_from.label")
					name: fieldName
					objecttype_data_key: "objecttype"
					store_value: "fullname"
					show_name: true
					placeholder: $$("custom.data.type.gazetteer.config.field-from-empty-text")
					filter: (field) ->
						return field instanceof TextColumn and
							field not instanceof NestedTable and
							field not instanceof NumberColumn and
							field not instanceof LocaTextColumn and
							not field.isTopLevelField() and
							not field.insideNested()
			when "field_to"
				field = new ez5.FieldSelector
					form: label: $$("custom.data.type.gazetteer.config.field_to.label")
					name: fieldName
					objecttype_data_key: "objecttype"
					store_value: "fullname"
					show_name: true
					filter: (fieldTo) =>
						if fieldTo not instanceof CustomDataTypeGazetteer
							return false

						if fieldTo.insideNested()
							return false

						mask = getMask(fieldTo.table.id())
						if not mask
							return false

						objecttype = new Objecttype(mask)
						requiredUniqueFields = getTopLevelRequiredFields(objecttype) # It will always return 1 or 0 fields.
						if requiredUniqueFields.length == 0
							return true

						return requiredUniqueFields[0].id() == fieldTo.id()
		return field

ez5.session_ready =>
	BaseConfig.registerPlugin(new CustomBaseConfigGazetteer())